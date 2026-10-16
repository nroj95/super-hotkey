WW_InitializeState() {
    global
; Internal Win Key Overhaul module; initialized once by the root launcher.
; Keep assignments at top level to preserve the existing global scope.

; =============================================================================
; defaults and shared state
; =============================================================================

WW_last_minimized_hwnd := 0
WW_isolation_minimized_windows := []
WW_isolation_active_hwnd := 0
WW_all_minimized_windows := []
WW_all_active_hwnd := 0
WW_borderless_windows := Map()
WW_switcher_demoted_borderless_windows := Map()
WW_horizontal_stretch_windows := Map()
WW_vertical_stretch_windows := Map()
WW_full_stretch_windows := Map()
WW_swap_zones := Map()
WW_layout_cycle_windows := Map()
WW_center_tile_next_sides := Map()
WW_normal_window_placements := Map()

WW_maximized_fullscreen_cycle := []
WW_last_maximized_fullscreen_hwnd := 0

WW_focus_highlight_guis := []
WW_focus_highlight_duration_ms := 1500
WW_focus_highlight_thickness := 12
WW_focus_highlight_overlap := 2
WW_focus_navigation_active := false
WW_focus_navigation_hwnd := 0

WW_screengrid_releases_url := "https://github.com/TtesseractT/ScreenGrid/releases/latest"
WW_fancyzones_process_id := 0
WW_fancyzones_integration_state := false
WW_fancyzones_check_in_progress := false


; =============================================================================
; debug settings
; =============================================================================


}
