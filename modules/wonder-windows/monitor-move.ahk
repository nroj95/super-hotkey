; Move the active window to the display on its left or right without adopting
; manual windows into Cascade Kingdom. Managed windows use destination smart placement.

; The display to the right of source, or to the left when backwards, wrapping
; at the ends; 0 with one display. lefts[i] is display i's left edge, so the
; order follows the physical layout rather than Windows' display numbers.
WW_NextSpatialMonitor(source, lefts, backwards := false)
{
    order := []
    for index, left in lefts {
        position := order.Length + 1
        while position > 1 && left < lefts[order[position - 1]]
            position -= 1
        order.InsertAt(position, index)
    }
    current := WW_FindWindowIndex(order, source)
    if order.Length < 2 || !current
        return 0
    return order[WW_GetNextCycleIndex(current, order.Length, backwards)]
}

WW_RelocateWindowRectangle(rect, source, target)
{
    width := Min(rect[3], target[3] - target[1])
    height := Min(rect[4], target[4] - target[2])
    x := Max(target[1], Min(target[1] + rect[1] - source[1], target[3] - width))
    y := Max(target[2], Min(target[2] + rect[2] - source[2], target[4] - height))
    return [x, y, width, height]
}

WW_MoveWindowToAdjacentMonitor(direction)
{
    Critical "On"
    hwnd := WinExist("A")
    if !IsSwitchableWindow(hwnd)
        return

    try {
        source := WindowMonitorIndex(hwnd)
        lefts := []
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &left)
            lefts.Push(left)
        }
        target := WW_NextSpatialMonitor(source, lefts, direction = "left")
        if !target || !WW_SetNativeFullscreen(hwnd, false)
            return

        ; A live Cascade-managed window must join the destination cascade,
        ; not become a permanent manually positioned Wonder Windows window.
        if SuiteManagedWindows.CanMoveToMonitor(hwnd, target) {
            if SuiteManagedWindows.MoveToMonitor(hwnd, target)
                WW_ForgetLastMinimizedWindow()
            return
        }

        MonitorGetWorkArea(source, &sourceLeft, &sourceTop, &sourceRight, &sourceBottom)
        MonitorGetWorkArea(target, &targetLeft, &targetTop, &targetRight, &targetBottom)
        sourceWork := [sourceLeft, sourceTop, sourceRight, sourceBottom]
        targetWork := [targetLeft, targetTop, targetRight, targetBottom]

        maximized := WinGetMinMax(hwnd) = 1
        if maximized
            WinRestore(hwnd)
        original := WW_GetWindowLayoutRectangle(hwnd)
        translated := WW_RelocateWindowRectangle(original, sourceWork, targetWork)
        if !WW_MoveWindowToVisibleRectangle(hwnd, translated) {
            if maximized
                WinMaximize(hwnd)
            return
        }
        WW_ForgetHorizontalStretch(hwnd)
        WW_ForgetVerticalStretch(hwnd)
        WW_ForgetFullStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_ForgetLogicalZone(hwnd)
        WW_ForgetLastMinimizedWindow()
        if maximized
            WinMaximize(hwnd)
    }
    catch Error as err
        WW_DebugError("Move window to adjacent monitor", err)
}
