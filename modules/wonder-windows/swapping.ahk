; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; clockwise / counter-clockwise window swapping
; =============================================================================

WW_SwapWindow(direction := "clockwise")
{
    Critical "On"
    if direction != "clockwise" && direction != "counter-clockwise"
        return
    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        WW_PrepareWindowForPlacement(hwnd)

        monitor_handle := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        WW_GetWindowMonitorWorkArea(
            hwnd,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        monitor_center_x :=
            work_left + (work_right - work_left) / 2

        monitor_center_y :=
            work_top + (work_bottom - work_top) / 2

        windows := WW_GetClockwiseWindowOrder(
            monitor_handle,
            monitor_center_x,
            monitor_center_y
        )

        if windows.Length < 2
            return

        active_index := 0

        for index, item in windows {
            if item["hwnd"] = hwnd {
                active_index := index
                break
            }
        }

        if !active_index
            return

        next_index := WW_GetNextCycleIndex(
            active_index, windows.Length, direction = "counter-clockwise"
        )

        target_hwnd := windows[next_index]["hwnd"]

        WW_RememberNormalWindowPlacement(target_hwnd)
        if !WW_SwapWindowRectangles(hwnd, target_hwnd)
            return
        WW_ForgetHorizontalStretch(target_hwnd)
        WW_ForgetVerticalStretch(target_hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_ForgetWindowLayoutCycle(target_hwnd)

        WinActivate(window)
    }
}

WW_GetClockwiseWindowOrder(
    monitor_handle,
    monitor_center_x,
    monitor_center_y
)
{
    items := []

    for hwnd in WinGetList() {
        if !WW_IsWindowSwapCandidate(hwnd, monitor_handle)
            continue

        try {
            WinGetPos(
                &x,
                &y,
                &width,
                &height,
                "ahk_id " hwnd
            )
        }
        catch {
            continue
        }

        center_x := x + width / 2
        center_y := y + height / 2

        angle := WW_GetClockwiseAngleFromTop(
            center_x - monitor_center_x,
            center_y - monitor_center_y
        )

        item := Map(
            "hwnd", hwnd,
            "angle", angle
        )

        insert_index := items.Length + 1

        Loop items.Length {
            if angle < items[A_Index]["angle"]
                || (angle = items[A_Index]["angle"] && hwnd < items[A_Index]["hwnd"])
            {
                insert_index := A_Index
                break
            }
        }

        items.InsertAt(insert_index, item)
    }

    return items
}

WW_GetClockwiseAngleFromTop(delta_x, delta_y)
{
    static two_pi := 6.283185307179586

    ; atan2(dx, -dy) makes 0 point upward and increases clockwise.
    angle := DllCall(
        "msvcrt\atan2",
        "double", delta_x,
        "double", -delta_y,
        "cdecl double"
    )

    if angle < 0
        angle += two_pi

    return angle
}

WW_IsWindowSwapCandidate(hwnd, monitor_handle)
{
    global WW_borderless_windows

    if !hwnd || SuiteWindowOwnership.IsSuiteSurface(hwnd)
        return false

    if WW_borderless_windows.Has(hwnd)
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
        if WinGetMinMax("ahk_id " hwnd) != 0
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

    if !(style & 0x00C00000) ; normal caption
        return false

    if !(style & 0x00040000) ; resizable
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if WW_IsWinKeyOverhaulShellClass(class_name)
        return false

    if WW_IsWinKeyOverhaulCloaked(hwnd)
        return false

    candidate_monitor := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2,
        "ptr"
    )

    return candidate_monitor = monitor_handle
}

WW_SwapWindowRectangles(first_hwnd, second_hwnd)
{
    WinGetPos(&first_x, &first_y, &first_width, &first_height, first_hwnd)
    WinGetPos(&second_x, &second_y, &second_width, &second_height, second_hwnd)
    first_visible := WW_GetWindowLayoutRectangle(first_hwnd)
    second_visible := WW_GetWindowLayoutRectangle(second_hwnd)

    try {
        ; Swap visible frames, not mismatched invisible resize-border widths.
        if !WW_MoveWindowToVisibleRectangle(first_hwnd, second_visible)
            || !WW_WindowMatchesVisibleRectangle(first_hwnd, second_visible)
        {
            throw Error("The first window did not accept the swap rectangle.")
        }
        if !WW_MoveWindowToVisibleRectangle(second_hwnd, first_visible)
            || !WW_WindowMatchesVisibleRectangle(second_hwnd, first_visible)
            || !WW_WindowMatchesVisibleRectangle(first_hwnd, second_visible)
        {
            throw Error("The second window did not accept the swap rectangle.")
        }
        return true
    }
    catch Error as err {
        ; WinMove can return normally after an app clamps its size. Roll both
        ; windows back on a mismatch, not only when the second move throws.
        try WinMove(first_x, first_y, first_width, first_height, first_hwnd)
        try WinMove(second_x, second_y, second_width, second_height, second_hwnd)
        WW_DebugError("Swap window rectangles", err)
        return false
    }
}
