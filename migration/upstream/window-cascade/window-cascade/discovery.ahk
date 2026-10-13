; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; desktop monitor selection
; =============================================================================

CaptureDesktopMonitorHint()
{
    if !IsCascadeEnabled()
        return

    global desktop_monitor_hint, desktop_monitor_hint_tick

    MouseGetPosPixels(&mouse_x, &mouse_y, &hover_hwnd)

    if !hover_hwnd
        return

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hover_hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if !IsDesktopSurfaceWindow(hover_hwnd)
        && !IsDesktopSurfaceWindow(root_hwnd)
        return

    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

    if !monitor_index
        return

    desktop_monitor_hint := monitor_index
    desktop_monitor_hint_tick := A_TickCount

}


; =============================================================================
; window discovery and placement queue
; =============================================================================

SeedStartupWindows()
{
    global startup_windows, known_windows

    startup_windows := Map()
    known_windows := Map()

    for hwnd in WinGetList() {
        startup_windows[hwnd] := true
        known_windows[hwnd] := true
    }

}

QueueWindowPlacement(hwnd, source_hwnd)
{
    if !IsCascadeEnabled()
        return
    if !IsCascadeAutoPlacementEnabled() {
        RememberWindowDuringAutoPlacementPause(hwnd)
        return
    }

    global pending_windows, known_windows, placement_delay_ms

    ; Once any discovery path adopts an HWND, the polling fallback no longer
    ; needs to rediscover the same window.
    known_windows[hwnd] := true


    if pending_windows.Has(hwnd)
        return
    try pid := WinGetPID(hwnd)
    catch
        return
    request := {pid: pid, focus: CaptureNewWindowFocusContext(hwnd)}
    ConsumeExplorerSpaceIntentForNewWindow(hwnd, source_hwnd, pid)
    pending_windows[hwnd] := request

    ; Snapshot once here. Readiness retries and settling reuse this monitor
    ; instead of sampling a later mouse position.
    MouseGetPosPixels(&queue_mouse_x, &queue_mouse_y)
    queued_monitor := GetMonitorForPoint(
        queue_mouse_x,
        queue_mouse_y
    )
    ; The device name survives an index reorder while a new window is settling.
    request.monitor_device := GetCascadeMonitorDevice(queued_monitor)

    DebugLog(
        "Queue placement."
        . " | target=" DebugDescribeWindow(hwnd)
        . " | source=" DebugDescribeWindow(source_hwnd)
        . " | queued-monitor=" queued_monitor
        . " | mouse=(" queue_mouse_x "," queue_mouse_y ")"
    )


    SetTimer(
        PlaceNewWindow.Bind(
            hwnd,
            source_hwnd,
            queued_monitor,
            0,
            false,
            request
        ),
        -placement_delay_ms
    )
}

ConsumeExplorerSpaceIntentForNewWindow(hwnd, source_hwnd, target_pid)
{
    global explorer_space_reshow_hint, handled_reshow_hint_max_age_ms
    global debug_enabled, debug_verbose_enabled

    if !IsObject(explorer_space_reshow_hint) || !hwnd || !source_hwnd
        return false

    hint := explorer_space_reshow_hint
    if hint.HasOwnProp("reshow_hwnd")
        return false

    hint_age := (A_TickCount - hint.tick) & 0xFFFFFFFF
    if hint_age > handled_reshow_hint_max_age_ms
        return false

    try {
        if source_hwnd != hint.source_hwnd
            || !WinExist("ahk_id " source_hwnd)
            || WinGetPID("ahk_id " source_hwnd) != hint.source_pid
            || WinGetProcessName("ahk_id " source_hwnd) != "explorer.exe"
            || target_pid = hint.source_pid
            return false
    }
    catch {
        return false
    }

    explorer_space_reshow_hint := 0
    if debug_enabled && debug_verbose_enabled {
        DebugLog(
            "Explorer Space re-show intent consumed by new window."
            . " | target=" DebugDescribeWindow(hwnd)
        )
    }
    return true
}

GetHandledWindowReshowIntent(hwnd, trigger := "show")
{
    global cascade_launch_hint, explorer_space_reshow_hint
    global handled_reshow_hint_max_age_ms
    global current_foreground_hwnd, previous_foreground_hwnd

    if trigger != "show" && trigger != "foreground"
        return 0

    ; Plain Space in Explorer is a generic re-show intent, not an app allow-list.
    ; Bind it to the first other-process managed HWND that re-shows, then require
    ; that target to own foreground when the delayed reconciliation runs.
    if IsObject(explorer_space_reshow_hint) {
        hint := explorer_space_reshow_hint
        hint_age := (A_TickCount - hint.tick) & 0xFFFFFFFF
        if hint_age <= handled_reshow_hint_max_age_ms {
            try {
                source_hwnd := hint.source_hwnd
                if source_hwnd
                    && hwnd != source_hwnd
                    && WinExist("ahk_id " source_hwnd)
                    && WinGetPID("ahk_id " source_hwnd) = hint.source_pid
                    && WinGetProcessName("ahk_id " source_hwnd) = "explorer.exe"
                    && WinGetPID("ahk_id " hwnd) != hint.source_pid
                {
                    if !hint.HasOwnProp("reshow_hwnd") || hint.reshow_hwnd = hwnd
                        return {kind: "explorer-space", trigger: trigger, hint: hint}
                }
            }
            catch {
                ; Identity or process queries failing simply invalidate the hint.
            }
        }
    }

    ; Taskbar intent remains SHOW-only. A foreground event by itself is too broad
    ; for taskbar clicks because ordinary focus changes can follow them.
    if trigger != "show" || !IsObject(cascade_launch_hint)
        return 0

    hint := cascade_launch_hint
    hint_age := (A_TickCount - hint.tick) & 0xFFFFFFFF
    if hint_age > handled_reshow_hint_max_age_ms
        return 0

    ; SHOW and FOREGROUND can arrive in either order. Require the current native
    ; foreground or one side of our foreground handoff to still be a taskbar.
    native_foreground := DllCall("GetForegroundWindow", "ptr")
    if !IsTaskbarSurfaceWindow(native_foreground)
        && !IsTaskbarSurfaceWindow(current_foreground_hwnd)
        && !IsTaskbarSurfaceWindow(previous_foreground_hwnd)
        return 0

    return {kind: "taskbar", trigger: trigger, hint: hint}
}

IsCurrentHandledWindowReshowIntent(kind, hint)
{
    global cascade_launch_hint, explorer_space_reshow_hint

    if kind = "taskbar"
        return IsObject(cascade_launch_hint) && cascade_launch_hint = hint
    if kind = "explorer-space"
        return IsObject(explorer_space_reshow_hint) && explorer_space_reshow_hint = hint
    return false
}

ConsumeHandledWindowReshowIntent(kind, hint)
{
    global cascade_launch_hint, explorer_space_reshow_hint

    if kind = "taskbar" {
        if IsObject(cascade_launch_hint) && cascade_launch_hint = hint
            cascade_launch_hint := 0
        return
    }

    if kind = "explorer-space"
        && IsObject(explorer_space_reshow_hint) && explorer_space_reshow_hint = hint
        explorer_space_reshow_hint := 0
}

CancelBoundExplorerSpaceReshowOnForeground(hwnd)
{
    global explorer_space_reshow_hint

    if !hwnd || !IsObject(explorer_space_reshow_hint)
        return

    hint := explorer_space_reshow_hint
    if !hint.HasOwnProp("reshow_hwnd")
        return

    ; Explorer itself and shell handoffs are expected before the preview wins focus.
    ; A different real application means the user has moved on from this intent.
    if hwnd = hint.reshow_hwnd || hwnd = hint.source_hwnd || IsShellSurfaceWindow(hwnd)
        return

    explorer_space_reshow_hint := 0
}

TryQueueHandledWindowReshow(hwnd, trigger := "show")
{
    global handled_windows, placement_delay_ms

    if !handled_windows.Has(hwnd)
        return false

    source_monitor := GetManagedCascadeMonitor(hwnd)
    if !source_monitor
        return false

    intent := GetHandledWindowReshowIntent(hwnd, trigger)
    if !IsObject(intent)
        return false

    hint := intent.hint
    target_monitor := 0
    monitor_device := ""
    try target_monitor := hint.monitor
    try monitor_device := hint.monitor_device
    if monitor_device != "" {
        resolved_monitor := FindCascadeMonitorDevice(monitor_device)
        if resolved_monitor
            target_monitor := resolved_monitor
    }
    if !target_monitor
        return false

    try pid := WinGetPID(hwnd)
    catch
        return false

    if hint.HasOwnProp("reshow_hwnd") {
        if hint.reshow_hwnd != hwnd
            return false
        ; A SHOW callback may have bound this target before it won foreground.
        ; Let the matching FOREGROUND event queue a fresh identity-checked pass.
        if intent.kind != "explorer-space" || trigger != "foreground"
            return true
    } else {
        hint.reshow_hwnd := hwnd
    }

    request := {
        hwnd: hwnd,
        pid: pid,
        source_monitor: source_monitor,
        target_monitor: target_monitor,
        monitor_device: monitor_device,
        intent_kind: intent.kind,
        trigger: intent.trigger,
        hint: hint
    }

    DebugLog(
        "Handled window " intent.kind " re-show queued."
        . " | trigger=" intent.trigger
        . " | from-monitor=" source_monitor
        . " | target-monitor=" target_monitor
        . " | target=" DebugDescribeWindow(hwnd)
    )

    SetTimer(
        PlaceHandledWindowReshow.Bind(request),
        -placement_delay_ms
    )
    return true
}

HandledWindowReshowMatchesRememberedPlacement(hwnd, placement)
{
    global placement_stabilize_tolerance

    if !IsObject(placement) || GetMonitorForWindow(hwnd) != placement.monitor
        return false

    if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
        return false

    return (
        Abs(x - placement.x) <= placement_stabilize_tolerance
        && Abs(y - placement.y) <= placement_stabilize_tolerance
        && Abs(width - placement.width) <= placement_stabilize_tolerance
        && Abs(height - placement.height) <= placement_stabilize_tolerance
    )
}


PlaceHandledWindowReshow(request)
{
    global handled_windows, handled_reshow_hint_max_age_ms

    keep_intent := false
    try {
        if !IsCascadeEnabled()
            || !IsCurrentHandledWindowReshowIntent(request.intent_kind, request.hint)
            return

        hint_age := (A_TickCount - request.hint.tick) & 0xFFFFFFFF
        if hint_age > handled_reshow_hint_max_age_ms {
            DebugLog(
                "Handled window " request.intent_kind " re-show skipped."
                . " | reason=intent-expired"
                . " | target=" DebugDescribeWindow(request.hwnd)
            )
            return
        }

        hwnd := request.hwnd
        if !handled_windows.Has(hwnd)
            || !WinExist("ahk_id " hwnd)
            || WinGetPID(hwnd) != request.pid
            return

        source_monitor := GetManagedCascadeMonitor(hwnd)
        if !source_monitor
            return

        ; SHOW can precede FOREGROUND. Keep the already-bound Explorer intent alive
        ; only for that ordering; a later matching FOREGROUND event queues another pass.
        if request.intent_kind = "explorer-space"
            && DllCall("GetForegroundWindow", "ptr") != hwnd
        {
            keep_intent := request.trigger = "show"
            DebugLog(
                "Handled window explorer-space re-show "
                . (keep_intent ? "waiting." : "skipped.")
                . " | reason=target-not-foreground"
                . " | trigger=" request.trigger
                . " | target=" DebugDescribeWindow(hwnd)
            )
            return
        }

        target_monitor := request.target_monitor
        if request.monitor_device != "" {
            resolved_monitor := FindCascadeMonitorDevice(request.monitor_device)
            if resolved_monitor
                target_monitor := resolved_monitor
        }
        if !target_monitor
            return

        same_monitor := target_monitor = source_monitor
        mode := same_monitor ? "restore-slot" : "move-monitor"
        requested_position := 0
        preserve_membership_order := false

        ; A trusted re-show may repair placement, but it is not permission to
        ; undo an application/user maximize or minimize state.
        if WinGetMinMax(hwnd) != 0 {
            DebugLog(
                "Handled window " request.intent_kind " re-show placement skipped."
                . " | mode=" mode
                . " | reason=non-normal-state"
                . " | target=" DebugDescribeWindow(hwnd)
            )
            return
        }

        if same_monitor {
            remembered := GetRememberedCascadePlacement(hwnd, target_monitor)
            if !IsObject(remembered) {
                DebugLog(
                    "Handled window " request.intent_kind " re-show placement skipped."
                    . " | mode=" mode
                    . " | reason=no-remembered-slot"
                    . " | target=" DebugDescribeWindow(hwnd)
                )
                return
            }
            if HandledWindowReshowMatchesRememberedPlacement(hwnd, remembered) {
                DebugLog(
                    "Handled window " request.intent_kind " re-show placement skipped."
                    . " | mode=" mode
                    . " | reason=already-matched"
                    . " | target=" DebugDescribeWindow(hwnd)
                )
                return
            }
            requested_position := [remembered.x, remembered.y]
            preserve_membership_order := true
        }

        DebugLog(
            "Handled window " request.intent_kind " re-show placement begin."
            . " | mode=" mode
            . " | from-monitor=" source_monitor
            . " | target-monitor=" target_monitor
            . " | target=" DebugDescribeWindow(hwnd)
        )

        placed := PlaceCascadeWindowOnMonitor(
            hwnd,
            target_monitor,
            requested_position,
            preserve_membership_order
        )

        if placed {
            DebugLog(
                "Handled window " request.intent_kind " re-show placement complete."
                . " | mode=" mode
                . " | monitor=" target_monitor
                . " | " DebugDescribeWindow(hwnd)
            )
        } else {
            DebugLog(
                "Handled window " request.intent_kind " re-show placement skipped."
                . " | mode=" mode
                . " | target-monitor=" target_monitor
                . " | " DebugDescribeWindow(hwnd)
            )
        }
    }
    catch Error as err {
        DebugError("Handled window re-show", err)
    }
    finally {
        if !keep_intent
            ConsumeHandledWindowReshowIntent(request.intent_kind, request.hint)
    }
}

WatchForMissedWindows()
{
    if !IsCascadeEnabled()
        return

    global known_windows
    global debug_enabled, debug_verbose_enabled
    global pending_windows, handled_windows
    global current_foreground_hwnd, previous_foreground_hwnd

    PollCascadeDisplayEnvironment()
    for hwnd in WinGetList() {
        if known_windows.Has(hwnd)
            continue

        ; Record the HWND immediately. Rejected helper windows should not be
        ; reconsidered every polling cycle.
        known_windows[hwnd] := true

        if debug_enabled && debug_verbose_enabled {
            DebugLog(
                "Poll discovered HWND."
                . " | " DebugDescribeWindow(hwnd)
            )
        }

        if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
            continue

        if !IsPlausibleTopLevelWindow(hwnd) {
            if debug_enabled && debug_verbose_enabled {
                DebugLog(
                    "Poll rejected by top-level prefilter."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }
            continue
        }

        source_hwnd := current_foreground_hwnd

        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd


        QueueWindowPlacement(hwnd, source_hwnd)
    }
    ReconcileCascadeRuntimeState()
}

TryQueueForegroundFallback(hwnd)
{
    if !IsCascadeEnabled()
        return

    global startup_windows
    global pending_windows, handled_windows
    global previous_foreground_hwnd

    if !hwnd
        return

    ; Never adopt a window merely because it was already open when this script
    ; started.
    if startup_windows.Has(hwnd)
        return

    if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
        return

    if !IsPlausibleTopLevelWindow(hwnd)
        return

    source_hwnd := previous_foreground_hwnd

    if source_hwnd = hwnd
        source_hwnd := 0


    QueueWindowPlacement(hwnd, source_hwnd)
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

    foreground_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_FOREGROUND,
        "uint", EVENT_SYSTEM_FOREGROUND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_show_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_SHOW,
        "uint", EVENT_OBJECT_SHOW,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_destroy_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_DESTROY,
        "uint", EVENT_OBJECT_DESTROY,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_move_size_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_MOVESIZESTART,
        "uint", EVENT_SYSTEM_MOVESIZEEND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )

    ; MINIMIZEEND announces a restore, not settled geometry. The shared
    ; completion watcher confirms readiness before requesting compaction.
    window_restore_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_MINIMIZESTART,
        "uint", EVENT_SYSTEM_MINIMIZEEND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )

    if (
        !foreground_hook
        || !window_show_hook
        || !window_destroy_hook
        || !window_move_size_hook
        || !window_restore_hook
    ) {

        MsgBox(
            "Could not install all Windows event hooks.`n`n"
            . "Window Cascade may not track windows correctly.",
            "Window Cascade",
            "Iconx"
        )
    }
}

StopWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook
    global window_move_size_hook, window_restore_hook

    SetTimer(WatchForMissedWindows, 0)
    SetTimer(UpdateFocusCornerOverlays, 0)
    SetTimer(RunQueuedFocusCornerUpdate, 0)
    SetTimer(WatchCascadeWindowDrag, 0)
    SetTimer(WatchCascadeWindowRestores, 0)
    SetTimer(FlushCascadeCompactions, 0)
    CancelNewWindowFocus()


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

HandleWinEvent(
    hook_handle,
    event,
    hwnd,
    object_id,
    child_id,
    event_thread,
    event_time
)
{
    global current_foreground_hwnd, previous_foreground_hwnd
    global pending_windows, handled_windows
    global startup_windows
    global desktop_monitor_hint, desktop_monitor_hint_tick
    global debug_enabled, debug_verbose_enabled

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
            ObserveNewWindowForeground(hwnd)
            if hwnd && hwnd != current_foreground_hwnd {
                CancelPendingAdoptionUndo()

                previous_foreground_hwnd := current_foreground_hwnd
                current_foreground_hwnd := hwnd

                DebugLog(
                    "Foreground changed."
                    . " | current=" DebugDescribeWindow(hwnd)
                    . " | previous="
                    . DebugDescribeWindow(previous_foreground_hwnd)
                )

                if IsDesktopSurfaceWindow(hwnd) {
                    MouseGetPosPixels(&mouse_x, &mouse_y)
                    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

                    if monitor_index {
                        desktop_monitor_hint := monitor_index
                        desktop_monitor_hint_tick := A_TickCount

                    }
                }
            }

            ; Some reusable managed windows become foreground without emitting a
            ; SHOW event. Only intent sources that explicitly allow foreground may
            ; bind here; taskbar intent remains SHOW-only.
            if handled_windows.Has(hwnd)
                TryQueueHandledWindowReshow(hwnd, "foreground")
            CancelBoundExplorerSpaceReshowOnForeground(hwnd)

            QueueFocusCornerUpdate()
            TryQueueForegroundFallback(hwnd)
            return
        }

        if object_id != OBJID_WINDOW || child_id != CHILDID_SELF || !hwnd
            return


        if event = EVENT_OBJECT_DESTROY {
            was_managed := !!GetManagedCascadeMonitor(hwnd)

            ; Filter logging, not cleanup. The first event clears tracking, so
            ; repeated/unrelated destroys are quiet unless verbose logging is on.
            if (
                debug_enabled
                && (debug_verbose_enabled || was_managed
                    || pending_windows.Has(hwnd) || handled_windows.Has(hwnd))
            ) {
                DebugLog(
                    "Destroy event."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }

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


        if event != EVENT_OBJECT_SHOW
            return

        if GetManagedCascadeMonitor(hwnd)
            QueueFocusCornerUpdate()

        if debug_enabled && debug_verbose_enabled {
            DebugLog(
                "Show event."
                . " | pending=" pending_windows.Has(hwnd)
                . " | handled=" handled_windows.Has(hwnd)
                . " | " DebugDescribeWindow(hwnd)
            )
        }

        ; Some already-managed apps re-show the same HWND rather than creating
        ; a new one. Only a narrowly captured, recent user intent may retarget it.
        if handled_windows.Has(hwnd) && TryQueueHandledWindowReshow(hwnd, "show")
            return

        ; EVENT_OBJECT_SHOW also fires when some existing minimized windows are
        ; restored. Only windows absent from the startup snapshot are new.
        if startup_windows.Has(hwnd) {
            if debug_enabled && debug_verbose_enabled {
                DebugLog(
                    "Show event skipped: window existed at script startup."
                    . " | " DebugDescribeWindow(hwnd)
                )
            }
            return
        }

        ; Cheap filtering here prevents Explorer controls, ribbon pieces,
        ; tooltips, and other child/helper windows from ever reaching the timer.
        if !IsPlausibleTopLevelWindow(hwnd)
            return


        if pending_windows.Has(hwnd) {
            return
        }

        if handled_windows.Has(hwnd) {
            return
        }

        source_hwnd := current_foreground_hwnd

        ; If focus already moved to the new window, use the prior foreground window.
        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd

        DebugLog(
            "Show event accepted."
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        QueueWindowPlacement(hwnd, source_hwnd)
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
    global pending_windows, handled_windows, placement_reservations
    global placement_stabilization_generations
    global pending_adoption_undo
    global cascade_history
    global startup_windows, known_windows
    global current_foreground_hwnd, previous_foreground_hwnd

    ; Do not wait for the next visual sweep: a destroyed target must never leave
    ; its script-owned focus GUI behind.
    DestroyFocusCornerOverlay(hwnd)

    affected_monitor := GetManagedCascadeMonitor(hwnd)

    if IsCascadeWindowBeingDragged(hwnd)
        StopCascadeWindowDrag()

    if IsPendingAdoptionUndoFor(hwnd)
        pending_adoption_undo := 0

    CancelPlacementStabilization(hwnd)

    if startup_windows.Has(hwnd)
        startup_windows.Delete(hwnd)

    if known_windows.Has(hwnd)
        known_windows.Delete(hwnd)

    if pending_windows.Has(hwnd) {
        pending_windows.Delete(hwnd)
    }

    if handled_windows.Has(hwnd) {
        handled_windows.Delete(hwnd)
    }

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if current_foreground_hwnd = hwnd
        current_foreground_hwnd := 0

    if previous_foreground_hwnd = hwnd
        previous_foreground_hwnd := 0

    RemoveWindowFromMinimizeState(hwnd)

    RemoveCascadeWindowFromHistory(hwnd)
    ForgetCascadeMinimizedObservation(hwnd)

    RemoveWindowFromCascadeCloseBatch(hwnd)

    if affected_monitor
        QueueCascadeCompaction(affected_monitor)
}
