; Internal Cascade Kingdom input opt-in gestures.

; A key-held launch captures one opt-in or opt-out for up to eight seconds.
; A physical hold at SHOW supports launchers whose input we cannot identify.

CascadeIsOptInIntentFresh(intent, now := 0)
{
    if !IsObject(intent) || !intent.HasOwnProp("tick")
        return false
    if !now
        now := A_TickCount
    return ((now - intent.tick) & 0xFFFFFFFF) <= 8000
}

CascadeRememberLaunchIntent(monitor := 0, source := 0)
{
    global cascade_opt_in_intent, cascade_auto_placement_enabled
    if !IsCascadeEnabled() || !CascadeGestureHeld()
        return
    if !monitor {
        MouseGetPosPixels(&x, &y)
        monitor := GetMonitorForPoint(x, y)
    }
    if !monitor
        return
    CascadeConsumeGesture()
    cascade_opt_in_intent := {tick: A_TickCount,
        monitor_device: GetCascadeMonitorDevice(monitor),
        source_hwnd: source, cascade: !cascade_auto_placement_enabled}
}

CascadeIsLaunchSurface(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    if IsTaskbarSurfaceWindow(hwnd) || IsDesktopSurfaceWindow(hwnd)
        return true
    try exe := StrLower(WinGetProcessName("ahk_id " hwnd))
    catch
        return false
    return exe = "explorer.exe" || exe = "startmenuexperiencehost.exe"
        || exe = "searchhost.exe" || exe = "shellexperiencehost.exe"
        || exe = "searchapp.exe"
}

; Explorer can keep a hidden CabinetWClass HWND alive even when no Explorer
; window appears open. Its first SHOW is effectively a new window, but the
; startup guard would otherwise reject it. Only permit the first *foreground*
; reveal of one of those exact, startup-hidden HWND/PID pairs.
CascadeTakeHiddenStartupExplorerReveal(hwnd)
{
    global cascade_hidden_startup_explorers
    if !cascade_hidden_startup_explorers.Has(hwnd)
        return 0

    ; Never transfer control of an existing, merely minimized/raised window.
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("GetForegroundWindow", "ptr") != hwnd
        return 0

    expected_pid := cascade_hidden_startup_explorers[hwnd]
    cascade_hidden_startup_explorers.Delete(hwnd) ; single use, even if mode is off
    try {
        if WinGetPID("ahk_id " hwnd) != expected_pid
            || WinGetClass("ahk_id " hwnd) != "CabinetWClass"
            || StrLower(WinGetProcessName("ahk_id " hwnd)) != "explorer.exe"
            || IsIgnoredByWindowCascade(hwnd)
            return 0
    }
    catch
        return 0

    ; Share the exact same captured opt-in/opt-out as ordinary new windows.
    return CascadeTakeOptInMonitor(hwnd)
}

CascadeCaptureKeyboardLaunch(*)
{
    if !IsCascadeEnabled() || !CascadeGestureHeld()
        return
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if CascadeIsLaunchSurface(hwnd)
        CascadeRememberLaunchIntent(0, hwnd)
}

; Separate from taskbar focus recovery. One eligible new HWND consumes intent.
CascadeTakeOptInMonitor(hwnd, &reason := "")
{
    global cascade_opt_in_intent, cascade_auto_placement_enabled
    reason := ""
    intent := cascade_opt_in_intent
    if !CascadeGestureEnabled() {
        cascade_opt_in_intent := 0
        intent := 0
    }
    if CascadeIsOptInIntentFresh(intent) && hwnd != intent.source_hwnd {
        cascade_opt_in_intent := 0
        if !intent.cascade {
            reason := "gesture-opt-out"
            return 0
        }
        monitor := FindCascadeMonitorDevice(intent.monitor_device)
        reason := "gesture-launch"
        return ResolveCascadeDestination(monitor ? monitor : MonitorGetPrimary())
    }
    if IsObject(intent) && !CascadeIsOptInIntentFresh(intent)
        cascade_opt_in_intent := 0
    held := CascadeGestureHeld()
    if !CascadeShouldLaunch(cascade_auto_placement_enabled, held) {
        if held {
            CascadeConsumeGesture()
            reason := "gesture-held-opt-out"
        }
        return 0
    }
    MouseGetPosPixels(&x, &y)
    monitor := GetMonitorForPoint(x, y)
    if held {
        CascadeConsumeGesture()
        reason := "gesture-held-at-show"
    } else
        reason := monitor ? "automatic-pointer" : "automatic-fallback"
    return ResolveCascadeDestination(monitor ? monitor : MonitorGetPrimary())
}

; Prefer a real OS caption hit. Custom title bars can report client-area hits,
; so for those we verify that the double-click caused native maximize/restore.
CascadeIsCaptionPoint(hwnd, x, y)
{
    if !hwnd
        return false
    lparam := (x & 0xFFFF) | ((y & 0xFFFF) << 16)
    result := 0
    try {
        ok := DllCall("SendMessageTimeoutW", "ptr", hwnd, "uint", 0x84,
            "uptr", 0, "ptr", lparam, "uint", 0x2, "uint", 80,
            "ptr*", &result, "ptr")
        return !!ok && result = 2 ; WM_NCHITTEST = HTCAPTION
    }
    catch
        return false
}

CascadeIsSecondCaptionClick(previous, hwnd, pid, x, y, now, limit, tolerance_x, tolerance_y)
{
    return IsObject(previous) && previous.hwnd = hwnd && previous.pid = pid
        && ((now - previous.tick) & 0xFFFFFFFF) <= limit
        && Abs(previous.x - x) <= tolerance_x
        && Abs(previous.y - y) <= tolerance_y
}

; Do not mistake an ordinary double-click in client content for a title-bar
; action: the OS/application must actually maximize or restore the window.
CascadeWasMaximizeRestore(before, after)
{
    return (before = 0 && after = 1) || (before = 1 && after = 0)
}

CascadeCanAdoptCaptionWindow(hwnd, before)
{
    ; Native restore may finish before the deferred callback, while the window
    ; is still in cascade history. Preserve the state from the first click.
    return before = 1 || !GetManagedCascadeMonitor(hwnd)
}

CascadeVerifyCustomCaptionDoubleClick(hwnd, pid, monitor, before)
{
    if !IsCascadeEnabled() || !CascadeGestureEnabled()
        || !CascadeCanAdoptCaptionWindow(hwnd, before)
        return
    try {
        if !WinExist("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != pid
            || IsShellSurfaceWindow(hwnd) || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
            return
        after := WinGetMinMax("ahk_id " hwnd)
        if !CascadeWasMaximizeRestore(before, after)
            return
        DebugLog("Custom title-bar double-click confirmed by maximize/restore."
            . " | " DescribeWindow(hwnd))
        CascadeAdoptCaptionWindow(hwnd, pid, monitor, before)
    }
    catch Error as err
        DebugError("Verify custom title-bar double-click", err)
}

CascadeObserveGestureMouseClick(hwnd, x, y)
{
    global cascade_titlebar_click
    if !CascadeGestureHeld() {
        cascade_titlebar_click := 0
        return
    }
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return
    monitor := GetMonitorForPoint(x, y)
    if !monitor
        return
    if !IsShellSurfaceWindow(hwnd) && SuiteWindowOwnership.AllowsWonderWindows(hwnd) {
        try {
            pid := WinGetPID("ahk_id " hwnd)
            state := WinGetMinMax("ahk_id " hwnd)
        }
        catch
            return
        if state = 0 || state = 1 {
            CascadeConsumeGesture()
            now := A_TickCount
            if CascadeIsSecondCaptionClick(cascade_titlebar_click, hwnd, pid, x, y,
                now, DllCall("GetDoubleClickTime", "uint"),
                DllCall("GetSystemMetrics", "int", 36, "int"),
                DllCall("GetSystemMetrics", "int", 37, "int")) {
                first := cascade_titlebar_click
                cascade_titlebar_click := 0
                if first.native_caption && CascadeIsCaptionPoint(hwnd, x, y) {
                    ; Preserve native title-bar adoption behavior.
                    CascadeQueueGesture(CascadeAdoptCaptionWindow, 80,
                        hwnd, pid, monitor, first.window_state)
                } else {
                    ; No geometry guesses for custom title bars or client content.
                    ; Wait for the native double-click to change maximize state.
                    CascadeQueueGesture(CascadeVerifyCustomCaptionDoubleClick, 120,
                        hwnd, pid, monitor, first.window_state)
                }
                return
            }
            native_caption := CascadeIsCaptionPoint(hwnd, x, y)
            cascade_titlebar_click := {hwnd: hwnd, pid: pid, x: x, y: y,
                tick: now, window_state: state, native_caption: native_caption}
            ; File Explorer's client area may launch apps under the cascade key.
            if !native_caption && CascadeIsLaunchSurface(hwnd)
                CascadeRememberLaunchIntent(monitor, hwnd)
            return
        }
    }
    cascade_titlebar_click := 0
    if CascadeIsLaunchSurface(hwnd)
        CascadeRememberLaunchIntent(monitor, hwnd)
}

CascadeAdoptCaptionWindow(hwnd, pid, monitor, before := 0)
{
    global cascade_opt_in_intent
    if !IsCascadeEnabled() || !CascadeGestureEnabled() || IsCascadeDisplayTransition()
        || HasCascadeWindowDrag() || !CascadeCanAdoptCaptionWindow(hwnd, before)
        return
    try {
        if !WinExist("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != pid
            || IsShellSurfaceWindow(hwnd) || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
            return
        monitor := ResolveCascadeDestination(monitor)
        if !monitor
            return
        ; Only confirmed title-bar adoption consumes a possible Explorer launch.
        cascade_opt_in_intent := 0
        ; Never adopt an unrelated foreground HWND or an internal tool surface.
        was_manual := SuiteWindowOwnership.Release(hwnd)
        if !PlaceCascadeWindowOnMonitor(hwnd, monitor) && was_manual
            SuiteWindowOwnership.Claim(hwnd)
    }
    catch Error as err
        DebugError("Cascade-key double-click adoption", err)
}
