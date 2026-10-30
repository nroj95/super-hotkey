; Wonder Windows stretching to neighbors and the layout state it shares.

; =============================================================================
; stretching to neighbors
; =============================================================================

; Win + Shift + Enter walks a window through three steps: across to the nearest
; windows on its left and right, then also up and down into the free space
; between its neighbors, then back to its original size. Other windows on the
; same display are the neighbors; without one, the work area's edge stops it.
WW_CycleNeighborStretch()
{
    Critical "On"
    global WW_stretched_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        if !WW_SetNativeFullscreen(hwnd, false)
            return
        WW_RememberNormalWindowPlacement(hwnd)
        if WinGetMinMax(hwnd) != 0
            WinRestore(hwnd)

        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        original := current
        step := "across"
        ; Continue only while the window is still where the last step left it.
        if WW_stretched_windows.Has(hwnd) {
            saved := WW_stretched_windows[hwnd]
            if WW_IsPlacementStateCurrent(hwnd, saved, monitor, work)
                && WW_RectanglesMatch(saved["applied"], current, 3) {
                original := saved["original"]
                step := saved["step"] = "across" ? "fill" : "back"
            }
            WW_stretched_windows.Delete(hwnd)
        }

        if step = "back" {
            WW_MoveWindowToVisibleRectangle(hwnd, original)
            return
        }
        target := WW_NeighborStretchRectangle(original, WW_GetStretchObstacles(hwnd, monitor), work, step)
        if !WW_MoveWindowToVisibleRectangle(hwnd, target)
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_stretched_windows[hwnd] := Map("pid", WinGetPID(hwnd), "monitor", monitor,
            "work_area", work, "original", original, "step", step,
            "applied", WW_GetWindowLayoutRectangle(hwnd))
    }
    catch Error as failure
        WW_DebugError("Stretch to neighbors", failure)
}

WW_ForgetStretch(hwnd)
{
    global WW_stretched_windows
    try WW_stretched_windows.Delete(hwnd)
}

; Visible rectangles of the other switchable windows on the same display.
WW_GetStretchObstacles(active_hwnd, monitor_handle)
{
    obstacles := []
    for hwnd in WinGetList() {
        if hwnd = active_hwnd || !IsSwitchableWindow(hwnd)
            continue
        if WindowMonitor(hwnd) != monitor_handle
            continue
        try obstacles.Push(WW_GetWindowLayoutRectangle(hwnd))
    }
    return obstacles
}

; =============================================================================
; placement state and geometry matching
; =============================================================================

WW_GetPlacementTarget(&fresh_entry)
{
    fresh_entry := false
    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return 0

    try {
        if !IsSwitchableWindow(hwnd)
            return 0
        if WW_IsNativeFullscreen(hwnd) || WinGetMinMax(hwnd) != 0
            fresh_entry := true
        WW_PruneLayoutStates()
        WW_PrepareWindowForPlacement(hwnd)
        return hwnd
    }
    catch Error as err {
        WW_DebugError("Prepare layout target", err)
        return 0
    }
}

WW_GetLayoutWorkArea(hwnd) => MonitorRects(WindowMonitor(hwnd)).work

WW_GetWindowLayoutRectangle(hwnd)
{
    if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
        WinGetPos(&x, &y, &width, &height, hwnd)
    return [x, y, width, height]
}

WW_FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
{
    global WW_layout_cycle_windows
    current_rect := WW_GetWindowLayoutRectangle(hwnd)

    if WW_layout_cycle_windows.Has(hwnd) {
        saved := WW_layout_cycle_windows[hwnd]
        if saved["pid"] = WinGetPID(hwnd)
            && WW_RectanglesMatch(saved["work_area"], work_area, 0)
            && WW_RectanglesMatch(saved["actual_rect"], current_rect)
        {
            ; Switching arrows starts that side at 25%; it no longer walks the
            ; opposite side's cycle backwards. Other shortcut families also start
            ; their own sequence, even when a rectangle happens to be shared.
            return saved["family"] = family ? saved["index"] : 0
        }
        WW_layout_cycle_windows.Delete(hwnd)
    }

    for index, layout in layouts {
        if WW_RectanglesMatch(current_rect, layout)
            return index
    }
    return 0
}

WW_ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
{
    global WW_layout_cycle_windows
    target := layouts[target_index]
    ; An app whose minimum size exceeds the tile would grow past the tile's
    ; outer edges. Place it once at that size, growing toward the middle.
    minimum := WW_GetMinimumVisibleSize(hwnd)
    if minimum[1] > target[3] || minimum[2] > target[4] {
        fitted := WW_FitAcceptedRectangle(target, [0, 0, Max(target[3], minimum[1]),
            Max(target[4], minimum[2])], work_area)
        if IsObject(fitted)
            target := fitted
    }
    if !WW_MoveWindowToVisibleRectangle(hwnd, target)
        return false

    ; Some apps enforce their size only after moving. Slide those back too.
    actual := WW_GetWindowLayoutRectangle(hwnd)
    fitted := WW_FitAcceptedRectangle(target, actual, work_area)
    if IsObject(fitted) && !WW_RectanglesMatch(actual, fitted, 2)
        WW_MoveWindowToVisibleRectangle(hwnd, fitted)

    ; Store the actual result: an app may enforce a minimum size larger than a
    ; quarter-screen tile. That must not strand the cycle on its first step.
    WW_layout_cycle_windows[hwnd] := Map("pid", WinGetPID(hwnd), "family", family,
        "work_area", work_area, "index", target_index,
        "actual_rect", WW_GetWindowLayoutRectangle(hwnd))
    return true
}

WW_ForgetWindowLayoutCycle(hwnd)
{
    global WW_layout_cycle_windows
    try WW_layout_cycle_windows.Delete(hwnd)
}

WW_PruneLayoutStates()
{
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_stretched_windows
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_stretched_windows] {
        stale_hwnds := []
        for hwnd, entry in states {
            stale := !DllCall("IsWindow", "ptr", hwnd, "int")
            if !stale {
                try stale := WinGetPID(hwnd) != entry["pid"]
                catch {
                    stale := true
                }
            }
            if stale
                stale_hwnds.Push(hwnd)
        }
        for hwnd in stale_hwnds
            states.Delete(hwnd)
    }
}

WW_PrepareWindowForPlacement(hwnd)
{
    ; A failed F11 exit must never leave a fullscreen interface tiled.
    if !WW_SetNativeFullscreen(hwnd, false)
        throw Error("Could not exit native fullscreen before placement.")
    SuiteWindowOwnership.Claim(hwnd)
    WW_RememberNormalWindowPlacement(hwnd)
    WW_ForgetStretch(hwnd)
    if WinGetMinMax(hwnd) != 0
        WinRestore(hwnd)
}

; Saved per-window state applies only on the same process, display and work area.
WW_IsPlacementStateCurrent(hwnd, saved, monitor_handle := 0, work_area := 0)
{
    if !WW_WindowStateMatchesProcess(hwnd, saved)
        return false
    try {
        if !monitor_handle
            monitor_handle := WindowMonitor(hwnd)
        if !work_area
            work_area := WW_GetLayoutWorkArea(hwnd)
        return saved["monitor"] = monitor_handle
            && WW_RectanglesMatch(saved["work_area"], work_area, 0)
    }
    catch {
        return false
    }
}
