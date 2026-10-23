; Cascade Kingdom implementation; included by the Super Hotkey launcher.
; Included into the same script; functions share the existing global state.

; =============================================================================
; debug logging
; =============================================================================

DebugLog(message) => SuiteState.Log.Debug("Cascade Kingdom", message)

; =============================================================================
; error reporting and window diagnostics
; =============================================================================

DebugError(context, failure) {
    SuiteState.Log.Error("Cascade Kingdom / " context, failure)
}

DebugDescribeWindow(hwnd)
{
    if !SuiteState.Log.verbose
        return "hwnd=" hwnd

    if !hwnd
        return "hwnd=0"

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"

    title := ""
    class_name := ""
    process_name := ""
    min_max := "?"
    x := "?"
    y := "?"
    width := "?"
    height := "?"

    try title := WinGetTitle("ahk_id " hwnd)
    try class_name := WinGetClass("ahk_id " hwnd)
    try process_name := WinGetProcessName("ahk_id " hwnd)
    try min_max := WinGetMinMax("ahk_id " hwnd)

    try {
        WinGetPosPixels(&window_x, &window_y, &window_width, &window_height, "ahk_id " hwnd)

        x := window_x
        y := window_y
        width := window_width
        height := window_height
    }

    title := StrReplace(
        StrReplace(title, "`r", " "),
        "`n",
        " "
    )

    visible := DllCall("IsWindowVisible", "ptr", hwnd, "int")

    iconic := DllCall("IsIconic", "ptr", hwnd, "int")

    cloaked := false
    try cloaked := IsWindowCloaked(hwnd)

    return ("hwnd=" hwnd . ' exe="' process_name '"' . ' class="' class_name '"'
        . ' title="' title '"' . " minmax=" min_max . " visible=" visible . " iconic=" iconic
        . " cloaked=" cloaked . " rect=(" x "," y . " " width "x" height ")")
}


; =============================================================================
; focus-tab appearance diagnostics
; =============================================================================

DebugFocusCornerAppearance(active_hwnd, active_slot_targets)
{
    global focus_corner_overlays, focus_corner_visible
    static previous_snapshot := ""

    if !SuiteState.Log.verbose
        return

    snapshot := ("active=" active_hwnd . " | foreground_now=" DllCall("GetForegroundWindow", "ptr")
        . " | active_slot_windows=" active_slot_targets.Count
        . " | tabs_visible=" focus_corner_visible . " | click_owned=" HasFocusTabClick())

    for target_hwnd, overlay in focus_corner_overlays {
        try {
            marker_hwnd := overlay.gui.Hwnd
            native_visible := DllCall("IsWindowVisible", "ptr", marker_hwnd, "int")

            if !overlay.shown && !native_visible
                continue

            ; Read native state, not just the cached intended opacity. Pure HWNDs
            ; also let diagnostics inspect a GUI during a hide/show transition.
            native_alpha := WinGetTransparent(marker_hwnd)
            native_topmost := !!(WinGetExStyle(marker_hwnd) & 0x8)
            WinGetPosPixels(&x, &y, &width, &height, marker_hwnd)
            preceding_hwnd := DllCall("GetWindow", "ptr", marker_hwnd, "uint", 3, "ptr") ; GW_HWNDPREV

            role := active_slot_targets.Has(target_hwnd) ? "active-slot" : "inactive-slot"

            snapshot .= (" | tab={target=" target_hwnd . ",hwnd=" marker_hwnd . ",role=" role
                . ",color=" overlay.gui.BackColor . ",dpi=" overlay.dpi
                . ",base_alpha=" overlay.alpha
                . ",native_alpha=" (native_alpha == "" ? "unknown" : native_alpha)
                . ",shown=" overlay.shown . ",visible=" native_visible . ",topmost=" native_topmost
                . ",above=" preceding_hwnd . ",rect=" x "," y "," width "," height "}")
        }
        catch {
            ; A target or its GUI may disappear during a diagnostic read.
            continue
        }
    }

    ; The fallback timer may read often, but unchanged state must not flood logs.
    if snapshot = previous_snapshot
        return

    previous_snapshot := snapshot
    DebugLog("Focus-tab appearance. | " snapshot)
}


DebugDescribeForegroundState()
{
    if !SuiteState.Log.verbose
        return ""

    ; Foreground, thread activation and keyboard focus are different handles.
    ; Capture them only for launch-recovery diagnostics, never on every repaint.
    info := Buffer(24 + 6 * A_PtrSize, 0)
    NumPut("uint", info.Size, info)

    foreground := DllCall("GetForegroundWindow", "ptr")
    result := ("foreground=" foreground . " | foreground-pid=" WindowProcessId(foreground))

    if DllCall("GetGUIThreadInfo", "uint", 0, "ptr", info, "int") {
        thread_active := NumGet(info, 8, "ptr")
        keyboard_focus := NumGet(info, 8 + A_PtrSize, "ptr")
        keyboard_focus_root := (
            keyboard_focus
            ? DllCall("GetAncestor", "ptr", keyboard_focus, "uint", 2, "ptr") ; GA_ROOT
            : 0
        )

        result .= (" | thread-active=" thread_active . " | keyboard-focus=" keyboard_focus
            . " | keyboard-focus-root=" keyboard_focus_root
            . " | keyboard-focus-pid=" WindowProcessId(keyboard_focus)
            . " | focus-root-is-foreground=" (keyboard_focus_root = foreground))
    }

    return result
}
