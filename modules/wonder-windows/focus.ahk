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
        WinGetPos(
            &active_x,
            &active_y,
            &active_width,
            &active_height,
            "ahk_id " active_hwnd
        )
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

        if !WW_IsWindowToggleCandidate(hwnd)
            continue

        try {
            WinGetPos(
                &candidate_x,
                &candidate_y,
                &candidate_width,
                &candidate_height,
                "ahk_id " hwnd
            )
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

        foreground_hwnd := DllCall(
            "GetForegroundWindow",
            "ptr"
        )

        if foreground_hwnd != minimized_hwnd
            && WW_IsWindowToggleCandidate(foreground_hwnd)
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

        if !WW_IsWindowToggleCandidate(hwnd)
            continue

        if WW_ActivateWindowReliably(hwnd) {
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
    global WW_focus_highlight_guis
    global WW_focus_highlight_duration_ms
    global WW_focus_highlight_thickness
    global WW_focus_highlight_overlap

    ; Refresh the session without destroying/recreating four HWNDs on every key.
    SetTimer WW_EndFocusNavigationSession, 0

    if !hwnd || !WinExist("ahk_id " hwnd) {
        WW_EndFocusNavigationSession()
        return
    }

    if !WW_GetVisibleWindowBounds(
        hwnd,
        &window_x,
        &window_y,
        &window_width,
        &window_height
    ) {
        WW_EndFocusNavigationSession()
        return
    }

    thickness := WW_focus_highlight_thickness
    overlap := WW_focus_highlight_overlap
    outside := thickness - overlap

    if window_width <= thickness * 2
        || window_height <= thickness * 2
    {
        WW_EndFocusNavigationSession()
        return
    }

    accent_color := WW_GetWindowsAccentHexColor()

    ; Keep most of the highlight outside the visible frame, but overlap the
    ; window slightly so Windows' frame/shadow boundary cannot leave a gap.
    border_rects := [
        [
            window_x - outside,
            window_y - outside,
            window_width + outside * 2,
            thickness
        ],
        [
            window_x - outside,
            window_y + window_height - overlap,
            window_width + outside * 2,
            thickness
        ],
        [
            window_x - outside,
            window_y,
            thickness,
            window_height
        ],
        [
            window_x + window_width - overlap,
            window_y,
            thickness,
            window_height
        ]
    ]

    try {
        if WW_focus_highlight_guis.Length != 4 {
            WW_ClearFocusHighlight(true)
            Loop 4 {
                highlight_gui := SuiteGui(
                    "+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000"
                )
                WW_focus_highlight_guis.Push(highlight_gui)
            }
        }

        for index, rect in border_rects {
            highlight_gui := WW_focus_highlight_guis[index]
            if highlight_gui.BackColor != accent_color
                highlight_gui.BackColor := accent_color
            highlight_gui.Show(
                "NA x" rect[1] " y" rect[2] " w" rect[3] " h" rect[4]
            )
        }
    }
    catch Error as err {
        ; A partial outline must not remain topmost after a GUI failure.
        WW_ClearFocusHighlight(true)
        WW_EndFocusNavigationSession()
        WW_DebugError("Show focus highlight", err)
        return
    }

    SetTimer(
        WW_EndFocusNavigationSession,
        -WW_focus_highlight_duration_ms
    )
}

WW_EndFocusNavigationSession()
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    ; An expiring timer must not resume halfway through hiding a newly reused
    ; outline after a directional hotkey refreshes the session.
    previous_critical := A_IsCritical
    Critical "On"
    try {
        SetTimer WW_EndFocusNavigationSession, 0
        WW_focus_navigation_active := false
        WW_focus_navigation_hwnd := 0
        WW_ClearFocusHighlight()
    }
    finally {
        Critical previous_critical
    }
}

WW_ClearFocusHighlight(destroy := false)
{
    global WW_focus_highlight_guis

    for highlight_gui in WW_focus_highlight_guis {
        if destroy {
            try highlight_gui.Destroy()
        } else {
            try highlight_gui.Hide()
        }
    }

    if destroy
        WW_focus_highlight_guis := []
}

; =============================================================================
; Windows accent color
; =============================================================================

WW_GetWindowsAccentHexColor()
{
    colorization_color := 0
    opaque_blend := 0

    result := DllCall(
        "dwmapi\DwmGetColorizationColor",
        "uint*", &colorization_color,
        "int*", &opaque_blend,
        "int"
    )

    if result != 0
        return "0078D4"

    red := (colorization_color >> 16) & 0xFF
    green := (colorization_color >> 8) & 0xFF
    blue := colorization_color & 0xFF

    return Format(
        "{:02X}{:02X}{:02X}",
        red,
        green,
        blue
    )
}
