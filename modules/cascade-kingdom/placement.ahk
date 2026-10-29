; Cascade Kingdom placement on a display and asynchronous stabilization.

; =============================================================================
; explicit placement on a monitor
; =============================================================================

PlaceCascadeWindowOnMonitor(hwnd, target_monitor, requested_position := 0,
    preserve_existing_membership_order := false)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return false

    global cascade_display_generation
    global placement_reservations

    if !hwnd || !CascadeDisplayAllowed(target_monitor) || !WinExist("ahk_id " hwnd)
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

        MonitorGetWorkAreaPixels(target_monitor, &work_left, &work_top, &work_right, &work_bottom)

        size := GetCascadeWindowSize(work_right - work_left, work_bottom - work_top)
        window_width := size[1]
        window_height := size[2]

        ; Exclude this HWND from occupancy without removing its membership yet.
        ; A display notification during placement must still find the old member.
        ; A mouse drop supplies the nearest slot explicitly. Keyboard adoption
        ; uses the normal least-used-slot policy.
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

        raw_target := VisibleToRawRect(hwnd, target_x, target_y, window_width, window_height)

        if !IsCascadeEnabled() || IsCascadeDisplayTransition()
            || display_generation != cascade_display_generation
            return false
        owned_reservation := Map("monitor", target_monitor, "x", target_x, "y", target_y)
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
            DebugLog("Explicit placement SetWindowPos failed." . " | last-error=" move_error
                . " | target=" DescribeWindow(hwnd))
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

        RecordCascadeWindow(target_monitor, hwnd)

        SchedulePlacementStabilization(hwnd, target_x, target_y, window_width, window_height,
            dpi_transition)

        if previous_monitor && previous_monitor != target_monitor
            QueueCascadeCompaction(previous_monitor)

        placed := true
        return true
    }
    catch Error as err {
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

SchedulePlacementStabilization(hwnd, target_x, target_y, target_width, target_height,
    dpi_transition := false)
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
            StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
                stabilization_generation, delay_ms),
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

StabilizePlacedWindow(hwnd, target_x, target_y, target_width, target_height,
    stabilization_generation, delay_ms, attempt := 0, passive_stage := 0, confirmation_count := 0)
{
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

    DebugLog("Stabilization callback." . " | generation=" stabilization_generation
        . " | delay-ms=" delay_ms . " | attempt=" attempt . " | passive-stage=" passive_stage
        . " | hwnd=" hwnd)

    ; Never correct a window that has left the cascade.
    if !GetManagedCascadeMonitor(hwnd) {
        FinishPlacementStabilization(hwnd, stabilization_generation)

        return
    }

    if !WinExist("ahk_id " hwnd) {
        FinishPlacementStabilization(hwnd, stabilization_generation)

        return
    }

    try {
        ; Do not fight an intentional maximize/minimize transition.
        if WinGetMinMax("ahk_id " hwnd) != 0 || IsIgnoredByCascade(hwnd)
            || IsCascadeWindowBeingDragged(hwnd) {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            return
        }

        if !(current_frame := GetWindowFrame(hwnd)) {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            return
        }
        current_x := current_frame.x
        current_y := current_frame.y
        current_width := current_frame.width
        current_height := current_frame.height

        needs_correction := (Abs(current_x - target_x) > placement_stabilize_tolerance
            || Abs(current_y - target_y) > placement_stabilize_tolerance
            || Abs(current_width - target_width) > placement_stabilize_tolerance
            || Abs(current_height - target_height) > placement_stabilize_tolerance)

        DebugLog("Stabilization check." . " | generation=" stabilization_generation
            . " | delay-ms=" delay_ms . " | matched=" (!needs_correction) . " | actual=("
            . current_x "," current_y " " . current_width "x" current_height . ")"
            . " | requested=(" . target_x "," target_y " " . target_width "x" target_height . ")"
            . " | hwnd=" hwnd)

        if !needs_correction {
            ; A DPI transfer can settle after the first match; check it once more.
            confirmation_delay := GetCascadeConfirmationDelay(dpi_transition, confirmation_count)
            if confirmation_delay {
                SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
                    target_height, stabilization_generation, confirmation_delay,
                    attempt, passive_stage, confirmation_count + 1), -confirmation_delay)
                return
            }
            FinishPlacementStabilization(hwnd, stabilization_generation)

            DebugLog("Placement reservation released." . " | reason=matched"
                . " | generation=" stabilization_generation . " | hwnd=" hwnd)

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
                StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
                    stabilization_generation, placement_stabilize_confirmation_ms, attempt,
                    passive_stage, confirmation_count + 1),
                -placement_stabilize_confirmation_ms
            )

            DebugLog("Stabilization confirmation-only recheck scheduled."
                . " | generation=" stabilization_generation . " | attempts=" attempt
                . " | delay-ms=" placement_stabilize_confirmation_ms . " | hwnd=" hwnd)

            return
        }

        ; A mismatch does not immediately mean that Cascade needs to fight the
        ; application. Give the window progressively more time to finish its
        ; own asynchronous geometry changes.
        ; A wrong monitor is not a cosmetic size disagreement. Correct the first
        ; three misses promptly even when both displays use the same DPI.
        current_monitor := GetMonitorForPoint(current_x + current_width / 2,
            current_y + current_height / 2)
        target_monitor := GetMonitorForPoint(target_x + target_width / 2,
            target_y + target_height / 2)
        if !ShouldCorrectCascadeMonitorPromptly(dpi_transition, current_monitor, target_monitor, attempt)
            && passive_stage < placement_stabilize_backoff_delays_ms.Length {
            next_passive_stage := passive_stage + 1

            passive_delay_ms :=
                placement_stabilize_backoff_delays_ms[next_passive_stage]

            SetTimer(
                StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
                    stabilization_generation, passive_delay_ms, attempt, next_passive_stage,
                    confirmation_count),
                -passive_delay_ms
            )

            DebugLog("Stabilization passive recheck scheduled."
                . " | generation=" stabilization_generation . " | stage=" next_passive_stage
                . "/" placement_stabilize_backoff_delays_ms.Length . " | delay-ms=" passive_delay_ms
                . " | hwnd=" hwnd)

            return
        }

        ; The full passive grace period expired and the window is still wrong.
        ; Post one asynchronous correction, then begin a fresh passive cycle if
        ; the application overrides that correction too.
        next_attempt := attempt + 1

        raw_target := VisibleToRawRect(hwnd, target_x, target_y, target_width, target_height)
        raw_target_x := raw_target[1]
        raw_target_y := raw_target[2]
        raw_target_width := raw_target[3]
        raw_target_height := raw_target[4]

        swp_flags := (
            0x4000  ; SWP_ASYNCWINDOWPOS
            | 0x0010  ; SWP_NOACTIVATE
            | 0x0004  ; SWP_NOZORDER
        )

        ; The callback may have been interrupted by a newer placement while it
        ; was checking geometry. Recheck immediately before posting the move.
        if !IsCurrentPlacementStabilization(hwnd, stabilization_generation) {
            return
        }

        if IsCascadeDisplayTransition() {
            SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
                target_height, stabilization_generation, delay_ms, attempt, passive_stage,
                confirmation_count), -200)
            return
        }

        DebugLog("Stabilization SetWindowPos begin." . " | generation=" stabilization_generation
            . " | attempt=" next_attempt . " | passive-grace-complete=1" . " | hwnd=" hwnd)

        stabilization_start_tick := A_TickCount

        stabilization_result := PhysicalDllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
            "int", raw_target_x, "int", raw_target_y, "int", raw_target_width,
            "int", raw_target_height, "uint", swp_flags, "int")

        stabilization_error := A_LastError
        stabilization_elapsed_ms :=
            (A_TickCount - stabilization_start_tick) & 0xFFFFFFFF

        DebugLog("Stabilization SetWindowPos returned." . " | result=" stabilization_result
            . " | generation=" stabilization_generation . " | attempt=" next_attempt
            . " | elapsed-ms=" stabilization_elapsed_ms . " | hwnd=" hwnd)

        if !stabilization_result {
            FinishPlacementStabilization(hwnd, stabilization_generation)

            DebugLog("Placement reservation released." . " | reason=stabilization-failed"
                . " | generation=" stabilization_generation . " | last-error=" stabilization_error
                . " | hwnd=" hwnd)

            return
        }

        SetTimer(
            StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
                stabilization_generation, placement_stabilize_retry_ms, next_attempt, 0,
                confirmation_count),
            -placement_stabilize_retry_ms
        )

        DebugLog("Stabilization recheck scheduled." . " | generation=" stabilization_generation
            . " | attempt=" next_attempt . " | passive-stage=0"
            . " | delay-ms=" placement_stabilize_retry_ms . " | hwnd=" hwnd)
    }
    catch Error as err {
        FinishPlacementStabilization(hwnd, stabilization_generation)
        DebugError("StabilizePlacedWindow", err)
    }
}


ShouldCorrectCascadeMonitorPromptly(dpi_transition, current_monitor, target_monitor, attempt)
{
    return attempt < 3 && (dpi_transition
        || (current_monitor && target_monitor && current_monitor != target_monitor))
}

GetCascadeConfirmationDelay(dpi_transition, confirmation_count)
{
    global placement_stabilize_retry_ms
    return dpi_transition && confirmation_count < 1 ? placement_stabilize_retry_ms : 0
}
