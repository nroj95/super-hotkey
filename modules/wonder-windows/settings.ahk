; Wonder Windows runtime state. Every name assigned here is a global shared by
; the Wonder Windows files.
WW_InitializeState() {
    global

; =============================================================================
; defaults and shared state
; =============================================================================

WW_minimized_stack := []  ; windows minimized with Win + Backspace, newest first: {hwnd, pid}
WW_minimized_all := Map()  ; per display device, windows minimized with Win + M, Win + Home or Win + D, front to back: {hwnd, pid}
WW_full_height_windows := Map()  ; Win + Alt + Enter: per window, the way back
WW_logical_zones := Map()
WW_layout_cycle_windows := Map()
WW_normal_window_placements := Map()

WW_maximized_fullscreen_cycle := []  ; every display's big windows in their cycle order
WW_last_maximized_fullscreen_hwnd := 0  ; the big window the cycle showed last

WW_monitor_cycle := []
WW_monitor_cycle_refused_hwnd := 0  ; the last target that refused activation
WW_monitor_cycle_refused_from := 0  ; the window it was requested from


WW_zone_cycle := 0  ; zone mode: {hwnd, pid, work_area, x0, x1, y0, y1, resized, loose} while it runs
; Zone mode's stop pairs along a display's long and short side; Settings may change them.
WW_zone_stops := Map("long", Map("sixths", false, "fourths", true, "thirds", true),
    "short", Map("sixths", false, "fourths", false, "thirds", true))

WW_fancyzones_process_id := 0
}
