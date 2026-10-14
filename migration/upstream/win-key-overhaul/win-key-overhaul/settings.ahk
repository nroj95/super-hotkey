; Internal Win Key Overhaul module; initialized once by the root launcher.
; Keep assignments at top level to preserve the existing global scope.

; =============================================================================
; defaults and shared state
; =============================================================================

last_minimized_hwnd := 0
isolation_minimized_windows := []
isolation_active_hwnd := 0
all_minimized_windows := []
all_active_hwnd := 0
borderless_windows := Map()
switcher_demoted_borderless_windows := Map()
horizontal_stretch_windows := Map()
vertical_stretch_windows := Map()
layout_cycle_windows := Map()
center_tile_next_sides := Map()
normal_window_placements := Map()

maximized_fullscreen_cycle := []
last_maximized_fullscreen_hwnd := 0

focus_highlight_guis := []
focus_highlight_duration_ms := 1500
focus_highlight_thickness := 12
focus_highlight_overlap := 2
focus_navigation_active := false
focus_navigation_hwnd := 0

startup_shortcut_path := A_Startup "\Win Key Overhaul.lnk"
previous_startup_shortcut_paths := [
    A_Startup "\Windows Key Overhaul.lnk",
    A_Startup "\Window Hotkeys.lnk"
]
user_preferences_directory := A_AppData "\WinKeyOverhaul"
user_preferences_path := user_preferences_directory "\preferences.ini"
previous_user_preferences_path := A_AppData "\WindowsKeyOverhaul\preferences.ini"
screengrid_releases_url := "https://github.com/TtesseractT/ScreenGrid/releases/latest"
fancyzones_process_id := 0
fancyzones_integration_state := false
fancyzones_check_in_progress := false


; =============================================================================
; debug settings
; =============================================================================

debug_enabled := false
debug_data_directory := EnvGet("LOCALAPPDATA") "\WinKeyOverhaul"
debug_log_path := debug_data_directory "\win-key-overhaul-debug.log"
