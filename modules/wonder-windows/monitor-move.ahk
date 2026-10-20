; Cycle the active window across connected displays without adopting manual
; windows into Cascade Kingdom. Managed windows use destination smart placement.

WW_NextMonitorIndex(source, count)
{
    return count < 2 || source < 1 || source > count ? 0 : Mod(source, count) + 1
}

WW_RelocateWindowRectangle(rect, source, target)
{
    width := Min(rect[3], target[3] - target[1])
    height := Min(rect[4], target[4] - target[2])
    x := Max(target[1], Min(target[1] + rect[1] - source[1], target[3] - width))
    y := Max(target[2], Min(target[2] + rect[2] - source[2], target[4] - height))
    return [x, y, width, height]
}

WW_CycleWindowMonitor()
{
    Critical "On"
    hwnd := WinExist("A")
    if !WW_IsWindowToggleCandidate(hwnd)
        return

    try {
        source := GetCascadeSourceMonitor(hwnd)
        target := WW_NextMonitorIndex(source, MonitorGetCount())
        if !target || !WW_SetNativeFullscreen(hwnd, false)
            return

        ; A live Cascade-managed window must join the destination cascade,
        ; not become a permanent manually positioned Wonder Windows window.
        if IsCascadeEnabled() && GetManagedCascadeMonitor(hwnd) && CascadeDisplayAllowed(target) {
            RemoveWindowFromMinimizeState(hwnd)
            if PlaceCascadeWindowOnMonitor(hwnd, target) {
                WW_ForgetLastMinimizedWindow()
                QueueFocusCornerUpdate()
            }
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
        WW_ForgetSwapZone(hwnd)
        WW_ForgetLastMinimizedWindow()
        if maximized
            WinMaximize(hwnd)
    }
    catch Error as err
        WW_DebugError("Move window to next monitor", err)
}
