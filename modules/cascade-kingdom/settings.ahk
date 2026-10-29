; Cascade Kingdom tuning constants, saved preferences and runtime state.
; Every name assigned here is a global shared by the Cascade Kingdom files.
InitializeCascadeState()
{
    global

; =============================================================================
; settings
; =============================================================================

; Cascade windows use a predictable generic size instead of an app's remembered size.
window_width_ratio := 0.80
window_height_ratio := 0.80

; First branch moves left/up from center; second branch moves right/down.
cascade_x := 28
cascade_y := 24

; One tolerance for slot membership and mouse drops (screen-coordinate pixels).
; During a native drag, the original slot is retained. On release, the visible
; top-left must be within this distance on both axes; the closest slot wins.
cascade_slot_tolerance := 56

; Restore requests can finish before their native/DWM rectangles settle.
; Poll only during restores; a failed restore must not lock compaction forever.
cascade_restore_poll_ms := 50
cascade_restore_settle_ms := 200
cascade_restore_timeout_ms := 5000

; A cancelled/ignored close must not defer this monitor's compaction forever.
; This only expires bookkeeping; it never forces a window to close.
cascade_close_timeout_ms := 5000

; Keep one late safety check in case an application changes geometry again.
placement_stabilize_delays_ms := [500]
placement_stabilize_tolerance := 6

; A busy window may not process an asynchronous placement immediately.
; Keep its slot reserved while retrying without blocking Cascade Kingdom.
placement_stabilize_retry_ms := 500
placement_stabilize_retry_limit := 20
; A final confirmation is bounded too; never poll a failed placement forever.
placement_stabilize_confirmation_ms := 2000
placement_stabilize_confirmation_limit := 3

; If an application overrides a Cascade placement, give it time to finish
; managing its own geometry before posting another corrective move.
placement_stabilize_backoff_delays_ms := [1000, 2000, 4000]

; If Windows stops reporting native move-loop state after mouse release, abandon
; the snap decision instead of leaving the cascade permanently locked in a drag.
cascade_drag_unknown_release_timeout_ms := 500

edge_margin := 12
minimum_width := 320
minimum_height := 220

; Focus-tab dimensions are 96-DPI UI units; only these are scaled per monitor.
; Slot spacing, drop tolerance, and cascade rectangles remain physical pixels.
focus_corner_size := 24
focus_corner_thickness := 54
focus_corner_full_height_thickness := 36
focus_corner_overlap := 2
; Coalesce event-driven focus-tab updates. The slow timer below is only a
; fallback for Windows events that may occasionally be missed.
focus_corner_update_ms := 50
focus_corner_fallback_ms := 1000

; Focus-tab colors are chosen from a small fixed palette. An inactive slot
; represents its exposed window; the active slot represents the next layer.
; Deeper tabs stay hidden, so opacity no longer accumulates with stack depth.
focus_tab_color_presets := Map("White", "FFFFFF", "Grey", "808080", "Red", "F44336",
    "Orange", "FF9800", "Yellow", "FBC02D", "Green", "4CAF50", "Cyan", "00BCD4", "Blue", "2196F3",
    "Purple", "9C27B0", "Pink", "E91E63")

; Inactive-slot tabs stay faint while active-slot tabs use stronger opacity.
; Alpha 1 is reserved for the hidden state so overlays remain hit-testable.
focus_corner_visible := true
focus_corner_inactive_slot_alpha := 128
focus_corner_active_slot_alpha := 255

; Only watch for a missed mouse-up while a focus-tab click owns the button.
focus_tab_release_poll_ms := 50

settings_path := SuiteState.App.Settings.directory "\cascade-kingdom\settings.ini"
focus_corner_visible := IniRead(settings_path, "FocusTabs", "Visible", "1") = "1"

focus_corner_active_slot_color_name := IniRead(settings_path, "FocusTabs", "ActiveSlotColor",
    "Yellow")
focus_corner_inactive_slot_color_name := IniRead(settings_path, "FocusTabs", "InactiveSlotColor",
    "White")

if !focus_tab_color_presets.Has(focus_corner_active_slot_color_name)
    focus_corner_active_slot_color_name := "Yellow"

if !focus_tab_color_presets.Has(focus_corner_inactive_slot_color_name)
    focus_corner_inactive_slot_color_name := "White"

focus_corner_active_slot_color :=
    focus_tab_color_presets[focus_corner_active_slot_color_name]
focus_corner_inactive_slot_color :=
    focus_tab_color_presets[focus_corner_inactive_slot_color_name]

; =============================================================================
; runtime state
; =============================================================================

cascade_command_queue := []
cascade_command_draining := false

placement_reservations := Map()
placement_stabilization_generations := Map()
placement_dpi_generations := Map()
placement_stabilization_generation_counter := 0
pending_adoption_undo := 0
cascade_poll_ms := 1000
cascade_history := Map()
; A display snapshot is refreshed by notifications and the existing slow fallback.
; Logical slots survive transient geometry/display changes; they are not reload persistence.
cascade_displays := Map()
cascade_dpi_probes := Map()
cascade_display_signature := ""
cascade_display_change_pending := false
cascade_display_refreshing := false
cascade_display_generation := 0
cascade_display_refresh_delay_ms := 250
cascade_window_slots := Map()
cascade_display_reflow := Map()
cascade_membership_generation := 0
cascade_minimized_observed := Map()
cascade_mouse_press := 0
cascade_window_drag := 0
cascade_drag_generation := 0
cascade_compaction_pending := Map()
cascade_compaction_timer_pending := false
cascade_restore_batches := Map()
cascade_restore_request_depth := 0
cascade_close_batches := Map()
cascade_target_display := IniRead(settings_path, "Controls", "Display", "All")
cascade_drop_guide_color_name := IniRead(settings_path, "DropGuides", "Color", "Pink")
if !focus_tab_color_presets.Has(cascade_drop_guide_color_name)
    cascade_drop_guide_color_name := "Pink"
cascade_minimize_toggle_in_progress := false
cascade_minimized_windows := []

focus_corner_overlays := Map()
focus_corner_targets := Map()
focus_corner_update_pending := false
focus_tab_pending_press := 0
focus_tab_click := 0
focus_tab_click_generation := 0

current_foreground_hwnd := WinExist("A")

win_event_callback := 0
foreground_hook := 0
window_show_hook := 0
window_destroy_hook := 0
window_move_size_hook := 0
window_restore_hook := 0
}
