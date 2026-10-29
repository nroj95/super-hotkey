; Cascade Kingdom navigation: focusing, swapping and rotating windows and
; bringing a cascade forward.

; =============================================================================
; current-layer focus and swapping
; =============================================================================

FocusCascadeLayerWindow(direction)
{
    if !IsCascadeEnabled()
        return

    monitor_index := SuiteWorkingMonitor.Get()

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length = 0
        return

    active_hwnd := WinExist("A")
    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    if active_index {
        target_index := active_index + (direction < 0 ? -1 : 1)

        if target_index < 1
            target_index := ordered_windows.Length
        else if target_index > ordered_windows.Length
            target_index := 1

        ActivateWindow(ordered_windows[target_index])
        return
    }

    ; If focus is outside the exposed layer, enter at the nearest window
    ; physically above/below the active window.
    target_hwnd := GetNearestSpatialCascadeWindow(ordered_windows, active_hwnd, direction)

    if target_hwnd
        ActivateWindow(target_hwnd)
}

SwapActiveCascadeWindow(direction)
{
    if !IsCascadeEnabled()
        return

    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return

    monitor_index := WindowMonitorIndex(active_hwnd)

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length < 2
        return

    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    ; Only an exposed current-layer window can move between slots.
    if !active_index
        return

    target_index := active_index + (direction < 0 ? -1 : 1)

    if target_index < 1
        target_index := ordered_windows.Length
    else if target_index > ordered_windows.Length
        target_index := 1

    target_hwnd := ordered_windows[target_index]

    active_frame := GetWindowFrame(active_hwnd)
    target_frame := GetWindowFrame(target_hwnd)
    if !active_frame || !target_frame
        return

    ; Swap only the two exposed layer windows. Deeper windows remain in place.
    if !MoveCascadeWindowToSlot(target_hwnd, active_frame.x, active_frame.y)
        return

    if !MoveCascadeWindowToSlot(active_hwnd, target_frame.x, target_frame.y) {
        MoveCascadeWindowToSlot(target_hwnd, target_frame.x, target_frame.y)
        return
    }

    ; Keep both swapped windows above the deeper layers in their new slots,
    ; while preserving focus on the active window.
    ; Never force a topmost window behind a normal window. If either native
    ; state query fails, skip the relative Z-order mutation rather than guessing.
    target_topmost := IsCascadeWindowTopmost(target_hwnd)
    active_topmost := IsCascadeWindowTopmost(active_hwnd)
    if target_topmost >= 0 && active_topmost >= 0
        && target_topmost = active_topmost
    {
        try SetCascadeZOrder(target_hwnd, active_hwnd)
    }

    QueueFocusCornerUpdate()
}

MoveCascadeWindowToSlot(hwnd, target_x, target_y, post_asynchronously := false)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return false

    global placement_reservations, cascade_display_generation
    display_generation := cascade_display_generation

    ; A minimize can complete after planning but before this individual move.
    if IsCascadeWindowBeingDragged(hwnd) || !WinExist(hwnd)
        return false
    try {
        if WinGetMinMax(hwnd) != 0
            return false
    }
    catch {
        return false
    }
    if !(frame := GetWindowFrame(hwnd))
        return false

    if IsCascadeDisplayTransition() || display_generation != cascade_display_generation
        return false
    if frame.x = target_x && frame.y = target_y {
        RememberCascadeSlot(hwnd, GetManagedCascadeMonitor(hwnd), target_x, target_y)
        return true
    }

    ; Compaction must replace the previous stabilization destination, otherwise
    ; its delayed retry could pull a just-dropped window back to an old slot.
    CancelPlacementStabilization(hwnd)

    raw_target := [target_x - frame.left, target_y - frame.top, frame.rawWidth, frame.rawHeight]

    if !IsCascadeEnabled() || IsCascadeWindowBeingDragged(hwnd)
        || IsCascadeDisplayTransition() || display_generation != cascade_display_generation
        return false

    owned_reservation := Map("monitor", WindowMonitorIndex(hwnd), "x", target_x, "y", target_y)
    placement_reservations[hwnd] := owned_reservation
    stabilization_scheduled := false

    try {
        move_accepted := false
        if post_asynchronously {
            ; Compaction can post geometry changes because reservations and the
            ; stabilization watcher already represent in-flight destinations.
            move_accepted := PhysicalDllCall(
                "SetWindowPos",
                "ptr", hwnd,
                "ptr", 0,
                "int", raw_target[1],
                "int", raw_target[2],
                "int", raw_target[3],
                "int", raw_target[4],
                "uint", 0x4014, ; ASYNC | NOACTIVATE | NOZORDER
                "int"
            )
        } else {
            ; Swaps depend on ordered move/rollback semantics, so keep those
            ; explicit callers synchronous instead of introducing a new race.
            WinMovePixels(raw_target[1], raw_target[2], raw_target[3], raw_target[4], "ahk_id " hwnd
            )
            move_accepted := true
        }

        if !move_accepted
            return false

        if !IsCascadeEnabled() || IsCascadeDisplayTransition()
            || display_generation != cascade_display_generation
            || !placement_reservations.Has(hwnd)
            || placement_reservations[hwnd] != owned_reservation
            return false

        if !IsCascadeWindowBeingDragged(hwnd) {
            SchedulePlacementStabilization(hwnd, target_x, target_y, frame.width, frame.height)
            stabilization_scheduled := true
        }
        return true
    }
    catch {
        return false
    }
    finally {
        ; A cancelled/failed move must not leave compaction occupancy behind.
        ; Do not remove a newer request's reservation for a recycled HWND.
        if !stabilization_scheduled
            && placement_reservations.Has(hwnd)
            && placement_reservations[hwnd] = owned_reservation
        {
            placement_reservations.Delete(hwnd)
        }
    }
}


; =============================================================================
; slot and layer rotation
; =============================================================================

RotateCascadeSlotForWindow(target_hwnd, direction, expected_monitor := 0, expected_slot := 0)
{
    if !target_hwnd || !WinExist("ahk_id " target_hwnd)
        || IsShellSurfaceWindow(target_hwnd)
        return 0

    monitor_index := WindowMonitorIndex(target_hwnd)

    if !monitor_index || (expected_monitor && monitor_index != expected_monitor)
        return 0

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)
    z_ranks := GetCascadeWindowZRanks()

    for stack_info in stacks {
        ; A tab click can pin rotation to the slot it actually resolved.
        if expected_slot && stack_info["slot_index"] != expected_slot
            continue

        ordered_stack := SortCascadeWindowsByZOrder(stack_info["windows"], z_ranks)

        ; Preserve keyboard behavior: only rotate an exposed window's own stack.
        if ordered_stack.Length < 2 || ordered_stack[1] != target_hwnd
            continue

        next_hwnd := RotateCascadeStackWindows(ordered_stack, direction)

        if next_hwnd
            ActivateWindow(next_hwnd)

        QueueFocusCornerUpdate()
        return next_hwnd
    }

    return 0
}

RotateCascadeStackWindows(ordered_windows, direction)
{
    if ordered_windows.Length < 2
        return 0

    ; Windows maintains separate topmost and normal Z-order bands. Crossing that
    ; boundary with SetWindowPos can silently change WS_EX_TOPMOST, so rotate only
    ; the front window's current band. The other band keeps its application state.
    front_is_topmost := IsCascadeWindowTopmost(ordered_windows[1])
    if front_is_topmost < 0
        return 0

    band_windows := []
    for hwnd in ordered_windows {
        window_is_topmost := IsCascadeWindowTopmost(hwnd)
        if window_is_topmost < 0
            return 0
        if window_is_topmost = front_is_topmost
            band_windows.Push(hwnd)
    }
    if band_windows.Length < 2
        return 0

    try {
        if direction < 0 {
            ; Bring the deepest window to the front of its existing native band
            ; in one operation. HWND_TOP does not make a normal window topmost;
            ; HWND_TOPMOST preserves an already-topmost window's band.
            target_hwnd := band_windows[band_windows.Length]
            insert_after := front_is_topmost ? -1 : 0 ; TOPMOST / TOP

            return SetCascadeZOrder(target_hwnd, insert_after) ? target_hwnd : 0
        }

        ; Move the exposed window behind the deepest window in the same band.
        current_hwnd := band_windows[1]
        deepest_hwnd := band_windows[band_windows.Length]

        return SetCascadeZOrder(current_hwnd, deepest_hwnd) ? band_windows[2] : 0
    }
    catch {
        return 0
    }
}

RotateCascadeLayers(direction := 1)
{
    if !IsCascadeEnabled()
        return

    monitor_index := SuiteWorkingMonitor.Get()

    if !monitor_index
        return

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    active_hwnd := WinExist("A")
    next_active_hwnd := 0

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(stack_info["windows"], z_ranks)

        if ordered_stack.Length < 2
            continue

        was_active := ordered_stack[1] = active_hwnd
        new_top_hwnd := RotateCascadeStackWindows(ordered_stack, direction)

        if was_active && new_top_hwnd
            next_active_hwnd := new_top_hwnd
    }

    if next_active_hwnd
        ActivateWindow(next_active_hwnd)

    QueueFocusCornerUpdate()
}


; =============================================================================
; spatial ordering
; =============================================================================

GetSpatialCascadeOrder(windows)
{
    spatial_items := []

    ; History order is the final stable tie-breaker when windows occupy the
    ; exact same physical position.
    for history_index, hwnd in windows {
        if !TryGetWindowCenter(hwnd, &center_x, &center_y)
            continue

        item := Map("hwnd", hwnd, "center_x", center_x, "center_y", center_y,
            "history_index", history_index)

        insert_index := spatial_items.Length + 1

        Loop spatial_items.Length {
            existing := spatial_items[A_Index]

            if SpatialItemComesBefore(item, existing) {
                insert_index := A_Index
                break
            }
        }

        spatial_items.InsertAt(insert_index, item)
    }

    ordered_windows := []

    for item in spatial_items
        ordered_windows.Push(item["hwnd"])

    return ordered_windows
}

SpatialItemComesBefore(item, existing)
{
    if item["center_y"] != existing["center_y"]
        return item["center_y"] < existing["center_y"]

    if item["center_x"] != existing["center_x"]
        return item["center_x"] < existing["center_x"]

    return item["history_index"] < existing["history_index"]
}

GetNearestSpatialCascadeWindow(ordered_windows, active_hwnd, direction)
{
    if active_hwnd
        && WinExist("ahk_id " active_hwnd)
        && TryGetWindowCenter(active_hwnd, &active_center_x, &active_center_y)
    {
        target_hwnd := 0
        best_distance := 0

        for hwnd in ordered_windows {
            if !TryGetWindowCenter(hwnd, &center_x, &center_y)
                continue

            vertical_delta := center_y - active_center_y

            if direction < 0 {
                if vertical_delta >= 0
                    continue

                distance := -vertical_delta
            } else {
                if vertical_delta <= 0
                    continue

                distance := vertical_delta
            }

            if !target_hwnd || distance < best_distance {
                target_hwnd := hwnd
                best_distance := distance
            }
        }

        if target_hwnd
            return target_hwnd
    }

    ; No window remains in the requested direction, so wrap.
    return (direction < 0 ? ordered_windows[ordered_windows.Length] : ordered_windows[1])
}


; =============================================================================
; activation and bringing a cascade forward
; =============================================================================

BringCascadeForward(monitor_index)
{
    if !IsCascadeEnabled() || !monitor_index
        return

    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()

    ordered_windows := SortCascadeWindowsByZOrder(windows, z_ranks)

    visible_windows := []
    originally_topmost := Map()

    for hwnd in ordered_windows {
        if !WinExist("ahk_id " hwnd)
            continue

        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
            originally_topmost[hwnd] := !!(WinGetExStyle(hwnd) & 0x8) ; WS_EX_TOPMOST
        }
        catch {
            continue
        }

        visible_windows.Push(hwnd)
    }

    if visible_windows.Length = 0
        return

    last_used_hwnd := visible_windows[1]

    ; Temporarily promote the whole cascade into the topmost band. Process
    ; bottom-to-top so its existing internal Z-order is preserved.
    Loop visible_windows.Length
        try SetCascadeZOrder(visible_windows[visible_windows.Length - A_Index + 1], -1) ; HWND_TOPMOST

    ; Return only temporarily promoted windows to the normal Z band, keeping
    ; the bottom-to-top order. Preserve an application's existing always-on-top
    ; setting rather than clearing it as a side effect of bringing the group up.
    Loop visible_windows.Length {
        hwnd := visible_windows[visible_windows.Length - A_Index + 1]
        if !originally_topmost[hwnd]
            try SetCascadeZOrder(hwnd, -2) ; HWND_NOTOPMOST
    }

    ActivateWindow(last_used_hwnd)
}
