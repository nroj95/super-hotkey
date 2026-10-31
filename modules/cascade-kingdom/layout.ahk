; Cascade Kingdom layout: window history, slots, stacks, exposed layers,
; Z-order and compaction.

; =============================================================================
; managed window history
; =============================================================================

GetManagedCascadeMonitor(hwnd)
{
    for monitor_index, history in CascadeState.history {
        for managed_hwnd in history {
            if managed_hwnd = hwnd
                return monitor_index
        }
    }

    return 0
}

RecordCascadeWindow(monitor_index, hwnd)
{
    RememberCascadeSlot(hwnd, monitor_index)
    if !CascadeState.history.Has(monitor_index)
        CascadeState.history[monitor_index] := []

    for existing_hwnd in CascadeState.history[monitor_index] {
        if existing_hwnd = hwnd
            return
    }
    CascadeState.history[monitor_index].Push(hwnd)
    CascadeState.membershipGeneration += 1
    ; Joining or moving to a display by choice makes it the window's home.
    if CascadeState.homeDevices.Has(hwnd)
        CascadeState.homeDevices.Delete(hwnd)

    QueueFocusCornerUpdate()
}

RemoveCascadeWindowFromHistory(hwnd)
{
    ForgetCascadeSlot(hwnd)

    for monitor_index, history in CascadeState.history {
        index := history.Length

        while index >= 1 {
            if history[index] = hwnd {
                history.RemoveAt(index)
                CascadeState.membershipGeneration += 1
            }

            index -= 1
        }
    }
}

GetLiveCascadeHistory(monitor_index)
{
    if !CascadeState.history.Has(monitor_index)
        return []
    ; OS resizing/repositioning during a display change is not manual detachment.
    if CascadeMonitorNeedsRefresh(monitor_index)
        return CascadeState.history[monitor_index].Clone()

    generation := CascadeState.membershipGeneration
    drag_generation := CascadeState.dragGeneration
    history := CascadeState.history[monitor_index].Clone()
    live_history := []
    geometry := GetCanonicalCascadeGeometry(monitor_index)
    for hwnd in history {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue
        if IsCascadeWindowBeingDragged(hwnd) || CascadeState.displayReflow.Has(hwnd)
            || (CascadeState.restoreBatches.Has(monitor_index)
                && CascadeState.restoreBatches[monitor_index].targets.Has(hwnd))
        {
            live_history.Push(hwnd)
            continue
        }
        ; Only a shown member leaves by being moved off its slot; window state
        ; never ends membership. A failed geometry query is not evidence either.
        try moved_off := IsCascadeWindowShown(hwnd)
            && TryGetCascadeLayoutOrigin(hwnd, &layout_monitor, &x, &y)
            && (layout_monitor != monitor_index
                || !FindNearestCascadeSlot(x, y, geometry.slots, CascadeState.slotTolerance))
        catch
            moved_off := false
        if !moved_off
            live_history.Push(hwnd)
    }

    previous_critical := Critical("On")
    try {
        ; Do not erase newly placed/dropped members with an older snapshot.
        if generation != CascadeState.membershipGeneration
            || drag_generation != CascadeState.dragGeneration
            || IsCascadeRestoreInProgress(monitor_index)
            return CascadeState.history.Has(monitor_index) ? CascadeState.history[monitor_index].Clone() : []
        if live_history.Length != history.Length {
            retained_windows := Map()
            for live_hwnd in live_history
                retained_windows[live_hwnd] := true
            for old_hwnd in history {
                if !retained_windows.Has(old_hwnd)
                    ForgetCascadeSlot(old_hwnd)
            }
            CascadeState.history[monitor_index] := live_history
            CascadeState.membershipGeneration += 1
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
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    stacks := BuildCascadeSlotStacks([hwnd], CascadeState.slotTolerance)

    return stacks.Length > 0
}


TryGetCascadeLayoutOrigin(hwnd, &monitor_index, &x, &y)
{
    if IsCascadeWindowBeingDragged(hwnd) && !CascadeState.windowDrag.completing {
        monitor_index := CascadeState.windowDrag.source_monitor
            ? CascadeState.windowDrag.source_monitor : CascadeState.windowDrag.monitor
        x := CascadeState.windowDrag.frame_x
        y := CascadeState.windowDrag.frame_y
        return true
    }
    if CascadeState.placementReservations.Has(hwnd) {
        reservation := CascadeState.placementReservations[hwnd]
        monitor_index := reservation["monitor"]
        x := reservation["x"]
        y := reservation["y"]
        return true
    }

    if CascadeState.displayReflow.Has(hwnd) {
        saved := CascadeState.displayReflow[hwnd]
        if CascadeState.displays.Has(saved.monitor) {
            monitor_index := saved.monitor
            slot := CascadeState.displays[monitor_index].geometry.slots[saved.slot]
            x := slot[1]
            y := slot[2]
            return true
        }
    }
    ; A minimized window has no slot, only a restore rectangle.
    monitor_index := DllCall("IsIconic", "ptr", hwnd, "int") ? 0 : WindowMonitorIndex(hwnd)
    return monitor_index && GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
}

GetCanonicalCascadeGeometry(monitor_index)
{
    if CascadeState.displays.Has(monitor_index)
        return CascadeState.displays[monitor_index].geometry
    MonitorGetWorkAreaPixels(monitor_index, &left, &top, &right, &bottom)
    return BuildCanonicalCascadeGeometry(left, top, right, bottom)
}

BuildCanonicalCascadeGeometry(left, top, right, bottom)
{
    size := GetCascadeWindowSize(right - left, bottom - top)
    return {
        width: size[1], height: size[2],
        slots: BuildCascadeSlots(left, top, right, bottom, size[1], size[2])
    }
}

; The canonical cascade window size for a work area: a share of it, at least
; the minimum size and never closer to its edges than the margin.
GetCascadeWindowSize(work_width, work_height)
{
    return [
        Min(Max(CascadeState.minimumWidth, Floor(work_width * CascadeState.windowWidthRatio)), work_width - CascadeState.edgeMargin * 2),
        Min(Max(CascadeState.minimumHeight, Floor(work_height * CascadeState.windowHeightRatio)), work_height - CascadeState.edgeMargin * 2)
    ]
}

; =============================================================================
; slots, stacks, and exposed layers
; =============================================================================

GetCascadeSlotStacksForMonitor(monitor_index)
{
    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return []

    return BuildCascadeSlotStacks(windows, CascadeState.slotTolerance)
}

GetCurrentCascadeLayerWindows(monitor_index)
{
    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return []

    z_ranks := GetCascadeWindowZRanks()
    layer_windows := []

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(stack_info["windows"], z_ranks)

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
            if !IsCascadeWindowShown(hwnd)
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

        best_slot_index := FindNearestCascadeSlot(window_x, window_y, slots, tolerance)

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

        stack_info := Map("slot_index", best_slot_index, "windows", [hwnd])

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

BuildCascadeSlots(work_left, work_top, work_right, work_bottom, window_width, window_height)
{
    work_width := work_right - work_left
    work_height := work_bottom - work_top
    step_x := CascadeState.mirrored ? -CascadeState.stepX : CascadeState.stepX

    center_x := CenterCoordinate(work_left, work_width, window_width)

    center_y := CenterCoordinate(work_top, work_height, window_height)

    ; Slot 1 is the optimally centered position. Fill every position upward
    ; from center before continuing downward from center.
    slots := [[center_x, center_y]]

    ; Slots 2...N: left (right when mirrored) and upward from center until no
    ; more positions fit.
    step := 1

    Loop {
        x := center_x - step_x * step
        y := center_y - CascadeState.stepY * step

        if !CascadePositionFits(x, y, window_width, window_height, work_left, work_top, work_right,
            work_bottom) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    ; Remaining slots: right (left when mirrored) and downward from center until
    ; the work area ends.
    step := 1

    Loop {
        x := center_x + step_x * step
        y := center_y + CascadeState.stepY * step

        if !CascadePositionFits(x, y, window_width, window_height, work_left, work_top, work_right,
            work_bottom) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    return slots
}

CascadePositionFits(x, y, window_width, window_height, work_left, work_top, work_right, work_bottom)
{
    return (x >= work_left + CascadeState.edgeMargin && y >= work_top + CascadeState.edgeMargin
        && x + window_width <= work_right - CascadeState.edgeMargin
        && y + window_height <= work_bottom - CascadeState.edgeMargin)
}

FindNearestCascadeSlot(window_x, window_y, slots, tolerance)
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

GetCascadeSlotCounts(monitor_index, slots, tolerance, excluded_hwnd := 0)
{
    counts := []

    Loop slots.Length
        counts.Push(0)

    if CascadeState.history.Has(monitor_index) {
        for hwnd in CascadeState.history[monitor_index] {
            if hwnd = excluded_hwnd || !WinExist("ahk_id " hwnd)
                continue

            ; A reserved window is counted at its intended slot below instead
            ; of at stale geometry from before its asynchronous move completes.
            if CascadeState.placementReservations.Has(hwnd)
                continue

            if !TryGetCascadeLayoutOrigin(hwnd, &layout_monitor, &window_x, &window_y)
                || layout_monitor != monitor_index || !IsCascadeWindowShown(hwnd)
                continue

            best_slot_index := FindNearestCascadeSlot(window_x, window_y, slots, tolerance)

            if best_slot_index
                counts[best_slot_index] += 1
        }
    }

    ; Reservations also include windows that have selected a slot but have not
    ; yet been recorded in cascade history.
    for reserved_hwnd, reservation in CascadeState.placementReservations {
        if reserved_hwnd = excluded_hwnd || reservation["monitor"] != monitor_index
            continue

        if !WinExist("ahk_id " reserved_hwnd)
            continue

        best_slot_index := FindNearestCascadeSlot(reservation["x"], reservation["y"], slots,
            tolerance)

        if best_slot_index
            counts[best_slot_index] += 1
    }

    return counts
}

GetNextCascadePosition(monitor_index, work_left, work_top, work_right, work_bottom, window_width,
    window_height, excluded_hwnd := 0)
{
    slots := BuildCascadeSlots(work_left, work_top, work_right, work_bottom, window_width,
        window_height)

    slot_counts := GetCascadeSlotCounts(monitor_index, slots, CascadeState.slotTolerance, excluded_hwnd)

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
    ; A global pause must not leave deferred layout work to replay on resume.
    if SuiteState.App.suspended
        return
    if !monitor_index
        return
    if preferred_hwnd || !CascadeState.compactionPending.Has(monitor_index)
        CascadeState.compactionPending[monitor_index] := preferred_hwnd
    if !IsCascadeCompactionDeferred(monitor_index)
        ScheduleCascadeCompactionFlush()
}

RequeueCascadeCompaction(monitor_index, preferred_hwnd)
{
    previous_critical := Critical("On")
    try {
        ; A retry belongs to an older plan. A newer drop already queued wins.
        if CascadeState.compactionPending.Has(monitor_index)
            && CascadeState.compactionPending[monitor_index]
            preferred_hwnd := CascadeState.compactionPending[monitor_index]
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

    ; Further events must not keep postponing an already scheduled flush.
    if CascadeState.compactionTimerPending && !recover
        return
    CascadeState.compactionTimerPending := true
    SetTimer(FlushCascadeCompactions, -120)
}

FlushCascadeCompactions()
{
    static running := false

    previous_critical := Critical("On")
    try {
        CascadeState.compactionTimerPending := false
        if running
            return
        running := true
        monitors := CascadeState.compactionPending
        CascadeState.compactionPending := Map()
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
                if !CascadeState.compactionPending.Has(monitor_index)
                    CascadeState.compactionPending[monitor_index] := preferred_hwnd
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
    drag_generation := CascadeState.dragGeneration
    ; Another monitor's compaction may have yielded to a newer drop. Prefer its
    ; queued target over the older request captured by this flush.
    if CascadeState.compactionPending.Has(monitor_index)
        && CascadeState.compactionPending[monitor_index]
    {
        preferred_hwnd := CascadeState.compactionPending[monitor_index]
    }
    if IsCascadeCompactionDeferred(monitor_index) {
        RequeueCascadeCompaction(monitor_index, preferred_hwnd)
        return
    }

    ; Compaction operates on existing membership only; auto-paused windows stay unmanaged.
    windows := GetLiveCascadeHistory(monitor_index)
    managed_window_count := windows.Length
    membership_generation := CascadeState.membershipGeneration

    ; Stack construction excludes members that are not shown, without touching them.
    if windows.Length = 0
        return

    stacks := BuildCascadeSlotStacks(windows, CascadeState.slotTolerance)

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

    target_stacks := BuildStableCascadeCompactionPlan(ordered_stacks, preferred_hwnd)

    ; Never apply an old plan after a newer drag or membership change, or while
    ; layout is deferred: queue it again instead.
    Superseded() {
        if drag_generation = CascadeState.dragGeneration
            && membership_generation = CascadeState.membershipGeneration
            && !IsCascadeCompactionDeferred(monitor_index)
            return false
        RequeueCascadeCompaction(monitor_index, preferred_hwnd)
        return true
    }

    failed_moves := 0
    for slot_index, stack_windows in target_stacks {
        target_slot := slots[slot_index]

        for hwnd in stack_windows {
            if Superseded()
                return

            ; Compaction has reservation/stabilization tracking, so geometry moves
            ; can be posted without waiting on each target application's UI thread.
            if !MoveCascadeWindowToSlot(hwnd, target_slot[1], target_slot[2], true)
                failed_moves += 1
        }
    }

    ; Keep each target stack in the same top-to-bottom order within each native
    ; Z-order band. Never place a topmost window after a normal window: Windows
    ; would remove its WS_EX_TOPMOST state as a side effect.
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
                if Superseded()
                    return
                upper_hwnd := band_windows[A_Index]
                lower_hwnd := band_windows[A_Index + 1]

                try SetCascadeZOrder(lower_hwnd, upper_hwnd)
            }
        }
    }

    QueueFocusCornerUpdate()
    DebugLog("Cascade compaction pass. | monitor=" monitor_index
        " | managed=" managed_window_count " | slots=" slots.Length
        " | failed-moves=" failed_moves)
}


; Plan without moving windows: preserve existing slots, then fill only holes.
; Only shown windows count: a hidden member's hole is filled like any other,
; and showing it again returns it to its slot.
BuildStableCascadeCompactionPlan(ordered_stacks, preferred_hwnd := 0)
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
        rank := (ranks.Has(hwnd) ? ranks[hwnd] : 2147483647)

        insert_index := ordered_windows.Length + 1

        Loop ordered_windows.Length {
            existing_hwnd := ordered_windows[A_Index]

            existing_rank := (ranks.Has(existing_hwnd) ? ranks[existing_hwnd] : 2147483647)

            if rank < existing_rank {
                insert_index := A_Index
                break
            }
        }

        ordered_windows.InsertAt(insert_index, hwnd)
    }

    return ordered_windows
}
