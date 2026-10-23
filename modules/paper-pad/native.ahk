; Paper Pad's small native helpers: editor focus, window idleness and dialogs,
; file paths and stamps, and a millisecond clock.

PaperPadEditorFocused()
{
    global paperPad

    if !IsSet(paperPad) || !IsObject(paperPad) || !paperPad.HasWindow()
        return false
    if !WinActive("ahk_id " paperPad.window_hwnd)
        return false
    if !paperPad.bridge || paperPad.bridge.tainted
        return false

    ; Read the actual focused HWND instead of relying on a ClassNN string.
    thread_info := Buffer(72, 0) ; GUITHREADINFO, 64-bit
    NumPut("uint", thread_info.Size, thread_info)

    if !DllCall("GetGUIThreadInfo", "uint", 0, "ptr", thread_info, "int")
        return false

    ; Native menus, popup menus and move/size loops keep their normal shortcuts.
    if NumGet(thread_info, 4, "uint") & 0x1E
        return false

    focused_hwnd := NumGet(thread_info, 16, "ptr")
    return focused_hwnd = paperPad.bridge.editor_hwnd
}

PaperPadWindowIdle(hwnd)
{
    if !DllCall("IsWindowEnabled", "ptr", hwnd, "int")
        return false
    thread_id := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    info := Buffer(72, 0) ; GUITHREADINFO, 64-bit
    NumPut("uint", info.Size, info)
    if !DllCall("GetGUIThreadInfo", "uint", thread_id, "ptr", info, "int")
        return false
    if NumGet(info, 4, "uint") & 0x1E ; menus, popup menus, move/size loops
        return false
    popup := DllCall("GetLastActivePopup", "ptr", hwnd, "ptr")
    return !popup || popup = hwnd || !DllCall("IsWindowVisible", "ptr", popup, "int")
}

PaperPadUsableWindow(hwnd)
{
    return hwnd
        && DllCall("IsWindow", "ptr", hwnd, "int")
        && DllCall("IsWindowVisible", "ptr", hwnd, "int")
        && !DllCall("IsIconic", "ptr", hwnd, "int")
}

PaperPadIsDialogWindow(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("IsIconic", "ptr", hwnd, "int") || IsWindowCloaked(hwnd)
        || !DllCall("IsWindowEnabled", "ptr", hwnd, "int")
        || DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != hwnd ; GA_ROOT
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    ex_style := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", -20, "ptr")
    owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
    owner_enabled := !owner || !DllCall("IsWindow", "ptr", owner, "int")
        || DllCall("IsWindowEnabled", "ptr", owner, "int")
    return PaperPadIsDialogCandidate(window_class, ex_style, owner, owner_enabled)
}

PaperPadIsDialogCandidate(window_class, ex_style, owner, owner_enabled := true)
{
    ; Native popup menus and shell chrome are not modal dialogs.
    if window_class = "PseudoConsoleWindow" || window_class = "Button"
        || window_class = "#32768" || window_class = "Desktop User Picture"
        return false
    if window_class = "#32770" || window_class = "OperationStatusWindow"
        return true
    ; Ownership and WS_EX_DLGMODALFRAME (a border style) do not prove modality.
    ; Custom dialogs must block their owner and accept activation themselves.
    return !!owner && !owner_enabled && !(ex_style & 0x08000000) ; WS_EX_NOACTIVATE
}

PaperPadIsOwnedBy(hwnd, expected_owner)
{
    if !hwnd || !expected_owner
        return false
    ; Bound traversal because foreign windows can close or change owners mid-scan.
    loop 16 {
        hwnd := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        if !hwnd
            return false
        if hwnd = expected_owner
            return true
    }
    return false
}

PaperPadFullPath(path)
{
    required := DllCall("GetFullPathNameW", "str", path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
    if !required
        throw OSError(A_LastError, "GetFullPathNameW", path)
    path_buffer := Buffer(required * 2, 0)
    length := DllCall("GetFullPathNameW", "str", path, "uint", required, "ptr", path_buffer, "ptr", 0, "uint")
    if !length || length >= required
        throw Error("Could not normalize the file path:`n" path)
    return StrGet(path_buffer, "UTF-16")
}

PaperPadFileStamp(path)
{
    attributes := Buffer(36, 0) ; WIN32_FILE_ATTRIBUTE_DATA
    if !DllCall("GetFileAttributesExW", "str", path, "int", 0, "ptr", attributes, "int")
        throw OSError(A_LastError, "GetFileAttributesExW", path)
    ; Preserve FILETIME precision, including same-size edits within one second.
    return Format("{:016X}:{:08X}{:08X}", NumGet(attributes, 20, "int64"),
        NumGet(attributes, 28, "uint"), NumGet(attributes, 32, "uint"))
}

PaperPadClockMs()
{
    static frequency := 0
    if !frequency
        DllCall("QueryPerformanceFrequency", "int64*", &frequency)
    counter := 0
    DllCall("QueryPerformanceCounter", "int64*", &counter)
    return counter * 1000 / frequency
}
