; Native F11 is application-controlled; do not change foreign window styles.
WW_IsNativeFullscreen(hwnd)
{
    if SuiteFullscreen.placements.Has(hwnd)
        return true
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
        if DllCall("GetPropW", "ptr", hwnd, "str", SuiteFullscreen.marker, "ptr")
            SuiteFullscreen.Toggle()
        else
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
