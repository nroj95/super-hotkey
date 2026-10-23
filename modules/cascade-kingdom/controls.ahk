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

    ; Closing the active window is not a cascade layout operation. In
    ; particular, maximized applications should still respond to it.
    if name = "close-active" {
        if HasCascadeWindowDrag() || IsCascadeDisplayTransition()
            return
    } else if ActiveWindowBlocksCascadeCommands(name = "adopt")
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
        case "close-active":
            ; A delayed command must not close whichever window was focused later.
            if command.foreground_hwnd
                && DllCall("GetForegroundWindow", "ptr") = command.foreground_hwnd
                CloseActiveCascadeWindow(command.foreground_hwnd, command.foreground_pid)
        case "close-monitor": CloseCommandMonitorCascade()
    }
}


; Caps + Delete asks the app to close, then lets Windows pick foreground.
; Some apps leave the taskbar or desktop active instead. Capture the eligible
; Z-order BEFORE closing so the fallback works across all monitors.
CascadeCaptureCloseFocusTargets(closing_hwnd)
{
    targets := []
    for hwnd in WinGetList() {
        if hwnd = closing_hwnd || !IsSwitchableWindow(hwnd)
            continue
        try targets.Push({hwnd: hwnd, pid: WinGetPID("ahk_id " hwnd)})
    }
    return targets
}

; Preserve ordinary focus handoffs, including modal save/confirmation dialogs.
; Unlike the fallback candidate test, a real foreground dialog may be owned.
CascadeHasUsableCloseForeground(hwnd, closing_hwnd, closing_pid)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    if hwnd = closing_hwnd {
        try {
            if WinGetPID("ahk_id " hwnd) = closing_pid
                return false
        }
        catch
            return false
    }
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("IsIconic", "ptr", hwnd, "int")
        || IsWindowCloaked(hwnd) || IsShellSurfaceWindow(hwnd)
        || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        return false
    try return !(WinGetExStyle("ahk_id " hwnd) & 0x08000000) ; WS_EX_NOACTIVATE
    catch
        return false
}

CascadeCloseOriginStillVisible(hwnd, pid)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    try return WinGetPID("ahk_id " hwnd) = pid
        && DllCall("IsWindowVisible", "ptr", hwnd, "int")
        && !DllCall("IsIconic", "ptr", hwnd, "int")
        && !IsWindowCloaked(hwnd)
    catch
        return false
}

CascadeCloseFocusDecision(other_focused, origin_visible)
{
    return other_focused ? "preserve" : (origin_visible ? "wait" : "recover")
}

; The accent border belongs to a completed close, never to a pending save dialog.
CascadeShouldHighlightCloseFocus(outcome, origin_visible)
{
    return outcome = "preserve" && !origin_visible
}

CloseActiveCascadeWindow(hwnd, pid)
{
    global cascade_close_focus_request
    if !hwnd || !pid || DllCall("GetForegroundWindow", "ptr") != hwnd
        return
    try {
        if WinGetPID("ahk_id " hwnd) != pid
            return
        targets := CascadeCaptureCloseFocusTargets(hwnd)
        ; Invalidate an earlier close request even if this was the last window.
        cascade_close_focus_request := 0
        WinClose("ahk_id " hwnd)
        ; Watch even with no fallback targets: Windows may still focus a valid
        ; window that became available during the close.
        request := {hwnd: hwnd, pid: pid, targets: targets, started: A_TickCount}
        cascade_close_focus_request := request
        SetTimer(CascadeWatchCloseFocus.Bind(request), -130)
    }
    catch Error as err
        DebugError("Close active window", err)
}

CascadeWatchCloseFocus(request)
{
    global cascade_close_focus_request
    if !IsCascadeEnabled() || cascade_close_focus_request != request
        return

    foreground := DllCall("GetForegroundWindow", "ptr")
    origin_visible := CascadeCloseOriginStillVisible(request.hwnd, request.pid)
    outcome := CascadeCloseFocusDecision(
        CascadeHasUsableCloseForeground(foreground, request.hwnd, request.pid),
        origin_visible)
    elapsed := (A_TickCount - request.started) & 0xFFFFFFFF

    if outcome = "preserve" {
        if !CascadeShouldHighlightCloseFocus(outcome, origin_visible) {
            ; Keep native focus untouched, including save dialogs. If the close
            ; completes shortly afterward, the next poll highlights its result.
            if elapsed < 3500
                SetTimer(CascadeWatchCloseFocus.Bind(request), -140)
            else
                cascade_close_focus_request := 0
            return
        }
        cascade_close_focus_request := 0
        ; Focus may have changed while the timer ran: highlight only the real
        ; current foreground, never an earlier snapshot.
        foreground := DllCall("GetForegroundWindow", "ptr")
        if CascadeHasUsableCloseForeground(foreground, request.hwnd, request.pid) {
            SuiteFocusBorder.Show(foreground, "cascade-close")
            DebugLog("Caps+Delete native focus highlighted. | target="
                . DescribeWindow(foreground))
        }
        return
    }

    if outcome = "wait" {
        ; WinClose can be asynchronous. Do not steal focus from an application
        ; that is still visible, or while it is waiting for a save prompt.
        if elapsed < 3500
            SetTimer(CascadeWatchCloseFocus.Bind(request), -140)
        else
            cascade_close_focus_request := 0
        return
    }

    ; Don't race a manual mouse/keyboard action during the shell handoff.
    for key in ["LButton", "RButton", "MButton", "LWin", "RWin", "Alt", "Ctrl"] {
        if GetKeyState(key, "P") {
            if elapsed < 3500
                SetTimer(CascadeWatchCloseFocus.Bind(request), -140)
            else
                cascade_close_focus_request := 0
            return
        }
    }

    cascade_close_focus_request := 0
    for target in request.targets {
        try {
            if !WinExist("ahk_id " target.hwnd)
                || WinGetPID("ahk_id " target.hwnd) != target.pid
                || !IsSwitchableWindow(target.hwnd)
                continue
            ; Never override a real foreground switch while evaluating choices.
            foreground := DllCall("GetForegroundWindow", "ptr")
            if CascadeHasUsableCloseForeground(foreground, request.hwnd, request.pid)
                return
            if ActivateWindow(target.hwnd) {
                ; Match Win+Backspace: show the accent border on the window
                ; actually focused by the fallback, including other monitors.
                if DllCall("GetForegroundWindow", "ptr") = target.hwnd
                    SuiteFocusBorder.Show(target.hwnd, "cascade-close")
                DebugLog("Caps+Delete focus fallback. | target="
                    . DescribeWindow(target.hwnd))
                return
            }
        }
        catch Error as err
            DebugError("Close focus fallback", err)
    }
}


CancelCascadePendingMouseActions(*)
{
    if !IsCascadeEnabled()
        return

    CancelPendingAdoptionUndo()
    CancelNewWindowFocus()
}
