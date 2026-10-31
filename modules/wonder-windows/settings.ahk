; Wonder Windows runtime state. Every name assigned here is a global shared by
; the Wonder Windows files.
WW_InitializeState() {
    global

; =============================================================================
; defaults and shared state
; =============================================================================

WW_minimized_stack := []  ; windows minimized with Win + Backspace, newest first: {hwnd, pid}
WW_minimized_all := Map()  ; per display device, windows minimized with Win + M, front to back: {hwnd, pid}
WW_stretched_windows := Map()
WW_logical_zones := Map()
WW_layout_cycle_windows := Map()
WW_normal_window_placements := Map()

WW_maximized_fullscreen_cycle := []  ; every display's big windows in their cycle order
WW_last_maximized_fullscreen_hwnd := 0  ; the big window the cycle showed last

WW_monitor_cycle := []
WW_monitor_cycle_refused_hwnd := 0  ; the last target that refused activation
WW_monitor_cycle_refused_from := 0  ; the window it was requested from


WW_zone_cycle := 0
WW_zone_cycle_unit := "fourths"

WW_fancyzones_process_id := 0
}
