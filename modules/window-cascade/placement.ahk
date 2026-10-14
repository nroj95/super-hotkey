; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; explicit placement on a monitor
; =============================================================================

PlaceCascadeWindowOnMonitor(
    hwnd,
    target_monitor,
    requested_position := 0,
    preserve_existing_membership_order := false
)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return false

    global cascade_display_generation
    global handled_windows, known_windows, pending_windows, placement_reservations
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    if !hwnd || !target_monitor || !WinExist("ahk_id " hwnd)
        return false

    window := "ahk_id " hwnd
    display_generation := cascade_display_generation
    dpi_transition := GetCascadeWindowMonitorDpi(hwnd) != GetCascadeMonitorDpi(target_monitor)
    CancelCascadeDisplayPlacement(hwnd)
    CancelPlacementStabilization(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)
    previous_monitor := GetManagedCascadeMonitor(hwnd)
    owned_reservation := 0
    placed := false

    try {
        ; Explicit adoption/gathering is allowed to restore a window before
        ; applying canonical cascade geometry on the destination monitor.
        if WinGetMinMax(window) != 0
            WinRestore(window)

        if !IsCascadeWindow(hwnd)
            return false

        MonitorGetWorkAreaPixels(
            target_monitor,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        work_width := work_right - work_left
        work_height := work_bottom - work_top

        window_width := Floor(work_width * window_width_ratio)
        window_height := Floor(work_height * window_height_ratio)

        window_width := Max(minimum_width, window_width)
        window_height := Max(minimum_height, window_height)

        window_width := Min(
            window_width,
            work_width - edge_margin * 2
        )

        window_height := Min(
            window_height,
            work_height - edge_margin * 2
        )

        ; Exclude this HWND from occupancy without removing its membership yet.
        ; A display notification during placement must still find the old member.
        ; A mouse drop supplies the nearest slot explicitly. Keyboard adoption
        ; and new-window placement keep using the normal least-used-slot policy.
        position := IsObject(requested_position) ? requested_position : GetNextCascadePosition(
            target_monitor,
            work_left,
            work_top,
            work_right,
            work_bottom,
            window_width,
            window_height,
            hwnd
        )

        target_x := position[1]
        target_y := position[2]

        raw_target := GetRawRectForVisibleTarget(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

        if !IsCascadeEnabled() || IsCascadeDisplayTransition()
            || display_generation != cascade_display_generation
            return false
        owned_reservation := Map(
            "monitor", target_monitor, "x", target_x, "y", target_y
        )
        placement_reservations[hwnd] := owned_reservation

        ; Explicit adoption/gather/drop placement does not need to block on the
        ; target application's UI thread. The reservation represents the intended
        ; slot until the existing stabilization path confirms the posted move.
        move_result := PhysicalDllCall(
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
        move_error := A_LastError

        if !move_result {
            if move_error = 5 {
                ; Preserve the old access-denied behavior: do not let discovery
                ; repeatedly retry a window Windows has refused to control.
                handled_windows[hwnd] := true
                known_windows[hwnd] := true
            }
            DebugLog(
                "Explicit placement SetWindowPos failed."
                . " | last-error=" move_error
                . " | target=" DebugDescribeWindow(hwnd)
            )
            return false
        }

        if !IsCascadeEnabled() || display_generation != cascade_display_generation
            || IsCascadeDisplayTransition()
            || !placement_reservations.Has(hwnd) || placement_reservations[hwnd] != owned_reservation
            return false
        ; Same-monitor reconciliation may need to repair geometry without turning
        ; the re-shown window into the newest history member. Cross-monitor moves,
        ; drops and explicit re-slotting keep their existing remove/re-record behavior.
        preserve_membership := preserve_existing_membership_order
            && previous_monitor = target_monitor
        if !preserve_membership
            RemoveCascadeWindowFromHistory(hwnd)
        handled_windows[hwnd] := true
        known_windows[hwnd] := true
        if pending_windows.Has(hwnd)
            pending_windows.Delete(hwnd)

        RecordCascadeWindow(target_monitor, hwnd)

        SchedulePlacementStabilization(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height,
            dpi_transition
        )

        if previous_monitor && previous_monitor != target_monitor
            QueueCascadeCompaction(previous_monitor)

        placed := true
        return true
    }
    catch Error as err {
        if placement_reservations.Has(hwnd) && placement_reservations[hwnd] = owned_reservation
            placement_reservations.Delete(hwnd)
        ; A failed re-slot/gather must not silently drop an already managed
        ; window from its original monitor history.
        if previous_monitor
            && !GetManagedCascadeMonitor(hwnd)
            && WinExist("ahk_id " hwnd)
        {
            RecordCascadeWindow(previous_monitor, hwnd)
        }

        return false
    }
    finally {
        ; An interrupted adoption may not have entered history yet. Never leave
        ; its unowned slot reserved forever, or delete a newer request's reservation.
        if !placed && placement_reservations.Has(hwnd) && placement_reservations[hwnd] = owned_reservation
            placement_reservations.Delete(hwnd)
    }
}


; =============================================================================
; new-window readiness and placement
; =============================================================================

GetPlacementReadinessReason(hwnd)
{
    ; Query title and state in the same order as the placement path.
    retry_reason := ""

    try {
        candidate_title := WinGetTitle("ahk_id " hwnd)
        candidate_min_max := WinGetMinMax("ahk_id " hwnd)

        if candidate_title = ""
            retry_reason := "empty title"
        else if candidate_min_max = -1
            retry_reason := "minimized"
        else if candidate_min_max = 1
            retry_reason := "maximized"
    }
    catch {
        retry_reason := "window state unavailable"
    }

    return retry_reason
}

ReserveNewWindowPlacement(hwnd, source_hwnd, queued_monitor, request)
{
    global handled_windows, placement_reservations
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height
    global cascade_display_generation

    display_generation := cascade_display_generation
    target_monitor := GetTargetMonitor(hwnd, source_hwnd, queued_monitor)
    dpi_transition :=
        GetCascadeWindowMonitorDpi(hwnd) != GetCascadeMonitorDpi(target_monitor)

    MonitorGetWorkAreaPixels(
        target_monitor,
        &work_left,
        &work_top,
        &work_right,
        &work_bottom
    )

    work_width := work_right - work_left
    work_height := work_bottom - work_top
    window_width := Min(
        Max(minimum_width, Floor(work_width * window_width_ratio)),
        work_width - edge_margin * 2
    )
    window_height := Min(
        Max(minimum_height, Floor(work_height * window_height_ratio)),
        work_height - edge_margin * 2
    )

    previous_critical := Critical("On")
    try {
        if !IsCurrentNewWindowPlacement(hwnd, request)
            || handled_windows.Has(hwnd)
            || IsCascadeWindowBeingDragged(hwnd)
            || IsCascadeDisplayTransition()
            || display_generation != cascade_display_generation
            return 0

        position := GetNextCascadePosition(
            target_monitor,
            work_left,
            work_top,
            work_right,
            work_bottom,
            window_width,
            window_height,
            hwnd
        )
        reservation := Map(
            "monitor", target_monitor,
            "x", position[1],
            "y", position[2]
        )
        placement_reservations[hwnd] := reservation
    }
    finally {
        Critical(previous_critical)
    }

    return {
        display_generation: display_generation,
        monitor: target_monitor,
        x: position[1],
        y: position[2],
        width: window_width,
        height: window_height,
        dpi_transition: dpi_transition,
        reservation: reservation
    }
}


TryProvisionalNewWindowPlacement(hwnd, source_hwnd, queued_monitor, request)
{
    global placement_reservations, cascade_display_generation

    if request.HasOwnProp("provisional_placement") && IsObject(request.provisional_placement)
        return true

    ; The settled pass retains the normal eligibility check. If the window is
    ; not ready enough yet, skip the early move and keep the old behavior.
    if !IsCascadeWindow(hwnd)
        return false

    plan := 0
    try {
        plan := ReserveNewWindowPlacement(
            hwnd,
            source_hwnd,
            queued_monitor,
            request
        )
        if !IsObject(plan)
            return false

        raw_target := GetRawRectForVisibleTarget(
            hwnd,
            plan.x,
            plan.y,
            plan.width,
            plan.height
        )

        initial_rect := "unavailable"
        if GetVisibleWindowBounds(
            hwnd,
            &initial_x,
            &initial_y,
            &initial_width,
            &initial_height
        ) {
            initial_rect :=
                "(" initial_x "," initial_y
                . " " initial_width "x" initial_height ")"
        }

        if !IsCurrentNewWindowPlacement(hwnd, request)
            || IsCascadeWindowBeingDragged(hwnd)
            || IsCascadeDisplayTransition()
            || plan.display_generation != cascade_display_generation
        {
            if placement_reservations.Has(hwnd)
                && placement_reservations[hwnd] = plan.reservation
                placement_reservations.Delete(hwnd)
            return false
        }

        DebugLog(
            "Provisional new-window placement begin."
            . " | monitor=" plan.monitor
            . " | initial-visible-rect=" initial_rect
            . " | target-visible-rect=(" plan.x "," plan.y
            . " " plan.width "x" plan.height ")"
            . " | hwnd=" hwnd
        )

        moved := PhysicalDllCall(
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
        move_error := A_LastError

        if !moved {
            if placement_reservations.Has(hwnd)
                && placement_reservations[hwnd] = plan.reservation
                placement_reservations.Delete(hwnd)
            DebugLog(
                "Provisional new-window placement failed."
                . " | last-error=" move_error
                . " | hwnd=" hwnd
            )
            return false
        }

        if !IsCurrentNewWindowPlacement(hwnd, request)
            || IsCascadeWindowBeingDragged(hwnd)
            || IsCascadeDisplayTransition()
            || plan.display_generation != cascade_display_generation
        {
            if placement_reservations.Has(hwnd)
                && placement_reservations[hwnd] = plan.reservation
                placement_reservations.Delete(hwnd)
            return false
        }

        request.provisional_placement := plan

        DebugLog(
            "Provisional new-window placement complete."
            . " | monitor=" plan.monitor
            . " | visible-rect=(" plan.x "," plan.y
            . " " plan.width "x" plan.height ")"
            . " | hwnd=" hwnd
        )
        return true
    }
    catch Error as err {
        if IsObject(plan) && placement_reservations.Has(hwnd)
            && placement_reservations[hwnd] = plan.reservation
            placement_reservations.Delete(hwnd)
        DebugError("Provisional new-window placement", err)
        return false
    }
}


ReleaseFailedNewWindowPlacementReservation(hwnd, request, reservation := 0)
{
    global placement_reservations

    ; A terminal callback may be cleaning up a reservation created by an earlier
    ; provisional pass rather than by this invocation of PlaceNewWindow().
    if !IsObject(reservation)
        && IsObject(request)
        && request.HasOwnProp("provisional_placement")
        && IsObject(request.provisional_placement)
    {
        reservation := request.provisional_placement.reservation
    }

    if !IsObject(reservation)
        return

    monitor_index := reservation.Has("monitor") ? reservation["monitor"] : 0

    ; Delete only the exact reservation owned by this failed request. A newer
    ; operation may already have reused the HWND and installed a different one.
    if placement_reservations.Has(hwnd)
        && placement_reservations[hwnd] = reservation
    {
        placement_reservations.Delete(hwnd)
    }

    if IsObject(request)
        && request.HasOwnProp("provisional_placement")
        && IsObject(request.provisional_placement)
        && request.provisional_placement.reservation = reservation
    {
        request.provisional_placement := 0
    }

    ; Another launch may already have chosen a later slot while this reservation
    ; existed. Recompact current membership after the abandoned slot is released.
    if monitor_index
        QueueCascadeCompaction(monitor_index)
}


PlaceNewWindow(
    hwnd,
    source_hwnd,
    queued_monitor := 0,
    retry_count := 0,
    settle_complete := false,
    request := 0
)
{
    global pending_windows, handled_windows, placement_reservations
    global placement_ready_retry_ms, placement_ready_retry_limit
    global placement_settle_delay_ms, placement_stabilize_tolerance
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    global cascade_display_generation
    display_generation := cascade_display_generation
    retry_scheduled := false
    owned_reservation := 0
    try {
        if !IsCurrentNewWindowPlacement(hwnd, request)
            || handled_windows.Has(hwnd) || IsCascadeWindowBeingDragged(hwnd)
            return
        if !WinExist(hwnd) || WinGetPID(hwnd) != request.pid
            return
        if IsCascadeDisplayTransition() {
            retry_scheduled := true
            SetTimer(PlaceNewWindow.Bind(hwnd, source_hwnd, queued_monitor,
                retry_count, settle_complete, request), -placement_ready_retry_ms)
            return
        }
        if request.HasOwnProp("monitor_device") && request.monitor_device != ""
            queued_monitor := FindCascadeMonitorDevice(request.monitor_device)

        DebugLog(
            "PlaceNewWindow begin."
            . " | retry=" retry_count
            . " | settled=" settle_complete
            . " | queued-monitor=" queued_monitor
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        retry_reason := GetPlacementReadinessReason(hwnd)

        ; Apps such as Explorer can remember that their previous window was
        ; maximized. Normalize that startup state before cascade placement.
        if retry_reason = "maximized" {
            try {
                WinRestore("ahk_id " hwnd)
                DebugLog(
                    "Restoring maximized new window before cascade placement."
                    . " | target=" DebugDescribeWindow(hwnd)
                )
            }
            catch {
            }
        }

        if retry_reason != ""
            && retry_count < placement_ready_retry_limit
        {
            next_retry := retry_count + 1
            retry_scheduled := true

            DebugLog(
                "Placement readiness retry."
                . " | reason=" retry_reason
                . " | retry=" next_retry
                . "/" placement_ready_retry_limit
                . " | target=" DebugDescribeWindow(hwnd)
            )

            SetTimer(
                PlaceNewWindow.Bind(
                    hwnd,
                    source_hwnd,
                    queued_monitor,
                    next_retry,
                    settle_complete,
                    request
                ),
                -placement_ready_retry_ms
            )

            return
        }

        if !settle_complete {
            source_is_shell_or_gone := (
                !source_hwnd
                || !WinExist("ahk_id " source_hwnd)
                || IsShellSurfaceWindow(source_hwnd)
            )

            if queued_monitor && source_is_shell_or_gone {
                ; Move a ready window before the shell/startup grace period.
                ; The settled pass reuses this exact reservation if it succeeds.
                TryProvisionalNewWindowPlacement(
                    hwnd,
                    source_hwnd,
                    queued_monitor,
                    request
                )

                retry_scheduled := true

                SetTimer(
                    PlaceNewWindow.Bind(
                        hwnd,
                        source_hwnd,
                        queued_monitor,
                        retry_count,
                        true,
                        request
                    ),
                    -placement_settle_delay_ms
                )

                return
            }
        }

        if !IsCascadeWindow(hwnd) {
            DebugLog(
                "Placement rejected by IsCascadeWindow."
                . " | " DebugDescribeWindow(hwnd)
            )
            return
        }

        provisional := (
            request.HasOwnProp("provisional_placement")
            ? request.provisional_placement
            : 0
        )

        if IsObject(provisional)
            && (
                provisional.display_generation != cascade_display_generation
                || !placement_reservations.Has(hwnd)
                || placement_reservations[hwnd] != provisional.reservation
            )
        {
            if placement_reservations.Has(hwnd)
                && placement_reservations[hwnd] = provisional.reservation
                placement_reservations.Delete(hwnd)
            request.provisional_placement := 0
            provisional := 0
        }

        reused_provisional := IsObject(provisional)
        plan := (
            reused_provisional
            ? provisional
            : ReserveNewWindowPlacement(
                hwnd,
                source_hwnd,
                queued_monitor,
                request
            )
        )
        if !IsObject(plan) {
            if IsCascadeDisplayTransition()
                || display_generation != cascade_display_generation
            {
                retry_scheduled := true
                SetTimer(
                    PlaceNewWindow.Bind(
                        hwnd,
                        source_hwnd,
                        queued_monitor,
                        retry_count,
                        settle_complete,
                        request
                    ),
                    -placement_ready_retry_ms
                )
            }
            return
        }

        target_monitor := plan.monitor
        target_x := plan.x
        target_y := plan.y
        window_width := plan.width
        window_height := plan.height
        dpi_transition := plan.dpi_transition
        owned_reservation := plan.reservation

        DebugLog(
            "Placement monitor resolved."
            . " | dpi-transfer=" dpi_transition
            . " | monitor=" target_monitor
            . " | queued-monitor=" queued_monitor
            . " | provisional=" reused_provisional
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        if reused_provisional
            && IsCurrentNewWindowPlacement(hwnd, request)
            && !handled_windows.Has(hwnd)
            && !IsCascadeWindowBeingDragged(hwnd)
            && !IsCascadeDisplayTransition()
            && display_generation = cascade_display_generation
        {
            try {
                if GetVisibleWindowBounds(
                    hwnd,
                    &current_x,
                    &current_y,
                    &current_width,
                    &current_height
                ) && GetMonitorForWindow(hwnd) = target_monitor
                    && Abs(current_x - target_x) <= placement_stabilize_tolerance
                    && Abs(current_y - target_y) <= placement_stabilize_tolerance
                    && Abs(current_width - window_width) <= placement_stabilize_tolerance
                    && Abs(current_height - window_height) <= placement_stabilize_tolerance
                {
                    DebugLog(
                        "Final placement move skipped."
                        . " | reason=provisional-matched"
                        . " | actual=(" current_x "," current_y
                        . " " current_width "x" current_height ")"
                        . " | requested=(" target_x "," target_y
                        . " " window_width "x" window_height ")"
                        . " | hwnd=" hwnd
                    )
                    handled_windows[hwnd] := true
                    RecordCascadeWindow(target_monitor, hwnd)
                    DebugLog(
                        "Placement complete."
                        . " | monitor=" target_monitor
                        . " | final-move=skipped"
                        . " | " DebugDescribeWindow(hwnd)
                    )
                    SchedulePlacementStabilization(
                        hwnd,
                        target_x,
                        target_y,
                        window_width,
                        window_height,
                        dpi_transition
                    )
                    StartNewWindowFocus(hwnd, request.focus)
                    return
                }
            }
            catch {
                ; Fall through to the normal settled move if geometry is unavailable.
            }
        }

        raw_target := GetRawRectForVisibleTarget(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

        raw_target_x := raw_target[1]
        raw_target_y := raw_target[2]
        raw_target_width := raw_target[3]
        raw_target_height := raw_target[4]

        DebugLog(
            "Placement slot reserved."
            . " | monitor=" target_monitor
            . " | provisional=" reused_provisional
            . " | visible-rect=(" target_x "," target_y
            . " " window_width "x" window_height ")"
            . " | hwnd=" hwnd
        )

        DebugLog(
            "Moving cascade window."
            . " | monitor=" target_monitor
            . " | visible-rect=(" target_x "," target_y
            . " " window_width "x" window_height ")"
            . " | raw-rect=(" raw_target_x "," raw_target_y
            . " " raw_target_width "x" raw_target_height ")"
            . " | " DebugDescribeWindow(hwnd)
        )

        ; Post the placement request instead of blocking on applications whose
        ; window thread is temporarily busy, such as DST during startup.
        swp_flags := (
            0x4000  ; SWP_ASYNCWINDOWPOS
            | 0x0010  ; SWP_NOACTIVATE
            | 0x0004  ; SWP_NOZORDER
        )

        DebugLog(
            "SetWindowPos begin."
            . " | flags=" swp_flags
            . " | target=" DebugDescribeWindow(hwnd)
        )

        set_window_pos_start_tick := A_TickCount

        if !IsCurrentNewWindowPlacement(hwnd, request)
            || handled_windows.Has(hwnd) || IsCascadeWindowBeingDragged(hwnd)
            return

        if IsCascadeDisplayTransition() || display_generation != cascade_display_generation {
            retry_scheduled := true
            SetTimer(PlaceNewWindow.Bind(hwnd, source_hwnd, queued_monitor,
                retry_count, settle_complete, request), -placement_ready_retry_ms)
            return
        }
        set_window_pos_result := PhysicalDllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0,
            "int", raw_target_x,
            "int", raw_target_y,
            "int", raw_target_width,
            "int", raw_target_height,
            "uint", swp_flags,
            "int"
        )

        ; Logging and diagnostics call Windows too; preserve the original error.
        set_window_pos_error := A_LastError
        set_window_pos_elapsed_ms :=
            (A_TickCount - set_window_pos_start_tick) & 0xFFFFFFFF

        DebugLog(
            "SetWindowPos returned."
            . " | result=" set_window_pos_result
            . " | elapsed-ms=" set_window_pos_elapsed_ms
            . " | target=" DebugDescribeWindow(hwnd)
        )

        if !set_window_pos_result {
            if placement_reservations.Has(hwnd) && placement_reservations[hwnd] = owned_reservation
                placement_reservations.Delete(hwnd)

            DebugLog(
                "SetWindowPos failed."
                . " | last-error=" set_window_pos_error
                . " | target=" DebugDescribeWindow(hwnd)
            )
            return
        }

        ; A native drag may have taken ownership while the async move was posted.
        if !IsCurrentNewWindowPlacement(hwnd, request)
            || handled_windows.Has(hwnd) || IsCascadeWindowBeingDragged(hwnd)
            return
        if IsCascadeDisplayTransition() || display_generation != cascade_display_generation {
            if placement_reservations.Has(hwnd) && placement_reservations[hwnd] = owned_reservation
                placement_reservations.Delete(hwnd)
            retry_scheduled := true
            SetTimer(PlaceNewWindow.Bind(hwnd, source_hwnd, queued_monitor,
                retry_count, settle_complete, request), -placement_ready_retry_ms)
            return
        }
        handled_windows[hwnd] := true
        RecordCascadeWindow(target_monitor, hwnd)

        DebugLog(
            "Placement complete."
            . " | monitor=" target_monitor
            . " | " DebugDescribeWindow(hwnd)
        )

        SchedulePlacementStabilization(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height,
            dpi_transition
        )
        StartNewWindowFocus(hwnd, request.focus)

    }
    catch Error as err {
        error_number := 0

        try
            error_number := err.Number

        if err.What = "WinMove" && error_number = 5 {
            ; The window was successfully identified but Windows denied control.
            ; Treat it as handled so fallback detection does not retry it, but do
            ; not leave an earlier provisional slot reserved for an unmanaged window.
            ReleaseFailedNewWindowPlacementReservation(hwnd, request, owned_reservation)
            handled_windows[hwnd] := true
            return
        }

        DebugError("PlaceNewWindow", err)
    }
    finally {
        if !retry_scheduled && IsCurrentNewWindowPlacement(hwnd, request) {
            pending_windows.Delete(hwnd)
            if !handled_windows.Has(hwnd)
                ReleaseFailedNewWindowPlacementReservation(hwnd, request, owned_reservation)
        }
    }
}


; =============================================================================
; asynchronous placement stabilization
; =============================================================================

CancelPlacementStabilization(hwnd)
{
    global placement_stabilization_generations, placement_reservations, placement_dpi_generations

    if hwnd && placement_dpi_generations.Has(hwnd)
        placement_dpi_generations.Delete(hwnd)
    if hwnd && placement_stabilization_generations.Has(hwnd)
        placement_stabilization_generations.Delete(hwnd)
    if hwnd && placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)
}

FinishPlacementStabilization(hwnd, generation)
{
    if !IsCurrentPlacementStabilization(hwnd, generation)
        return
    CancelPlacementStabilization(hwnd)
    ; Do not queue a fresh compaction here: an application-enforced offset could
    ; otherwise restart the same correction cycle indefinitely after its limit.
    QueueFocusCornerUpdate()
}

SchedulePlacementStabilization(
    hwnd,
    target_x,
    target_y,
    target_width,
    target_height,
    dpi_transition := false
)
{
    if !IsCascadeEnabled()
        return

    global placement_stabilize_delays_ms
    global placement_stabilization_generations
    global placement_stabilization_generation_counter, placement_dpi_generations

    placement_stabilization_generation_counter += 1
    stabilization_generation :=
        placement_stabilization_generation_counter

    placement_stabilization_generations[hwnd] :=
        stabilization_generation
    if dpi_transition
        placement_dpi_generations[hwnd] := stabilization_generation
    else if placement_dpi_generations.Has(hwnd)
        placement_dpi_generations.Delete(hwnd)
    RememberCascadeSlot(hwnd, GetManagedCascadeMonitor(hwnd), target_x, target_y)

    for delay_ms in placement_stabilize_delays_ms {
        SetTimer(
            StabilizePlacedWindow.Bind(
                hwnd,
                target_x,
                target_y,
                target_width,
                target_height,
                stabilization_generation,
                delay_ms
            ),
            -delay_ms
        )
    }
}

IsCurrentPlacementStabilization(hwnd, stabilization_generation)
{
    global placement_stabilization_generations

    return IsCascadeEnabled() && placement_stabilization_generations.Has(hwnd)
        && placement_stabilization_generations[hwnd]
            = stabilization_generation
}

StabilizePlacedWindow(
    hwnd,
    target_x,
    target_y,
    target_width,
    target_height,
    stabilization_generation,
    delay_ms,
    attempt := 0,
    passive_stage := 0,
    confirmation_count := 0
)
{
    global handled_windows, placement_reservations
    global placement_stabilize_tolerance
    global placement_stabilize_retry_ms
    global placement_stabilize_retry_limit
    global placement_stabilize_confirmation_ms, placement_stabilize_confirmation_limit
    global placement_stabilize_backoff_delays_ms, placement_dpi_generations

    if !IsCurrentPlacementStabilization(hwnd, stabilization_generation)
        return

    if IsCascadeDisplayTransition() {
        SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
            target_height, stabilization_generation, delay_ms, attempt, passive_stage,
            confirmation_count), -200)
        return
    }
    dpi_transition := placement_dpi_generations.Has(hwnd)
        && placement_dpi_generations[hwnd] = stabilization_generation

    DebugLog(
        "Stabilization callback."
        . " | generation=" stabilization_generation
        . " | delay-ms=" delay_ms
        . " | attempt=" attempt
        . " | passive-stage=" passive_stage
        . " | hwnd=" hwnd
    )

    if !handled_windows.Has(hwnd) {
        FinishPlacementStabilization(hwnd, stabilization_generation)

        return
    }

    if !WinExist("ahk_id " hwnd) {
        FinishPlacementStabilization(hwnd, stabilization_generation)

        return
    }

    try {
        ; Do not fight an intentional maximize/minimize transition.
        if WinGetMinMax("ahk_id " hwnd) != 0 {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            return
        }

        if !TryGetVisibleFrameRect(
            hwnd,
            &current_x,
            &current_y,
            &current_width,
            &current_height,
            &current_inset_left,
            &current_inset_top,
            &current_inset_right,
            &current_inset_bottom
        ) {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            return
        }

        needs_correction := (
            Abs(current_x - target_x) > placement_stabilize_tolerance
            || Abs(current_y - target_y) > placement_stabilize_tolerance
            || Abs(current_width - target_width) > placement_stabilize_tolerance
            || Abs(current_height - target_height) > placement_stabilize_tolerance
        )

        DebugLog(
            "Stabilization check."
            . " | generation=" stabilization_generation
            . " | delay-ms=" delay_ms
            . " | matched=" (!needs_correction)
            . " | actual=("
            . current_x "," current_y " "
            . current_width "x" current_height
            . ")"
            . " | requested=("
            . target_x "," target_y " "
            . target_width "x" target_height
            . ")"
            . " | hwnd=" hwnd
        )

        if !needs_correction {
            ; A destination app can apply WM_DPICHANGED after the first move.
            ; Require one additional match for DPI transfers, not endless polling.
            if dpi_transition && confirmation_count < 1 {
                SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
                    target_height, stabilization_generation, placement_stabilize_retry_ms,
                    attempt, passive_stage, confirmation_count + 1), -placement_stabilize_retry_ms)
                return
            }
            FinishPlacementStabilization(hwnd, stabilization_generation)

            DebugLog(
                "Placement reservation released."
                . " | reason=matched"
                . " | generation=" stabilization_generation
                . " | hwnd=" hwnd
            )

            return
        }

        if attempt >= placement_stabilize_retry_limit {
            ; Bound confirmation-only polling as well as corrective moves.
            if confirmation_count >= placement_stabilize_confirmation_limit {
                DebugLog("Placement stabilization exhausted. | hwnd=" hwnd)
                FinishPlacementStabilization(hwnd, stabilization_generation)
                return
            }
            SetTimer(
                StabilizePlacedWindow.Bind(
                    hwnd,
                    target_x,
                    target_y,
                    target_width,
                    target_height,
                    stabilization_generation,
                    placement_stabilize_confirmation_ms,
                    attempt,
                    passive_stage,
                    confirmation_count + 1
                ),
                -placement_stabilize_confirmation_ms
            )

            DebugLog(
                "Stabilization confirmation-only recheck scheduled."
                . " | generation=" stabilization_generation
                . " | attempts=" attempt
                . " | delay-ms=" placement_stabilize_confirmation_ms
                . " | hwnd=" hwnd
            )

            return
        }

        ; A mismatch does not immediately mean that Cascade needs to fight the
        ; application. Give the window progressively more time to finish its
        ; own startup or asynchronous geometry changes.
        ; Resolve at most three DPI-transition mismatches promptly. Unrelated
        ; app-driven geometry changes retain the existing passive/backoff policy.
        if !(dpi_transition && attempt < 3)
            && passive_stage < placement_stabilize_backoff_delays_ms.Length {
            next_passive_stage := passive_stage + 1

            passive_delay_ms :=
                placement_stabilize_backoff_delays_ms[
                    next_passive_stage
                ]

            SetTimer(
                StabilizePlacedWindow.Bind(
                    hwnd,
                    target_x,
                    target_y,
                    target_width,
                    target_height,
                    stabilization_generation,
                    passive_delay_ms,
                    attempt,
                    next_passive_stage
                ),
                -passive_delay_ms
            )

            DebugLog(
                "Stabilization passive recheck scheduled."
                . " | generation=" stabilization_generation
                . " | stage=" next_passive_stage
                . "/" placement_stabilize_backoff_delays_ms.Length
                . " | delay-ms=" passive_delay_ms
                . " | hwnd=" hwnd
            )

            return
        }

        ; The full passive grace period expired and the window is still wrong.
        ; Post one asynchronous correction, then begin a fresh passive cycle if
        ; the application overrides that correction too.
        next_attempt := attempt + 1

        raw_target_x := target_x - current_inset_left
        raw_target_y := target_y - current_inset_top

        raw_target_width := Max(
            1,
            target_width
            + current_inset_left
            + current_inset_right
        )

        raw_target_height := Max(
            1,
            target_height
            + current_inset_top
            + current_inset_bottom
        )

        swp_flags := (
            0x4000  ; SWP_ASYNCWINDOWPOS
            | 0x0010  ; SWP_NOACTIVATE
            | 0x0004  ; SWP_NOZORDER
        )

        ; The callback may have been interrupted by a newer placement while it
        ; was checking geometry. Recheck immediately before posting the move.
        if !IsCurrentPlacementStabilization(
            hwnd,
            stabilization_generation
        ) {
            return
        }

        if IsCascadeDisplayTransition() {
            SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
                target_height, stabilization_generation, delay_ms, attempt, passive_stage,
                confirmation_count), -200)
            return
        }

        DebugLog(
            "Stabilization SetWindowPos begin."
            . " | generation=" stabilization_generation
            . " | attempt=" next_attempt
            . " | passive-grace-complete=1"
            . " | hwnd=" hwnd
        )

        stabilization_start_tick := A_TickCount

        stabilization_result := PhysicalDllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0,
            "int", raw_target_x,
            "int", raw_target_y,
            "int", raw_target_width,
            "int", raw_target_height,
            "uint", swp_flags,
            "int"
        )

        stabilization_error := A_LastError
        stabilization_elapsed_ms :=
            (A_TickCount - stabilization_start_tick) & 0xFFFFFFFF

        DebugLog(
            "Stabilization SetWindowPos returned."
            . " | result=" stabilization_result
            . " | generation=" stabilization_generation
            . " | attempt=" next_attempt
            . " | elapsed-ms=" stabilization_elapsed_ms
            . " | hwnd=" hwnd
        )

        if !stabilization_result {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            DebugLog(
                "Placement reservation released."
                . " | reason=stabilization-failed"
                . " | generation=" stabilization_generation
                . " | last-error=" stabilization_error
                . " | hwnd=" hwnd
            )

            return
        }

        SetTimer(
            StabilizePlacedWindow.Bind(
                hwnd,
                target_x,
                target_y,
                target_width,
                target_height,
                stabilization_generation,
                placement_stabilize_retry_ms,
                next_attempt,
                0
            ),
            -placement_stabilize_retry_ms
        )

        DebugLog(
            "Stabilization recheck scheduled."
            . " | generation=" stabilization_generation
            . " | attempt=" next_attempt
            . " | passive-stage=0"
            . " | delay-ms=" placement_stabilize_retry_ms
            . " | hwnd=" hwnd
        )
    }
    catch Error as err {
        FinishPlacementStabilization(hwnd, stabilization_generation)
        DebugError("StabilizePlacedWindow", err)
    }
}


IsCurrentNewWindowPlacement(hwnd, request)
{
    global pending_windows
    return IsCascadeEnabled() && IsObject(request)
        && pending_windows.Has(hwnd) && pending_windows[hwnd] = request
}
