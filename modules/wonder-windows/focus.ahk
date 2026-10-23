; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; directional focus
; =============================================================================

WW_FocusNearestWindow(direction)
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    active_hwnd := WinExist("A")

    if !active_hwnd
        return

    ; The first directional-focus press starts on the current window instead
    ; of immediately leaving it. A manual focus change also starts a new
    ; session from that newly focused window.
    if !WW_focus_navigation_active
        || active_hwnd != WW_focus_navigation_hwnd
    {
        WW_ForgetLastMinimizedWindow()
        WW_focus_navigation_active := true
        WW_focus_navigation_hwnd := active_hwnd
        WW_HighlightFocusedWindow(active_hwnd)
        return
    }

    try {
        WinGetPos(&active_x, &active_y, &active_width, &active_height, "ahk_id " active_hwnd)
    }
    catch {
        return
    }

    active_center_x := active_x + active_width / 2
    active_center_y := active_y + active_height / 2

    target_hwnd := 0
    best_score := 0

    for hwnd in WinGetList() {
        if hwnd = active_hwnd
            continue

        if !IsSwitchableWindow(hwnd)
            continue

        try {
            WinGetPos(&candidate_x, &candidate_y, &candidate_width, &candidate_height,
                "ahk_id " hwnd)
        }
        catch {
            continue
        }

        candidate_center_x :=
            candidate_x + candidate_width / 2

        candidate_center_y :=
            candidate_y + candidate_height / 2

        delta_x := candidate_center_x - active_center_x
        delta_y := candidate_center_y - active_center_y

        switch direction {
            case "left":
                if delta_x >= 0
                    continue

                primary_distance := -delta_x
                perpendicular_distance := Abs(delta_y)

            case "right":
                if delta_x <= 0
                    continue

                primary_distance := delta_x
                perpendicular_distance := Abs(delta_y)

            case "up":
                if delta_y >= 0
                    continue

                primary_distance := -delta_y
                perpendicular_distance := Abs(delta_x)

            case "down":
                if delta_y <= 0
                    continue

                primary_distance := delta_y
                perpendicular_distance := Abs(delta_x)

            default:
                return
        }

        ; Prefer nearby windows while strongly favoring alignment with the
        ; requested direction.
        score :=
            primary_distance
            + perpendicular_distance * 2

        if !target_hwnd || score < best_score {
            target_hwnd := hwnd
            best_score := score
        }
    }

    if !target_hwnd
        return

    WW_ForgetLastMinimizedWindow()

    try {
        WinActivate("ahk_id " target_hwnd)
        WW_focus_navigation_hwnd := target_hwnd
        WW_HighlightFocusedWindow(target_hwnd)
    }
}

; =============================================================================
; focus after minimize
; =============================================================================

WW_FocusAfterMinimize(minimized_hwnd)
{
    ; Prefer the foreground window Windows naturally selects after minimization.
    ; Wait briefly because shell focus transitions are not always immediate.
    Loop 8 {
        if A_Index > 1
            Sleep 25

        foreground_hwnd := DllCall("GetForegroundWindow", "ptr")

        if foreground_hwnd != minimized_hwnd
            && IsSwitchableWindow(foreground_hwnd)
        {
            WW_BeginSpatialFocus(foreground_hwnd)
            return
        }
    }

    ; If Windows left focus on the shell, activate the topmost eligible window
    ; on the current desktop. Cloaked/minimized/shell windows are filtered out.
    for hwnd in WinGetList() {
        if hwnd = minimized_hwnd
            continue

        if !IsSwitchableWindow(hwnd)
            continue

        if ActivateWindow(hwnd) {
            WW_BeginSpatialFocus(hwnd)
            return
        }
    }

    ; With no other eligible window, leave focus to the Windows shell/desktop.
    WW_EndFocusNavigationSession()
}

WW_BeginSpatialFocus(hwnd)
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    if !hwnd || !WinExist("ahk_id " hwnd) {
        WW_EndFocusNavigationSession()
        return false
    }

    WW_focus_navigation_active := true
    WW_focus_navigation_hwnd := hwnd
    WW_HighlightFocusedWindow(hwnd)
    return true
}

; =============================================================================
; focus highlight and session lifetime
; =============================================================================

WW_HighlightFocusedWindow(hwnd)
{
    ; The border belongs to core. Wonder Windows owns only its navigation session.
    if SuiteFocusBorder.Show(hwnd, "wonder-windows")
        SetTimer WW_EndFocusNavigationSession, -SuiteFocusBorder.durationMs
    else
        WW_EndFocusNavigationSession()
}

WW_EndFocusNavigationSession()
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    previous_critical := A_IsCritical
    Critical "On"
    try {
        SetTimer WW_EndFocusNavigationSession, 0
        WW_focus_navigation_active := false
        WW_focus_navigation_hwnd := 0
        ; A late Wonder Windows timer cannot erase a newer Cascade Kingdom border.
        SuiteFocusBorder.Hide("wonder-windows")
    }
    finally {
        Critical previous_critical
    }
}
