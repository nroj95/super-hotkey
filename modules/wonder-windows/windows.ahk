; Wonder Windows shared helpers: serialized commands, identity checks,
; window filtering, monitor geometry and placement snapshots.

; =============================================================================
; serialized window commands and native identity checks
; =============================================================================

WW_RunWindowCommand(command, arguments*)
{
    previous_critical := A_IsCritical
    previous_dpi_context := 0
    previous_win_delay := A_WinDelay
    SetWinDelay 10
    Critical "On"
    try {
        ; DWM frame bounds are physical pixels. Match WinGetPos/WinMove to them
        ; for the whole operation, including WINDOWPLACEMENT capture/restore.
        ; Scope this per entry point: a tray/menu thread can start in another context.
        try previous_dpi_context := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        return command(arguments*)
    }
    finally {
        if previous_dpi_context
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi_context, "ptr")
        SetWinDelay previous_win_delay
        Critical previous_critical
    }
}

WW_WindowStateMatchesProcess(hwnd, saved)
{
    process_id := WindowProcessId(hwnd)
    return process_id && saved.Has("pid") && process_id = saved["pid"]
}

; =============================================================================
; window filtering
; =============================================================================

; =============================================================================
; monitor geometry
; =============================================================================

WW_GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
{
    ; rcMonitor includes the taskbar area.
    rect := MonitorRects(WindowMonitor(hwnd)).monitor
    left := rect[1], top := rect[2], right := rect[3], bottom := rect[4]
}

WW_GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
{
    ; rcWork excludes the taskbar.
    rect := MonitorRects(WindowMonitor(hwnd)).work
    left := rect[1], top := rect[2], right := rect[3], bottom := rect[4]
}

; =============================================================================
; native placement snapshots and frame refresh
; =============================================================================

WW_ApplyWindowPlacement(hwnd, placement, show_command := unset)
{
    SuiteWindowOwnership.Claim(hwnd)
    original_show_command := NumGet(placement, 8, "uint")

    try {
        if IsSet(show_command)
            NumPut("uint", show_command, placement, 8)

        if !DllCall("SetWindowPlacement", "ptr", hwnd, "ptr", placement, "int") {
            throw OSError()
        }
    }
    finally {
        if IsSet(show_command)
            NumPut("uint", original_show_command, placement, 8)
    }
}

; =============================================================================
; activation and window-list lookup
; =============================================================================

WW_FindWindowIndex(windows, target_hwnd)
{
    if !target_hwnd
        return 0

    for index, hwnd in windows {
        if hwnd = target_hwnd
            return index
    }

    return 0
}

; =============================================================================
; visible-frame placement
; =============================================================================

WW_MoveWindowToVisibleRectangle(hwnd, target)
{
    SuiteWindowOwnership.Claim(hwnd)
    if target[3] <= 0 || target[4] <= 0
        return false

    try {
        ; DWM's visible frame excludes the invisible resize borders. Compensate
        ; for all four so tiled windows visually meet the requested boundaries.
        raw := VisibleToRawRect(hwnd, target*)
        WinMove(raw[1], raw[2], raw[3], raw[4], hwnd)
        Sleep 10
        return true
    }
    catch Error as err {
        WW_DebugError("Move visible window rectangle", err)
        return false
    }
}

; The smallest visible size an app accepts, from its own WM_GETMINMAXINFO
; answer, which Windows marshals across processes. [0, 0] when unknown.
WW_GetMinimumVisibleSize(hwnd)
{
    info := Buffer(40, 0) ; MINMAXINFO
    if !DllCall("SendMessageTimeoutW", "ptr", hwnd, "uint", 0x24, "ptr", 0, "ptr", info,
        "uint", 0x2, "uint", 100, "ptr", 0, "ptr") ; WM_GETMINMAXINFO, SMTO_ABORTIFHUNG
        return [0, 0]
    frame := GetWindowFrame(hwnd)
    width := NumGet(info, 24, "int") - (frame ? frame.left + frame.right : 0)
    height := NumGet(info, 28, "int") - (frame ? frame.top + frame.bottom : 0)
    return [Max(0, width), Max(0, height)]
}

; Confirm the visible result, not merely that WinMove accepted the request.
WW_WindowMatchesVisibleRectangle(hwnd, target, tolerance := 2)
{
    Loop 4 {
        try {
            if WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), target, tolerance)
                return true
        }
        catch {
            return false
        }
        if A_Index < 4
            Sleep 10
    }
    return false
}
