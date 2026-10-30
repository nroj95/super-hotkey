; Cascade Kingdom command availability and the serialized command queue.

; =============================================================================
; command availability
; =============================================================================

ActiveWindowBlocksCascadeCommands(allow_maximized := false)
{
    ; Do not rotate, gather or reposition windows underneath a native drag.
    if HasCascadeWindowDrag() || IsCascadeDisplayTransition()
        return true
    command_monitor := SuiteWorkingMonitor.Get()
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

        WinGetPosPixels(&x, &y, &width, &height, "ahk_id " active_hwnd)
        monitor := CallWithDpiContext(-3, MonitorRects, WindowMonitor(active_hwnd)).monitor
    }
    catch {
        return false
    }

    ; Borderless/exclusive fullscreen normally covers its display exactly.
    return Abs(x - monitor[1]) <= 2 && Abs(y - monitor[2]) <= 2
        && Abs(x + width - monitor[3]) <= 2 && Abs(y + height - monitor[4]) <= 2
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
    global cascade_minimize_in_progress

    name := command.name
    if cascade_minimize_in_progress
        return

    if name = "minimize" || name = "restore" {
        if monitor := SuiteWorkingMonitor.Get()
            RunCascadeMinimizeCommand((name = "minimize" ? MinimizeCascadeWindows
                : RestoreMinimizedCascadeWindows).Bind(monitor))
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

    if ActiveWindowBlocksCascadeCommands(name = "adopt")
        return

    switch name {
        case "focus-previous": FocusCascadeLayerWindow(-1)
        case "focus-next": FocusCascadeLayerWindow(1)
        case "slot-previous": RotateCascadeSlotForWindow(WinExist("A"), -1)
        case "slot-next": RotateCascadeSlotForWindow(WinExist("A"), 1)
        case "swap-up": SwapActiveCascadeWindow(-1)
        case "swap-down": SwapActiveCascadeWindow(1)
        case "rotate-next": RotateCascadeLayers(1)
        case "adopt": AdoptActiveWindow()
        case "release": ReleaseActiveCascadeWindow()
        case "bring-forward": BringCascadeForward(SuiteWorkingMonitor.Get())
        case "gather": GatherCascadesToCommandMonitor()
        case "close-monitor": CloseCommandMonitorCascade()
    }
}

