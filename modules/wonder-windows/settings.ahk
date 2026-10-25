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
WW_horizontal_stretch_windows := Map()
WW_vertical_stretch_windows := Map()
WW_full_stretch_windows := Map()
WW_swap_zones := Map()
WW_layout_cycle_windows := Map()
WW_center_tile_next_sides := Map()
WW_normal_window_placements := Map()

WW_maximized_fullscreen_cycle := []
WW_last_maximized_fullscreen_hwnd := 0

WW_focus_navigation_active := false
WW_focus_navigation_hwnd := 0

WW_zone_cycle := 0
WW_zone_cycle_unit := "fourths"

WW_fancyzones_process_id := 0
}
