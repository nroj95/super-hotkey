; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; adoption and cross-monitor commands
; =============================================================================

AdoptActiveWindow()
{
    if !IsCascadeEnabled()
        return

    global pending_adoption_undo

    hwnd := WinExist("A")

    if !hwnd || IsShellSurfaceWindow(hwnd)
        return

    ; A second Caps + Insert is the one-shot undo only while nothing else has
    ; consumed it. After cancellation this same command returns to normal re-slot.
    if IsPendingAdoptionUndoFor(hwnd) {
        UndoPendingAdoption()
        return
    }

    CancelPendingAdoptionUndo()

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Prune stale membership before deciding whether this is a true adoption.
    ; A window released by a completed drop is adoptable again.
    if managed_monitor {
        GetLiveCascadeHistory(managed_monitor)
        managed_monitor := GetManagedCascadeMonitor(hwnd)
    }

    undo_snapshot := 0

    if !managed_monitor
        undo_snapshot := CaptureAdoptionUndoSnapshot(hwnd)

    target_monitor := GetMonitorForWindow(hwnd)

    if !target_monitor
        return

    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor)
        return

    if undo_snapshot
        pending_adoption_undo := undo_snapshot
}

CaptureAdoptionUndoSnapshot(hwnd)
{
    global handled_windows

    try {
        WinGetPosPixels(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " hwnd
        )
    }
    catch {
        return 0
    }

    return Map(
        "hwnd", hwnd,
        "x", window_x,
        "y", window_y,
        "width", window_width,
        "height", window_height,
        "was_handled", handled_windows.Has(hwnd)
    )
}

IsPendingAdoptionUndoFor(hwnd)
{
    global pending_adoption_undo

    return IsObject(pending_adoption_undo)
        && pending_adoption_undo.Has("hwnd")
        && pending_adoption_undo["hwnd"] = hwnd
}

CancelPendingAdoptionUndo()
{
    global pending_adoption_undo

    pending_adoption_undo := 0
}

UndoPendingAdoption()
{
    global pending_adoption_undo
    global handled_windows, placement_reservations

    if !IsObject(pending_adoption_undo)
        return false

    snapshot := pending_adoption_undo
    pending_adoption_undo := 0
    hwnd := snapshot["hwnd"]

    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Stop the delayed placement correction before restoring the old geometry.
    CancelPlacementStabilization(hwnd)

    try {
        WinMovePixels(
            snapshot["x"],
            snapshot["y"],
            snapshot["width"],
            snapshot["height"],
            "ahk_id " hwnd
        )
    }
    catch {
        ; If restoration fails, keep the window managed rather than leaving a
        ; half-undone state. A fresh placement also re-enables stabilization.
        if managed_monitor
            PlaceCascadeWindowOnMonitor(hwnd, managed_monitor)

        return false
    }

    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if snapshot["was_handled"]
        handled_windows[hwnd] := true
    else if handled_windows.Has(hwnd)
        handled_windows.Delete(hwnd)

    if managed_monitor
        QueueCascadeCompaction(managed_monitor)

    QueueFocusCornerUpdate()
    return true
}

GatherCascadesToCommandMonitor()
{
    if !IsCascadeEnabled()
        return

    global cascade_history

    target_monitor := GetCommandMonitor()
    if !target_monitor
        return

    windows_to_gather := []
    seen := Map()

    ; Snapshot first: successful placement moves entries into the target history.
    for monitor_index, history in cascade_history {
        if monitor_index = target_monitor
            continue
        for hwnd in history {
            if seen.Has(hwnd) || !WinExist(hwnd)
                continue
            seen[hwnd] := true
            windows_to_gather.Push(hwnd)
        }
    }

    if !windows_to_gather.Length
        return
    for hwnd in windows_to_gather
        PlaceCascadeWindowOnMonitor(hwnd, target_monitor)

    BringCascadeForward(target_monitor)
    QueueFocusCornerUpdate()
}

MoveCascadeWindowAcrossMonitor(hwnd, direction)
{
    if !IsCascadeEnabled()
        return

    if !hwnd || !WinExist("ahk_id " hwnd)
        return

    if IsShellSurfaceWindow(hwnd) || !IsCascadeWindow(hwnd)
        return

    ; The CapsLock layer sends the hwnd that was active when the chord fired.
    ; Abort instead of moving a different window if focus changed meanwhile.
    if WinExist("A") != hwnd {
        DebugLog(
            "Cascade monitor move ignored: active window changed."
            . " | direction=" direction
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    source_monitor := GetMonitorForWindow(hwnd)

    if !source_monitor
        return

    target_monitor := GetAdjacentMonitor(source_monitor, direction)

    if !target_monitor {
        DebugLog(
            "Cascade monitor move ignored: no monitor in direction."
            . " | direction=" direction
            . " | source-monitor=" source_monitor
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Hand the window directly to the destination cascade. Normal smart
    ; placement chooses the shallowest slot and earliest slot number on ties.
    RemoveWindowFromMinimizeState(hwnd)

    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor) {
        DebugLog(
            "Cascade monitor move destination placement failed."
            . " | source-monitor=" source_monitor
            . " | target-monitor=" target_monitor
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    DebugLog(
        "Window moved, adopted, and smart-sorted by destination cascade."
        . " | direction=" direction
        . " | source-monitor=" source_monitor
        . " | managed-monitor=" managed_monitor
        . " | target-monitor=" target_monitor
        . " | " DebugDescribeWindow(hwnd)
    )

    QueueFocusCornerUpdate()
}


; =============================================================================
; close commands
; =============================================================================

CloseCommandMonitorCascade()
{
    if !IsCascadeEnabled()
        return

    monitor_index := GetCommandMonitor()
    if !monitor_index
        return

    ; Caps + F4 owns every visible, non-minimized managed layer on this monitor.
    CloseCascadeWindowList(GetCascadeWindowsForMonitorClose(monitor_index), monitor_index)
}

GetCascadeWindowsForMonitorClose(monitor_index)
{
    global placement_reservations

    windows := []
    seen := Map()

    for hwnd in GetLiveCascadeHistory(monitor_index) {
        if !IsCascadeCloseEligible(hwnd)
            continue

        seen[hwnd] := true
        windows.Push(hwnd)
    }

    ; Include visible, non-minimized windows already reserved for this monitor even if
    ; asynchronous placement has not reached cascade history yet.
    for hwnd, reservation in placement_reservations {
        if reservation["monitor"] != monitor_index
            continue
        if seen.Has(hwnd) || !IsCascadeCloseEligible(hwnd)
            continue

        seen[hwnd] := true
        windows.Push(hwnd)
    }

    return windows
}

IsCascadeCloseEligible(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") || IsWindowCloaked(hwnd)
        return false

    try return WinGetMinMax(hwnd) != -1
    catch
        return false
}

CloseCascadeWindowList(windows, monitor_index)
{
    global cascade_close_batches, cascade_close_timeout_ms

    if !IsCascadeEnabled() || windows.Length = 0 || !monitor_index
        return

    ordered_windows := SortCascadeWindowsByZOrder(windows, GetCascadeWindowZRanks())
    ; Register every target before the first close can deliver a destroy event.
    batch := BeginCascadeCloseBatch(monitor_index, ordered_windows)
    if !IsObject(batch)
        return

    try {
        for hwnd in ordered_windows {
            ; A pause or newer batch can take ownership while WinClose yields.
            if !IsCascadeEnabled() || !cascade_close_batches.Has(monitor_index)
                || cascade_close_batches[monitor_index] != batch
                break
            if !batch.targets.Has(hwnd)
                continue
            try {
                if !WinExist(hwnd) || WinGetPID(hwnd) != batch.targets[hwnd]
                    || !IsCascadeCloseEligible(hwnd)
                {
                    RemoveWindowFromCascadeCloseBatch(hwnd, batch)
                    continue
                }
                WinClose(hwnd)
            }
            catch Error as err {
                RemoveWindowFromCascadeCloseBatch(hwnd, batch)
                DebugError("Close cascade window", err)
            }
        }
    }
    finally {
        ; Give the whole batch its grace period after issuing the requests.
        ; An old bound callback cannot expire a newer close command's batch.
        if cascade_close_batches.Has(monitor_index)
            && cascade_close_batches[monitor_index] = batch
            SetTimer(ExpireCascadeCloseBatch.Bind(monitor_index, batch), -cascade_close_timeout_ms)
    }
}


BeginCascadeCloseBatch(monitor_index, windows)
{
    global cascade_close_batches

    batch := {targets: Map()}
    for hwnd in windows {
        try batch.targets[hwnd] := WinGetPID(hwnd)
    }
    if !batch.targets.Count
        return 0
    cascade_close_batches[monitor_index] := batch
    return batch
}


RemoveWindowFromCascadeCloseBatch(hwnd, expected_batch := 0)
{
    global cascade_close_batches

    previous_critical := Critical("On")
    try {
        for monitor_index, batch in cascade_close_batches.Clone() {
            if IsObject(expected_batch) && batch != expected_batch
                continue
            if !batch.targets.Has(hwnd)
                continue
            batch.targets.Delete(hwnd)
            if batch.targets.Count
                continue
            cascade_close_batches.Delete(monitor_index)
            QueueCascadeCompaction(monitor_index)
        }
    }
    finally {
        Critical(previous_critical)
    }
}

ExpireCascadeCloseBatch(monitor_index, expected_batch)
{
    global cascade_close_batches

    previous_critical := Critical("On")
    try {
        if !cascade_close_batches.Has(monitor_index)
            || cascade_close_batches[monitor_index] != expected_batch
            return
        cascade_close_batches.Delete(monitor_index)
        ; A save prompt may still be open. Only release the layout gate.
        QueueCascadeCompaction(monitor_index)
    }
    finally {
        Critical(previous_critical)
    }
    DebugLog("Cascade close batch expired. | monitor=" monitor_index
        " | remaining-targets=" expected_batch.targets.Count)
}


IsCascadeCloseBatchActive(monitor_index)
{
    global cascade_close_batches

    return (
        monitor_index
        && cascade_close_batches.Has(monitor_index)
    )
}


; =============================================================================
; restore saved cascade windows
; =============================================================================

RestoreCascadeWindows(windows)
{
    global cascade_restore_batches, cascade_restore_request_depth

    if windows.Length = 0
        return

    ; Register the whole saved set before the first WinRestore can yield.
    ; Caps + M restores the complete saved set across monitors in one batch.
    batches := Map()
    cascade_restore_request_depth += 1
    try {
        batches := TrackCascadeWindowRestores(windows)
        RestoreCascadeWindowList(windows)
    }
    finally {
        ; Start the bounded settling period after all requests/Z-order work,
        ; not before a large saved set has even finished receiving WinRestore.
        for monitor_index, batch in batches {
            if cascade_restore_batches.Has(monitor_index)
                && cascade_restore_batches[monitor_index] = batch
            {
                batch.started_tick := A_TickCount
                batch.snapshot := ""
            }
        }
        cascade_restore_request_depth -= 1
        for monitor_index in batches
            QueueCascadeCompaction(monitor_index)
    }
}

RestoreCascadeWindowList(windows)
{
    top_restored_hwnd := 0

    ; The saved list is top-to-bottom. Restore bottom-to-top first.
    Loop windows.Length {
        index := windows.Length - A_Index + 1
        hwnd := windows[index]

        if !WinExist("ahk_id " hwnd)
            continue

        try WinRestore("ahk_id " hwnd)
    }

    ; Rebuild the saved Z-order explicitly.
    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    Loop windows.Length {
        index := windows.Length - A_Index + 1
        hwnd := windows[index]

        if !WinExist("ahk_id " hwnd)
            continue

        try PhysicalDllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0, ; HWND_TOP
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )
    }

    for hwnd in windows {
        if !WinExist("ahk_id " hwnd)
            continue

        top_restored_hwnd := hwnd
        break
    }

    if top_restored_hwnd
        ActivateCascadeWindow(top_restored_hwnd)
}


; =============================================================================
; restore completion and combined-layout compaction
; =============================================================================

TrackCascadeWindowRestores(windows)
{

    global cascade_restore_batches, cascade_restore_poll_ms, cascade_membership_generation

    tracked_batches := Map()
    for hwnd in windows {
        monitor_index := GetManagedCascadeMonitor(hwnd)
        if !monitor_index
            continue
        try pid := WinGetPID(hwnd)
        catch
            continue

        if !cascade_restore_batches.Has(monitor_index) {
            cascade_restore_batches[monitor_index] := {
                targets: Map(), started_tick: A_TickCount,
                snapshot: "", stable_since: 0, generation: 0
            }
        }
        batch := cascade_restore_batches[monitor_index]
        tracked_batches[monitor_index] := batch
        if batch.targets.Has(hwnd) && batch.targets[hwnd] = pid
            continue
        batch.targets[hwnd] := pid
        batch.generation += 1
        cascade_membership_generation += 1
        batch.snapshot := ""
    }

    if tracked_batches.Count
        SetTimer(WatchCascadeWindowRestores, cascade_restore_poll_ms)
    return tracked_batches
}

IsCascadeRestoreInProgress(monitor_index)
{
    global cascade_restore_batches, cascade_restore_request_depth

    return cascade_restore_request_depth > 0
        || cascade_restore_batches.Has(monitor_index)
}

WatchCascadeWindowRestores()
{
    if !IsCascadeEnabled()
        return

    global cascade_restore_batches, cascade_restore_request_depth
    global cascade_restore_settle_ms, cascade_restore_timeout_ms
    global cascade_slot_tolerance

    ; Read-only queries stay interruptible. The generation check below discards
    ; a snapshot if a native callback or another restore changed its batch.
    if cascade_restore_request_depth
        return

    for monitor_index, batch in cascade_restore_batches.Clone() {
        generation := batch.generation
        geometry := 0
        snapshot := ""
        ready := true
        stale_targets := []

        for hwnd, pid in batch.targets.Clone() {
            if !WinExist(hwnd) || GetManagedCascadeMonitor(hwnd) != monitor_index
                || IsCascadeWindowBeingDragged(hwnd)
            {
                stale_targets.Push(hwnd)
                continue
            }
            try {
                if WinGetPID(hwnd) != pid {
                    stale_targets.Push(hwnd)
                    continue
                }
                state := WinGetMinMax(hwnd)
                if state = 1 {
                    ; Respect a maximized window instead of pulling it into slots.
                    stale_targets.Push(hwnd)
                    continue
                }
                if state != 0 || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
                    || IsWindowCloaked(hwnd)
                    || !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
                {
                    ready := false
                    continue
                }
                ; Do not accept a stable but still off-screen/minimized DWM frame.
                ; Use actual bounds, not an in-flight placement reservation.
                if !IsObject(geometry)
                    geometry := GetCanonicalCascadeGeometry(monitor_index)
                if GetMonitorForWindow(hwnd) != monitor_index
                    || !FindNearestCascadeSlot(x, y, geometry.slots, cascade_slot_tolerance)
                {
                    ready := false
                    continue
                }
                WinGetPosPixels(&raw_x, &raw_y, &raw_width, &raw_height, hwnd)
                snapshot .= (
                    hwnd ":" x "," y "," width "," height
                    . ":" raw_x "," raw_y "," raw_width "," raw_height "|"
                )
            }
            catch {
                ready := false
            }
        }

        previous_critical := Critical("On")
        try {
            ; A native callback may have superseded this snapshot during a query.
            if !cascade_restore_batches.Has(monitor_index)
                || cascade_restore_batches[monitor_index] != batch
                || batch.generation != generation
                continue

            for hwnd in stale_targets
                batch.targets.Delete(hwnd)

            now := A_TickCount
            settled := batch.targets.Count = 0
            if !ready {
                batch.snapshot := ""
            } else if snapshot != batch.snapshot {
                batch.snapshot := snapshot
                batch.stable_since := now
            } else if ((now - batch.stable_since) & 0xFFFFFFFF) >= cascade_restore_settle_ms {
                settled := true
            }

            timed_out := ((now - batch.started_tick) & 0xFFFFFFFF) >= cascade_restore_timeout_ms
            if !settled && !timed_out
                continue

            if settled && ready {
                for hwnd in batch.targets
                    ForgetCascadeMinimizedObservation(hwnd)
            }
            cascade_restore_batches.Delete(monitor_index)
            ; Rebuild from current history without adopting windows opened while paused.
            ; The existing planner still preserves explicit drop-slot preferences.
            QueueCascadeCompaction(monitor_index)
            QueueFocusCornerUpdate()
            DebugLog("Cascade restore reconciliation. | monitor=" monitor_index
                " | reason=" (settled ? "settled" : "timeout")
                " | targets=" batch.targets.Count)
        }
        finally {
            Critical(previous_critical)
        }
    }

    if !cascade_restore_batches.Count
        SetTimer(WatchCascadeWindowRestores, 0)
}

RemoveWindowFromCascadeRestore(hwnd)
{
    global cascade_restore_batches

    for monitor_index, batch in cascade_restore_batches.Clone() {
        if !batch.targets.Has(hwnd)
            continue
        batch.targets.Delete(hwnd)
        batch.generation += 1
        batch.snapshot := ""
        if batch.targets.Count
            continue

        cascade_restore_batches.Delete(monitor_index)
        QueueCascadeCompaction(monitor_index)
    }
    if !cascade_restore_batches.Count
        SetTimer(WatchCascadeWindowRestores, 0)
}


; =============================================================================
; minimize state cleanup
; =============================================================================

RemoveWindowFromMinimizeState(hwnd)
{
    RemoveWindowFromCascadeRestore(hwnd)
    ForgetMinimizedCascadeWindow(hwnd)
}

; =============================================================================
; missed restore-event and deferred-work recovery
; =============================================================================

ObserveCascadeMinimizedWindow(hwnd)
{
    global cascade_minimized_observed, cascade_membership_generation
    try {
        pid := WinGetPID(hwnd)
        if !cascade_minimized_observed.Has(hwnd) || cascade_minimized_observed[hwnd] != pid {
            cascade_minimized_observed[hwnd] := pid
            cascade_membership_generation += 1
        }
    }
}

ForgetCascadeMinimizedObservation(hwnd)
{
    global cascade_minimized_observed
    if cascade_minimized_observed.Has(hwnd)
        cascade_minimized_observed.Delete(hwnd)
}

ReconcileCascadeRuntimeState()
{
    if !IsCascadeEnabled()
        return

    global cascade_history, cascade_minimized_observed, cascade_compaction_pending

    ; Reuse the discovery fallback. A missed MINIMIZEEND must not require another
    ; user toggle, and a queued compaction must not depend on one timer delivery.
    for monitor_index, history in cascade_history.Clone() {
        for hwnd in history.Clone() {
            if !DllCall("IsWindow", "ptr", hwnd, "int") {
                ForgetWindow(hwnd)
                continue
            }
            try {
                if WinGetMinMax(hwnd) = -1 {
                    if !cascade_minimized_observed.Has(hwnd)
                        ObserveCascadeMinimizedWindow(hwnd)
                } else if cascade_minimized_observed.Has(hwnd) {
                    pid := cascade_minimized_observed[hwnd]
                    ForgetCascadeMinimizedObservation(hwnd)
                    if WinGetPID(hwnd) = pid
                        TrackCascadeWindowRestores([hwnd])
                }
            }
            catch {
                continue
            }
        }
    }
    for hwnd in cascade_minimized_observed.Clone() {
        if !GetManagedCascadeMonitor(hwnd) || !DllCall("IsWindow", "ptr", hwnd, "int")
            ForgetCascadeMinimizedObservation(hwnd)
    }
    for monitor_index in cascade_compaction_pending {
        if !IsCascadeCompactionDeferred(monitor_index) {
            ScheduleCascadeCompactionFlush(true)
            break
        }
    }
}
