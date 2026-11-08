; Wonder Windows stretching, Win + Shift + Up and Down, and the layout state
; it shares with zones and maximize.

; =============================================================================
; full height and full width
; =============================================================================

; Win + Shift + Up stretches the active window to the work area's full height,
; keeping its width and left edge; again to the full width instead, keeping its
; height and top; again back to how it was. A window moved in between starts
; over. Win + Down takes it back to normal size at once.
WW_CycleFullSpan()
{
    Critical "On"
    global WW_full_span_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        WW_PrepareWindowForPlacement(hwnd, false)
        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        step := "height", before := current
        if WW_full_span_windows.Has(hwnd) {
            saved := WW_full_span_windows.Delete(hwnd)
            if WW_IsPlacementStateCurrent(hwnd, saved, monitor, work)
                && WW_RectanglesMatch(saved["applied"], current, 3) {
                before := saved["before"]
                if saved["step"] = "width" {
                    WW_MoveWindowToVisibleRectangle(hwnd, before)
                    return
                }
                step := "width"
            }
        }
        target := step = "height"
            ? [before[1], work[2], before[3], work[4] - work[2]]
            : [work[1], before[2], work[3] - work[1], before[4]]
        if !WW_MoveWindowToVisibleRectangle(hwnd, target)
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_full_span_windows[hwnd] := Map("pid", WinGetPID(hwnd), "monitor", monitor, "work_area", work,
            "before", before, "step", step, "applied", WW_GetWindowLayoutRectangle(hwnd))
    }
    catch Error as failure
        WW_DebugError("Full height and width", failure)
}

; =============================================================================
; stretch to neighbors
; =============================================================================

; Win + Shift + Down grows the active window into the largest empty rectangle
; around it, and again puts it back, while it is still where the stretch left
; it. Only what is visible stops it: the display's edges and the front window
; of each other stack. Windows it already overlaps never shrink it. When the
; whole work area is free, it maximizes instead, so the window is what it
; looks like: maximize keeps a cascade window in its cascade, and the
; big-window cycle knows it.
WW_ToggleNeighborStretch()
{
    Critical "On"
    global WW_neighbor_stretch_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        if WW_neighbor_stretch_windows.Has(hwnd) {
            saved := WW_neighbor_stretch_windows.Delete(hwnd)
            if WW_IsPlacementStateCurrent(hwnd, saved, monitor, work) {
                if saved["maximized"] && WinGetMinMax(hwnd) = 1 {
                    WinRestore(hwnd)
                    return
                }
                if !saved["maximized"] && WinGetMinMax(hwnd) = 0
                    && WW_RectanglesMatch(saved["applied"], WW_GetWindowLayoutRectangle(hwnd), 3) {
                    WW_MoveWindowToVisibleRectangle(hwnd, saved["before"])
                    return
                }
            }
        }
        ; Measure the window at its normal size, before anything claims it.
        if !WW_SetNativeFullscreen(hwnd, false)
            return
        if WinGetMinMax(hwnd) != 0
            WinRestore(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        target := WW_LargestFreeRectangle(current, WW_GetVisibleNeighbors(hwnd, monitor), work)
        if WW_RectanglesMatch(target, [work[1], work[2], work[3] - work[1], work[4] - work[2]], 3) {
            WW_ForgetWindowLayoutCycle(hwnd)
            WinMaximize(hwnd)
            WW_neighbor_stretch_windows[hwnd] := Map("pid", WinGetPID(hwnd), "monitor", monitor,
                "work_area", work, "maximized", true)
            return
        }
        if WW_RectanglesMatch(target, current, 3) {
            SuiteNotice.Show("status", "No free space around this window", 1400)
            return
        }
        WW_PrepareWindowForPlacement(hwnd, false)
        if !WW_MoveWindowToVisibleRectangle(hwnd, target)
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_neighbor_stretch_windows[hwnd] := Map("pid", WinGetPID(hwnd), "monitor", monitor,
            "work_area", work, "maximized", false, "before", current,
            "applied", WW_GetWindowLayoutRectangle(hwnd))
    }
    catch Error as failure
        WW_DebugError("Stretch to neighbors", failure)
}

; The front window of each other stack on the display, as [x, y, width,
; height]: a stack counts once, as what you see of it. Cascade windows count.
WW_GetVisibleNeighbors(active_hwnd, monitor_handle)
{
    entries := []
    for hwnd in WinGetList() {
        if hwnd = active_hwnd || !IsSwitchableWindow(hwnd) || WindowMonitor(hwnd) != monitor_handle
            continue
        try entries.Push({hwnd: hwnd, rect: WW_GetWindowLayoutRectangle(hwnd)})
    }
    rects := Map()
    for entry in entries
        rects[entry.hwnd] := entry.rect
    neighbors := []
    for stack in WW_GroupWindowStacks(entries)
        neighbors.Push(rects[stack[1]])
    return neighbors
}

; The largest rectangle inside work_area ([left, top, right, bottom]) that
; contains rect and overlaps no obstacle; obstacles rect already overlaps are
; ignored. Every [x, y, width, height]. Each left and right edge a neighbor
; offers is tried, and for each span the top and bottom grow until a
; neighbor stops them.
WW_LargestFreeRectangle(rect, obstacles, work_area)
{
    left := rect[1], top := rect[2], right := rect[1] + rect[3], bottom := rect[2] + rect[4]
    walls := []
    for obstacle in obstacles
        if WW_IntersectionArea(rect, obstacle) <= 0
            walls.Push([obstacle[1], obstacle[2], obstacle[1] + obstacle[3], obstacle[2] + obstacle[4]])
    lefts := [Min(work_area[1], left)], rights := [Max(work_area[3], right)]
    for wall in walls {
        if wall[3] <= left && wall[3] > lefts[1]
            lefts.Push(wall[3])
        if wall[1] >= right && wall[1] < rights[1]
            rights.Push(wall[1])
    }
    best := rect, best_area := rect[3] * rect[4]
    for span_left in lefts {
        for span_right in rights {
            span_top := Min(work_area[2], top), span_bottom := Max(work_area[4], bottom)
            blocked := false
            for wall in walls {
                if wall[3] <= span_left || wall[1] >= span_right
                    continue
                if wall[4] <= top
                    span_top := Max(span_top, wall[4])
                else if wall[2] >= bottom
                    span_bottom := Min(span_bottom, wall[2])
                else {
                    blocked := true
                    break
                }
            }
            area := (span_right - span_left) * (span_bottom - span_top)
            if !blocked && area > best_area
                best := [span_left, span_top, span_right - span_left, span_bottom - span_top], best_area := area
        }
    }
    return best
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
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_full_span_windows,
        WW_neighbor_stretch_windows
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_full_span_windows,
        WW_neighbor_stretch_windows] {
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

; forgetSpans: a zone or half replaces any stretch; the stretches keep each
; other's way back.
WW_PrepareWindowForPlacement(hwnd, forgetSpans := true)
{
    ; A failed F11 exit must never leave a fullscreen interface tiled.
    if !WW_SetNativeFullscreen(hwnd, false)
        throw Error("Could not exit native fullscreen before placement.")
    SuiteWindowOwnership.Claim(hwnd)
    WW_RememberNormalWindowPlacement(hwnd)
    if forgetSpans
        WW_ForgetStretches(hwnd)
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

WW_ForgetStretches(hwnd)
{
    global WW_full_span_windows, WW_neighbor_stretch_windows
    for states in [WW_full_span_windows, WW_neighbor_stretch_windows]
        try states.Delete(hwnd)
}
