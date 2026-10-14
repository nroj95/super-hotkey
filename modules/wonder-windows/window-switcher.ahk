; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; maximized / fullscreen / borderless switcher
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

    if WW_ActivateMaximizedFullscreenWindow(target_hwnd, active_hwnd)
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
    global WW_borderless_windows

    if !WW_IsWindowToggleCandidate(hwnd)
        return false

    ; Win Key Overhaul's own borderless mode is authoritative even if an
    ; application's style/geometry changes slightly after entry.
    if WW_borderless_windows.Has(hwnd)
        && WW_WindowStateMatchesProcess(hwnd, WW_borderless_windows[hwnd])
    {
        return true
    }

    try {
        if WinGetMinMax("ahk_id " hwnd) = 1
            return true
    }
    catch {
        return false
    }

    return WW_WindowFillsPhysicalMonitor(hwnd)
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

WW_ActivateMaximizedFullscreenWindow(target_hwnd, source_hwnd := 0)
{
    if !WW_IsMaximizedFullscreenSwitcherWindow(target_hwnd)
        return false

    ; A Win Key Overhaul borderless source is topmost. Lower it before trying
    ; to activate another window, otherwise the target can remain hidden behind it.
    if source_hwnd && source_hwnd != target_hwnd
        WW_DemoteBorderlessSwitcherSource(source_hwnd)

    ; A previously lowered borderless target must re-enter the topmost band
    ; before activation so it behaves like normal borderless fullscreen again.
    promoted_target := WW_PromoteBorderlessSwitcherTarget(target_hwnd)

    activation_succeeded := WW_ActivateWindowReliably(target_hwnd)

    if activation_succeeded
        return true

    ; Roll both sides back if activation failed.
    if promoted_target
        WW_DemoteBorderlessSwitcherSource(target_hwnd)

    if source_hwnd && source_hwnd != target_hwnd
        WW_PromoteBorderlessSwitcherTarget(source_hwnd)

    return false
}
