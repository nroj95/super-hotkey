; Cascade Kingdom window filtering, visible frames and monitor lookup.

; =============================================================================
; window filtering
; =============================================================================

; Suite surfaces are never cascaded. Windows positioned by hand are left alone
; too, unless allow_manual says the user is moving one right now.
IsIgnoredByCascade(hwnd, allow_manual := false)
{
    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    return (!allow_manual && SuiteWindowOwnership.IsManual(hwnd))
        || !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr")
}

; Standard Windows dialogs, Explorer file-operation prompts and hung-window
; ghosts are transient UI, not standalone application windows.
IsPlausibleTopLevelWindow(hwnd, allow_manual := false)
{
    return !IsIgnoredByCascade(hwnd, allow_manual) && IsTopLevelAppWindow(hwnd, &window_class)
        && window_class != "#32770" && window_class != "OperationStatusWindow"
        && window_class != "Ghost"
}

IsCascadeWindow(hwnd, allow_manual := false)
{
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") || IsIgnoredByCascade(hwnd, allow_manual)
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
; monitor lookup
; =============================================================================

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
