; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; current-layer focus and swapping
; =============================================================================

FocusCascadeLayerWindow(direction)
{
    if !IsCascadeEnabled()
        return

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length = 0
        return

    active_hwnd := WinExist("A")
    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    if active_index {
        target_index := active_index + (direction < 0 ? -1 : 1)

        if target_index < 1
            target_index := ordered_windows.Length
        else if target_index > ordered_windows.Length
            target_index := 1

        ActivateCascadeWindow(ordered_windows[target_index])
        return
    }

    ; If focus is outside the exposed layer, enter at the nearest window
    ; physically above/below the active window.
    target_hwnd := GetNearestSpatialCascadeWindow(
        ordered_windows,
        active_hwnd,
        direction
    )

    if target_hwnd
        ActivateCascadeWindow(target_hwnd)
}

SwapActiveCascadeWindow(direction)
{
    if !IsCascadeEnabled()
        return

    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return

    monitor_index := GetMonitorForWindow(active_hwnd)

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length < 2
        return

    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    ; Only an exposed current-layer window can move between slots.
    if !active_index
        return

    target_index := active_index + (direction < 0 ? -1 : 1)

    if target_index < 1
        target_index := ordered_windows.Length
    else if target_index > ordered_windows.Length
        target_index := 1

    target_hwnd := ordered_windows[target_index]

    if !TryGetVisibleFrameRect(
        active_hwnd,
        &active_x,
        &active_y,
        &active_width,
        &active_height,
        &active_inset_left,
        &active_inset_top,
        &active_inset_right,
        &active_inset_bottom
    ) {
        return
    }

    if !TryGetVisibleFrameRect(
        target_hwnd,
        &target_x,
        &target_y,
        &target_width,
        &target_height,
        &target_inset_left,
        &target_inset_top,
        &target_inset_right,
        &target_inset_bottom
    ) {
        return
    }

    ; Swap only the two exposed layer windows. Deeper windows remain in place.
    if !MoveCascadeWindowToSlot(target_hwnd, active_x, active_y)
        return

    if !MoveCascadeWindowToSlot(active_hwnd, target_x, target_y) {
        MoveCascadeWindowToSlot(target_hwnd, target_x, target_y)
        return
    }

    ; Keep both swapped windows above the deeper layers in their new slots,
    ; while preserving focus on the active window.
    z_flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    ; Never force a topmost window behind a normal window. If either native
    ; state query fails, skip the relative Z-order mutation rather than guessing.
    target_topmost := IsCascadeWindowTopmost(target_hwnd)
    active_topmost := IsCascadeWindowTopmost(active_hwnd)
    if target_topmost >= 0 && active_topmost >= 0
        && target_topmost = active_topmost
    {
        try PhysicalDllCall(
            "SetWindowPos",
            "ptr", target_hwnd,
            "ptr", active_hwnd,
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", z_flags,
            "int"
        )
    }

    QueueFocusCornerUpdate()
}

MoveCascadeWindowToSlot(hwnd, target_x, target_y, post_asynchronously := false)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return false

    global placement_reservations, cascade_display_generation
    display_generation := cascade_display_generation

    ; A minimize can complete after planning but before this individual move.
    if IsCascadeWindowBeingDragged(hwnd) || !WinExist(hwnd)
        return false
    try {
        if WinGetMinMax(hwnd) != 0
            return false
    }
    catch {
        return false
    }
    if !TryGetVisibleFrameRect(
        hwnd,
        &current_x,
        &current_y,
        &current_width,
        &current_height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return false
    }

    if IsCascadeDisplayTransition() || display_generation != cascade_display_generation
        return false
    if current_x = target_x && current_y = target_y {
        RememberCascadeSlot(hwnd, GetManagedCascadeMonitor(hwnd), target_x, target_y)
        return true
    }

    ; Compaction must replace the previous stabilization destination, otherwise
    ; its delayed retry could pull a just-dropped window back to an old slot.
    CancelPlacementStabilization(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    raw_target := [
        target_x - inset_left, target_y - inset_top,
        current_width + inset_left + inset_right,
        current_height + inset_top + inset_bottom
    ]

    if !IsCascadeEnabled() || IsCascadeWindowBeingDragged(hwnd)
        || IsCascadeDisplayTransition() || display_generation != cascade_display_generation
        return false

    owned_reservation := Map(
        "monitor", GetMonitorForWindow(hwnd), "x", target_x, "y", target_y
    )
    placement_reservations[hwnd] := owned_reservation
    stabilization_scheduled := false

    try {
        move_accepted := false
        if post_asynchronously {
            ; Compaction can post geometry changes because reservations and the
            ; stabilization watcher already represent in-flight destinations.
            move_accepted := PhysicalDllCall(
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
        } else {
            ; Swaps depend on ordered move/rollback semantics, so keep those
            ; explicit callers synchronous instead of introducing a new race.
            WinMovePixels(
                raw_target[1],
                raw_target[2],
                raw_target[3],
                raw_target[4],
                "ahk_id " hwnd
            )
            move_accepted := true
        }

        if !move_accepted
            return false

        if !IsCascadeEnabled() || IsCascadeDisplayTransition()
            || display_generation != cascade_display_generation
            || !placement_reservations.Has(hwnd)
            || placement_reservations[hwnd] != owned_reservation
            return false

        if !IsCascadeWindowBeingDragged(hwnd) {
            SchedulePlacementStabilization(
                hwnd,
                target_x,
                target_y,
                current_width,
                current_height
            )
            stabilization_scheduled := true
        }
        return true
    }
    catch {
        return false
    }
    finally {
        ; A cancelled/failed move must not leave compaction occupancy behind.
        ; Do not remove a newer request's reservation for a recycled HWND.
        if !stabilization_scheduled
            && placement_reservations.Has(hwnd)
            && placement_reservations[hwnd] = owned_reservation
        {
            placement_reservations.Delete(hwnd)
        }
    }
}


; =============================================================================
; slot and layer rotation
; =============================================================================

RotateCurrentCascadeSlot(direction)
{
    return RotateCascadeSlotForWindow(WinExist("A"), direction)
}

RotateCascadeSlotForWindow(
    target_hwnd,
    direction,
    expected_monitor := 0,
    expected_slot := 0
)
{
    if !target_hwnd || !WinExist("ahk_id " target_hwnd)
        || IsShellSurfaceWindow(target_hwnd)
        return 0

    monitor_index := GetMonitorForWindow(target_hwnd)

    if !monitor_index || (expected_monitor && monitor_index != expected_monitor)
        return 0

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)
    z_ranks := GetCascadeWindowZRanks()

    for stack_info in stacks {
        ; A tab click can pin rotation to the slot it actually resolved.
        if expected_slot && stack_info["slot_index"] != expected_slot
            continue

        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        ; Preserve keyboard behavior: only rotate an exposed window's own stack.
        if ordered_stack.Length < 2 || ordered_stack[1] != target_hwnd
            continue

        next_hwnd := RotateCascadeStackWindows(
            ordered_stack,
            direction
        )

        if next_hwnd
            ActivateCascadeWindow(next_hwnd)

        QueueFocusCornerUpdate()
        return next_hwnd
    }

    return 0
}

RotateCascadeStackWindows(ordered_windows, direction)
{
    if ordered_windows.Length < 2
        return 0

    ; Windows maintains separate topmost and normal Z-order bands. Crossing that
    ; boundary with SetWindowPos can silently change WS_EX_TOPMOST, so rotate only
    ; the front window's current band. The other band keeps its application state.
    front_is_topmost := IsCascadeWindowTopmost(ordered_windows[1])
    if front_is_topmost < 0
        return 0

    band_windows := []
    for hwnd in ordered_windows {
        window_is_topmost := IsCascadeWindowTopmost(hwnd)
        if window_is_topmost < 0
            return 0
        if window_is_topmost = front_is_topmost
            band_windows.Push(hwnd)
    }
    if band_windows.Length < 2
        return 0

    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    try {
        if direction < 0 {
            ; Bring the deepest window to the front of its existing native band
            ; in one operation. HWND_TOP does not make a normal window topmost;
            ; HWND_TOPMOST preserves an already-topmost window's band.
            target_hwnd := band_windows[band_windows.Length]
            insert_after := front_is_topmost ? -1 : 0 ; TOPMOST / TOP

            succeeded := PhysicalDllCall(
                "SetWindowPos",
                "ptr", target_hwnd,
                "ptr", insert_after,
                "int", 0,
                "int", 0,
                "int", 0,
                "int", 0,
                "uint", flags,
                "int"
            )

            return succeeded ? target_hwnd : 0
        }

        ; Move the exposed window behind the deepest window in the same band.
        current_hwnd := band_windows[1]
        deepest_hwnd := band_windows[band_windows.Length]

        succeeded := PhysicalDllCall(
            "SetWindowPos",
            "ptr", current_hwnd,
            "ptr", deepest_hwnd,
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        return succeeded ? band_windows[2] : 0
    }
    catch {
        return 0
    }
}

RotateCascadeLayers(direction := 1)
{
    if !IsCascadeEnabled()
        return

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    active_hwnd := WinExist("A")
    next_active_hwnd := 0

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        if ordered_stack.Length < 2
            continue

        was_active := ordered_stack[1] = active_hwnd
        new_top_hwnd := RotateCascadeStackWindows(
            ordered_stack,
            direction
        )

        if was_active && new_top_hwnd
            next_active_hwnd := new_top_hwnd
    }

    if next_active_hwnd
        ActivateCascadeWindow(next_active_hwnd)

    QueueFocusCornerUpdate()
}


; =============================================================================
; spatial ordering
; =============================================================================

GetSpatialCascadeOrder(windows)
{
    spatial_items := []

    ; History order is the final stable tie-breaker when windows occupy the
    ; exact same physical position.
    for history_index, hwnd in windows {
        if !TryGetWindowCenter(hwnd, &center_x, &center_y)
            continue

        item := Map(
            "hwnd", hwnd,
            "center_x", center_x,
            "center_y", center_y,
            "history_index", history_index
        )

        insert_index := spatial_items.Length + 1

        Loop spatial_items.Length {
            existing := spatial_items[A_Index]

            if SpatialItemComesBefore(item, existing) {
                insert_index := A_Index
                break
            }
        }

        spatial_items.InsertAt(insert_index, item)
    }

    ordered_windows := []

    for item in spatial_items
        ordered_windows.Push(item["hwnd"])

    return ordered_windows
}

SpatialItemComesBefore(item, existing)
{
    if item["center_y"] != existing["center_y"]
        return item["center_y"] < existing["center_y"]

    if item["center_x"] != existing["center_x"]
        return item["center_x"] < existing["center_x"]

    return item["history_index"] < existing["history_index"]
}

GetNearestSpatialCascadeWindow(
    ordered_windows,
    active_hwnd,
    direction
)
{
    if active_hwnd
        && WinExist("ahk_id " active_hwnd)
        && TryGetWindowCenter(
            active_hwnd,
            &active_center_x,
            &active_center_y
        )
    {
        target_hwnd := 0
        best_distance := 0

        for hwnd in ordered_windows {
            if !TryGetWindowCenter(hwnd, &center_x, &center_y)
                continue

            vertical_delta := center_y - active_center_y

            if direction < 0 {
                if vertical_delta >= 0
                    continue

                distance := -vertical_delta
            } else {
                if vertical_delta <= 0
                    continue

                distance := vertical_delta
            }

            if !target_hwnd || distance < best_distance {
                target_hwnd := hwnd
                best_distance := distance
            }
        }

        if target_hwnd
            return target_hwnd
    }

    ; No window remains in the requested direction, so wrap.
    return (
        direction < 0
        ? ordered_windows[ordered_windows.Length]
        : ordered_windows[1]
    )
}


; =============================================================================
; activation and bringing a cascade forward
; =============================================================================

ActivateCascadeWindow(hwnd)
{
    if !hwnd
        return

    try {
        if WinGetMinMax("ahk_id " hwnd) = -1
            WinRestore("ahk_id " hwnd)

        WinActivate("ahk_id " hwnd)
    }
    catch {
        return
    }
}

BringCommandMonitorCascadeForward()
{
    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    BringCascadeForward(monitor_index)
}

BringCascadeForward(monitor_index)
{
    if !IsCascadeEnabled()
        return

    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()

    ordered_windows := SortCascadeWindowsByZOrder(
        windows,
        z_ranks
    )

    visible_windows := []
    originally_topmost := Map()

    for hwnd in ordered_windows {
        if !WinExist("ahk_id " hwnd)
            continue

        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
            originally_topmost[hwnd] := !!(WinGetExStyle(hwnd) & 0x8) ; WS_EX_TOPMOST
        }
        catch {
            continue
        }

        visible_windows.Push(hwnd)
    }

    if visible_windows.Length = 0
        return

    last_used_hwnd := visible_windows[1]

    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    ; Temporarily promote the whole cascade into the topmost band. Process
    ; bottom-to-top so its existing internal Z-order is preserved.
    index := visible_windows.Length

    while index >= 1 {
        hwnd := visible_windows[index]

        try PhysicalDllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", -1, ; HWND_TOPMOST
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        index -= 1
    }

    ; Return only temporarily promoted windows to the normal Z band, keeping
    ; the bottom-to-top order. Preserve an application's existing always-on-top
    ; setting rather than clearing it as a side effect of bringing the group up.
    index := visible_windows.Length

    while index >= 1 {
        hwnd := visible_windows[index]

        if originally_topmost[hwnd] {
            index -= 1
            continue
        }

        try PhysicalDllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", -2, ; HWND_NOTOPMOST
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        index -= 1
    }

    ActivateCascadeWindow(last_used_hwnd)
}


; =============================================================================
; guarded new-window foreground recovery
; =============================================================================

CaptureCascadeLaunchIntent(hwnd)
{
    if !IsCascadeEnabled()
        return

    global cascade_launch_hint, current_foreground_hwnd, previous_foreground_hwnd

    CancelNewWindowFocus()
    if IsTaskbarSurfaceWindow(hwnd) {
        foreground := DllCall("GetForegroundWindow", "ptr")
        if IsShellSurfaceWindow(foreground) {
            if current_foreground_hwnd && !IsShellSurfaceWindow(current_foreground_hwnd)
                foreground := current_foreground_hwnd
            else if previous_foreground_hwnd && !IsShellSurfaceWindow(previous_foreground_hwnd)
                foreground := previous_foreground_hwnd
        }
        monitor := GetMonitorForWindow(hwnd)
        cascade_launch_hint := {
            tick: A_TickCount,
            foreground: foreground,
            monitor: monitor,
            monitor_device: monitor ? GetCascadeMonitorDevice(monitor) : ""
        }
    }
}

CaptureNewWindowFocusContext(hwnd)
{
    global cascade_launch_hint, new_window_focus_timeout_ms

    foreground := DllCall("GetForegroundWindow", "ptr")
    if IsObject(cascade_launch_hint)
        && ((A_TickCount - cascade_launch_hint.tick) & 0xFFFFFFFF) <= new_window_focus_timeout_ms
        return {
            foreground: cascade_launch_hint.foreground,
            hint: cascade_launch_hint,
            proved_foreground: foreground = hwnd
        }
    if foreground = hwnd
        return {foreground: foreground, hint: 0, proved_foreground: true}
    return 0
}

StartNewWindowFocus(hwnd, context)
{
    if !IsCascadeEnabled()
        return

    global cascade_launch_hint, new_window_focus_request, new_window_focus_poll_ms
    global new_window_focus_timeout_ms

    if !IsObject(context)
        return

    ; Foreground events can start recovery before placement finishes. Keep
    ; this marker after cancellation so placement cannot restart that request.
    recovery_started := false
    try recovery_started := !!context.recovery_started
    if recovery_started
        return

    foreground := DllCall("GetForegroundWindow", "ptr")
    proved_foreground := false
    try proved_foreground := !!context.proved_foreground
    if !IsObject(context.hint) && !proved_foreground && foreground != hwnd
        return
    if IsObject(context.hint) && (context.hint != cascade_launch_hint
        || ((A_TickCount - context.hint.tick) & 0xFFFFFFFF) > new_window_focus_timeout_ms)
        return
    try pid := WinGetPID(hwnd)
    catch
        return
    new_window_focus_request := {
        hwnd: hwnd, pid: pid, context: context,
        started_tick: A_TickCount, attempts: 0, visual_synced: false,
        saw_target_foreground: proved_foreground || foreground = hwnd,
        shell_settle: IsObject(context.hint)
            || proved_foreground || foreground = hwnd,
        launch_settle_started_tick: A_TickCount, launch_settle_attempts: 0,
        launch_settle_fallback_used: false, launch_settle_logged: false
    }
    context.recovery_started := true
    SyncNewWindowForegroundVisual(new_window_focus_request)
    SetTimer(WatchNewWindowFocus, new_window_focus_poll_ms)
}

CancelNewWindowFocus(expected_request := 0)
{
    global new_window_focus_request, cascade_launch_hint
    if IsObject(expected_request) && new_window_focus_request != expected_request
        return
    new_window_focus_request := 0
    cascade_launch_hint := 0
    SetTimer(WatchNewWindowFocus, 0)
}

ObserveNewWindowForeground(hwnd)
{
    if !IsCascadeEnabled()
        return

    global new_window_focus_request, cascade_launch_hint, pending_windows

    ; SHOW and FOREGROUND are separate WinEvents and their order is not stable.
    ; If this HWND is still waiting for placement, preserve foreground ownership
    ; on that placement request so StartNewWindowFocus() cannot lose the proof.
    if hwnd && pending_windows.Has(hwnd) {
        pending_request := pending_windows[hwnd]
        if IsObject(pending_request) {
            if IsObject(pending_request.focus) {
                pending_request.focus.proved_foreground := true
            } else {
                pending_request.focus := {
                    foreground: hwnd,
                    hint: 0,
                    proved_foreground: true
                }
            }
            DebugLog("Pending new-window foreground proof captured. | hwnd=" hwnd)

            ; Start protection immediately. Waiting until placement completes
            ; leaves a few hundred milliseconds for the shell to take focus.
            StartNewWindowFocus(hwnd, pending_request.focus)
        }
    }

    if IsObject(new_window_focus_request) {
        request := new_window_focus_request
        if hwnd = request.hwnd {
            request.saw_target_foreground := true
            request.visual_synced := false
            SyncNewWindowForegroundVisual(request)
            return
        }

        request.visual_synced := false

        ; Before the target has ever owned foreground, the original source is an
        ; expected part of launch settling. After it has owned foreground, any
        ; real application switch is intentional; only shell surfaces are noise.
        if request.saw_target_foreground {
            if !IsShellSurfaceWindow(hwnd)
                CancelNewWindowFocus(request)
        } else if hwnd != request.context.foreground
            && !IsShellSurfaceWindow(hwnd)
            CancelNewWindowFocus(request)
    }
}


SyncNewWindowForegroundVisual(request)
{
    if !IsObject(request) || request.visual_synced
        return false
    if DllCall("GetForegroundWindow", "ptr") != request.hwnd
        return false

    ; Remove this HWND's stale marker only while it really owns foreground.
    ; The overlay renderer still chooses the next layer's tab independently.
    request.visual_synced := true
    HideFocusCornerOverlay(request.hwnd)
    QueueFocusCornerUpdate()
    return true
}


RecoverNewWindowDuringShellSettle(request, foreground)
{
    global new_window_focus_request
    if !IsCascadeEnabled() || new_window_focus_request != request
        return false

    global new_window_shell_settle_ms

    if !request.shell_settle
        return false

    if ((A_TickCount - request.launch_settle_started_tick) & 0xFFFFFFFF)
        >= new_window_shell_settle_ms
        return false

    ; Mouse buttons and command modifiers still own the interaction.
    for key in ["LButton", "RButton", "MButton", "Ctrl", "Alt", "LWin", "RWin"] {
        if GetKeyState(key, "P")
            return true
    }

    ; Never force a launch that has not already proved foreground ownership.
    if !request.saw_target_foreground
        return true

    if !request.launch_settle_logged {
        request.launch_settle_logged := true
        DebugLog("New-window shell settle. | hwnd=" request.hwnd
            . " | " DebugDescribeForegroundState())
    }

    if foreground = request.hwnd {
        SyncNewWindowForegroundVisual(request)
        return true
    }

    ; Once the target has genuinely owned foreground, only a shell/taskbar
    ; handoff counts as transient launch noise. A real application switch,
    ; including back to the original source, cancels recovery before this path.
    if !IsShellSurfaceWindow(foreground)
        return true

    if !IsCascadeEnabled() || new_window_focus_request != request
        return false

    request.launch_settle_attempts += 1
    method := "SetForegroundWindow"
    DllCall("SetForegroundWindow", "ptr", request.hwnd, "int")

    used_fallback := false
    if DllCall("GetForegroundWindow", "ptr") != request.hwnd
        && request.launch_settle_attempts >= 3
        && !request.launch_settle_fallback_used
    {
        ; WinActivate can synthesize Alt during its built-in recovery.
        ; Keep it to one fallback for this foreground-proven request; do not
        ; replace it with an unconditional startup or close-command workaround.
        method := "WinActivate"
        used_fallback := true
        request.launch_settle_fallback_used := true
        try WinActivate(request.hwnd)
    }

    if DllCall("GetForegroundWindow", "ptr") = request.hwnd {
        request.launch_settle_attempts := 0
        request.visual_synced := false
        SyncNewWindowForegroundVisual(request)
        DebugLog("New-window shell foreground recovered. | hwnd="
            . request.hwnd
            . " | method=" method
            . " | " DebugDescribeForegroundState())
    } else if used_fallback {
        DebugLog("New-window shell foreground denied. | hwnd="
            . request.hwnd
            . " | method=" method
            . " | " DebugDescribeForegroundState())
    }

    return true
}


WatchNewWindowFocus()
{
    if !IsCascadeEnabled()
        return

    global new_window_focus_request, new_window_focus_timeout_ms
    global pending_windows

    request := new_window_focus_request
    if !IsObject(request) {
        SetTimer(WatchNewWindowFocus, 0)
        return
    }
    try {
        hwnd := request.hwnd
        foreground := DllCall("GetForegroundWindow", "ptr")
        SyncNewWindowForegroundVisual(request)
        if !WinExist(hwnd) || WinGetPID(hwnd) != request.pid
            || (!GetManagedCascadeMonitor(hwnd) && !pending_windows.Has(hwnd))
            || WinGetMinMax(hwnd) != 0
            || HasCascadeWindowDrag() || HasFocusTabClick()
        {
            CancelNewWindowFocus(request)
            return
        }
        ; Before first ownership, the original source may still be foreground.
        ; After the target has owned foreground, any non-shell app switch is a
        ; deliberate user choice and must cancel the guarded settle window.
        if foreground != hwnd && !IsShellSurfaceWindow(foreground) {
            if request.saw_target_foreground
                || foreground != request.context.foreground
            {
                CancelNewWindowFocus(request)
                return
            }
        }

        if !IsCascadeEnabled() || new_window_focus_request != request
            return
        if RecoverNewWindowDuringShellSettle(request, foreground)
            return

        if ((A_TickCount - request.started_tick) & 0xFFFFFFFF) >= new_window_focus_timeout_ms {
            CancelNewWindowFocus(request)
            return
        }

        ; Outside the shell-settle workaround, wait for the launch gesture and
        ; command modifiers to finish before normal foreground recovery.
        for key in ["LButton", "RButton", "MButton", "Ctrl", "Alt", "LWin", "RWin"] {
            if GetKeyState(key, "P")
                return
        }
        if IsCascadeRestoreInProgress(GetManagedCascadeMonitor(hwnd))
            return
        if new_window_focus_request != request
            return

        request.attempts += 1
        method := "SetForegroundWindow"

        ; Try the ordinary Win32 request first. WinActivate may synthesize
        ; Alt during its own recovery, so reserve it for the final attempt of
        ; this authorized request rather than running it on every activation.
        if foreground != hwnd
            DllCall("SetForegroundWindow", "ptr", hwnd, "int")

        if DllCall("GetForegroundWindow", "ptr") != hwnd
            && request.attempts >= 3
        {
            method := "WinActivate"
            try WinActivate(hwnd)
        }

        if DllCall("GetForegroundWindow", "ptr") = hwnd {
            ; An already-active window is not necessarily foremost in Z-order.
            PhysicalDllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
                "int", 0, "int", 0, "int", 0, "int", 0,
                "uint", 0x4213, "int") ; ASYNC | NOOWNERZORDER | NOACTIVATE | NOMOVE | NOSIZE
            QueueFocusCornerUpdate()
            DebugLog("New-window foreground confirmed. | hwnd=" hwnd
                " | method=" method " | attempts=" request.attempts
                " | " DebugDescribeForegroundState())
            CancelNewWindowFocus(request)
        } else if request.attempts >= 3 {
            DebugLog("New-window foreground denied. | hwnd=" hwnd
                " | method=" method " | " DebugDescribeForegroundState())
            CancelNewWindowFocus(request)
        }
    }
    catch Error as err {
        if new_window_focus_request = request
            CancelNewWindowFocus(request)
        DebugError("WatchNewWindowFocus", err)
    }
}
