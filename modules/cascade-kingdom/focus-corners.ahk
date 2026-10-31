; Cascade Kingdom focus tabs: updates, placement, lifetime and visibility.
; Each exposed window has a tab outside its left edge at the bottom and one
; outside its right edge at the top, mirrored. The highest slot's left tab and
; the lowest slot's right tab run along the whole side. A mirrored cascade
; swaps all of it left for right.

; =============================================================================
; overlay updates
; =============================================================================

QueueFocusCornerUpdate()
{
    if !IsCascadeEnabled()
        return

    if CascadeState.focusCornerUpdatePending
        return

    CascadeState.focusCornerUpdatePending := true

    SetTimer(RunQueuedFocusCornerUpdate, -CascadeState.focusCornerUpdateMs)
}

RunQueuedFocusCornerUpdate()
{
    CascadeState.focusCornerUpdatePending := false
    UpdateFocusCornerOverlays()
}

UpdateFocusCornerOverlays()
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return

    static update_generation := 0

    generation := ++update_generation
    click_generation := CascadeState.focusTabClickGeneration
    drag_generation := CascadeState.dragGeneration
    membership_generation := CascadeState.membershipGeneration
    active_hwnd := DllCall("GetForegroundWindow", "ptr")

    ; Geometry reads stay interruptible. Never mutate membership while rendering.
    live_windows := GetCascadeWindowsForOverlay()
    live_targets := live_windows
    visible_bounds := Map()
    slot_stacks := []
    stacks_by_slot := Map()
    geometry_by_monitor := Map()
    dpi_by_monitor := Map()
    highest_hwnd_by_monitor := Map()
    highest_y_by_monitor := Map()
    lowest_hwnd_by_monitor := Map()
    lowest_y_by_monitor := Map()

    for hwnd, managed_monitor in live_windows {

        if !IsCascadeWindowShown(hwnd)
            continue

        if !GetVisibleWindowBounds(hwnd, &window_x, &window_y, &window_width, &window_height) {
            continue
        }

        monitor_index := WindowMonitorIndex(hwnd)
        if !monitor_index || monitor_index != managed_monitor
            continue
        if !geometry_by_monitor.Has(monitor_index) {
            if CascadeMonitorNeedsRefresh(monitor_index)
                return
            geometry_by_monitor[monitor_index] := GetCanonicalCascadeGeometry(monitor_index)
            dpi_by_monitor[monitor_index] := GetCascadeMonitorDpi(monitor_index)
        }
        slot_index := FindNearestCascadeSlot(window_x, window_y,
            geometry_by_monitor[monitor_index].slots, CascadeState.slotTolerance)
        if !slot_index
            continue

        ; Use the same observed rectangle for membership, grouping and painting.
        stack_key := monitor_index ":" slot_index
        if !stacks_by_slot.Has(stack_key) {
            stack_info := Map("slot_index", slot_index, "windows", [])
            stacks_by_slot[stack_key] := stack_info
            slot_stacks.Push(stack_info)
        }
        stacks_by_slot[stack_key]["windows"].Push(hwnd)
        visible_bounds[hwnd] := [window_x, window_y, window_width, window_height, monitor_index]

        if !highest_hwnd_by_monitor.Has(monitor_index)
            || window_y < highest_y_by_monitor[monitor_index]
        {
            highest_hwnd_by_monitor[monitor_index] := hwnd
            highest_y_by_monitor[monitor_index] := window_y
        }
        if !lowest_hwnd_by_monitor.Has(monitor_index)
            || window_y > lowest_y_by_monitor[monitor_index]
        {
            lowest_hwnd_by_monitor[monitor_index] := hwnd
            lowest_y_by_monitor[monitor_index] := window_y
        }
    }

    ; No visible slot means no need to enumerate every desktop window for Z-order.
    z_ranks := slot_stacks.Length ? GetCascadeWindowZRanks() : Map()

    ; Keep the hide/show handoff together, but do not lock the geometry queries.
    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; A newer refresh or tab press may have changed the stack during queries.
        if !IsCascadeEnabled() || IsCascadeDisplayTransition() || generation != update_generation
            return
        if active_hwnd != DllCall("GetForegroundWindow", "ptr")
            || click_generation != CascadeState.focusTabClickGeneration
            || drag_generation != CascadeState.dragGeneration
            || membership_generation != CascadeState.membershipGeneration
        {
            QueueFocusCornerUpdate()
            return
        }

        selected_targets := Map()
        active_slot_targets := Map()

        for stack_info in slot_stacks {
            ordered_windows := SortCascadeWindowsByZOrder(stack_info["windows"], z_ranks)
            selected_hwnd := SelectFocusCornerSlotTarget(ordered_windows, active_hwnd)
            contains_active := false
            sides := {left: false, right: false}

            for hwnd in ordered_windows {
                if hwnd = active_hwnd
                    contains_active := true

                monitor_index := visible_bounds[hwnd][5]
                if highest_hwnd_by_monitor[monitor_index] = hwnd
                    sides.%CascadeState.mirrored ? "right" : "left"% := true
                if lowest_hwnd_by_monitor[monitor_index] = hwnd
                    sides.%CascadeState.mirrored ? "left" : "right"% := true
            }

            if contains_active {
                for hwnd in ordered_windows
                    active_slot_targets[hwnd] := true
            }

            ; A full-height left tab belongs to the highest slot and a full-height
            ; right tab to the lowest, mirrored when the cascade is, not to one
            ; particular layer.
            if selected_hwnd
                selected_targets[selected_hwnd] := sides
        }

        stale_targets := []

        ; Hide every old representative before showing any replacement.
        ; Cached per-window GUIs stay reusable without stacking visible pixels.
        for hwnd, overlay in CascadeState.focusCornerOverlays {
            if !live_targets.Has(hwnd)
                stale_targets.Push(hwnd)
            else if !selected_targets.Has(hwnd)
                HideFocusCornerOverlay(hwnd)
        }

        for hwnd in stale_targets
            DestroyFocusCornerOverlay(hwnd)

        for hwnd, sides in selected_targets {
            if hwnd = active_hwnd || !WinExist("ahk_id " hwnd)
                continue

            bounds := visible_bounds[hwnd]
            try {
                ShowFocusCornerOverlay(hwnd, bounds[1], bounds[2], bounds[3], bounds[4],
                    dpi_by_monitor[bounds[5]], sides.left, sides.right, active_slot_targets.Has(hwnd))
            }
            catch Error as err {
                ; Closing targets must not interrupt updates for the other slots.
                DebugError("ShowFocusCornerOverlay", err)
            }
        }
    }
    finally {
        Critical(previous_critical)
    }

    ; External applications can still change foreground focus during rendering.
    if active_hwnd != DllCall("GetForegroundWindow", "ptr")
        QueueFocusCornerUpdate()
}

GetCascadeWindowsForOverlay()
{
    windows := Map()
    ; Keep minimized members' GUIs cached; the rendering pass hides them.
    ; Geometry is read once there, not again in this membership-only snapshot.
    for monitor_index, history in CascadeState.history.Clone() {
        for hwnd in history.Clone() {
            if DllCall("IsWindow", "ptr", hwnd, "int") && !IsCascadeWindowBeingDragged(hwnd)
                windows[hwnd] := monitor_index
        }
    }
    return windows
}

SelectFocusCornerSlotTarget(ordered_windows, active_hwnd)
{
    if !ordered_windows.Length
        return 0

    ; Inactive slot: always expose the actual front window.
    if ordered_windows[1] != active_hwnd
        return ordered_windows[1]

    ; Active slot: offer the next layer only within the foreground window's
    ; topmost/normal Z-order band. Crossing bands would change app topmost state.
    active_is_topmost := IsCascadeWindowTopmost(active_hwnd)
    if active_is_topmost < 0
        return 0

    Loop ordered_windows.Length - 1 {
        hwnd := ordered_windows[A_Index + 1]
        window_is_topmost := IsCascadeWindowTopmost(hwnd)
        if window_is_topmost < 0
            return 0
        if window_is_topmost = active_is_topmost
            return hwnd
    }

    return 0
}


; =============================================================================
; overlay placement and lifetime
; =============================================================================

; A window's two edge tabs: one outside its left edge at the bottom, one outside
; its right edge at the top, or the other way round in a mirrored cascade.
; full_left and full_right run a tab along that side.
ShowFocusCornerOverlay(hwnd, window_x, window_y, window_width, window_height, dpi,
    full_left := false, full_right := false, active_slot := false)
{
    if !IsCascadeEnabled()
        return

    marker_color := active_slot ? SuiteAccentColor() : CascadeState.focusCornerInactiveSlotColor
    marker_alpha := (active_slot ? CascadeState.focusCornerActiveSlotAlpha : CascadeState.focusCornerInactiveSlotAlpha
    )

    if !CascadeState.focusCornerOverlays.Has(hwnd)
        CreateFocusCornerOverlay(hwnd, marker_color, marker_alpha)

    overlay := CascadeState.focusCornerOverlays[hwnd]
    appearance_changed := (overlay.color != marker_color || overlay.alpha != marker_alpha)

    if overlay.color != marker_color {
        for marker_gui in overlay.guis
            marker_gui.BackColor := marker_color
        overlay.color := marker_color
    }

    overlay.alpha := marker_alpha
    ; Reuse the pass's validated monitor DPI instead of enumerating displays here.

    if (overlay.shown && overlay.window_x = window_x && overlay.window_y = window_y
        && overlay.window_width = window_width && overlay.window_height = window_height
        && overlay.full_left = full_left && overlay.full_right = full_right && overlay.dpi = dpi
        && overlay.mirrored = CascadeState.mirrored) {
        SetFocusCornerOpacity(overlay, CascadeState.focusCornerVisible ? marker_alpha : 1)
        if appearance_changed
            for marker_gui in overlay.guis
                WinRedraw(marker_gui.Hwnd)

        PlaceFocusCornerAboveTarget(hwnd, overlay)
        return
    }

    ShowFocusCornerTab(overlay.guis[1], false, full_left, window_x, window_y, window_width, window_height, dpi)
    ShowFocusCornerTab(overlay.guis[2], true, full_right, window_x, window_y, window_width, window_height, dpi)

    SetFocusCornerOpacity(overlay, CascadeState.focusCornerVisible ? marker_alpha : 1)

    ; A reused hidden GUI can have a new BackColor but an old painted surface.
    ; Repaint after showing it; changing alpha alone does not repaint its pixels.
    for marker_gui in overlay.guis
        WinRedraw(marker_gui.Hwnd)
    PlaceFocusCornerAboveTarget(hwnd, overlay)

    overlay.window_x := window_x
    overlay.window_y := window_y
    overlay.window_width := window_width
    overlay.window_height := window_height
    overlay.full_left := full_left
    overlay.full_right := full_right
    overlay.mirrored := CascadeState.mirrored
    overlay.dpi := dpi
    overlay.shown := true
}

; One edge tab, mirrored on the right: the left tab sits at the bottom, the
; right one at the top, swapped in a mirrored cascade, and a full tab runs
; along the whole side.
ShowFocusCornerTab(marker_gui, right_side, full, window_x, window_y, window_width, window_height, dpi)
{
    ; Scale UI dimensions only. DWM positions and full-height bounds are pixels.
    tab_width := full ? CascadeState.focusCornerFullHeightThickness : CascadeState.focusCornerThickness
    thickness := Max(1, ScaleForDpi(tab_width, dpi))
    overlap := Min(thickness - 1, Max(0, ScaleForDpi(CascadeState.focusCornerOverlap, dpi)))
    marker_height := full ? window_height : Max(1, ScaleForDpi(CascadeState.focusCornerSize, dpi))
    at_top := right_side != CascadeState.mirrored
    marker_x := right_side ? window_x + window_width - overlap : window_x - thickness + overlap
    marker_y := full || at_top ? window_y : window_y + window_height - marker_height

    ShowPhysicalGui(marker_gui,
        "NA"
        . " x" marker_x
        . " y" marker_y
        . " w" thickness
        . " h" marker_height
    )

    ; Trim the outer edge and the end at the window's corner, plus both ends
    ; on full-height tabs.
    trim_top := full || at_top
    trim_bottom := full || !at_top
    WinSetRegion((right_side ? 0 : 1) "-" (trim_top ? 1 : 0) " W" (thickness - 1)
        " H" (marker_height - trim_top - trim_bottom), marker_gui.Hwnd)
}

PlaceFocusCornerAboveTarget(hwnd, overlay)
{
    ; The target precedes its edge tabs in the existing Z-order convention:
    ; the target, then its left tab, then its right tab.
    if !WinExist("ahk_id " hwnd)
        return
    previous := hwnd
    for marker_gui in overlay.guis {
        if DllCall("GetWindow", "ptr", marker_gui.Hwnd, "uint", 3, "ptr") != previous
            SetCascadeZOrder(marker_gui.Hwnd, previous)
        previous := marker_gui.Hwnd
    }
}

HideFocusCornerOverlay(hwnd)
{
    if !CascadeState.focusCornerOverlays.Has(hwnd)
        return

    overlay := CascadeState.focusCornerOverlays[hwnd]

    if !overlay.shown
        return

    for marker_gui in overlay.guis
        try marker_gui.Hide()

    overlay.shown := false
}

CreateFocusCornerOverlay(hwnd, marker_color, marker_alpha)
{
    ; Only these borderless, control-free GUIs are per-monitor aware. The help
    ; window retains normal AHK scaling. Both creation and movement need PM context.
    guis := []
    loop 2 {
        marker_gui := CreatePhysicalGui("-Caption -DPIScale" . " +ToolWindow" . " +E0x08000000",
            "Cascade Kingdom Focus Marker")
        marker_gui.BackColor := marker_color
        CascadeState.focusCornerTargets[marker_gui.Hwnd] := hwnd
        guis.Push(marker_gui)
    }

    ; guis holds the left tab, then the right one.
    CascadeState.focusCornerOverlays[hwnd] := {
        guis: guis,
        color: marker_color,
        alpha: marker_alpha,
        native_alpha: -1,
        shown: false,
        window_x: 0,
        window_y: 0,
        window_width: 0,
        window_height: 0,
        full_left: false,
        full_right: false,
        mirrored: false,
        dpi: 0
    }
}

DestroyFocusCornerOverlay(hwnd)
{
    if !CascadeState.focusCornerOverlays.Has(hwnd)
        return

    overlay := CascadeState.focusCornerOverlays[hwnd]
    CascadeState.focusCornerOverlays.Delete(hwnd)

    for marker_gui in overlay.guis {
        overlay_hwnd := marker_gui.Hwnd
        try marker_gui.Destroy()
        if CascadeState.focusCornerTargets.Has(overlay_hwnd)
            CascadeState.focusCornerTargets.Delete(overlay_hwnd)
    }
}


; =============================================================================
; visibility
; =============================================================================

ToggleFocusCornerVisibility(*)
{
    CascadeState.focusCornerVisible := !CascadeState.focusCornerVisible

    for hwnd, overlay in CascadeState.focusCornerOverlays {
        transparency := CascadeState.focusCornerVisible ? overlay.alpha : 1

        try SetFocusCornerOpacity(overlay, transparency)
    }
}


SetFocusCornerOpacity(overlay, alpha)
{
    ; Clicks no longer override alpha. Avoid repainting unchanged native state.
    ; Update the cache only after Windows accepts the change.
    if overlay.native_alpha = alpha
        return
    for marker_gui in overlay.guis
        WinSetTransparent(alpha, marker_gui.Hwnd)
    overlay.native_alpha := alpha
}
