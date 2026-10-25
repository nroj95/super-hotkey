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

    if SuiteState.Log.verbose {
        DebugLog("Explorer Space re-show intent captured." . " | monitor=" monitor
            . " | source=" DescribeWindow(source_hwnd))
    }
}


; =============================================================================
; command availability
; =============================================================================

ActiveWindowBlocksCascadeCommands(allow_maximized := false)
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
        ; Explicit adoption restores maximized windows; other layout commands
        ; must not rearrange the cascade underneath them.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return !allow_maximized

        WinGetPosPixels(&window_x, &window_y, &window_width, &window_height, "ahk_id " active_hwnd)
    }
    catch {
        return false
    }

    window_right := window_x + window_width
    window_bottom := window_y + window_height
    tolerance_px := 2

    ; Borderless/exclusive fullscreen normally covers one monitor exactly.
    Loop MonitorGetCount() {
        MonitorGetPixels(A_Index, &monitor_left, &monitor_top, &monitor_right, &monitor_bottom)

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

QueueCascadeCommand(command, foregroundHwnd := 0)
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
            name: command,
            foreground_hwnd: foregroundHwnd,
            foreground_pid: foregroundPid
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
    global cascade_minimize_toggle_in_progress

    name := command.name
    if cascade_minimize_toggle_in_progress
        return

    if name = "minimize" {
        ToggleCascadeMinimize()
        return
    }

    ; A command delayed behind a slower one must still belong to the exact
    ; foreground window that owned it.
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
        DebugLog("Queued cascade command skipped." . " | reason=foreground-identity-changed"
            . " | command=" name . " | expected-foreground=" command.foreground_hwnd
            . " | expected-pid=" command.foreground_pid . " | actual-foreground=" actual_foreground)
        return
    }

    CancelNewWindowFocus()

    if ActiveWindowBlocksCascadeCommands(name = "adopt")
        return

    if name != "adopt"
        CancelPendingAdoptionUndo()

    switch name {
        case "focus-previous": FocusCascadeLayerWindow(-1)
        case "focus-next": FocusCascadeLayerWindow(1)
        case "slot-previous": RotateCurrentCascadeSlot(-1)
        case "slot-next": RotateCurrentCascadeSlot(1)
        case "swap-up": SwapActiveCascadeWindow(-1)
        case "swap-down": SwapActiveCascadeWindow(1)
        case "rotate-next": RotateCascadeLayers(1)
        case "adopt": AdoptActiveWindow()
        case "bring-forward": BringCommandMonitorCascadeForward()
        case "gather": GatherCascadesToCommandMonitor()
        case "close-monitor": CloseCommandMonitorCascade()
    }
}


CancelCascadePendingMouseActions(*)
{
    if !IsCascadeEnabled()
        return

    CancelPendingAdoptionUndo()
    CancelNewWindowFocus()
}
