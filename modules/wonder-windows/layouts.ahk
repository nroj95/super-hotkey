; Wonder Windows full height, Win + Alt + Enter, and the layout state it
; shares with zones, maximize and moving a window onto its neighbor: where a
; window was before Wonder Windows placed it.

; =============================================================================
; full height
; =============================================================================

; Win + Alt + Enter stretches the active window to the work area's full
; height, keeping its width and left edge. The same key again takes it back
; while the window is still where the toggle left it; from the window's
; original shape that ends as Win + Down does, handing a lent cascade window
; back. A maximized or fullscreen window stays as it is, with a notice. Any
; other placement forgets the way back.
WW_ToggleFullHeight(*)
{
    Critical "On"
    global WW_full_height_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        ; A maximized or fullscreen window is already as tall as it gets: the
        ; key only says so.
        if WinGetMinMax(hwnd) = 1 || WW_IsNativeFullscreen(hwnd) {
            SuiteNotice.Show("status", WW_IsNativeFullscreen(hwnd) ? "Already fullscreen" : "Already maximized", 1400)
            return
        }
        saved := WW_full_height_windows.Get(hwnd, 0)
        fresh := !WW_IsPlacedWindow(hwnd)
        WW_PrepareWindowForPlacement(hwnd)
        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        if IsObject(saved) && WW_IsPlacementStateCurrent(hwnd, saved, monitor, work)
            && WW_RectanglesMatch(saved["applied"], current, 3) {
            if saved["fresh"] {
                WW_RestoreWindowTarget()
                return
            }
            before := saved["before"]
            WW_MoveWindowToVisibleRectangle(hwnd, [current[1], before[2], current[3], before[4]])
            return
        }
        if !WW_MoveWindowToVisibleRectangle(hwnd, [current[1], work[2], current[3], work[4] - work[2]])
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_full_height_windows[hwnd] := Map("pid", WinGetPID(hwnd), "monitor", monitor, "work_area", work,
            "before", current, "fresh", fresh, "applied", WW_GetWindowLayoutRectangle(hwnd))
    }
    catch Error as failure
        WW_DebugError("Full height toggle", failure)
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
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_full_height_windows
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_full_height_windows] {
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
    WW_ForgetFullHeight(hwnd)
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

; True when Wonder Windows has placed the window: full height from anywhere
; else ends back at the window's original shape.
WW_IsPlacedWindow(hwnd)
{
    global WW_normal_window_placements
    return WW_normal_window_placements.Has(hwnd)
}

WW_ForgetFullHeight(hwnd)
{
    global WW_full_height_windows
    try WW_full_height_windows.Delete(hwnd)
}
