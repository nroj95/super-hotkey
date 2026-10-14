; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; directional focus
; =============================================================================

FocusNearestWindow(direction)
{
    global focus_navigation_active, focus_navigation_hwnd

    active_hwnd := WinExist("A")

    if !active_hwnd
        return

    ; The first directional-focus press starts on the current window instead
    ; of immediately leaving it. A manual focus change also starts a new
    ; session from that newly focused window.
    if !focus_navigation_active
        || active_hwnd != focus_navigation_hwnd
    {
        ForgetLastMinimizedWindow()
        focus_navigation_active := true
        focus_navigation_hwnd := active_hwnd
        HighlightFocusedWindow(active_hwnd)
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

        if !IsWindowToggleCandidate(hwnd)
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

    ForgetLastMinimizedWindow()

    try {
        WinActivate("ahk_id " target_hwnd)
        focus_navigation_hwnd := target_hwnd
        HighlightFocusedWindow(target_hwnd)
    }
}

; =============================================================================
; focus after minimize
; =============================================================================

FocusAfterMinimize(minimized_hwnd)
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
            && IsWindowToggleCandidate(foreground_hwnd)
        {
            BeginSpatialFocus(foreground_hwnd)
            return
        }
    }

    ; If Windows left focus on the shell, activate the topmost eligible window
    ; on the current desktop. Cloaked/minimized/shell windows are filtered out.
    for hwnd in WinGetList() {
        if hwnd = minimized_hwnd
            continue

        if !IsWindowToggleCandidate(hwnd)
            continue

        if ActivateWindowReliably(hwnd) {
            BeginSpatialFocus(hwnd)
            return
        }
    }

    ; With no other eligible window, leave focus to the Windows shell/desktop.
    EndFocusNavigationSession()
}

BeginSpatialFocus(hwnd)
{
    global focus_navigation_active, focus_navigation_hwnd

    if !hwnd || !WinExist("ahk_id " hwnd) {
        EndFocusNavigationSession()
        return false
    }

    focus_navigation_active := true
    focus_navigation_hwnd := hwnd
    HighlightFocusedWindow(hwnd)
    return true
}

; =============================================================================
; focus highlight and session lifetime
; =============================================================================

HighlightFocusedWindow(hwnd)
{
    global focus_highlight_guis
    global focus_highlight_duration_ms
    global focus_highlight_thickness
    global focus_highlight_overlap

    ; Refresh the session without destroying/recreating four HWNDs on every key.
    SetTimer EndFocusNavigationSession, 0

    if !hwnd || !WinExist("ahk_id " hwnd) {
        EndFocusNavigationSession()
        return
    }

    if !GetVisibleWindowBounds(
        hwnd,
        &window_x,
        &window_y,
        &window_width,
        &window_height
    ) {
        EndFocusNavigationSession()
        return
    }

    thickness := focus_highlight_thickness
    overlap := focus_highlight_overlap
    outside := thickness - overlap

    if window_width <= thickness * 2
        || window_height <= thickness * 2
    {
        EndFocusNavigationSession()
        return
    }

    accent_color := GetWindowsAccentHexColor()

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
        if focus_highlight_guis.Length != 4 {
            ClearFocusHighlight(true)
            Loop 4 {
                highlight_gui := Gui(
                    "+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000"
                )
                focus_highlight_guis.Push(highlight_gui)
            }
        }

        for index, rect in border_rects {
            highlight_gui := focus_highlight_guis[index]
            if highlight_gui.BackColor != accent_color
                highlight_gui.BackColor := accent_color
            highlight_gui.Show(
                "NA x" rect[1] " y" rect[2] " w" rect[3] " h" rect[4]
            )
        }
    }
    catch Error as err {
        ; A partial outline must not remain topmost after a GUI failure.
        ClearFocusHighlight(true)
        EndFocusNavigationSession()
        DebugError("Show focus highlight", err)
        return
    }

    SetTimer(
        EndFocusNavigationSession,
        -focus_highlight_duration_ms
    )
}

EndFocusNavigationSession()
{
    global focus_navigation_active, focus_navigation_hwnd

    ; An expiring timer must not resume halfway through hiding a newly reused
    ; outline after a directional hotkey refreshes the session.
    previous_critical := A_IsCritical
    Critical "On"
    try {
        SetTimer EndFocusNavigationSession, 0
        focus_navigation_active := false
        focus_navigation_hwnd := 0
        ClearFocusHighlight()
    }
    finally {
        Critical previous_critical
    }
}

ClearFocusHighlight(destroy := false)
{
    global focus_highlight_guis

    for highlight_gui in focus_highlight_guis {
        if destroy {
            try highlight_gui.Destroy()
        } else {
            try highlight_gui.Hide()
        }
    }

    if destroy
        focus_highlight_guis := []
}

; =============================================================================
; Windows accent color
; =============================================================================

GetWindowsAccentHexColor()
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
