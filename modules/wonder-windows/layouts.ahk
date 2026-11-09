; Wonder Windows full height and width, Win + Shift + Up and Down, and the
; layout state they share with zones and maximize.

; =============================================================================
; full height and full width
; =============================================================================

; Win + Shift + Up stretches the active window to the work area's full height,
; keeping its width and left edge, and Win + Shift + Down to its full width,
; keeping its height and top. The same key again takes back that direction
; only, while the window is still where the toggle left it, so height and
; width combine and undo in any order. Undoing the last one from the window's
; original shape ends as Win + Down does, handing a lent cascade window back.
; A maximized or fullscreen window stays as it is, with a notice.
WW_ToggleFullSpan(axis)
{
    Critical "On"
    global WW_full_span_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        ; A maximized or fullscreen window is already as tall and wide as it
        ; gets: the key only says so.
        if WinGetMinMax(hwnd) = 1 || WW_IsNativeFullscreen(hwnd) {
            SuiteNotice.Show("status", WW_IsNativeFullscreen(hwnd) ? "Already fullscreen" : "Already maximized", 1400)
            return
        }
        fresh := WW_IsFreshPlacement(hwnd)
        WW_PrepareWindowForPlacement(hwnd, false)
        pid := WinGetPID(hwnd)
        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        spans := WW_full_span_windows.Get(hwnd, 0)
        if !IsObject(spans) || spans["pid"] != pid
            spans := WW_full_span_windows[hwnd] := Map("pid", pid)
        height := axis = "height"
        if spans.Has(axis) {
            saved := spans.Delete(axis)
            if WW_IsPlacementStateCurrent(hwnd, saved, monitor, work)
                && WW_RectanglesMatch(saved["applied"], current, 3) {
                other := height ? "width" : "height"
                if saved["fresh"] && !spans.Has(other) {
                    WW_full_span_windows.Delete(hwnd)
                    WW_RestoreWindowTarget()
                    return
                }
                before := saved["before"]
                WW_MoveWindowToVisibleRectangle(hwnd, height
                    ? [current[1], before[2], current[3], before[4]]
                    : [before[1], current[2], before[3], current[4]])
                if spans.Has(other)
                    spans[other]["applied"] := WW_GetWindowLayoutRectangle(hwnd)
                return
            }
        }
        target := height
            ? [current[1], work[2], current[3], work[4] - work[2]]
            : [work[1], current[2], work[3] - work[1], current[4]]
        if !WW_MoveWindowToVisibleRectangle(hwnd, target)
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        applied := WW_GetWindowLayoutRectangle(hwnd)
        spans[axis] := Map("pid", pid, "monitor", monitor, "work_area", work, "before", current,
            "fresh", fresh || spans.Has(height ? "width" : "height") && spans[height ? "width" : "height"]["fresh"],
            "applied", applied)
        for other in ["height", "width"]
            if other != axis && spans.Has(other)
                spans[other]["applied"] := applied
    }
    catch Error as failure
        WW_DebugError("Full " axis " toggle", failure)
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
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_full_span_windows
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_full_span_windows] {
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

; True when Wonder Windows has not placed the window yet: a full height or
; width from here ends back at its original shape.
WW_IsFreshPlacement(hwnd)
{
    global WW_normal_window_placements
    return !WW_normal_window_placements.Has(hwnd)
}

WW_ForgetStretches(hwnd)
{
    global WW_full_span_windows
    try WW_full_span_windows.Delete(hwnd)
}
