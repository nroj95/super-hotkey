; Cascade Kingdom placement on a display and the check that confirms it.

; =============================================================================
; explicit placement on a monitor
; =============================================================================

PlaceCascadeWindowOnMonitor(hwnd, target_monitor, requested_position := 0,
    preserve_existing_membership_order := false)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return false

    if !hwnd || !CascadeDisplayAllowed(target_monitor) || !WinExist("ahk_id " hwnd)
        return false

    window := "ahk_id " hwnd
    display_generation := CascadeState.displayGeneration
    CancelCascadeDisplayPlacement(hwnd)
    CancelPlacementStabilization(hwnd)
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
            || display_generation != CascadeState.displayGeneration
            return false
        owned_reservation := Map("monitor", target_monitor, "x", target_x, "y", target_y)
        CascadeState.placementReservations[hwnd] := owned_reservation

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

        if !IsCascadeEnabled() || display_generation != CascadeState.displayGeneration
            || IsCascadeDisplayTransition()
            || !CascadeState.placementReservations.Has(hwnd) || CascadeState.placementReservations[hwnd] != owned_reservation
            return false
        ; Same-monitor reconciliation may need to repair geometry without turning
        ; the re-shown window into the newest history member. Cross-monitor moves,
        ; drops and explicit re-slotting keep their existing remove/re-record behavior.
        preserve_membership := preserve_existing_membership_order
            && previous_monitor = target_monitor
        if !preserve_membership
            RemoveCascadeWindowFromHistory(hwnd)

        RecordCascadeWindow(target_monitor, hwnd)

        SchedulePlacementStabilization(hwnd, target_x, target_y, window_width, window_height)

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
        if !placed && CascadeState.placementReservations.Has(hwnd) && CascadeState.placementReservations[hwnd] = owned_reservation
            CascadeState.placementReservations.Delete(hwnd)
    }
}

; =============================================================================
; placement check
; =============================================================================

; Moves are posted without waiting on the target application, so a short check
; confirms each one and keeps its slot reserved meanwhile. An application can
; still override the result, for example by resizing itself for a new display
; scale: one correction, then the application wins and Cascade never fights it.

CancelPlacementStabilization(hwnd)
{
    if hwnd && CascadeState.placementStabilizationGenerations.Has(hwnd)
        CascadeState.placementStabilizationGenerations.Delete(hwnd)
    if hwnd && CascadeState.placementReservations.Has(hwnd)
        CascadeState.placementReservations.Delete(hwnd)
}

FinishPlacementStabilization(hwnd, generation)
{
    if !IsCurrentPlacementStabilization(hwnd, generation)
        return
    CancelPlacementStabilization(hwnd)
    QueueFocusCornerUpdate()
}

SchedulePlacementStabilization(hwnd, target_x, target_y, target_width, target_height)
{
    if !IsCascadeEnabled()
        return

    CascadeState.placementStabilizationGenerationCounter += 1
    generation := CascadeState.placementStabilizationGenerationCounter
    CascadeState.placementStabilizationGenerations[hwnd] := generation
    RememberCascadeSlot(hwnd, GetManagedCascadeMonitor(hwnd), target_x, target_y)
    SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
        generation), -CascadeState.placementStabilizeDelayMs)
}

IsCurrentPlacementStabilization(hwnd, generation)
{
    return IsCascadeEnabled() && CascadeState.placementStabilizationGenerations.Has(hwnd)
        && CascadeState.placementStabilizationGenerations[hwnd] = generation
}

StabilizePlacedWindow(hwnd, target_x, target_y, target_width, target_height, generation,
    corrected := false)
{
    if !IsCurrentPlacementStabilization(hwnd, generation)
        return
    if IsCascadeDisplayTransition() {
        SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width,
            target_height, generation, corrected), -200)
        return
    }

    try {
        ; Never correct a window that left the cascade, closed, changed state
        ; or is being moved by hand.
        if !GetManagedCascadeMonitor(hwnd) || !WinExist("ahk_id " hwnd)
            || WinGetMinMax("ahk_id " hwnd) != 0 || IsIgnoredByCascade(hwnd)
            || IsCascadeWindowBeingDragged(hwnd) || !(frame := GetWindowFrame(hwnd)) {
            FinishPlacementStabilization(hwnd, generation)
            return
        }
        matched := Abs(frame.x - target_x) <= CascadeState.placementStabilizeTolerance
            && Abs(frame.y - target_y) <= CascadeState.placementStabilizeTolerance
            && Abs(frame.width - target_width) <= CascadeState.placementStabilizeTolerance
            && Abs(frame.height - target_height) <= CascadeState.placementStabilizeTolerance
        DebugLog("Placement check. | matched=" matched " | corrected=" (corrected ? 1 : 0)
            . " | actual=(" frame.x "," frame.y " " frame.width "x" frame.height ")"
            . " | requested=(" target_x "," target_y " " target_width "x" target_height ")"
            . " | " DescribeWindow(hwnd))
        if matched || corrected {
            FinishPlacementStabilization(hwnd, generation)
            return
        }

        raw := VisibleToRawRect(hwnd, target_x, target_y, target_width, target_height)
        if !PhysicalDllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
            "int", raw[1], "int", raw[2], "int", raw[3], "int", raw[4],
            "uint", 0x4014, "int") { ; ASYNC | NOACTIVATE | NOZORDER
            FinishPlacementStabilization(hwnd, generation)
            return
        }
        SetTimer(StabilizePlacedWindow.Bind(hwnd, target_x, target_y, target_width, target_height,
            generation, true), -CascadeState.placementStabilizeVerifyMs)
    }
    catch Error as err {
        FinishPlacementStabilization(hwnd, generation)
        DebugError("StabilizePlacedWindow", err)
    }
}
