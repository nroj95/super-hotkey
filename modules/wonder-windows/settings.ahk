; Wonder Windows runtime state. Every name assigned here is a global shared by
; the Wonder Windows files.
WW_InitializeState() {
    global

; =============================================================================
; defaults and shared state
; =============================================================================

WW_last_minimized_hwnd := 0
WW_isolation_minimized_windows := []
WW_isolation_active_hwnd := 0
WW_all_minimized_windows := []
WW_all_active_hwnd := 0
WW_stretched_windows := Map()
WW_logical_zones := Map()
WW_layout_cycle_windows := Map()
WW_normal_window_placements := Map()

WW_monitor_cycle := []
WW_monitor_cycle_refused_hwnd := 0  ; the last target that refused activation
WW_monitor_cycle_refused_from := 0  ; the window it was requested from

WW_focus_navigation_active := false
WW_focus_navigation_hwnd := 0

WW_zone_cycle := 0
WW_zone_cycle_unit := "fourths"

WW_fancyzones_process_id := 0
}
