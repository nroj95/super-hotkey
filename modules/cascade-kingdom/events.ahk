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
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook
    global window_move_size_hook, window_restore_hook

    EVENT_SYSTEM_FOREGROUND := 0x0003
    EVENT_OBJECT_DESTROY := 0x8001
    EVENT_OBJECT_SHOW := 0x8002
    EVENT_SYSTEM_MOVESIZESTART := 0x000A
    EVENT_SYSTEM_MOVESIZEEND := 0x000B
    EVENT_SYSTEM_MINIMIZESTART := 0x0016
    EVENT_SYSTEM_MINIMIZEEND := 0x0017

    WINEVENT_OUTOFCONTEXT := 0x0000
    WINEVENT_SKIPOWNPROCESS := 0x0002
    flags := WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS

    win_event_callback := CallbackCreate(HandleWinEvent)

    foreground_hook := DllCall("SetWinEventHook", "uint", EVENT_SYSTEM_FOREGROUND,
        "uint", EVENT_SYSTEM_FOREGROUND, "ptr", 0, "ptr", win_event_callback, "uint", 0, "uint", 0,
        "uint", flags, "ptr")


    window_show_hook := DllCall("SetWinEventHook", "uint", EVENT_OBJECT_SHOW,
        "uint", EVENT_OBJECT_SHOW, "ptr", 0, "ptr", win_event_callback, "uint", 0, "uint", 0,
        "uint", flags, "ptr")


    window_destroy_hook := DllCall("SetWinEventHook", "uint", EVENT_OBJECT_DESTROY,
        "uint", EVENT_OBJECT_DESTROY, "ptr", 0, "ptr", win_event_callback, "uint", 0, "uint", 0,
        "uint", flags, "ptr")


    window_move_size_hook := DllCall("SetWinEventHook", "uint", EVENT_SYSTEM_MOVESIZESTART,
        "uint", EVENT_SYSTEM_MOVESIZEEND, "ptr", 0, "ptr", win_event_callback, "uint", 0, "uint", 0,
        "uint", flags, "ptr")

    ; MINIMIZEEND announces a restore, not settled geometry. The shared
    ; completion watcher confirms readiness before requesting compaction.
    window_restore_hook := DllCall("SetWinEventHook", "uint", EVENT_SYSTEM_MINIMIZESTART,
        "uint", EVENT_SYSTEM_MINIMIZEEND, "ptr", 0, "ptr", win_event_callback, "uint", 0, "uint", 0,
        "uint", flags, "ptr")

    if (!foreground_hook || !window_show_hook || !window_destroy_hook || !window_move_size_hook
        || !window_restore_hook) {

        MsgBox(
            "Could not install all Windows event hooks.`n`n"
            . "Cascade Kingdom may not track windows correctly.",
            "Cascade Kingdom",
            "Iconx"
        )
    }
}

StopWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook
    global window_move_size_hook, window_restore_hook

    SetTimer(PollCascadeState, 0)
    SetTimer(UpdateFocusCornerOverlays, 0)
    SetTimer(RunQueuedFocusCornerUpdate, 0)
    SetTimer(WatchCascadeWindowDrag, 0)
    SetTimer(WatchCascadeWindowRestores, 0)
    SetTimer(FlushCascadeCompactions, 0)

    if foreground_hook {
        DllCall("UnhookWinEvent", "ptr", foreground_hook)
        foreground_hook := 0
    }

    if window_show_hook {
        DllCall("UnhookWinEvent", "ptr", window_show_hook)
        window_show_hook := 0
    }

    if window_destroy_hook {
        DllCall("UnhookWinEvent", "ptr", window_destroy_hook)
        window_destroy_hook := 0
    }

    if window_move_size_hook {
        DllCall("UnhookWinEvent", "ptr", window_move_size_hook)
        window_move_size_hook := 0
    }

    if window_restore_hook {
        DllCall("UnhookWinEvent", "ptr", window_restore_hook)
        window_restore_hook := 0
    }

    if win_event_callback {
        CallbackFree(win_event_callback)
        win_event_callback := 0
    }
}

HandleWinEvent(hook_handle, event, hwnd, object_id, child_id, event_thread, event_time)
{
    global current_foreground_hwnd
    try {
        EVENT_SYSTEM_FOREGROUND := 0x0003
        EVENT_OBJECT_DESTROY := 0x8001
        EVENT_OBJECT_SHOW := 0x8002
        EVENT_SYSTEM_MOVESIZESTART := 0x000A
        EVENT_SYSTEM_MOVESIZEEND := 0x000B
        EVENT_SYSTEM_MINIMIZESTART := 0x0016
        EVENT_SYSTEM_MINIMIZEEND := 0x0017
        OBJID_WINDOW := 0
        CHILDID_SELF := 0

        if event = EVENT_SYSTEM_FOREGROUND {
            ; Moving to another window expires a pending Caps + Insert undo.
            if hwnd && hwnd != current_foreground_hwnd {
                CancelPendingAdoptionUndo()
                current_foreground_hwnd := hwnd
                DebugLog("Foreground changed." . " | current=" DescribeWindow(hwnd))
            }
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
            if GetManagedCascadeMonitor(hwnd) {
                ObserveCascadeMinimizedWindow(hwnd)
                CancelPlacementStabilization(hwnd)
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

        if event = EVENT_OBJECT_SHOW && GetManagedCascadeMonitor(hwnd)
            QueueFocusCornerUpdate()
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
    global placement_reservations, pending_adoption_undo, current_foreground_hwnd

    ; Do not wait for the next visual sweep: a destroyed target must never leave
    ; its script-owned focus GUI behind.
    DestroyFocusCornerOverlay(hwnd)

    affected_monitor := GetManagedCascadeMonitor(hwnd)

    if IsCascadeWindowBeingDragged(hwnd)
        StopCascadeWindowDrag()

    if IsPendingAdoptionUndoFor(hwnd)
        pending_adoption_undo := 0

    CancelPlacementStabilization(hwnd)

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if current_foreground_hwnd = hwnd
        current_foreground_hwnd := 0

    RemoveWindowFromMinimizeState(hwnd)

    RemoveCascadeWindowFromHistory(hwnd)
    ForgetCascadeMinimizedObservation(hwnd)

    RemoveWindowFromCascadeCloseBatch(hwnd)

    if affected_monitor
        QueueCascadeCompaction(affected_monitor)
}
