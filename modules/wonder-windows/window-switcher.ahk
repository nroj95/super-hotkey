; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; overlapping-window switcher
; =============================================================================

WW_CycleStackedWindows()
{
    Critical "On"
    active := WinExist("A")
    if !WW_IsWindowToggleCandidate(active) || GetManagedCascadeMonitor(active)
        return

    monitor := DllCall("MonitorFromWindow", "ptr", active, "uint", 2, "ptr")
    activeRect := WW_GetWindowLayoutRectangle(active)
    backmost := 0

    ; WinGetList lists front to back. Bringing the last overlapping window
    ; forward rotates even a large stack without tracking activation history.
    for hwnd in WinGetList() {
        if hwnd = active || !WW_IsWindowToggleCandidate(hwnd)
            || GetManagedCascadeMonitor(hwnd)
            continue
        if DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") != monitor
            continue
        try {
            if WW_WindowsSubstantiallyOverlap(activeRect, WW_GetWindowLayoutRectangle(hwnd))
                backmost := hwnd
        }
    }
    if backmost {
        WW_ForgetLastMinimizedWindow()
        WW_EndFocusNavigationSession()
        WW_ActivateWindowReliably(backmost)
    }
}

WW_WindowsSubstantiallyOverlap(first, second)
{
    if first[3] <= 0 || first[4] <= 0 || second[3] <= 0 || second[4] <= 0
        return false
    width := Min(first[1] + first[3], second[1] + second[3]) - Max(first[1], second[1])
    height := Min(first[2] + first[4], second[2] + second[4]) - Max(first[2], second[2])
    if width <= 0 || height <= 0
        return false
    overlap := width * height * 2
    return overlap >= first[3] * first[4] && overlap >= second[3] * second[4]
}

; =============================================================================
; maximized / native fullscreen switcher
; =============================================================================

WW_CycleMaximizedFullscreenWindows()
{
    Critical "On"
    WW_ForgetLastMinimizedWindow()
    WW_EndFocusNavigationSession()

    global WW_maximized_fullscreen_cycle, WW_last_maximized_fullscreen_hwnd

    WW_RefreshMaximizedFullscreenCycle()

    if WW_maximized_fullscreen_cycle.Length = 0 {
        WW_last_maximized_fullscreen_hwnd := 0
        WW_DebugLog("Expanded-window cycle stopped: no candidates detected.")
        return
    }

    active_hwnd := WinExist("A")
    target_hwnd := WW_NextMaximizedFullscreenWindow(WW_maximized_fullscreen_cycle, active_hwnd,
        WW_last_maximized_fullscreen_hwnd)

    WW_DebugLog("Expanded-window cycle step." . " | from=" WW_DebugDescribeWindow(active_hwnd)
        . " | to=" WW_DebugDescribeWindow(target_hwnd))

    if WW_ShowMaximizedFullscreenCycleWindow(WW_maximized_fullscreen_cycle, target_hwnd)
        WW_last_maximized_fullscreen_hwnd := target_hwnd
}

WW_NextMaximizedFullscreenWindow(windows, active_hwnd, last_hwnd)
{
    if !windows.Length
        return 0
    active_index := WW_FindWindowIndex(windows, active_hwnd)
    if active_index
        return active_index = windows.Length ? 0 : windows[active_index + 1]
    if WW_FindWindowIndex(windows, last_hwnd)
        return last_hwnd
    return windows[1]
}

WW_RefreshMaximizedFullscreenCycle()
{
    global WW_maximized_fullscreen_cycle

    detected_windows := WW_GetMaximizedFullscreenWindows()
    detected_set := Map()

    for hwnd in detected_windows
        detected_set[hwnd] := true

    refreshed_cycle := []
    preserved_set := Map()

    ; Keep the established order stable even though activating a window changes
    ; native Z-order. Minimized members stay; closed/normal-size windows fall out.
    for hwnd in WW_maximized_fullscreen_cycle {
        if !detected_set.Has(hwnd)
            continue

        refreshed_cycle.Push(hwnd)
        preserved_set[hwnd] := true
    }

    for hwnd in detected_windows {
        if preserved_set.Has(hwnd)
            continue

        refreshed_cycle.Push(hwnd)
    }

    WW_maximized_fullscreen_cycle := refreshed_cycle
}

WW_GetMaximizedFullscreenWindows()
{
    windows := []

    for hwnd in WinGetList() {
        if WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
            windows.Push(hwnd)
    }

    return windows
}

WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
{
    if !WW_IsWindowToggleCandidate(hwnd, true)
        return false
    try {
        state := WinGetMinMax(hwnd)
        if state != -1
            return state = 1 || WW_IsNativeFullscreen(hwnd)

        placement := WW_CaptureWindowPlacement(hwnd)
        ; Windows remembers whether an iconic window should restore maximized.
        if (NumGet(placement, 4, "uint") & 0x0002) ; WPF_RESTORETOMAXIMIZED
            || SuiteFullscreen.placements.Has(hwnd)
            return true

        ; Native fullscreen is a normal-state window filling a physical monitor.
        ; Its current minimized rectangle cannot identify that saved geometry.
        return WW_WindowPlacementFillsPhysicalMonitor(placement, WW_GetWindowMonitorInfo(hwnd))
    }
    catch
        return false
}

WW_WindowPlacementFillsPhysicalMonitor(placement, monitor_info, tolerance := 2)
{
    ; Candidates exclude tool windows, so rcNormalPosition uses workspace
    ; coordinates. Convert to screen coordinates, including top/left taskbars.
    offset_x := NumGet(monitor_info, 20, "int") - NumGet(monitor_info, 4, "int")
    offset_y := NumGet(monitor_info, 24, "int") - NumGet(monitor_info, 8, "int")
    return (
        Abs(NumGet(placement, 28, "int") + offset_x - NumGet(monitor_info, 4, "int")) <= tolerance
        && Abs(NumGet(placement, 32, "int") + offset_y - NumGet(monitor_info, 8, "int")) <= tolerance
        && Abs(NumGet(placement, 36, "int") + offset_x - NumGet(monitor_info, 12, "int")) <= tolerance
        && Abs(NumGet(placement, 40, "int") + offset_y - NumGet(monitor_info, 16, "int")) <= tolerance
    )
}

WW_WindowFillsPhysicalMonitor(hwnd, tolerance := 2)
{
    try {
        if !GetVisibleWindowBounds(hwnd, &window_x, &window_y, &window_width, &window_height) {
            WinGetPos(&window_x, &window_y, &window_width, &window_height, "ahk_id " hwnd)
        }

        WW_GetWindowMonitorBounds(hwnd, &monitor_left, &monitor_top, &monitor_right, &monitor_bottom
        )
    }
    catch {
        return false
    }

    return (Abs(window_x - monitor_left) <= tolerance && Abs(window_y - monitor_top) <= tolerance
        && Abs(window_x + window_width - monitor_right) <= tolerance
        && Abs(window_y + window_height - monitor_bottom) <= tolerance)
}

WW_ShowMaximizedFullscreenCycleWindow(windows, target_hwnd)
{
    if target_hwnd && !WW_IsMaximizedFullscreenSwitcherWindow(target_hwnd)
        return false

    ; Minimize the whole snapshot before restoring the next window. Target 0 is
    ; the all-minimized step; clearing the last target starts the next pass at 1.
    for hwnd in windows {
        if hwnd = target_hwnd || !WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
            continue
        try {
            if WinGetMinMax(hwnd) != -1
                WinMinimize(hwnd)
            if WinExist(hwnd) && WinGetMinMax(hwnd) != -1 {
                WW_DebugLog("Expanded-window cycle could not minimize hwnd=" hwnd)
                return false
            }
        }
        catch Error as err {
            if WinExist(hwnd) {
                WW_DebugError("Expanded-window cycle minimize", err)
                return false
            }
        }
    }

    return !target_hwnd || WW_ActivateWindowReliably(target_hwnd)
}
