; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

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

WW_IsWindowToggleCandidate(hwnd, include_minimized := false)
{
    if !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || !IsTopLevelAppWindow(hwnd) || IsWindowCloaked(hwnd)
        return false

    try return (include_minimized || WinGetMinMax("ahk_id " hwnd) != -1)
        && WinGetTitle("ahk_id " hwnd) != ""
    return false
}

; =============================================================================
; monitor geometry
; =============================================================================

WW_GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := WW_GetWindowMonitorInfo(hwnd)

    ; rcMonitor includes the taskbar area.
    left := NumGet(monitor_info, 4, "int")
    top := NumGet(monitor_info, 8, "int")
    right := NumGet(monitor_info, 12, "int")
    bottom := NumGet(monitor_info, 16, "int")
}

WW_GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := WW_GetWindowMonitorInfo(hwnd)

    ; rcWork excludes the taskbar.
    left := NumGet(monitor_info, 20, "int")
    top := NumGet(monitor_info, 24, "int")
    right := NumGet(monitor_info, 28, "int")
    bottom := NumGet(monitor_info, 32, "int")
}

WW_GetWindowMonitorInfo(hwnd)
{
    monitor_handle := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2, ; MONITOR_DEFAULTTONEAREST
        "ptr"
    )

    monitor_info := Buffer(40, 0)
    NumPut("uint", monitor_info.Size, monitor_info, 0)

    if !DllCall("GetMonitorInfo", "ptr", monitor_handle, "ptr", monitor_info) {
        throw OSError()
    }

    return monitor_info
}

; =============================================================================
; native placement snapshots and frame refresh
; =============================================================================

WW_CaptureWindowPlacement(hwnd)
{
    placement := Buffer(44, 0)
    NumPut("uint", placement.Size, placement, 0)

    if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", placement, "int") {
        throw OSError()
    }

    return placement
}

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

WW_ActivateWindowReliably(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    if WinActive(hwnd) && !DllCall("IsIconic", "ptr", hwnd, "int")
        return true

    WW_DebugLog("ActivateWindowReliably begin." . " | target=" WW_DebugDescribeWindow(hwnd))

    try {
        if WinGetMinMax(hwnd) = -1
            WinRestore(hwnd)
    }

    Loop 6 {
        attempt := A_Index

        try WinActivate(hwnd)
        if WinActive(hwnd)
            return true

        set_foreground_result := DllCall("SetForegroundWindow", "ptr", hwnd, "int")

        Sleep 50

        foreground_hwnd :=
            DllCall("GetForegroundWindow", "ptr")

        WW_DebugLog("Normal-window activation attempt." . " | attempt=" attempt
            . " | SetForegroundWindow=" . set_foreground_result
            . " | requested=" WW_DebugDescribeWindow(hwnd) . " | foreground="
            . WW_DebugDescribeWindow(foreground_hwnd))

        if foreground_hwnd = hwnd
            return true
    }

    return false
}

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
