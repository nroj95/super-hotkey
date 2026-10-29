; Cascade Kingdom logging, and window and focus-tab diagnostics that run
; only with verbose logging.

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
