; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; maximized / fullscreen / borderless switcher
; =============================================================================

CycleMaximizedFullscreenWindows()
{
    Critical "On"
    ForgetLastMinimizedWindow()

    global maximized_fullscreen_cycle, last_maximized_fullscreen_hwnd

    RefreshMaximizedFullscreenCycle()

    if maximized_fullscreen_cycle.Length = 0 {
        last_maximized_fullscreen_hwnd := 0
        DebugLog("Expanded-window cycle stopped: no candidates detected.")
        return
    }

    active_hwnd := WinExist("A")
    active_index := FindWindowIndex(
        maximized_fullscreen_cycle,
        active_hwnd
    )

    if active_index {
        last_maximized_fullscreen_hwnd := active_hwnd

        if maximized_fullscreen_cycle.Length = 1 {
            DebugLog(
                "Expanded-window cycle stopped: active window is the only candidate."
                . " | target=" DebugDescribeWindow(active_hwnd)
            )
            return
        }

        target_index := (
            active_index = maximized_fullscreen_cycle.Length
            ? 1
            : active_index + 1
        )
        target_hwnd := maximized_fullscreen_cycle[target_index]
    } else if last_maximized_fullscreen_hwnd
        && FindWindowIndex(
            maximized_fullscreen_cycle,
            last_maximized_fullscreen_hwnd
        )
    {
        target_hwnd := last_maximized_fullscreen_hwnd
    } else {
        target_hwnd := maximized_fullscreen_cycle[1]
    }

    DebugLog(
        "Expanded-window cycle activation."
        . " | from=" DebugDescribeWindow(active_hwnd)
        . " | to=" DebugDescribeWindow(target_hwnd)
    )

    if ActivateMaximizedFullscreenWindow(target_hwnd, active_hwnd)
        last_maximized_fullscreen_hwnd := target_hwnd
}

RefreshMaximizedFullscreenCycle()
{
    global maximized_fullscreen_cycle

    detected_windows := GetMaximizedFullscreenWindows()
    detected_set := Map()

    for hwnd in detected_windows
        detected_set[hwnd] := true

    refreshed_cycle := []
    preserved_set := Map()

    ; Keep the established order stable even though activating a window changes
    ; native Z-order. Closed/restored windows simply fall out of the cycle.
    for hwnd in maximized_fullscreen_cycle {
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

    maximized_fullscreen_cycle := refreshed_cycle
}

GetMaximizedFullscreenWindows()
{
    windows := []

    for hwnd in WinGetList() {
        if IsMaximizedFullscreenSwitcherWindow(hwnd)
            windows.Push(hwnd)
    }

    return windows
}

IsMaximizedFullscreenSwitcherWindow(hwnd)
{
    global borderless_windows

    if !IsWindowToggleCandidate(hwnd)
        return false

    ; Win Key Overhaul's own borderless mode is authoritative even if an
    ; application's style/geometry changes slightly after entry.
    if borderless_windows.Has(hwnd)
        && WindowStateMatchesProcess(hwnd, borderless_windows[hwnd])
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

    return WindowFillsPhysicalMonitor(hwnd)
}

WindowFillsPhysicalMonitor(hwnd, tolerance := 2)
{
    try {
        if !GetVisibleWindowBounds(
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

        GetWindowMonitorBounds(
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

ActivateMaximizedFullscreenWindow(target_hwnd, source_hwnd := 0)
{
    if !IsMaximizedFullscreenSwitcherWindow(target_hwnd)
        return false

    ; A Win Key Overhaul borderless source is topmost. Lower it before trying
    ; to activate another window, otherwise the target can remain hidden behind it.
    if source_hwnd && source_hwnd != target_hwnd
        DemoteBorderlessSwitcherSource(source_hwnd)

    ; A previously lowered borderless target must re-enter the topmost band
    ; before activation so it behaves like normal borderless fullscreen again.
    promoted_target := PromoteBorderlessSwitcherTarget(target_hwnd)

    activation_succeeded := ActivateWindowReliably(target_hwnd)

    if activation_succeeded
        return true

    ; Roll both sides back if activation failed.
    if promoted_target
        DemoteBorderlessSwitcherSource(target_hwnd)

    if source_hwnd && source_hwnd != target_hwnd
        PromoteBorderlessSwitcherTarget(source_hwnd)

    return false
}
