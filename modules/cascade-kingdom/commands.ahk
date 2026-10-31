; Cascade Kingdom commands: adopting, moving, closing, minimizing and
; restoring cascade windows, and recovering missed restore events.

; =============================================================================
; adoption and cross-monitor commands
; =============================================================================

AdoptActiveWindow()
{
    if !IsCascadeEnabled()
        return

    hwnd := WinExist("A")

    if !hwnd || IsShellSurfaceWindow(hwnd)
        return

    ; Prune stale membership before deciding whether this is a true adoption.
    ; A window released by a completed drop is adoptable again. A member is
    ; moved to the least-used slot and keeps its join position.
    managed_monitor := GetLiveCascadeMonitor(hwnd)
    join_position := managed_monitor ? 0 : CaptureWindowShape(hwnd)

    target_monitor := ResolveCascadeDestination(WindowMonitorIndex(hwnd))

    if !target_monitor
        return

    was_manual := SuiteWindowOwnership.Release(hwnd)
    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor) {
        if was_manual
            SuiteWindowOwnership.Claim(hwnd)
        return
    }

    if !managed_monitor
        RememberCascadeJoinPosition(hwnd, join_position, was_manual)
}

; The display of a cascade member after pruning stale membership, or 0.
GetLiveCascadeMonitor(hwnd)
{
    if monitor := GetManagedCascadeMonitor(hwnd) {
        GetLiveCascadeHistory(monitor)
        monitor := GetManagedCascadeMonitor(hwnd)
    }
    return monitor
}

; Where a window was before it joined (a CaptureWindowShape). Each join
; replaces it, so a position never outlives the membership it belongs to; a
; window back from Wonder Windows joins anew from where Wonder Windows had it.
; A fresh join also ends a loan.
RememberCascadeJoinPosition(hwnd, position, was_manual)
{
    if CascadeState.lentWindows.Has(hwnd)
        CascadeState.lentWindows.Delete(hwnd)

    if IsObject(position) {
        position.was_manual := was_manual
        CascadeState.joinPositions[hwnd] := position
    }
    else if CascadeState.joinPositions.Has(hwnd)
        CascadeState.joinPositions.Delete(hwnd)
}

; Caps + Shift + Insert: the active window leaves its cascade and returns to
; where it was before it joined.
ReleaseActiveCascadeWindow()
{
    if !IsCascadeEnabled()
        return

    hwnd := WinExist("A")
    if !hwnd || !GetLiveCascadeMonitor(hwnd) {
        SuiteNotice.Show("status", "Not in a cascade", 1400)
        return
    }

    position := CascadeState.joinPositions.Has(hwnd) ? CascadeState.joinPositions.Delete(hwnd) : 0
    ReleaseCascadeWindow(hwnd)
    ReturnToCascadeJoinPosition(hwnd, position)
}

; A window whose old display is gone stays where it is.
ReturnToCascadeJoinPosition(hwnd, position)
{
    try {
        if !IsObject(position) || WinGetPID(hwnd) != position.pid
            || !GetMonitorForPoint(position.x + position.width // 2, position.y + position.height // 2)
            return false
        if position.placement {
            if !DllCall("SetWindowPlacement", "ptr", hwnd, "ptr", position.placement, "int")
                throw OSError()
        }
        else
            WinMovePixels(position.x, position.y, position.width, position.height, "ahk_id " hwnd)
        if position.was_manual
            SuiteWindowOwnership.Claim(hwnd)
        return true
    }
    catch Error as err {
        DebugError("Return a window to its join position", err)
        return false
    }
}

GatherCascadesToCommandMonitor()
{
    if !IsCascadeEnabled()
        return

    target_monitor := ResolveCascadeDestination(SuiteWorkingMonitor.Get())
    if !target_monitor
        return

    windows_to_gather := []
    seen := Map()

    ; Snapshot first: successful placement moves entries into the target history.
    for monitor_index, history in CascadeState.history {
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

; =============================================================================
; close commands
; =============================================================================

CloseCommandMonitorCascade()
{
    if !IsCascadeEnabled()
        return

    monitor_index := SuiteWorkingMonitor.Get()
    if !monitor_index
        return

    ; Caps + F4 owns every shown cascade window on this monitor.
    CloseCascadeWindowList(GetCascadeWindowsForMonitorClose(monitor_index), monitor_index)
}

GetCascadeWindowsForMonitorClose(monitor_index)
{
    windows := []
    seen := Map()

    for hwnd in GetLiveCascadeHistory(monitor_index) {
        if !IsCascadeCloseEligible(hwnd)
            continue

        seen[hwnd] := true
        windows.Push(hwnd)
    }

    ; Include shown windows already reserved for this monitor even if
    ; asynchronous placement has not reached cascade history yet.
    for hwnd, reservation in CascadeState.placementReservations {
        if reservation["monitor"] != monitor_index
            continue
        if seen.Has(hwnd) || !IsCascadeCloseEligible(hwnd)
            continue

        seen[hwnd] := true
        windows.Push(hwnd)
    }

    return windows
}

IsCascadeCloseEligible(hwnd) => hwnd && WinExist("ahk_id " hwnd) && IsCascadeWindowShown(hwnd)

CloseCascadeWindowList(windows, monitor_index)
{
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
            if !IsCascadeEnabled() || !CascadeState.closeBatches.Has(monitor_index)
                || CascadeState.closeBatches[monitor_index] != batch
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
        if CascadeState.closeBatches.Has(monitor_index)
            && CascadeState.closeBatches[monitor_index] = batch
            SetTimer(ExpireCascadeCloseBatch.Bind(monitor_index, batch), -CascadeState.closeTimeoutMs)
    }
}


BeginCascadeCloseBatch(monitor_index, windows)
{
    batch := {targets: Map()}
    for hwnd in windows {
        try batch.targets[hwnd] := WinGetPID(hwnd)
    }
    if !batch.targets.Count
        return 0
    CascadeState.closeBatches[monitor_index] := batch
    return batch
}


RemoveWindowFromCascadeCloseBatch(hwnd, expected_batch := 0)
{
    previous_critical := Critical("On")
    try {
        for monitor_index, batch in CascadeState.closeBatches.Clone() {
            if IsObject(expected_batch) && batch != expected_batch
                continue
            if !batch.targets.Has(hwnd)
                continue
            batch.targets.Delete(hwnd)
            if batch.targets.Count
                continue
            CascadeState.closeBatches.Delete(monitor_index)
            QueueCascadeCompaction(monitor_index)
        }
    }
    finally {
        Critical(previous_critical)
    }
}

ExpireCascadeCloseBatch(monitor_index, expected_batch)
{
    previous_critical := Critical("On")
    try {
        if !CascadeState.closeBatches.Has(monitor_index)
            || CascadeState.closeBatches[monitor_index] != expected_batch
            return
        CascadeState.closeBatches.Delete(monitor_index)
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
    return (monitor_index && CascadeState.closeBatches.Has(monitor_index))
}


; =============================================================================
; restore saved cascade windows
; =============================================================================

RestoreCascadeWindows(windows)
{
    if windows.Length = 0
        return

    ; Register the whole saved set before the first WinRestore can yield.
    ; Caps + M restores the complete saved set across monitors in one batch.
    batches := Map()
    CascadeState.restoreRequestDepth += 1
    try {
        batches := TrackCascadeWindowRestores(windows)
        RestoreCascadeWindowList(windows)
    }
    finally {
        ; Start the bounded settling period after all requests/Z-order work,
        ; not before a large saved set has even finished receiving WinRestore.
        for monitor_index, batch in batches {
            if CascadeState.restoreBatches.Has(monitor_index)
                && CascadeState.restoreBatches[monitor_index] = batch
            {
                batch.started_tick := A_TickCount
                batch.snapshot := ""
            }
        }
        CascadeState.restoreRequestDepth -= 1
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
    Loop windows.Length {
        hwnd := windows[windows.Length - A_Index + 1]
        if WinExist("ahk_id " hwnd)
            try SetCascadeZOrder(hwnd, 0) ; HWND_TOP
    }

    for hwnd in windows {
        if !WinExist("ahk_id " hwnd)
            continue

        top_restored_hwnd := hwnd
        break
    }

    if top_restored_hwnd
        ActivateWindow(top_restored_hwnd)
}


; =============================================================================
; restore completion and combined-layout compaction
; =============================================================================

TrackCascadeWindowRestores(windows)
{

    tracked_batches := Map()
    for hwnd in windows {
        monitor_index := GetManagedCascadeMonitor(hwnd)
        if !monitor_index
            continue
        try pid := WinGetPID(hwnd)
        catch
            continue

        if !CascadeState.restoreBatches.Has(monitor_index) {
            CascadeState.restoreBatches[monitor_index] := {
                targets: Map(), started_tick: A_TickCount,
                snapshot: "", stable_since: 0, generation: 0
            }
        }
        batch := CascadeState.restoreBatches[monitor_index]
        tracked_batches[monitor_index] := batch
        if batch.targets.Has(hwnd) && batch.targets[hwnd] = pid
            continue
        batch.targets[hwnd] := pid
        batch.generation += 1
        CascadeState.membershipGeneration += 1
        batch.snapshot := ""
    }

    if tracked_batches.Count
        SetTimer(WatchCascadeWindowRestores, CascadeState.restorePollMs)
    return tracked_batches
}

IsCascadeRestoreInProgress(monitor_index)
{
    return CascadeState.restoreRequestDepth > 0
        || CascadeState.restoreBatches.Has(monitor_index)
}

WatchCascadeWindowRestores()
{
    if !IsCascadeEnabled()
        return

    ; Read-only queries stay interruptible. The generation check below discards
    ; a snapshot if a native callback or another restore changed its batch.
    if CascadeState.restoreRequestDepth
        return

    for monitor_index, batch in CascadeState.restoreBatches.Clone() {
        generation := batch.generation
        observed := ReadCascadeRestoreSnapshot(monitor_index, batch)
        previous_critical := Critical("On")
        try SettleCascadeRestore(monitor_index, batch, generation, observed)
        finally {
            Critical(previous_critical)
        }
    }

    if !CascadeState.restoreBatches.Count
        SetTimer(WatchCascadeWindowRestores, 0)
}

; Where a restore batch's windows are now: a signature of their rectangles,
; whether every one is back and shown in a slot, and the targets that left.
ReadCascadeRestoreSnapshot(monitor_index, batch)
{
    geometry := 0
    observed := {snapshot: "", ready: true, stale: []}

    for hwnd, pid in batch.targets.Clone() {
        if !WinExist(hwnd) || GetManagedCascadeMonitor(hwnd) != monitor_index
            || IsCascadeWindowBeingDragged(hwnd)
        {
            observed.stale.Push(hwnd)
            continue
        }
        try {
            if WinGetPID(hwnd) != pid {
                observed.stale.Push(hwnd)
                continue
            }
            state := WinGetMinMax(hwnd)
            if state = 1 {
                ; Respect a maximized window instead of pulling it into slots.
                observed.stale.Push(hwnd)
                continue
            }
            if state != 0 || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
                || IsWindowCloaked(hwnd)
                || !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
            {
                observed.ready := false
                continue
            }
            ; Do not accept a stable but still off-screen/minimized DWM frame.
            ; Use actual bounds, not an in-flight placement reservation.
            if !IsObject(geometry)
                geometry := GetCanonicalCascadeGeometry(monitor_index)
            if WindowMonitorIndex(hwnd) != monitor_index
                || !FindNearestCascadeSlot(x, y, geometry.slots, CascadeState.slotTolerance)
            {
                observed.ready := false
                continue
            }
            WinGetPosPixels(&raw_x, &raw_y, &raw_width, &raw_height, hwnd)
            observed.snapshot .= (hwnd ":" x "," y "," width "," height
                . ":" raw_x "," raw_y "," raw_width "," raw_height "|")
        }
        catch {
            observed.ready := false
        }
    }
    return observed
}

; Ends a restore batch once its windows have held still long enough, or it
; timed out, and lets the cascade close up. Runs inside a critical section.
SettleCascadeRestore(monitor_index, batch, generation, observed)
{
    ; A native callback may have superseded this snapshot during a query.
    if !CascadeState.restoreBatches.Has(monitor_index)
        || CascadeState.restoreBatches[monitor_index] != batch
        || batch.generation != generation
        return

    for hwnd in observed.stale
        batch.targets.Delete(hwnd)

    now := A_TickCount
    settled := batch.targets.Count = 0
    if !observed.ready {
        batch.snapshot := ""
    } else if observed.snapshot != batch.snapshot {
        batch.snapshot := observed.snapshot
        batch.stable_since := now
    } else if ((now - batch.stable_since) & 0xFFFFFFFF) >= CascadeState.restoreSettleMs {
        settled := true
    }

    timed_out := ((now - batch.started_tick) & 0xFFFFFFFF) >= CascadeState.restoreTimeoutMs
    if !settled && !timed_out
        return

    if settled && observed.ready {
        for hwnd in batch.targets
            ForgetCascadeMinimizedObservation(hwnd)
    }
    CascadeState.restoreBatches.Delete(monitor_index)
    ; Rebuild from current history without adopting windows opened while paused.
    ; The existing planner still preserves explicit drop-slot preferences.
    QueueCascadeCompaction(monitor_index)
    QueueFocusCornerUpdate()
    DebugLog("Cascade restore reconciliation. | monitor=" monitor_index
        " | reason=" (settled ? "settled" : "timeout")
        " | targets=" batch.targets.Count)
}

RemoveWindowFromCascadeRestore(hwnd)
{
    for monitor_index, batch in CascadeState.restoreBatches.Clone() {
        if !batch.targets.Has(hwnd)
            continue
        batch.targets.Delete(hwnd)
        batch.generation += 1
        batch.snapshot := ""
        if batch.targets.Count
            continue

        CascadeState.restoreBatches.Delete(monitor_index)
        QueueCascadeCompaction(monitor_index)
    }
    if !CascadeState.restoreBatches.Count
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
    try {
        pid := WinGetPID(hwnd)
        if !CascadeState.minimizedObserved.Has(hwnd) || CascadeState.minimizedObserved[hwnd] != pid {
            CascadeState.minimizedObserved[hwnd] := pid
            CascadeState.membershipGeneration += 1
        }
    }
}

ForgetCascadeMinimizedObservation(hwnd)
{
    if CascadeState.minimizedObserved.Has(hwnd)
        CascadeState.minimizedObserved.Delete(hwnd)
}

; The display a member now sits on when something other than Cascade Kingdom
; moved it there, such as Win + Shift + Left/Right or the app itself; else 0.
GetMovedCascadeMemberMonitor(hwnd, monitor_index)
{
    if IsCascadeDisplayTransition() || HasPendingCascadeDisplayLayout(monitor_index)
        || IsCascadeRestoreInProgress(monitor_index) || IsCascadeWindowBeingDragged(hwnd)
        || CascadeState.placementReservations.Has(hwnd) || CascadeState.placementStabilizationGenerations.Has(hwnd)
        || WinGetMinMax(hwnd) != 0
        return 0
    current := WindowMonitorIndex(hwnd)
    return current && current != monitor_index ? current : 0
}

; A moved member joins the cascade on its new display, or leaves the cascade
; when that display is excluded, as a drag there would.
FollowMovedCascadeMember(hwnd, monitor)
{
    RemoveWindowFromMinimizeState(hwnd)
    if CascadeDisplayAllowed(monitor) && PlaceCascadeWindowOnMonitor(hwnd, monitor)
        QueueFocusCornerUpdate()
    else
        ReleaseCascadeWindow(hwnd)
    DebugLog("Cascade member moved to display " monitor ". | " DescribeWindow(hwnd))
}

ReconcileCascadeRuntimeState()
{
    if !IsCascadeEnabled()
        return

    static shown_members := Map()

    ; A missed MINIMIZEEND must not require another user toggle, and a queued
    ; compaction must not depend on one timer delivery.
    shown_now := Map()
    for monitor_index, history in CascadeState.history.Clone() {
        for hwnd in history.Clone() {
            if !DllCall("IsWindow", "ptr", hwnd, "int") {
                ForgetWindow(hwnd)
                continue
            }
            ; Catch slot changes no event announces, such as a maximize or a
            ; move to another virtual desktop.
            shown_now[hwnd] := IsCascadeWindowShown(hwnd)
            if shown_members.Has(hwnd) && shown_members[hwnd] != shown_now[hwnd]
                QueueCascadeCompaction(monitor_index)
            try {
                if WinGetMinMax(hwnd) = -1 {
                    if !CascadeState.minimizedObserved.Has(hwnd)
                        ObserveCascadeMinimizedWindow(hwnd)
                } else if CascadeState.minimizedObserved.Has(hwnd) {
                    pid := CascadeState.minimizedObserved[hwnd]
                    ForgetCascadeMinimizedObservation(hwnd)
                    if WinGetPID(hwnd) = pid
                        TrackCascadeWindowRestores([hwnd])
                } else if (moved_to := GetMovedCascadeMemberMonitor(hwnd, monitor_index))
                    FollowMovedCascadeMember(hwnd, moved_to)
            }
            catch {
                continue
            }
        }
    }
    shown_members := shown_now
    for hwnd in CascadeState.minimizedObserved.Clone() {
        if !GetManagedCascadeMonitor(hwnd) || !DllCall("IsWindow", "ptr", hwnd, "int")
            ForgetCascadeMinimizedObservation(hwnd)
    }
    for monitor_index in CascadeState.compactionPending {
        if !IsCascadeCompactionDeferred(monitor_index) {
            ScheduleCascadeCompactionFlush(true)
            break
        }
    }
}
