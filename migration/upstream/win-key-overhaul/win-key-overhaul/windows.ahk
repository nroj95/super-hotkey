; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; serialized window commands and native identity checks
; =============================================================================

RunWindowCommand(command, arguments*)
{
    previous_critical := A_IsCritical
    previous_dpi_context := 0
    Critical "On"
    try {
        ; DWM frame bounds are physical pixels. Match WinGetPos/WinMove to them
        ; for the whole operation, including WINDOWPLACEMENT capture/restore.
        ; Scope this per entry point: a tray/menu thread can start in another context.
        try previous_dpi_context := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        PruneBorderlessWindows()
        return command(arguments*)
    }
    finally {
        if previous_dpi_context
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi_context, "ptr")
        Critical previous_critical
    }
}

GetWindowProcessId(hwnd)
{
    process_id := 0
    if !hwnd || !DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &process_id, "uint")
        return 0
    return process_id
}

WindowStateMatchesProcess(hwnd, saved)
{
    process_id := GetWindowProcessId(hwnd)
    return process_id && saved.Has("pid") && process_id = saved["pid"]
}

; =============================================================================
; window filtering
; =============================================================================

IsWindowToggleCandidate(hwnd)
{
    if !hwnd
        return false

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        return false

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if root_hwnd != hwnd
        return false

    try {
        if WinGetMinMax("ahk_id " hwnd) = -1
            return false

        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)
        class_name := WinGetClass("ahk_id " hwnd)
    }
    catch {
        return false
    }

    if title = ""
        return false

    if style & 0x40000000 ; WS_CHILD
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if IsWinKeyOverhaulShellClass(class_name)
        return false

    if IsWinKeyOverhaulCloaked(hwnd)
        return false

    return true
}

IsWinKeyOverhaulCloaked(hwnd)
{
    cloaked := 0

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 14, ; DWMWA_CLOAKED
        "uint*", &cloaked,
        "uint", 4,
        "int"
    )

    return result = 0 && cloaked != 0
}

IsWinKeyOverhaulShellClass(class_name)
{
    return (
        class_name = "Shell_TrayWnd"
        || class_name = "Shell_SecondaryTrayWnd"
        || class_name = "Progman"
        || class_name = "WorkerW"
        || class_name = "NotifyIconOverflowWindow"
        || class_name = "tooltips_class32"
    )
}

; =============================================================================
; visible frame and monitor geometry
; =============================================================================

GetVisibleWindowBounds(
    hwnd,
    &x,
    &y,
    &width,
    &height
)
{
    static DWMWA_EXTENDED_FRAME_BOUNDS := 9

    frame := Buffer(16, 0)

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", DWMWA_EXTENDED_FRAME_BOUNDS,
        "ptr", frame,
        "uint", frame.Size,
        "int"
    )

    if result != 0
        return false

    left := NumGet(frame, 0, "int")
    top := NumGet(frame, 4, "int")
    right := NumGet(frame, 8, "int")
    bottom := NumGet(frame, 12, "int")

    x := left
    y := top
    width := right - left
    height := bottom - top

    return width > 0 && height > 0
}

GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := GetWindowMonitorInfo(hwnd)

    ; rcMonitor includes the taskbar area.
    left := NumGet(monitor_info, 4, "int")
    top := NumGet(monitor_info, 8, "int")
    right := NumGet(monitor_info, 12, "int")
    bottom := NumGet(monitor_info, 16, "int")
}

GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := GetWindowMonitorInfo(hwnd)

    ; rcWork excludes the taskbar.
    left := NumGet(monitor_info, 20, "int")
    top := NumGet(monitor_info, 24, "int")
    right := NumGet(monitor_info, 28, "int")
    bottom := NumGet(monitor_info, 32, "int")
}

GetWindowMonitorInfo(hwnd)
{
    monitor_handle := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2, ; MONITOR_DEFAULTTONEAREST
        "ptr"
    )

    monitor_info := Buffer(40, 0)
    NumPut("uint", monitor_info.Size, monitor_info, 0)

    if !DllCall(
        "GetMonitorInfo",
        "ptr", monitor_handle,
        "ptr", monitor_info
    ) {
        throw OSError()
    }

    return monitor_info
}

; =============================================================================
; native placement snapshots and frame refresh
; =============================================================================

CaptureWindowPlacement(hwnd)
{
    placement := Buffer(44, 0)
    NumPut("uint", placement.Size, placement, 0)

    if !DllCall(
        "GetWindowPlacement",
        "ptr", hwnd,
        "ptr", placement,
        "int"
    ) {
        throw OSError()
    }

    return placement
}

ApplyWindowPlacement(hwnd, placement, show_command := unset)
{
    original_show_command := NumGet(
        placement,
        8,
        "uint"
    )

    try {
        if IsSet(show_command)
            NumPut(
                "uint",
                show_command,
                placement,
                8
            )

        if !DllCall(
            "SetWindowPlacement",
            "ptr", hwnd,
            "ptr", placement,
            "int"
        ) {
            throw OSError()
        }
    }
    finally {
        if IsSet(show_command)
            NumPut(
                "uint",
                original_show_command,
                placement,
                8
            )
    }
}

RefreshWindowFrame(hwnd)
{
    static SWP_NOSIZE := 0x0001
    static SWP_NOMOVE := 0x0002
    static SWP_NOZORDER := 0x0004
    static SWP_NOACTIVATE := 0x0010
    static SWP_FRAMECHANGED := 0x0020

    DllCall(
        "SetWindowPos",
        "ptr", hwnd,
        "ptr", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "uint",
        SWP_NOSIZE
        | SWP_NOMOVE
        | SWP_NOZORDER
        | SWP_NOACTIVATE
        | SWP_FRAMECHANGED
    )
}

; =============================================================================
; activation and window-list lookup
; =============================================================================

ActivateWindowReliably(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    if WinActive(hwnd) && !DllCall("IsIconic", "ptr", hwnd, "int")
        return true

    DebugLog(
        "ActivateWindowReliably begin."
        . " | target=" DebugDescribeWindow(hwnd)
    )

    try {
        if WinGetMinMax(hwnd) = -1
            WinRestore(hwnd)
    }

    Loop 6 {
        attempt := A_Index

        try WinActivate(hwnd)
        if WinActive(hwnd)
            return true

        set_foreground_result := DllCall(
            "SetForegroundWindow",
            "ptr", hwnd,
            "int"
        )

        Sleep 50

        foreground_hwnd :=
            DllCall("GetForegroundWindow", "ptr")

        DebugLog(
            "Normal-window activation attempt."
            . " | attempt=" attempt
            . " | SetForegroundWindow="
            . set_foreground_result
            . " | requested=" DebugDescribeWindow(hwnd)
            . " | foreground="
            . DebugDescribeWindow(foreground_hwnd)
        )

        if foreground_hwnd = hwnd
            return true
    }

    return false
}

FindWindowIndex(windows, target_hwnd)
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

MoveWindowToVisibleRectangle(hwnd, target)
{
    if target[3] <= 0 || target[4] <= 0
        return false

    try {
        WinGetPos(&raw_x, &raw_y, &raw_width, &raw_height, hwnd)
        if !GetVisibleWindowBounds(hwnd, &visible_x, &visible_y, &visible_width, &visible_height) {
            visible_x := raw_x
            visible_y := raw_y
            visible_width := raw_width
            visible_height := raw_height
        }

        ; DWM's visible frame excludes the invisible resize borders. Compensate
        ; for all four so tiled windows visually meet the requested boundaries.
        inset_left := visible_x - raw_x
        inset_top := visible_y - raw_y
        inset_right := raw_x + raw_width - visible_x - visible_width
        inset_bottom := raw_y + raw_height - visible_y - visible_height
        WinMove(
            target[1] - inset_left,
            target[2] - inset_top,
            target[3] + inset_left + inset_right,
            target[4] + inset_top + inset_bottom,
            hwnd
        )
        Sleep 10
        return true
    }
    catch Error as err {
        DebugError("Move visible window rectangle", err)
        return false
    }
}

; Confirm the visible result, not merely that WinMove accepted the request.
WindowMatchesVisibleRectangle(hwnd, target, tolerance := 2)
{
    Loop 4 {
        try {
            if RectanglesMatch(GetWindowLayoutRectangle(hwnd), target, tolerance)
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
