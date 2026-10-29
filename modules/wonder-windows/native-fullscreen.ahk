; Native F11 is application-controlled; do not change foreign window styles.
WW_IsNativeFullscreen(hwnd)
{
    if !WW_WindowFillsPhysicalMonitor(hwnd)
        return false
    try {
        ; Maximized windows with normal captions are not native fullscreen.
        return WinGetMinMax(hwnd) != 1 || !(WinGetStyle(hwnd) & 0x00C00000)
    }
    catch {
        return false
    }
}

WW_SetNativeFullscreen(hwnd, enabled)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    if WW_IsNativeFullscreen(hwnd) = enabled
        return true
    if !WinActive("ahk_id " hwnd)
        return false

    try {
        SendEvent("{F11}") ; non-blind Send releases held shortcut modifiers

        Loop 10 {
            Sleep 40
            if !WinActive("ahk_id " hwnd)
                return false
            if WW_IsNativeFullscreen(hwnd) = enabled
                return true
        }
    }
    catch Error as err {
        WW_DebugError("Native F11", err)
    }
    WW_DebugLog("Native F11 transition not confirmed. hwnd=" hwnd " expected=" enabled)
    return false
}

; A window fills its display when it covers every edge. Borderless games such
; as Chrono Trigger overhang their display, by more after each restore; that
; is fine where no other display is. A window reaching more than 1/16 of this
; display's size onto another display spans both and does not count.
; Rectangles are [left, top, right, bottom].
WW_RectCoversMonitor(rect, monitor, others, tolerance := 2)
{
    if rect[1] > monitor[1] + tolerance || rect[2] > monitor[2] + tolerance
        || rect[3] < monitor[3] - tolerance || rect[4] < monitor[4] - tolerance
        return false
    reach_x := Max(tolerance, (monitor[3] - monitor[1]) // 16)
    reach_y := Max(tolerance, (monitor[4] - monitor[2]) // 16)
    for other in others {
        width := Min(rect[3], other[3]) - Max(rect[1], other[1])
        height := Min(rect[4], other[4]) - Max(rect[2], other[2])
        if width > reach_x && height > reach_y
            return false
    }
    return true
}

; Every display except the one at monitor, as [left, top, right, bottom].
WW_OtherMonitorRects(monitor)
{
    others := []
    loop MonitorGetCount() {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if left != monitor[1] || top != monitor[2] || right != monitor[3] || bottom != monitor[4]
            others.Push([left, top, right, bottom])
    }
    return others
}

WW_WindowFillsPhysicalMonitor(hwnd, tolerance := 2)
{
    try {
        if !GetVisibleWindowBounds(hwnd, &window_x, &window_y, &window_width, &window_height) {
            WinGetPos(&window_x, &window_y, &window_width, &window_height, "ahk_id " hwnd)
        }

        WW_GetWindowMonitorBounds(hwnd, &monitor_left, &monitor_top, &monitor_right, &monitor_bottom
        )
    }
    catch {
        return false
    }

    monitor := [monitor_left, monitor_top, monitor_right, monitor_bottom]
    return WW_RectCoversMonitor([window_x, window_y, window_x + window_width, window_y + window_height],
        monitor, WW_OtherMonitorRects(monitor), tolerance)
}
