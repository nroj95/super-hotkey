; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; managed window history
; =============================================================================

GetManagedCascadeMonitor(hwnd)
{
    global cascade_history

    for monitor_index, history in cascade_history {
        for managed_hwnd in history {
            if managed_hwnd = hwnd
                return monitor_index
        }
    }

    return 0
}

RecordCascadeWindow(monitor_index, hwnd)
{
    global cascade_history, cascade_membership_generation

    RememberCascadeSlot(hwnd, monitor_index)
    if !cascade_history.Has(monitor_index)
        cascade_history[monitor_index] := []

    for existing_hwnd in cascade_history[monitor_index] {
        if existing_hwnd = hwnd
            return
    }
    cascade_history[monitor_index].Push(hwnd)
    cascade_membership_generation += 1

    QueueFocusCornerUpdate()
}

RemoveCascadeWindowFromHistory(hwnd)
{
    global cascade_history, cascade_membership_generation

    ForgetCascadeSlot(hwnd)

    for monitor_index, history in cascade_history {
        index := history.Length

        while index >= 1 {
            if history[index] = hwnd {
                history.RemoveAt(index)
                cascade_membership_generation += 1
            }

            index -= 1
        }
    }
}

GetLiveCascadeHistory(monitor_index)
{
    global cascade_history, cascade_restore_batches, cascade_slot_tolerance
    global cascade_membership_generation, cascade_drag_generation, cascade_display_reflow

    if !cascade_history.Has(monitor_index)
        return []
    ; OS resizing/repositioning during a display change is not manual detachment.
    if CascadeMonitorNeedsRefresh(monitor_index)
        return cascade_history[monitor_index].Clone()

    generation := cascade_membership_generation
    drag_generation := cascade_drag_generation
    history := cascade_history[monitor_index].Clone()
    live_history := []
    geometry := GetCanonicalCascadeGeometry(monitor_index)
    for hwnd in history {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue
        if IsCascadeWindowBeingDragged(hwnd) || cascade_display_reflow.Has(hwnd)
            || (cascade_restore_batches.Has(monitor_index)
                && cascade_restore_batches[monitor_index].targets.Has(hwnd))
        {
            live_history.Push(hwnd)
            continue
        }
        try {
            state := WinGetMinMax(hwnd)
            if state = -1 {
                live_history.Push(hwnd)
                continue
            }
            if state != 0
                continue
            ; A failed geometry query is not evidence that a live member left.
            if !TryGetCascadeLayoutOrigin(hwnd, &layout_monitor, &x, &y) {
                live_history.Push(hwnd)
                continue
            }
            if layout_monitor = monitor_index
                && FindNearestCascadeSlot(x, y, geometry.slots, cascade_slot_tolerance)
                live_history.Push(hwnd)
        }
        catch {
            if DllCall("IsWindow", "ptr", hwnd, "int")
                live_history.Push(hwnd)
        }
    }

    previous_critical := Critical("On")
    try {
        ; Do not erase newly placed/dropped members with an older snapshot.
        if generation != cascade_membership_generation
            || drag_generation != cascade_drag_generation
            || IsCascadeRestoreInProgress(monitor_index)
            return cascade_history.Has(monitor_index) ? cascade_history[monitor_index].Clone() : []
        if live_history.Length != history.Length {
            retained_windows := Map()
            for live_hwnd in live_history
                retained_windows[live_hwnd] := true
            for old_hwnd in history {
                if !retained_windows.Has(old_hwnd)
                    ForgetCascadeSlot(old_hwnd)
            }
            cascade_history[monitor_index] := live_history
            cascade_membership_generation += 1
            QueueCascadeCompaction(monitor_index)
        }
    }
    finally {
        Critical(previous_critical)
    }
    return live_history
}

IsWindowInCascadeLayout(hwnd)
{
    global cascade_slot_tolerance

    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    stacks := BuildCascadeSlotStacks(
        [hwnd],
        cascade_slot_tolerance
    )

    return stacks.Length > 0
}


TryGetCascadeLayoutOrigin(hwnd, &monitor_index, &x, &y)
{
    global cascade_window_drag, placement_reservations, cascade_display_reflow, cascade_displays

    if IsCascadeWindowBeingDragged(hwnd) && !cascade_window_drag.completing {
        monitor_index := cascade_window_drag.source_monitor
            ? cascade_window_drag.source_monitor : cascade_window_drag.monitor
        x := cascade_window_drag.frame_x
        y := cascade_window_drag.frame_y
        return true
    }
    if placement_reservations.Has(hwnd) {
        reservation := placement_reservations[hwnd]
        monitor_index := reservation["monitor"]
        x := reservation["x"]
        y := reservation["y"]
        return true
    }

    if cascade_display_reflow.Has(hwnd) {
        saved := cascade_display_reflow[hwnd]
        if cascade_displays.Has(saved.monitor) {
            monitor_index := saved.monitor
            slot := cascade_displays[monitor_index].geometry.slots[saved.slot]
            x := slot[1]
            y := slot[2]
            return true
        }
    }
    monitor_index := GetMonitorForWindow(hwnd)
    return monitor_index && GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
}

GetCanonicalCascadeGeometry(monitor_index)
{
    global cascade_displays
    if cascade_displays.Has(monitor_index)
        return cascade_displays[monitor_index].geometry
    MonitorGetWorkAreaPixels(monitor_index, &left, &top, &right, &bottom)
    return BuildCanonicalCascadeGeometry(left, top, right, bottom)
}

BuildCanonicalCascadeGeometry(left, top, right, bottom)
{
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height
    width := Min(Max(minimum_width, Floor((right - left) * window_width_ratio)),
        right - left - edge_margin * 2)
    height := Min(Max(minimum_height, Floor((bottom - top) * window_height_ratio)),
        bottom - top - edge_margin * 2)
    return {
        width: width, height: height,
        slots: BuildCascadeSlots(left, top, right, bottom, width, height)
    }
}

; =============================================================================
; slots, stacks, and exposed layers
; =============================================================================

GetCascadeSlotStacksForMonitor(monitor_index)
{
    global cascade_slot_tolerance

    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return []

    return BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )
}

GetCurrentCascadeLayerWindows(monitor_index)
{
    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return []

    z_ranks := GetCascadeWindowZRanks()
    layer_windows := []

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        if ordered_stack.Length
            layer_windows.Push(ordered_stack[1])
    }

    return GetSpatialCascadeOrder(layer_windows)
}

BuildCascadeSlotStacks(windows, tolerance)
{
    stacks := []
    stacks_by_slot := Map()
    geometry_by_monitor := Map()

    for hwnd in windows {
        try {
            if !IsCascadeWindowBeingDragged(hwnd) && WinGetMinMax(hwnd) != 0
                continue
            if !TryGetCascadeLayoutOrigin(hwnd, &monitor_index, &window_x, &window_y)
                continue
            if !geometry_by_monitor.Has(monitor_index)
                geometry_by_monitor[monitor_index] := GetCanonicalCascadeGeometry(monitor_index)
            slots := geometry_by_monitor[monitor_index].slots
        }
        catch {
            continue
        }

        best_slot_index := FindNearestCascadeSlot(
            window_x,
            window_y,
            slots,
            tolerance
        )

        ; A manually moved window that is no longer near a canonical slot does
        ; not belong to any stack.
        if !best_slot_index
            continue

        stack_key :=
            monitor_index
            . ":"
            . best_slot_index

        if stacks_by_slot.Has(stack_key) {
            stacks_by_slot[stack_key]["windows"].Push(hwnd)
            continue
        }

        stack_info := Map(
            "slot_index", best_slot_index,
            "windows", [hwnd]
        )

        stacks_by_slot[stack_key] := stack_info
        stacks.Push(stack_info)
    }

    return stacks
}


; =============================================================================
; canonical slot geometry and occupancy
; =============================================================================

CenterCoordinate(work_start, work_size, window_size)
{
    return work_start + Floor((work_size - window_size) / 2)
}

BuildCascadeSlots(
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height
)
{
    global cascade_x, cascade_y

    work_width := work_right - work_left
    work_height := work_bottom - work_top

    center_x := CenterCoordinate(
        work_left,
        work_width,
        window_width
    )

    center_y := CenterCoordinate(
        work_top,
        work_height,
        window_height
    )

    ; Slot 1 is the optimally centered position. Fill every position upward
    ; from center before continuing downward from center.
    slots := [[center_x, center_y]]

    ; Slots 2...N: left and upward from center until no more positions fit.
    step := 1

    Loop {
        x := center_x - cascade_x * step
        y := center_y - cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    ; Remaining slots: right and downward from center until the work area ends.
    step := 1

    Loop {
        x := center_x + cascade_x * step
        y := center_y + cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    return slots
}

CascadePositionFits(
    x,
    y,
    window_width,
    window_height,
    work_left,
    work_top,
    work_right,
    work_bottom
)
{
    global edge_margin

    return (
        x >= work_left + edge_margin
        && y >= work_top + edge_margin
        && x + window_width <= work_right - edge_margin
        && y + window_height <= work_bottom - edge_margin
    )
}

FindNearestCascadeSlot(
    window_x,
    window_y,
    slots,
    tolerance
)
{
    best_slot_index := 0
    best_distance := 0

    Loop slots.Length {
        slot_index := A_Index
        slot := slots[slot_index]

        delta_x := Abs(window_x - slot[1])
        delta_y := Abs(window_y - slot[2])

        if delta_x > tolerance || delta_y > tolerance
            continue

        distance := delta_x * delta_x + delta_y * delta_y

        if !best_slot_index
            || distance < best_distance
        {
            best_slot_index := slot_index
            best_distance := distance
        }
    }

    return best_slot_index
}

GetCascadeSlotCounts(
    monitor_index,
    slots,
    tolerance,
    excluded_hwnd := 0
)
{
    global cascade_history, placement_reservations

    counts := []

    Loop slots.Length
        counts.Push(0)

    if cascade_history.Has(monitor_index) {
        for hwnd in cascade_history[monitor_index] {
            if hwnd = excluded_hwnd || !WinExist("ahk_id " hwnd)
                continue

            ; A reserved window is counted at its intended slot below instead
            ; of at stale geometry from before its asynchronous move completes.
            if placement_reservations.Has(hwnd)
                continue

            if !TryGetCascadeLayoutOrigin(hwnd, &layout_monitor, &window_x, &window_y)
                || layout_monitor != monitor_index
                continue

            try {
                if !IsCascadeWindowBeingDragged(hwnd) && WinGetMinMax("ahk_id " hwnd) != 0
                    continue
            }
            catch {
                continue
            }

            best_slot_index := FindNearestCascadeSlot(
                window_x,
                window_y,
                slots,
                tolerance
            )

            if best_slot_index
                counts[best_slot_index] += 1
        }
    }

    ; Reservations also include windows that have selected a slot but have not
    ; yet been recorded in cascade history.
    for reserved_hwnd, reservation in placement_reservations {
        if reserved_hwnd = excluded_hwnd || reservation["monitor"] != monitor_index
            continue

        if !WinExist("ahk_id " reserved_hwnd)
            continue

        best_slot_index := FindNearestCascadeSlot(
            reservation["x"],
            reservation["y"],
            slots,
            tolerance
        )

        if best_slot_index
            counts[best_slot_index] += 1
    }

    return counts
}

GetNextCascadePosition(
    monitor_index,
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height,
    excluded_hwnd := 0
)
{
    global cascade_slot_tolerance

    slots := BuildCascadeSlots(
        work_left,
        work_top,
        work_right,
        work_bottom,
        window_width,
        window_height
    )

    slot_counts := GetCascadeSlotCounts(
        monitor_index,
        slots,
        cascade_slot_tolerance,
        excluded_hwnd
    )

    selected_slot_index := 1
    selected_count := slot_counts[1]

    ; Smart placement sorts by stack depth first, then canonical slot number.
    ; This fills the shallowest slot and prefers the earliest slot on ties.
    Loop slots.Length {
        slot_index := A_Index
        count := slot_counts[slot_index]

        if count < selected_count {
            selected_slot_index := slot_index
            selected_count := count
        }
    }

    return slots[selected_slot_index]
}


; =============================================================================
; layout compaction
; =============================================================================

IsCascadeCompactionDeferred(monitor_index)
{
    ; Never mutate the layout halfway through a drag or window-state batch.
    return !IsCascadeEnabled() || HasCascadeWindowDrag() || IsCascadeCloseBatchActive(monitor_index)
        || IsCascadeRestoreInProgress(monitor_index) || IsCascadeDisplayTransition()
        || HasPendingCascadeDisplayLayout(monitor_index)
}

QueueCascadeCompaction(monitor_index, preferred_hwnd := 0)
{
    global cascade_compaction_pending

    if !monitor_index
        return
    if preferred_hwnd || !cascade_compaction_pending.Has(monitor_index)
        cascade_compaction_pending[monitor_index] := preferred_hwnd
    if !IsCascadeCompactionDeferred(monitor_index)
        ScheduleCascadeCompactionFlush()
}

RequeueCascadeCompaction(monitor_index, preferred_hwnd)
{
    global cascade_compaction_pending

    previous_critical := Critical("On")
    try {
        ; A retry belongs to an older plan. A newer drop already queued wins.
        if cascade_compaction_pending.Has(monitor_index)
            && cascade_compaction_pending[monitor_index]
            preferred_hwnd := cascade_compaction_pending[monitor_index]
        QueueCascadeCompaction(monitor_index, preferred_hwnd)
    }
    finally {
        Critical(previous_critical)
    }
}

ScheduleCascadeCompactionFlush(recover := false)
{
    if !IsCascadeEnabled()
        return

    global cascade_compaction_timer_pending

    ; Further events must not keep postponing an already scheduled flush.
    if cascade_compaction_timer_pending && !recover
        return
    cascade_compaction_timer_pending := true
    SetTimer(FlushCascadeCompactions, -120)
}

FlushCascadeCompactions()
{
    global cascade_compaction_pending, cascade_compaction_timer_pending
    static running := false

    previous_critical := Critical("On")
    try {
        cascade_compaction_timer_pending := false
        if running
            return
        running := true
        monitors := cascade_compaction_pending
        cascade_compaction_pending := Map()
    }
    finally {
        Critical(previous_critical)
    }

    try {
        for monitor_index, preferred_hwnd in monitors {
            try {
                if IsCascadeCompactionDeferred(monitor_index)
                    RequeueCascadeCompaction(monitor_index, preferred_hwnd)
                else
                    CompactCascadeLayout(monitor_index, preferred_hwnd)
            }
            catch Error as err {
                ; Retain this request for the slow recovery poll; finish the rest.
                if !cascade_compaction_pending.Has(monitor_index)
                    cascade_compaction_pending[monitor_index] := preferred_hwnd
                DebugError("CompactCascadeLayout", err)
            }
        }
    }
    finally {
        running := false
        ; Requests raised during this flush remain in the new pending map.
    }
}

CompactCascadeLayout(monitor_index, preferred_hwnd := 0)
{
    global cascade_slot_tolerance
    global cascade_drag_generation, cascade_compaction_pending, cascade_membership_generation

    drag_generation := cascade_drag_generation
    ; Another monitor's compaction may have yielded to a newer drop. Prefer its
    ; queued target over the older request captured by this flush.
    if cascade_compaction_pending.Has(monitor_index)
        && cascade_compaction_pending[monitor_index]
    {
        preferred_hwnd := cascade_compaction_pending[monitor_index]
    }
    if IsCascadeCompactionDeferred(monitor_index) {
        RequeueCascadeCompaction(monitor_index, preferred_hwnd)
        return
    }

    ; Compaction operates on existing membership only; auto-paused windows stay unmanaged.
    windows := GetLiveCascadeHistory(monitor_index)
    managed_window_count := windows.Length
    membership_generation := cascade_membership_generation

    ; Stack construction excludes minimized members without restoring them.
    if windows.Length = 0
        return

    stacks := BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )

    if stacks.Length = 0
        return

    geometry := GetCanonicalCascadeGeometry(monitor_index)
    slots := geometry.slots

    if slots.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    ordered_stacks := []

    Loop slots.Length
        ordered_stacks.Push([])

    for stack_info in stacks {
        ordered_stacks[stack_info["slot_index"]] := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )
    }

    target_stacks := BuildStableCascadeCompactionPlan(
        ordered_stacks,
        managed_window_count,
        preferred_hwnd
    )

    failed_moves := 0
    for slot_index, stack_windows in target_stacks {
        target_slot := slots[slot_index]

        for hwnd in stack_windows {
            ; Never apply an old plan after a newer drag has changed the layout.
            if drag_generation != cascade_drag_generation
                || membership_generation != cascade_membership_generation {
                RequeueCascadeCompaction(monitor_index, preferred_hwnd)
                return
            }
            if IsCascadeCompactionDeferred(monitor_index) {
                RequeueCascadeCompaction(monitor_index, preferred_hwnd)
                return
            }

            ; Compaction has reservation/stabilization tracking, so geometry moves
            ; can be posted without waiting on each target application's UI thread.
            if !MoveCascadeWindowToSlot(hwnd, target_slot[1], target_slot[2], true)
                failed_moves += 1
        }
    }

    ; Keep each target stack in the same top-to-bottom order within each native
    ; Z-order band. Never place a topmost window after a normal window: Windows
    ; would remove its WS_EX_TOPMOST state as a side effect.
    z_flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    for stack_windows in target_stacks {
        topmost_windows := []
        normal_windows := []
        topmost_state_known := true
        for hwnd in stack_windows {
            window_is_topmost := IsCascadeWindowTopmost(hwnd)
            if window_is_topmost < 0 {
                topmost_state_known := false
                break
            }
            if window_is_topmost
                topmost_windows.Push(hwnd)
            else
                normal_windows.Push(hwnd)
        }

        if !topmost_state_known {
            ; Geometry compaction already completed. Do not turn a transient style
            ; query failure into a 120 ms retry loop; simply leave this stack's
            ; current Z-order untouched for this pass.
            continue
        }

        for band_windows in [topmost_windows, normal_windows] {
            if band_windows.Length < 2
                continue

            Loop band_windows.Length - 1 {
                if drag_generation != cascade_drag_generation
                    || membership_generation != cascade_membership_generation {
                    RequeueCascadeCompaction(monitor_index, preferred_hwnd)
                    return
                }
                if IsCascadeCompactionDeferred(monitor_index) {
                    RequeueCascadeCompaction(monitor_index, preferred_hwnd)
                    return
                }
                upper_hwnd := band_windows[A_Index]
                lower_hwnd := band_windows[A_Index + 1]

                try PhysicalDllCall(
                    "SetWindowPos",
                    "ptr", lower_hwnd,
                    "ptr", upper_hwnd,
                    "int", 0,
                    "int", 0,
                    "int", 0,
                    "int", 0,
                    "uint", z_flags,
                    "int"
                )
            }
        }
    }

    QueueFocusCornerUpdate()
    DebugLog("Cascade compaction pass. | monitor=" monitor_index
        " | managed=" managed_window_count " | slots=" slots.Length
        " | failed-moves=" failed_moves)
}


; Plan without moving windows: preserve existing slots, then fill only holes.
BuildStableCascadeCompactionPlan(ordered_stacks, managed_window_count, preferred_hwnd := 0)
{
    slot_count := ordered_stacks.Length
    target_stacks := []
    target_counts := []
    window_count := 0
    maximum_depth := 0
    preferred_slot := 0

    for slot_index, stack_windows in ordered_stacks {
        target_stacks.Push([])
        window_count += stack_windows.Length
        maximum_depth := Max(maximum_depth, stack_windows.Length)
        for hwnd in stack_windows {
            if hwnd = preferred_hwnd
                preferred_slot := slot_index
        }
    }
    if !slot_count || !window_count
        return target_stacks

    ; Full layers occupy every slot; the last partial layer fills early slots.
    ; Thus every slot retains at least its front window once a layer is full.
    complete_layers := Floor(window_count / slot_count)
    remaining_windows := Mod(window_count, slot_count)
    Loop slot_count
        target_counts.Push(complete_layers + (A_Index <= remaining_windows))

    if window_count < slot_count && managed_window_count > window_count {
        ; Minimized members still count toward the user's total. Keep them hidden
        ; and preserve visible slots rather than collapsing a merely hidden layer.
        slot_limit := Min(slot_count, managed_window_count)
        Loop slot_count
            target_counts[A_Index] := 0
        remaining_windows := window_count
        if preferred_slot && preferred_slot <= slot_limit {
            target_counts[preferred_slot] := 1
            remaining_windows -= 1
        }
        Loop slot_limit {
            slot_index := A_Index
            if remaining_windows && !target_counts[slot_index]
                && ordered_stacks[slot_index].Length
            {
                target_counts[slot_index] := 1
                remaining_windows -= 1
            }
        }
        Loop slot_limit {
            if !remaining_windows
                break
            if !target_counts[A_Index] {
                target_counts[A_Index] := 1
                remaining_windows -= 1
            }
        }
    }

    overflow_targets := Map()
    for slot_index, stack_windows in ordered_stacks {
        target_count := target_counts[slot_index]
        keep_preferred := target_count > 0 && slot_index = preferred_slot
        keep_other_count := Min(target_count, stack_windows.Length) - keep_preferred

        ; Reserve room for the dropped window before choosing other survivors.
        ; Retain their existing Z-order; only surplus background windows move.
        for hwnd in stack_windows {
            if keep_preferred && hwnd = preferred_hwnd
                target_stacks[slot_index].Push(hwnd)
            else if keep_other_count > 0 {
                target_stacks[slot_index].Push(hwnd)
                keep_other_count -= 1
            } else {
                overflow_targets[hwnd] := true
            }
        }
    }

    ; Keep displaced windows in layer/slot order, without flattening survivors.
    overflow_windows := []
    Loop maximum_depth {
        layer_index := A_Index
        for stack_windows in ordered_stacks {
            if layer_index <= stack_windows.Length {
                hwnd := stack_windows[layer_index]
                if overflow_targets.Has(hwnd)
                    overflow_windows.Push(hwnd)
            }
        }
    }

    overflow_index := 1
    Loop maximum_depth {
        layer_index := A_Index
        for slot_index, target_count in target_counts {
            if layer_index <= target_count
                && target_stacks[slot_index].Length < layer_index
            {
                target_stacks[slot_index].Push(overflow_windows[overflow_index])
                overflow_index += 1
            }
        }
    }

    return target_stacks
}


; =============================================================================
; stack Z-order
; =============================================================================

GetCascadeWindowZRanks()
{
    ranks := Map()

    ; WinGetList returns top-level windows in Z-order.
    for rank, hwnd in WinGetList()
        ranks[hwnd] := rank

    return ranks
}

SortCascadeWindowsByZOrder(windows, ranks)
{
    ordered_windows := []

    for hwnd in windows {
        rank := (
            ranks.Has(hwnd)
            ? ranks[hwnd]
            : 2147483647
        )

        insert_index := ordered_windows.Length + 1

        Loop ordered_windows.Length {
            existing_hwnd := ordered_windows[A_Index]

            existing_rank := (
                ranks.Has(existing_hwnd)
                ? ranks[existing_hwnd]
                : 2147483647
            )

            if rank < existing_rank {
                insert_index := A_Index
                break
            }
        }

        ordered_windows.InsertAt(insert_index, hwnd)
    }

    return ordered_windows
}
