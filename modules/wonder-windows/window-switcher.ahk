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

    global WW_maximized_fullscreen_cycle, WW_last_maximized_fullscreen_hwnd

    WW_RefreshMaximizedFullscreenCycle()

    if WW_maximized_fullscreen_cycle.Length = 0 {
        WW_last_maximized_fullscreen_hwnd := 0
        WW_DebugLog("Expanded-window cycle stopped: no candidates detected.")
        return
    }

    active_hwnd := WinExist("A")
    active_index := WW_FindWindowIndex(
        WW_maximized_fullscreen_cycle,
        active_hwnd
    )

    if active_index {
        WW_last_maximized_fullscreen_hwnd := active_hwnd

        if WW_maximized_fullscreen_cycle.Length = 1 {
            WW_DebugLog(
                "Expanded-window cycle stopped: active window is the only candidate."
                . " | target=" WW_DebugDescribeWindow(active_hwnd)
            )
            return
        }

        target_index := (
            active_index = WW_maximized_fullscreen_cycle.Length
            ? 1
            : active_index + 1
        )
        target_hwnd := WW_maximized_fullscreen_cycle[target_index]
    } else if WW_last_maximized_fullscreen_hwnd
        && WW_FindWindowIndex(
            WW_maximized_fullscreen_cycle,
            WW_last_maximized_fullscreen_hwnd
        )
    {
        target_hwnd := WW_last_maximized_fullscreen_hwnd
    } else {
        target_hwnd := WW_maximized_fullscreen_cycle[1]
    }

    WW_DebugLog(
        "Expanded-window cycle activation."
        . " | from=" WW_DebugDescribeWindow(active_hwnd)
        . " | to=" WW_DebugDescribeWindow(target_hwnd)
    )

    if WW_ActivateMaximizedFullscreenWindow(target_hwnd)
        WW_last_maximized_fullscreen_hwnd := target_hwnd
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
    ; native Z-order. Closed/restored windows simply fall out of the cycle.
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
    if !WW_IsWindowToggleCandidate(hwnd)
        return false
    try return WinGetMinMax(hwnd) = 1 || WW_IsNativeFullscreen(hwnd)
    catch
        return false
}

WW_WindowFillsPhysicalMonitor(hwnd, tolerance := 2)
{
    try {
        if !WW_GetVisibleWindowBounds(
            hwnd,
            &window_x,
            &window_y,
            &window_width,
            &window_height
        ) {
            WinGetPos(
                &window_x,
                &window_y,
                &window_width,
                &window_height,
                "ahk_id " hwnd
            )
        }

        WW_GetWindowMonitorBounds(
            hwnd,
            &monitor_left,
            &monitor_top,
            &monitor_right,
            &monitor_bottom
        )
    }
    catch {
        return false
    }

    return (
        Abs(window_x - monitor_left) <= tolerance
        && Abs(window_y - monitor_top) <= tolerance
        && Abs(window_x + window_width - monitor_right) <= tolerance
        && Abs(window_y + window_height - monitor_bottom) <= tolerance
    )
}

WW_ActivateMaximizedFullscreenWindow(target_hwnd)
{
    if !WW_IsMaximizedFullscreenSwitcherWindow(target_hwnd)
        return false
    return WW_ActivateWindowReliably(target_hwnd)
}
