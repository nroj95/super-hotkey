; Native mouse observations are registered by the shared manager.

IsExplorerSpaceReshowIntentContext()
{
    if !IsCascadeEnabled()
        return false

    hwnd := WinExist("A")
    if !hwnd || IsShellSurfaceWindow(hwnd)
        return false

    try return WinGetProcessName("ahk_id " hwnd) = "explorer.exe"
    catch
        return false
}

CaptureExplorerSpaceReshowIntent()
{
    global explorer_space_reshow_hint


    ; Modifier/Caps chords belong to Explorer, another app, or CapsLock Layer.
    ; Only the native plain-Space action may become a re-show intent.
    for modifier in ["CapsLock", "Shift", "Ctrl", "Alt", "LWin", "RWin"] {
        if GetKeyState(modifier, "P")
            return
    }

    source_hwnd := WinExist("A")
    if !source_hwnd || !IsExplorerSpaceReshowIntentContext()
        return

    try source_pid := WinGetPID("ahk_id " source_hwnd)
    catch
        return

    monitor := GetMonitorForWindow(source_hwnd)
    if !monitor
        return

    explorer_space_reshow_hint := {
        tick: A_TickCount,
        source_hwnd: source_hwnd,
        source_pid: source_pid,
        monitor: monitor,
        monitor_device: GetCascadeMonitorDevice(monitor)
    }

    if SuiteState.Log.verbose && SuiteState.Log.verbose {
        DebugLog(
            "Explorer Space re-show intent captured."
            . " | monitor=" monitor
            . " | source=" DebugDescribeWindow(source_hwnd)
        )
    }
}


; =============================================================================
; command availability
; =============================================================================

ActiveWindowBlocksCascadeCommands()
{
    ; Do not rotate, gather or reposition windows underneath a native drag.
    if HasCascadeWindowDrag() || IsCascadeDisplayTransition()
        return true
    command_monitor := GetCommandMonitor()
    if command_monitor && (CascadeMonitorNeedsRefresh(command_monitor)
        || HasPendingCascadeDisplayLayout(command_monitor))
        return true

    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return false

    try {
        ; Maximized windows are intentionally outside cascade management.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return true

        WinGetPosPixels(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " active_hwnd
        )
    }
    catch {
        return false
    }

    window_right := window_x + window_width
    window_bottom := window_y + window_height
    tolerance_px := 2

    ; Borderless/exclusive fullscreen normally covers one monitor exactly.
    Loop MonitorGetCount() {
        MonitorGetPixels(
            A_Index,
            &monitor_left,
            &monitor_top,
            &monitor_right,
            &monitor_bottom
        )

        if Abs(window_x - monitor_left) <= tolerance_px
            && Abs(window_y - monitor_top) <= tolerance_px
            && Abs(window_right - monitor_right) <= tolerance_px
            && Abs(window_bottom - monitor_bottom) <= tolerance_px
        {
            return true
        }
    }

    return false
}


; =============================================================================
; deferred, local command dispatch
; =============================================================================

QueueCascadeCommand(commandId, parameter := 0, foregroundHwnd := 0)
{
    global cascade_command_queue, cascade_command_draining

    if !IsCascadeEnabled()
        return

    foregroundPid := 0
    if foregroundHwnd {
        try foregroundPid := WinGetPID(foregroundHwnd)
    }

    previousCritical := Critical("On")
    try {
        ; Revalidate the originating window's HWND/PID before moving or closing.
        cascade_command_queue.Push({
            id: commandId,
            parameter: parameter,
            foreground_hwnd: foregroundHwnd,
            foreground_pid: foregroundPid,
            queued: true
        })
        if !cascade_command_draining
            SetTimer(DrainCascadeCommandQueue, -1)
    }
    finally Critical(previousCritical)
}

DrainCascadeCommandQueue(*)
{
    global cascade_command_queue, cascade_command_draining

    previousCritical := Critical("On")
    if cascade_command_draining {
        Critical(previousCritical)
        return
    }
    cascade_command_draining := true
    Critical(previousCritical)

    Loop {
        previousCritical := Critical("On")
        if !cascade_command_queue.Length {
            cascade_command_draining := false
            Critical(previousCritical)
            return
        }
        command := cascade_command_queue.RemoveAt(1)
        Critical(previousCritical)

        try DispatchCascadeCommand(command)
        catch Error as failure
            DebugError("Cascade command dispatch", failure)
    }
}

DispatchCascadeCommand(command)
{
    global cascade_command_focus_previous, cascade_command_focus_next
    global cascade_command_rotate_slot_previous, cascade_command_rotate_slot_next
    global cascade_command_swap_window_up, cascade_command_swap_window_down
    global cascade_command_adopt_active, cascade_command_rotate_layers
    global cascade_command_toggle_minimize, cascade_command_bring_forward
    global cascade_command_close_active, cascade_command_close_scope
    global cascade_command_gather_to_monitor, cascade_command_show_help
    global cascade_command_move_monitor_left, cascade_command_move_monitor_right
    global cascade_command_toggle_auto_placement
    global cascade_auto_placement_toggle_in_progress
    global cascade_minimize_toggle_in_progress

    command_id := command.id
    parameter := command.parameter

    if cascade_auto_placement_toggle_in_progress || cascade_minimize_toggle_in_progress
        return

    ; Auto-placement pause/resume is a script-level control and never disables existing cascades.
    if command_id = cascade_command_toggle_auto_placement {
        ToggleCascadeAutoPlacement()
        return
    }

    if command_id = cascade_command_toggle_minimize {
        ToggleCascadeMinimize()
        return
    }

    ; A command delayed behind a slower one must still belong to the exact
    ; foreground window that owned it. Context-free help is safe regardless.
    if command.queued && command_id != cascade_command_show_help {
        actual_foreground := DllCall("GetForegroundWindow", "ptr")
        foreground_matches := actual_foreground = command.foreground_hwnd

        if foreground_matches && command.foreground_hwnd {
            if !command.foreground_pid {
                foreground_matches := false
            } else {
                try foreground_matches :=
                    WinGetPID(command.foreground_hwnd) = command.foreground_pid
                catch
                    foreground_matches := false
            }
        }

        if !foreground_matches {
            DebugLog(
                "Queued cascade command skipped."
                . " | reason=foreground-identity-changed"
                . " | command=" command_id
                . " | expected-foreground=" command.foreground_hwnd
                . " | expected-pid=" command.foreground_pid
                . " | actual-foreground=" actual_foreground
            )
            return
        }
    }

    CancelNewWindowFocus()

    if ActiveWindowBlocksCascadeCommands()
        return

    if command_id != cascade_command_adopt_active
        CancelPendingAdoptionUndo()

    switch command_id {
        case cascade_command_focus_previous:
            FocusCascadeLayerWindow(-1)

        case cascade_command_focus_next:
            FocusCascadeLayerWindow(1)

        case cascade_command_rotate_slot_previous:
            RotateCurrentCascadeSlot(-1)

        case cascade_command_rotate_slot_next:
            RotateCurrentCascadeSlot(1)

        case cascade_command_swap_window_up:
            SwapActiveCascadeWindow(-1)

        case cascade_command_swap_window_down:
            SwapActiveCascadeWindow(1)

        case cascade_command_adopt_active:
            AdoptActiveWindow()

        case cascade_command_rotate_layers:
            ; OnMessage exposes -1 as 0xFFFFFFFF in a 32-bit receiver.
            ; Zero remains forward so the existing one-shot sender still works.
            direction := (parameter = -1 || parameter = 0xFFFFFFFF) ? -1 : 1
            RotateCascadeLayers(direction)

        case cascade_command_bring_forward:
            BringCommandMonitorCascadeForward()

        case cascade_command_close_active:
            ; Close the same foreground window that owned the command message.
            ; Never let a delayed close follow focus into another application.
            if command.foreground_hwnd
                && DllCall("GetForegroundWindow", "ptr") = command.foreground_hwnd
                try WinClose(command.foreground_hwnd)

        case cascade_command_close_scope:
            CloseCommandMonitorCascade()

        case cascade_command_gather_to_monitor:
            GatherCascadesToCommandMonitor()

        case cascade_command_show_help:
            ToggleWindowCascadeHelp()

        case cascade_command_move_monitor_left:
            MoveCascadeWindowAcrossMonitor(parameter, "Left")

        case cascade_command_move_monitor_right:
            MoveCascadeWindowAcrossMonitor(parameter, "Right")
    }
}


CancelCascadePendingMouseActions(*)
{
    if !IsCascadeEnabled()
        return

    CancelPendingAdoptionUndo()
    CancelNewWindowFocus()
}
