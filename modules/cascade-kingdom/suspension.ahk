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
    global cascade_minimize_in_progress

    if cascade_minimize_in_progress
        return
    ; Do not hide a target in the middle of a native drag or paired tab click.
    if HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return

    previous_critical := Critical("On")
    cascade_minimize_in_progress := true
    try {
        PruneMinimizedCascadeWindows()
        command()
    }
    catch Error as err {
        DebugError("Hide or restore cascade windows", err)
    }
    finally {
        cascade_minimize_in_progress := false
        QueueFocusCornerUpdate()
        Critical(previous_critical)
    }
}

MinimizeCascadeWindows(monitor)
{
    global cascade_minimized_windows

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
            cascade_minimized_windows.InsertAt(++added, target)
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
        FocusAfterCascadeHide(monitor, cascade_minimized_windows[1].hwnd)
    DebugLog("Cascade windows minimized. | monitor=" monitor " | added=" added
        . " | saved-windows=" cascade_minimized_windows.Length)
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
    global cascade_minimized_windows

    windows_to_restore := []
    kept := []
    for target in cascade_minimized_windows {
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

    cascade_minimized_windows := kept
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
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") || IsWindowCloaked(hwnd)
        return false

    try {
        ; Independently minimized windows are never owned by Caps + M.
        if WinGetMinMax(hwnd) = -1
            return false

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
    global cascade_minimized_windows

    index := cascade_minimized_windows.Length
    while index >= 1 {
        if cascade_minimized_windows[index].hwnd = hwnd
            cascade_minimized_windows.RemoveAt(index)
        index -= 1
    }
}

PruneMinimizedCascadeWindows()
{
    global cascade_minimized_windows

    index := cascade_minimized_windows.Length
    while index >= 1 {
        target := cascade_minimized_windows[index]
        keep := IsSameMinimizedCascadeWindow(target)

        if keep {
            try keep := (WinGetMinMax(target.hwnd) = -1 && !!GetManagedCascadeMonitor(target.hwnd))
            catch
                keep := false
        }

        if !keep
            cascade_minimized_windows.RemoveAt(index)
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

    global cascade_poll_ms, focus_corner_fallback_ms, cascade_history
    global cascade_restore_batches, cascade_restore_poll_ms

    SetTimer(ApplyPendingCascadeDisplayLayout, -50)
    SetTimer(PollCascadeState, cascade_poll_ms)
    SetTimer(UpdateFocusCornerOverlays, focus_corner_fallback_ms)
    if cascade_restore_batches.Count
        SetTimer(WatchCascadeWindowRestores, cascade_restore_poll_ms)
    for monitor_index in cascade_history
        QueueCascadeCompaction(monitor_index)
    QueueFocusCornerUpdate()
}

RestoreMinimizedCascadeWindowsOnExit()
{
    global cascade_minimized_windows

    ; Native hooks are already stopped. Do not run layout, Z-order, or focus work
    ; during exit/reload, and never restore independently minimized applications.
    Loop cascade_minimized_windows.Length {
        target := cascade_minimized_windows[cascade_minimized_windows.Length - A_Index + 1]
        if !IsSameMinimizedCascadeWindow(target)
            continue

        try {
            if WinGetMinMax(target.hwnd) = -1
                WinRestore(target.hwnd)
        }
    }
    cascade_minimized_windows := []
}


; =============================================================================
; cascades kept across restarts
; =============================================================================

; Saved on exit, one line per member in join order: hwnd=pid|device|join.
SaveCascades()
{
    global cascade_history, cascade_displays, cascade_join_positions, cascade_state_path

    lines := ""
    for monitor_index, history in cascade_history {
        if !cascade_displays.Has(monitor_index)
            continue
        device := cascade_displays[monitor_index].device
        for hwnd in history {
            try pid := WinGetPID(hwnd)
            catch
                continue
            join := cascade_join_positions.Has(hwnd)
                ? FormatCascadeJoinPosition(cascade_join_positions[hwnd]) : ""
            lines .= hwnd "=" pid "|" device "|" join "`n"
        }
    }
    try {
        SplitPath(cascade_state_path, , &directory)
        DirCreate(directory)
        IniWrite(lines, cascade_state_path, "Cascades")
    }
    catch Error as err
        DebugError("Save cascades", err)
}

; A saved member rejoins only while it is the same window, by handle and
; process, on an allowed display. GetLiveCascadeHistory then drops one that
; was moved off its slot while Super Hotkey was not running.
RestoreSavedCascades()
{
    global cascade_history, cascade_state_path

    try saved := IniRead(cascade_state_path, "Cascades")
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
    for monitor_index in cascade_history.Clone()
        GetLiveCascadeHistory(monitor_index)
    DebugLog("Saved cascades restored. | windows=" restored)
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
