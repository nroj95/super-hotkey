; Cascade Kingdom Windows event hooks, the slow polling fallback and cleanup
; after destroyed windows. Windows join a cascade only when the user adopts
; one (Caps + Insert) or drops one onto a slot; nothing here adopts windows.

; =============================================================================
; slow polling fallback
; =============================================================================

; Catches display changes, minimize and restore events and compactions that
; the hooks missed.
PollCascadeState()
{
    if !IsCascadeEnabled()
        return
    PollCascadeDisplayEnvironment()
    ReconcileCascadeRuntimeState()
}


; =============================================================================
; Windows event hooks
; =============================================================================

StartWindowHooks()
{
    global win_event_callback, win_event_hooks

    win_event_callback := CallbackCreate(HandleWinEvent)
    ; Foreground, move/size start and end, minimize start and end, and window
    ; destroy, show and hide, out of context and skipping our own process.
    ; MINIMIZEEND announces a restore, not settled geometry. The shared
    ; completion watcher confirms readiness before requesting compaction.
    for range in [[0x0003, 0x0003], [0x000A, 0x000B], [0x0016, 0x0017], [0x8001, 0x8003]] {
        hook := DllCall("SetWinEventHook", "uint", range[1], "uint", range[2], "ptr", 0,
            "ptr", win_event_callback, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")
        if !hook {
            SuiteState.Log.Write("Cascade Kingdom", "could not install all Windows event hooks", "ERROR")
            continue
        }
        win_event_hooks.Push(hook)
    }
}

StopWindowHooks()
{
    global win_event_callback, win_event_hooks

    SetTimer(PollCascadeState, 0)
    SetTimer(UpdateFocusCornerOverlays, 0)
    SetTimer(RunQueuedFocusCornerUpdate, 0)
    SetTimer(WatchCascadeWindowDrag, 0)
    SetTimer(WatchCascadeWindowRestores, 0)
    SetTimer(FlushCascadeCompactions, 0)

    for hook in win_event_hooks
        DllCall("UnhookWinEvent", "ptr", hook)
    win_event_hooks := []
    if win_event_callback {
        CallbackFree(win_event_callback)
        win_event_callback := 0
    }
}

HandleWinEvent(hook_handle, event, hwnd, object_id, child_id, event_thread, event_time)
{
    try {
        EVENT_SYSTEM_FOREGROUND := 0x0003
        EVENT_OBJECT_DESTROY := 0x8001
        EVENT_OBJECT_SHOW := 0x8002
        EVENT_OBJECT_HIDE := 0x8003
        EVENT_SYSTEM_MOVESIZESTART := 0x000A
        EVENT_SYSTEM_MOVESIZEEND := 0x000B
        EVENT_SYSTEM_MINIMIZESTART := 0x0016
        EVENT_SYSTEM_MINIMIZEEND := 0x0017
        OBJID_WINDOW := 0
        CHILDID_SELF := 0

        if event = EVENT_SYSTEM_FOREGROUND {
            QueueFocusCornerUpdate()
            return
        }

        if object_id != OBJID_WINDOW || child_id != CHILDID_SELF || !hwnd
            return

        if event = EVENT_OBJECT_DESTROY {
            was_managed := !!GetManagedCascadeMonitor(hwnd)
            ; Filter logging, not cleanup: unrelated system-wide destroys stay quiet.
            if was_managed
                DebugLog("Destroy event." . " | " DescribeWindow(hwnd))
            ForgetWindow(hwnd)
            if was_managed
                QueueFocusCornerUpdate()
            return
        }

        if event = EVENT_SYSTEM_MINIMIZESTART {
            if monitor := GetManagedCascadeMonitor(hwnd) {
                ObserveCascadeMinimizedWindow(hwnd)
                CancelPlacementStabilization(hwnd)
                ; Close the gap; a restore returns the window to its slot.
                QueueCascadeCompaction(monitor)
            }
            RemoveWindowFromCascadeRestore(hwnd)
            return
        }

        if event = EVENT_SYSTEM_MINIMIZEEND {
            ; A manual restore relinquishes ownership of the Caps + M saved set.
            ForgetMinimizedCascadeWindow(hwnd)
            CancelPlacementStabilization(hwnd)
            TrackCascadeWindowRestores([hwnd])
            SetTimer(ApplyPendingCascadeDisplayLayout, -50)
            return
        }

        if event = EVENT_SYSTEM_MOVESIZESTART {
            BeginCascadeWindowDrag(hwnd, event_time)
            return
        }

        if event = EVENT_SYSTEM_MOVESIZEEND {
            EndCascadeWindowDrag(hwnd)
            return
        }

        ; A member hidden to the tray gives up its slot; shown again, it takes it back.
        if (event = EVENT_OBJECT_SHOW || event = EVENT_OBJECT_HIDE)
            && (monitor := GetManagedCascadeMonitor(hwnd))
        {
            QueueCascadeCompaction(monitor)
            QueueFocusCornerUpdate()
        }
    }
    catch Error as err {
        DebugError("HandleWinEvent", err)
    }
}


; =============================================================================
; destroyed window cleanup
; =============================================================================

ForgetWindow(hwnd)
{
    global cascade_join_positions, cascade_lent_windows

    ; Do not wait for the next visual sweep: a destroyed target must never leave
    ; its script-owned focus GUI behind.
    DestroyFocusCornerOverlay(hwnd)

    affected_monitor := GetManagedCascadeMonitor(hwnd)

    if IsCascadeWindowBeingDragged(hwnd)
        StopCascadeWindowDrag()

    if cascade_join_positions.Has(hwnd)
        cascade_join_positions.Delete(hwnd)
    if cascade_lent_windows.Has(hwnd)
        cascade_lent_windows.Delete(hwnd)

    CancelPlacementStabilization(hwnd)

    RemoveWindowFromMinimizeState(hwnd)

    RemoveCascadeWindowFromHistory(hwnd)
    ForgetCascadeMinimizedObservation(hwnd)

    RemoveWindowFromCascadeCloseBatch(hwnd)

    if affected_monitor
        QueueCascadeCompaction(affected_monitor)
}
