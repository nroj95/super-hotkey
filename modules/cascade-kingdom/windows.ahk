; Cascade Kingdom window filtering, visible frames and monitor lookup.

; =============================================================================
; window filtering
; =============================================================================

; Suite surfaces are never cascaded. Windows positioned by hand are left alone
; too, unless allow_manual says the user is moving one right now.
IsIgnoredByWindowCascade(hwnd, allow_manual := false)
{
    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    return (!allow_manual && SuiteWindowOwnership.IsManual(hwnd))
        || !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.WindowCascade.Ignore", "ptr")
}

; Standard Windows dialogs, Explorer file-operation prompts and hung-window
; ghosts are transient UI, not standalone application windows.
IsPlausibleTopLevelWindow(hwnd, allow_manual := false)
{
    return !IsIgnoredByWindowCascade(hwnd, allow_manual) && IsTopLevelAppWindow(hwnd, &window_class)
        && window_class != "#32770" && window_class != "OperationStatusWindow"
        && window_class != "Ghost"
}

IsCascadeWindow(hwnd, allow_manual := false)
{
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") || IsIgnoredByWindowCascade(hwnd, allow_manual)
        || !IsTopLevelAppWindow(hwnd, &window_class) || IsWindowCloaked(hwnd)
        || window_class = "#32770" || window_class = "OperationStatusWindow"
        return false

    try {
        min_max := WinGetMinMax("ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)
        WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
    }
    catch {
        return false
    }

    ; Require a restored, captioned, resizable application window. Empty-title
    ; windows are commonly invisible framework/helper windows.
    return min_max = 0 && (style & 0x00C00000) && (style & 0x00040000)
        && width >= 1 && height >= 1 && title != ""
}

IsDesktopSurfaceWindow(hwnd)
{
    try window_class := hwnd && WinExist("ahk_id " hwnd) ? WinGetClass("ahk_id " hwnd) : ""
    catch
        return false
    return window_class = "Progman" || window_class = "WorkerW"
}

IsTaskbarSurfaceWindow(hwnd)
{
    try window_class := hwnd && WinExist("ahk_id " hwnd) ? WinGetClass("ahk_id " hwnd) : ""
    catch
        return false
    return window_class = "Shell_TrayWnd" || window_class = "Shell_SecondaryTrayWnd"
}

IsCascadeWindowTopmost(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return -1

    try return !!(WinGetExStyle("ahk_id " hwnd) & 0x8) ; WS_EX_TOPMOST
    catch
        return -1
}


; =============================================================================
; visible frame geometry
; =============================================================================

TryGetWindowCenter(hwnd, &center_x, &center_y)
{
    if !(frame := GetWindowFrame(hwnd))
        return false

    center_x := frame.x + frame.width / 2
    center_y := frame.y + frame.height / 2

    return true
}


; =============================================================================
; monitor selection and lookup
; =============================================================================

GetCommandMonitor() => SuiteWorkingMonitor.Get()

ResolveCascadePlacementMonitor(request, fallback_monitor)
{
    global cascade_target_display
    if cascade_target_display != "All"
        return ResolveCascadeDestination(fallback_monitor)
    if request.HasOwnProp("monitor_device") && request.monitor_device != "" {
        monitor := FindCascadeMonitorDevice(request.monitor_device)
        ; Never reuse a removed display's old index or re-sample a later mouse.
        return monitor ? monitor : MonitorGetPrimary()
    }
    return fallback_monitor ? fallback_monitor : MonitorGetPrimary()
}

GetMonitorForWindow(hwnd)
{
    try {
        WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
    }
    catch {
        return 0
    }

    if width <= 0 || height <= 0
        return 0

    return GetMonitorForPoint(x + Floor(width / 2), y + Floor(height / 2))
}

GetMonitorForPoint(x, y)
{
    monitor_count := MonitorGetCount()

    Loop monitor_count {
        MonitorGetPixels(A_Index, &left, &top, &right, &bottom)

        if x >= left && x < right && y >= top && y < bottom
            return A_Index
    }

    return 0
}
