; Internal Window Cascade input opt-in gestures.

; Launch intent is deliberately one-shot. Normal new windows are never adopted.
; A shell click/Enter is recognized up to eight seconds after the gesture.
; Holding CapsLock until SHOW is also supported for launchers we cannot identify.

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
    global cascade_opt_in_intent
    if !IsCascadeEnabled() || !GetKeyState("CapsLock", "P")
        return
    if !monitor {
        MouseGetPosPixels(&x, &y)
        monitor := GetMonitorForPoint(x, y)
    }
    if !monitor
        return
    cascade_opt_in_intent := {tick: A_TickCount,
        monitor_device: GetCascadeMonitorDevice(monitor),
        source_hwnd: source}
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
CascadeShouldAdoptHiddenExplorer(was_hidden_at_start, foreground_matches,
    automatic_enabled, caps_held)
{
    return was_hidden_at_start && foreground_matches
        && (automatic_enabled || caps_held)
}

CascadeTakeHiddenStartupExplorerReveal(hwnd)
{
    global cascade_hidden_startup_explorers, cascade_auto_placement_enabled
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

    if !CascadeShouldAdoptHiddenExplorer(true, true,
        cascade_auto_placement_enabled, GetKeyState("CapsLock", "P"))
        return 0

    MouseGetPosPixels(&x, &y)
    monitor := GetMonitorForPoint(x, y)
    return monitor ? monitor : MonitorGetPrimary()
}

CascadeCaptureKeyboardLaunch(*)
{
    if !IsCascadeEnabled() || !GetKeyState("CapsLock", "P")
        return
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if CascadeIsLaunchSurface(hwnd)
        CascadeRememberLaunchIntent(0, hwnd)
}

; This is deliberately separate from the existing taskbar *focus recovery* hint.
; The first eligible NEW window consumes the opt-in; subsequent windows are normal.
CascadeTakeOptInMonitor(hwnd, &reason := "")
{
    global cascade_opt_in_intent, cascade_auto_placement_enabled
    reason := ""
    intent := cascade_opt_in_intent
    if CascadeIsOptInIntentFresh(intent) && hwnd != intent.source_hwnd {
        cascade_opt_in_intent := 0
        monitor := FindCascadeMonitorDevice(intent.monitor_device)
        if monitor {
            reason := "caps-launch"
            return monitor
        }
        ; A disconnected display must never be replaced by a stale monitor index.
        reason := "caps-launch-disconnected"
        return MonitorGetPrimary()
    }
    if IsObject(intent) && !CascadeIsOptInIntentFresh(intent)
        cascade_opt_in_intent := 0
    if GetKeyState("CapsLock", "P") {
        MouseGetPosPixels(&x, &y)
        monitor := GetMonitorForPoint(x, y)
        if monitor {
            reason := "caps-held-at-show"
            return monitor
        }
    }
    if cascade_auto_placement_enabled {
        MouseGetPosPixels(&x, &y)
        monitor := GetMonitorForPoint(x, y)
        reason := monitor ? "automatic-pointer" : "automatic-fallback"
        return monitor ? monitor : MonitorGetPrimary()
    }
    return 0
}

; A real caption hit uses the OS non-client hit test. Do not infer a title bar
; from a Y coordinate: tabs, browser toolbars and custom clients are not captions.
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

CascadeObserveCapsMouseClick(hwnd, x, y)
{
    global cascade_titlebar_click
    if !GetKeyState("CapsLock", "P") {
        cascade_titlebar_click := 0
        return
    }
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return
    monitor := GetMonitorForPoint(x, y)
    if !monitor
        return
    if CascadeIsCaptionPoint(hwnd, x, y) && SuiteWindowOwnership.AllowsWonderWindows(hwnd) {
        try pid := WinGetPID("ahk_id " hwnd)
        catch
            return
        now := A_TickCount
        if CascadeIsSecondCaptionClick(cascade_titlebar_click, hwnd, pid, x, y,
            now, DllCall("GetDoubleClickTime", "uint"),
            DllCall("GetSystemMetrics", "int", 36, "int"),
            DllCall("GetSystemMetrics", "int", 37, "int")) {
            cascade_titlebar_click := 0
            ; Let the native second click (including maximize/restore) complete.
            SetTimer(CascadeAdoptCaptionWindow.Bind(hwnd, pid, monitor), -80)
        } else {
            cascade_titlebar_click := {hwnd: hwnd, pid: pid, x: x, y: y, tick: now}
        }
        return
    }
    cascade_titlebar_click := 0
    if CascadeIsLaunchSurface(hwnd)
        CascadeRememberLaunchIntent(monitor, hwnd)
}

CascadeAdoptCaptionWindow(hwnd, pid, monitor)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        || HasCascadeWindowDrag() || GetManagedCascadeMonitor(hwnd)
        return
    try {
        if !WinExist("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != pid
            || IsShellSurfaceWindow(hwnd) || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
            return
        ; Never adopt an unrelated foreground HWND or an internal tool surface.
        was_manual := SuiteWindowOwnership.Release(hwnd)
        if !PlaceCascadeWindowOnMonitor(hwnd, monitor) && was_manual
            SuiteWindowOwnership.Claim(hwnd)
    }
    catch Error as err
        DebugError("Caps double-click adoption", err)
}
