; Cascade Kingdom implementation; included by the Super Hotkey launcher.
; Included into the same script; functions share the existing global state.

; =============================================================================
; window filtering
; =============================================================================

IsIgnoredByWindowCascade(hwnd)
{
    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    return SuiteWindowOwnership.IsManual(hwnd)
        || !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.WindowCascade.Ignore", "ptr")
}

IsPlausibleTopLevelWindow(hwnd)
{
    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    if IsIgnoredByWindowCascade(hwnd)
        return false

    ; Reject child controls before doing any higher-level AutoHotkey queries.
    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if root_hwnd != hwnd
        return false

    try {
        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        window_class := WinGetClass("ahk_id " hwnd)
    }
    catch {
        return false
    }

    if style & 0x40000000 ; WS_CHILD
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    ; Standard Windows dialogs and Explorer file-operation prompts are
    ; transient UI, not standalone application windows.
    if window_class = "#32770"
        || window_class = "OperationStatusWindow"
        return false

    ; Owned top-level windows are normally dialogs or transient popups.
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if window_class = "Shell_TrayWnd"
        || window_class = "Shell_SecondaryTrayWnd"
        || window_class = "Progman"
        || window_class = "WorkerW"
        || window_class = "NotifyIconOverflowWindow"
        || window_class = "tooltips_class32"
        || window_class = "Ghost"
        return false

    return true
}

IsCascadeWindow(hwnd)
{
    if !hwnd {
        return false
    }

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") {
        return false
    }

    if IsIgnoredByWindowCascade(hwnd) {
        return false
    }

    try {
        min_max := WinGetMinMax("ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        window_class := WinGetClass("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)

        WinGetPosPixels(
            &x,
            &y,
            &width,
            &height,
            "ahk_id " hwnd
        )
    }
    catch {
        return false
    }

    if min_max != 0 {
        return false
    }

    ; Require a normal captioned, resizable application window.
    if !(style & 0x00C00000) {
        return false
    }

    if !(style & 0x00040000) {
        return false
    }

    ; Ignore tool windows and windows that deliberately cannot activate.
    if ex_style & 0x00000080 {
        return false
    }

    if ex_style & 0x08000000 {
        return false
    }

    ; Standard Windows dialogs and Explorer file-operation prompts are
    ; transient UI, not standalone application windows.
    if window_class = "#32770"
        || window_class = "OperationStatusWindow"
        return false

    ; Owned top-level windows are normally dialogs or transient popups.
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") {
        return false
    }

    if width < 1 || height < 1 {
        return false
    }

    if IsWindowCloaked(hwnd) {
        return false
    }

    if IsShellSurfaceWindow(hwnd) {
        return false
    }

    ; Empty-title windows are commonly invisible framework/helper windows.
    if title = "" {
        return false
    }

    return true
}

IsDesktopSurfaceWindow(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    return window_class = "Progman" || window_class = "WorkerW"
}

IsTaskbarSurfaceWindow(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    return (
        window_class = "Shell_TrayWnd"
        || window_class = "Shell_SecondaryTrayWnd"
    )
}


IsShellSurfaceWindow(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    return (
        window_class = "Shell_TrayWnd"
        || window_class = "Shell_SecondaryTrayWnd"
        || window_class = "Progman"
        || window_class = "WorkerW"
        || window_class = "NotifyIconOverflowWindow"
        || window_class = "tooltips_class32"
    )
}

IsCascadeWindowTopmost(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return -1

    try return !!(WinGetExStyle("ahk_id " hwnd) & 0x8) ; WS_EX_TOPMOST
    catch
        return -1
}


IsWindowCloaked(hwnd)
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


; =============================================================================
; visible frame geometry
; =============================================================================

TryGetVisibleFrameRect(
    hwnd,
    &frame_x,
    &frame_y,
    &frame_width,
    &frame_height,
    &inset_left,
    &inset_top,
    &inset_right,
    &inset_bottom
)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    try {
        WinGetPosPixels(
            &raw_x,
            &raw_y,
            &raw_width,
            &raw_height,
            "ahk_id " hwnd
        )
    }
    catch {
        return false
    }

    if raw_width <= 0 || raw_height <= 0
        return false

    ; Fall back to the raw HWND rectangle when DWM frame information is not
    ; available. This keeps ordinary Win32 behavior as the safe default.
    frame_x := raw_x
    frame_y := raw_y
    frame_width := raw_width
    frame_height := raw_height

    inset_left := 0
    inset_top := 0
    inset_right := 0
    inset_bottom := 0

    frame_rect := Buffer(16, 0)

    dwm_result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 9, ; DWMWA_EXTENDED_FRAME_BOUNDS
        "ptr", frame_rect.Ptr,
        "uint", frame_rect.Size,
        "int"
    )

    if dwm_result != 0
        return true

    frame_left := NumGet(frame_rect, 0, "int")
    frame_top := NumGet(frame_rect, 4, "int")
    frame_right := NumGet(frame_rect, 8, "int")
    frame_bottom := NumGet(frame_rect, 12, "int")

    if frame_right <= frame_left || frame_bottom <= frame_top
        return true

    frame_x := frame_left
    frame_y := frame_top
    frame_width := frame_right - frame_left
    frame_height := frame_bottom - frame_top

    inset_left := frame_left - raw_x
    inset_top := frame_top - raw_y
    inset_right := (raw_x + raw_width) - frame_right
    inset_bottom := (raw_y + raw_height) - frame_bottom

    return true
}

GetRawRectForVisibleTarget(
    hwnd,
    visible_x,
    visible_y,
    visible_width,
    visible_height
)
{
    if !TryGetVisibleFrameRect(
        hwnd,
        &current_frame_x,
        &current_frame_y,
        &current_frame_width,
        &current_frame_height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return [
            visible_x,
            visible_y,
            visible_width,
            visible_height
        ]
    }

    raw_x := visible_x - inset_left
    raw_y := visible_y - inset_top

    raw_width := Max(
        1,
        visible_width + inset_left + inset_right
    )

    raw_height := Max(
        1,
        visible_height + inset_top + inset_bottom
    )

    return [
        raw_x,
        raw_y,
        raw_width,
        raw_height
    ]
}

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

TryGetWindowCenter(hwnd, &center_x, &center_y)
{
    if !TryGetVisibleFrameRect(
        hwnd,
        &x,
        &y,
        &width,
        &height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return false
    }

    center_x := x + width / 2
    center_y := y + height / 2

    return true
}


; =============================================================================
; monitor selection and lookup
; =============================================================================

GetCommandMonitor()
{
    active_hwnd := WinExist("A")

    if active_hwnd
        && !IsShellSurfaceWindow(active_hwnd)
    {
        monitor_index := GetMonitorForWindow(active_hwnd)

        if monitor_index
            return monitor_index
    }

    MouseGetPosPixels(&mouse_x, &mouse_y)
    return GetMonitorForPoint(mouse_x, mouse_y)
}

GetTargetMonitor(hwnd, source_hwnd, queued_monitor := 0, &reason := "")
{
    if queued_monitor {
        reason := "launch-pointer"
        return queued_monitor
    }
    MouseGetPosPixels(&x, &y)
    monitor := GetMonitorForPoint(x, y)
    if monitor {
        reason := "live-pointer"
        return monitor
    }
    if source_hwnd && source_hwnd != hwnd && WinExist("ahk_id " source_hwnd) {
        monitor := GetCascadeSourceMonitor(source_hwnd)
        if monitor {
            reason := "source-fallback"
            return monitor
        }
    }
    reason := "primary-monitor"
    return MonitorGetPrimary()
}

GetCascadeSourceMonitor(hwnd)
{
    ; Windows uses the largest intersection and the restored rectangle for a
    ; minimized source. A window center can lie in a gap between displays.
    monitor_handle := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    info := Buffer(104, 0) ; MONITORINFOEXW
    NumPut("uint", info.Size, info)
    if monitor_handle && DllCall("GetMonitorInfoW", "ptr", monitor_handle, "ptr", info, "int") {
        monitor := FindCascadeMonitorDevice(StrGet(info.Ptr + 40, 32, "UTF-16"))
        if monitor
            return monitor
    }
    return GetMonitorForWindow(hwnd)
}

TakeCascadeTaskbarMonitor(hwnd, context)
{
    global cascade_launch_hint, new_window_focus_timeout_ms
    if !IsObject(context) || !IsObject(context.hint)
        return 0
    hint := context.hint
    if hint != cascade_launch_hint
        || ((A_TickCount - hint.tick) & 0xFFFFFFFF) > new_window_focus_timeout_ms
        || hint.HasOwnProp("placement_hwnd") || hint.HasOwnProp("reshow_hwnd")
        || hint.HasOwnProp("placement_cancelled")
        return 0
    monitor := FindCascadeMonitorDevice(hint.monitor_device)
    if !monitor
        return 0
    ; A taskbar click is more specific than the app that happened to retain
    ; foreground. Bind it once so it cannot redirect subsequent new windows.
    hint.placement_hwnd := hwnd
    StopCascadeLaunchObserver(hint)
    return monitor
}

ResolveCascadePlacementMonitor(request, fallback_monitor)
{
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
        WinGetPosPixels(
            &x,
            &y,
            &width,
            &height,
            "ahk_id " hwnd
        )
    }
    catch {
        return 0
    }

    if width <= 0 || height <= 0
        return 0

    return GetMonitorForPoint(
        x + Floor(width / 2),
        y + Floor(height / 2)
    )
}

GetMonitorForPoint(x, y)
{
    monitor_count := MonitorGetCount()

    Loop monitor_count {
        MonitorGetPixels(
            A_Index,
            &left,
            &top,
            &right,
            &bottom
        )

        if x >= left && x < right && y >= top && y < bottom
            return A_Index
    }

    return 0
}
