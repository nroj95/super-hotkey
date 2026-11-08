; Cascade Kingdom's enabled state, hiding and restoring (Caps + M and
; Caps + Shift + M), activity startup, hidden-window cleanup on exit and the
; cascades kept across restarts.

IsCascadeEnabled() {
    app := SuiteState.App
    return app.ModuleActive("cascade-kingdom") && !app.dryRun && !app.stopping
        && !app.suspended && !app.systemSuspended && !app.sessionLocked
}

; =============================================================================
; Caps + M hide / Caps + Shift + M restore
; =============================================================================

; Both act on the display the user is on. Caps + M adds that display's visible
; cascade windows to the hidden list; Caps + Shift + M brings back the windows
; hidden from that display. A window restored, closed or released another way
; leaves the list; a window minimized by hand never joins it.
RunCascadeMinimizeCommand(command)
{
    if CascadeState.minimizeInProgress
        return
    ; Do not hide a target in the middle of a native drag or paired tab click.
    if HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return

    previous_critical := Critical("On")
    CascadeState.minimizeInProgress := true
    try {
        PruneMinimizedCascadeWindows()
        command()
    }
    catch Error as err {
        DebugError("Hide or restore cascade windows", err)
    }
    finally {
        CascadeState.minimizeInProgress := false
        QueueFocusCornerUpdate()
        Critical(previous_critical)
    }
}

MinimizeCascadeWindows(monitor)
{
    ; The newest batch goes first, so it comes back on top.
    targets := CaptureCascadeMinimizeTargets(monitor)
    added := 0

    for target in targets {
        if !IsSameMinimizedCascadeWindow(target)
            continue

        listed := false
        try {
            if WinGetMinMax(target.hwnd) = -1
                continue

            ; Publish ownership before WinMinimize can yield to a lifetime callback.
            CascadeState.minimizedWindows.InsertAt(++added, target)
            listed := true
            CancelPlacementStabilization(target.hwnd)
            RemoveWindowFromCascadeRestore(target.hwnd)
            WinMinimize(target.hwnd)

            if DllCall("IsIconic", "ptr", target.hwnd, "int") {
                ObserveCascadeMinimizedWindow(target.hwnd)
            } else {
                ForgetMinimizedCascadeWindow(target.hwnd)
                added -= 1
                DebugLog("Cascade minimize was not accepted. | hwnd=" target.hwnd)
            }
        }
        catch Error as err {
            if listed {
                ForgetMinimizedCascadeWindow(target.hwnd)
                added -= 1
            }
            DebugError("Minimize cascade window", err)
        }
    }

    if added
        FocusAfterCascadeHide(monitor, CascadeState.minimizedWindows[1].hwnd)
    DebugLog("Cascade windows minimized. | monitor=" monitor " | added=" added
        . " | saved-windows=" CascadeState.minimizedWindows.Length)
}

; Focus stays on the display the cascade left: Windows would hand it to the
; next window anywhere, possibly on another display where keystrokes would land
; unseen. The next window on this display gets focus and an outline, like after
; Win + Backspace; with none, the desktop does, and this display stays the
; user's, so Caps + Shift + M brings the cascade straight back.
FocusAfterCascadeHide(monitor, hidden_hwnd)
{
    ; Windows' own handoff is asynchronous; let it settle first.
    Loop 8 {
        foreground := DllCall("GetForegroundWindow", "ptr")
        if foreground != hidden_hwnd && !DllCall("IsIconic", "ptr", foreground, "int")
            break
        Sleep 25
    }
    target := 0
    if IsSwitchableWindow(foreground) && WindowMonitorIndex(foreground) = monitor
        target := foreground
    else
        for hwnd in WinGetList()
            if IsSwitchableWindow(hwnd) && WindowMonitorIndex(hwnd) = monitor {
                target := hwnd
                break
            }
    if target && ActivateWindow(target) {
        SuiteFocusBorder.Show(target, "cascade-kingdom")
        return
    }
    DllCall("SetForegroundWindow", "ptr", DllCall("GetShellWindow", "ptr"), "int")
    SuiteWorkingMonitor.Return(hidden_hwnd)
}

RestoreMinimizedCascadeWindows(monitor)
{
    windows_to_restore := []
    kept := []
    for target in CascadeState.minimizedWindows {
        if target.monitor != monitor {
            kept.Push(target)
            continue
        }
        if !IsSameMinimizedCascadeWindow(target)
            continue

        try {
            ; Manual restores and closed windows relinquish Caps + M ownership.
            if WinGetMinMax(target.hwnd) = -1
                && GetManagedCascadeMonitor(target.hwnd) = target.monitor
            {
                windows_to_restore.Push(target.hwnd)
            }
        }
    }

    CascadeState.minimizedWindows := kept
    RestoreCascadeWindows(windows_to_restore)
    DebugLog("Cascade windows restored. | monitor=" monitor " | restored-windows=" windows_to_restore.Length)
}

CaptureCascadeMinimizeTargets(monitor)
{
    targets := Map()
    try history := GetLiveCascadeHistory(monitor)
    catch
        history := []
    for hwnd in history
        CaptureCascadeMinimizeTarget(targets, hwnd, monitor)

    windows := []
    for hwnd in targets
        windows.Push(hwnd)

    ordered := []
    for hwnd in SortCascadeWindowsByZOrder(windows, GetCascadeWindowZRanks())
        ordered.Push(targets[hwnd])
    return ordered
}

CaptureCascadeMinimizeTarget(targets, hwnd, monitor_index)
{
    if targets.Has(hwnd) || !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    ; Windows minimized, maximized or hidden on their own are never owned by Caps + M.
    if !IsCascadeWindowShown(hwnd)
        return false

    try {
        targets[hwnd] := {
            hwnd: hwnd,
            pid: WinGetPID(hwnd),
            monitor: monitor_index
        }
        return true
    }
    catch {
        return false
    }
}

IsSameMinimizedCascadeWindow(target)
{
    if !DllCall("IsWindow", "ptr", target.hwnd, "int")
        return false
    try return WinGetPID(target.hwnd) = target.pid
    catch
        return false
}

ForgetMinimizedCascadeWindow(hwnd)
{
    index := CascadeState.minimizedWindows.Length
    while index >= 1 {
        if CascadeState.minimizedWindows[index].hwnd = hwnd
            CascadeState.minimizedWindows.RemoveAt(index)
        index -= 1
    }
}

PruneMinimizedCascadeWindows()
{
    index := CascadeState.minimizedWindows.Length
    while index >= 1 {
        target := CascadeState.minimizedWindows[index]
        keep := IsSameMinimizedCascadeWindow(target)

        if keep {
            try keep := (WinGetMinMax(target.hwnd) = -1 && !!GetManagedCascadeMonitor(target.hwnd))
            catch
                keep := false
        }

        if !keep
            CascadeState.minimizedWindows.RemoveAt(index)
        index -= 1
    }
}


; =============================================================================
; activity startup and minimized-window cleanup on exit
; =============================================================================

StartCascadeActivity()
{
    if !IsCascadeEnabled()
        return

    SetTimer(ApplyPendingCascadeDisplayLayout, -50)
    SetTimer(PollCascadeState, CascadeState.pollMs)
    SetTimer(UpdateFocusCornerOverlays, CascadeState.focusCornerFallbackMs)
    if CascadeState.restoreBatches.Count
        SetTimer(WatchCascadeWindowRestores, CascadeState.restorePollMs)
    for monitor_index in CascadeState.history
        QueueCascadeCompaction(monitor_index)
    QueueFocusCornerUpdate()
}

RestoreMinimizedCascadeWindowsOnExit()
{
    ; Native hooks are already stopped. Do not run layout, Z-order, or focus work
    ; during exit/reload, and never restore independently minimized applications.
    Loop CascadeState.minimizedWindows.Length {
        target := CascadeState.minimizedWindows[CascadeState.minimizedWindows.Length - A_Index + 1]
        if !IsSameMinimizedCascadeWindow(target)
            continue

        try {
            if WinGetMinMax(target.hwnd) = -1
                WinRestore(target.hwnd)
        }
    }
    CascadeState.minimizedWindows := []
}


; =============================================================================
; cascades kept across restarts
; =============================================================================

; Saved on exit, one line per member in join order: hwnd=pid|device|join, and
; one per window lent to Wonder Windows: hwnd=pid|device|slot.
SaveCascades()
{
    lent := ""
    for hwnd, slot in CascadeState.lentWindows
        lent .= hwnd "=" slot.pid "|" slot.device "|" slot.slot "`n"
    lines := ""
    for monitor_index, history in CascadeState.history {
        if !CascadeState.displays.Has(monitor_index)
            continue
        device := CascadeState.displays[monitor_index].device
        for hwnd in history {
            try pid := WinGetPID(hwnd)
            catch
                continue
            join := CascadeState.joinPositions.Has(hwnd)
                ? FormatCascadeJoinPosition(CascadeState.joinPositions[hwnd]) : ""
            lines .= hwnd "=" pid "|" device "|" join "`n"
        }
    }
    try {
        SplitPath(CascadeState.statePath, , &directory)
        DirCreate(directory)
        IniWrite(lines, CascadeState.statePath, "Cascades")
        IniWrite(lent, CascadeState.statePath, "Lent")
    }
    catch Error as err
        DebugError("Save cascades", err)
}

; A saved member rejoins only while it is the same window, by handle and
; process, on an allowed display. GetLiveCascadeHistory then drops one that
; was moved off its slot while Super Hotkey was not running.
RestoreSavedCascades()
{
    try saved := IniRead(CascadeState.statePath, "Cascades")
    catch
        return
    restored := 0
    for line in StrSplit(saved, "`n", "`r") {
        try {
            entry := StrSplit(line, "=", , 2)
            fields := StrSplit(entry[2], "|")
            hwnd := Integer(entry[1])
            pid := Integer(fields[1])
            if !DllCall("IsWindow", "ptr", hwnd, "int") || WinGetPID(hwnd) != pid
                continue
            monitor := FindCascadeMonitorDevice(fields[2])
            if !CascadeDisplayAllowed(monitor)
                continue
            RecordCascadeWindow(monitor, hwnd)
            if position := ParseCascadeJoinPosition(fields[3], pid)
                RememberCascadeJoinPosition(hwnd, position, position.was_manual)
            restored += 1
        }
    }
    for monitor_index in CascadeState.history.Clone()
        GetLiveCascadeHistory(monitor_index)
    DebugLog("Saved cascades restored. | windows=" restored " | lent=" RestoreLentCascadeWindows())
}

; Ownership by hand ends on exit, so a window Wonder Windows still has gets its
; claim back and Win + Down can still return it to its slot. One already back
; in a slot rejoins instead.
RestoreLentCascadeWindows()
{
    try saved := IniRead(CascadeState.statePath, "Lent")
    catch
        return 0
    restored := 0
    for line in StrSplit(saved, "`n", "`r") {
        try {
            entry := StrSplit(line, "=", , 2)
            fields := StrSplit(entry[2], "|")
            hwnd := Integer(entry[1])
            pid := Integer(fields[1])
            if !DllCall("IsWindow", "ptr", hwnd, "int") || WinGetPID(hwnd) != pid
                || GetManagedCascadeMonitor(hwnd)
                continue
            monitor := FindCascadeMonitorDevice(fields[2])
            if !CascadeDisplayAllowed(monitor)
                continue
            if IsCascadeWindowShown(hwnd)
                && TryGetCascadeLayoutOrigin(hwnd, &layout_monitor, &x, &y) && layout_monitor = monitor
                && FindNearestCascadeSlot(x, y, GetCanonicalCascadeGeometry(monitor).slots,
                    CascadeState.slotTolerance)
            {
                RecordCascadeWindow(monitor, hwnd)
                continue
            }
            SuiteWindowOwnership.Claim(hwnd)
            CascadeState.lentWindows[hwnd] := {pid: pid, monitor: monitor, device: fields[2],
                slot: Integer(fields[3])}
            restored += 1
        }
    }
    return restored
}

; A join position as text: x,y,width,height,was_manual[,placement in hex].
FormatCascadeJoinPosition(position)
{
    text := position.x "," position.y "," position.width "," position.height
        . "," (position.was_manual ? 1 : 0)
    if position.placement {
        text .= ","
        Loop position.placement.Size
            text .= Format("{:02X}", NumGet(position.placement, A_Index - 1, "uchar"))
    }
    return text
}

ParseCascadeJoinPosition(text, pid)
{
    parts := StrSplit(text, ",")
    if parts.Length < 5
        return 0
    placement := 0
    if parts.Length > 5 {
        placement := Buffer(StrLen(parts[6]) // 2)
        Loop placement.Size
            NumPut("uchar", Integer("0x" SubStr(parts[6], 2 * A_Index - 1, 2)), placement, A_Index - 1)
    }
    return {pid: pid, x: Integer(parts[1]), y: Integer(parts[2]), width: Integer(parts[3]),
        height: Integer(parts[4]), placement: placement, was_manual: parts[5] = "1"}
}
