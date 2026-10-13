; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.
;
; Caps + M owns only its saved minimize/restore set. Caps + P pauses/resumes
; automatic placement of newly opened windows without disabling existing cascades.

; =============================================================================
; automatic new-window placement pause / resume
; =============================================================================

IsCascadeEnabled()
{
    ; Auto-placement pause does not disable the managed Cascade runtime.
    return true
}

IsCascadeAutoPlacementEnabled()
{
    global cascade_auto_placement_paused, cascade_auto_placement_toggle_in_progress
    return !cascade_auto_placement_paused && !cascade_auto_placement_toggle_in_progress
}

ToggleCascadeAutoPlacement(*)
{
    global cascade_auto_placement_paused, cascade_auto_placement_toggle_in_progress

    if cascade_auto_placement_toggle_in_progress
        return

    previous_critical := Critical("On")
    cascade_auto_placement_toggle_in_progress := true
    toggle_succeeded := false
    try {
        if cascade_auto_placement_paused
            ResumeCascadeAutoPlacement()
        else
            PauseCascadeAutoPlacement()
        toggle_succeeded := true
    }
    catch Error as err {
        DebugError("Toggle cascade auto placement", err)
    }
    finally {
        cascade_auto_placement_toggle_in_progress := false
        UpdateTrayMenu()
        if toggle_succeeded {
            ShowCascadeStatusTip(
                cascade_auto_placement_paused
                ? "auto cascading paused"
                : "auto cascading resumed"
            )
        }
        Critical(previous_critical)
    }
}

PauseCascadeAutoPlacement()
{
    global cascade_auto_placement_paused

    cascade_auto_placement_paused := true
    DebugLog("Cascade auto placement paused.")
}

ResumeCascadeAutoPlacement()
{
    global cascade_auto_placement_paused

    ; Snapshot everything that appeared during the pause before reopening
    ; automatic discovery. Those windows stay unmanaged until explicitly adopted.
    RememberWindowsOpenedWhileAutoPlacementPaused()
    cascade_auto_placement_paused := false
    DebugLog("Cascade auto placement resumed.")
}

RememberWindowDuringAutoPlacementPause(hwnd)
{
    global startup_windows, known_windows

    if !hwnd
        return

    startup_windows[hwnd] := true
    known_windows[hwnd] := true
}

; =============================================================================
; Caps + M minimize / restore
; =============================================================================

ToggleCascadeMinimize(*)
{
    global cascade_minimize_toggle_in_progress, cascade_minimized_windows

    if cascade_minimize_toggle_in_progress
        return
    ; Do not hide a target in the middle of a native drag or paired tab click.
    if HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return

    previous_critical := Critical("On")
    cascade_minimize_toggle_in_progress := true
    try {
        PruneMinimizedCascadeWindows()
        if cascade_minimized_windows.Length
            RestoreMinimizedCascadeWindows()
        else
            MinimizeCascadeWindows()
    }
    catch Error as err {
        DebugError("Toggle cascade minimized state", err)
    }
    finally {
        cascade_minimize_toggle_in_progress := false
        QueueFocusCornerUpdate()
        Critical(previous_critical)
    }
}

MinimizeCascadeWindows()
{
    global cascade_minimized_windows

    targets := CaptureCascadeMinimizeTargets()
    cascade_minimized_windows := []

    for target in targets {
        if !IsSameMinimizedCascadeWindow(target)
            continue

        try {
            if WinGetMinMax(target.hwnd) = -1
                continue

            ; Publish ownership before WinMinimize can yield to a lifetime callback.
            cascade_minimized_windows.Push(target)
            CancelPlacementStabilization(target.hwnd)
            RemoveWindowFromCascadeRestore(target.hwnd)
            WinMinimize(target.hwnd)

            if DllCall("IsIconic", "ptr", target.hwnd, "int") {
                ObserveCascadeMinimizedWindow(target.hwnd)
            } else {
                ForgetMinimizedCascadeWindow(target.hwnd)
                DebugLog("Cascade minimize was not accepted. | hwnd=" target.hwnd)
            }
        }
        catch Error as err {
            ForgetMinimizedCascadeWindow(target.hwnd)
            DebugError("Minimize cascade window", err)
        }
    }

    DebugLog("Cascade windows minimized. | saved-windows=" cascade_minimized_windows.Length)
}

RestoreMinimizedCascadeWindows()
{
    global cascade_minimized_windows

    windows_to_restore := []
    for target in cascade_minimized_windows.Clone() {
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

    RestoreCascadeWindows(windows_to_restore)
    cascade_minimized_windows := []
    DebugLog("Cascade windows restored. | restored-windows=" windows_to_restore.Length)
}

CaptureCascadeMinimizeTargets()
{
    global cascade_history

    targets := Map()
    for monitor_index, history in cascade_history.Clone() {
        try history := GetLiveCascadeHistory(monitor_index)
        catch
            continue

        for hwnd in history
            CaptureCascadeMinimizeTarget(targets, hwnd, monitor_index)
    }

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
            try keep := (
                WinGetMinMax(target.hwnd) = -1
                && !!GetManagedCascadeMonitor(target.hwnd)
            )
            catch
                keep := false
        }

        if !keep
            cascade_minimized_windows.RemoveAt(index)
        index -= 1
    }
}


; =============================================================================
; activity startup and paused-window bookkeeping
; =============================================================================

StartCascadeActivity()
{
    if !IsCascadeEnabled()
        return

    global missed_window_poll_ms, focus_corner_fallback_ms, cascade_history
    global cascade_restore_batches, cascade_restore_poll_ms

    SetTimer(ApplyPendingCascadeDisplayLayout, -50)
    SetTimer(WatchForMissedWindows, missed_window_poll_ms)
    SetTimer(UpdateFocusCornerOverlays, focus_corner_fallback_ms)
    if cascade_restore_batches.Count
        SetTimer(WatchCascadeWindowRestores, cascade_restore_poll_ms)
    for monitor_index in cascade_history
        QueueCascadeCompaction(monitor_index)
    QueueFocusCornerUpdate()
}

RememberWindowsOpenedWhileAutoPlacementPaused()
{
    global startup_windows, known_windows

    ; Include hidden top-level windows too, so showing an auto-paused app later
    ; does not make it look like a fresh launch. Do not adopt any of this snapshot.
    previous_hidden := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList() {
            startup_windows[hwnd] := true
            known_windows[hwnd] := true
        }
    }
    finally {
        DetectHiddenWindows(previous_hidden)
    }
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
