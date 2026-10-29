; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; window stretch
; =============================================================================

WW_StretchWindowVertically()
{
    Critical "On"

    global WW_vertical_stretch_windows

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if !WW_SetNativeFullscreen(hwnd, false)
            return
        WW_RememberNormalWindowPlacement(hwnd)
        WW_PruneVerticalStretchWindows()

        if WinGetMinMax(window) != 0 {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !WW_GetVerticalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
            &visible_top, &visible_bottom, &inset_top, &inset_bottom) {
            return
        }

        monitor_handle := WindowMonitor(hwnd)

        WW_GetWindowMonitorWorkArea(hwnd, &work_left, &work_top, &work_right, &work_bottom)

        if !WW_vertical_stretch_windows.Has(hwnd)
            || !WW_IsStretchStateCurrent(hwnd, WW_vertical_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            WW_vertical_stretch_windows[hwnd] := Map("pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_top", visible_top, "original_bottom", visible_bottom)
        }

        bounds := WW_GetCollisionLimitedVerticalBounds(WW_GetWindowLayoutRectangle(hwnd),
            WW_GetHorizontalStretchObstacles(hwnd, monitor_handle), work_top, work_bottom)
        if !WW_MoveWindowToVisibleVerticalBounds(hwnd, bounds[1], bounds[2]) {
            WW_DebugLog(
                "Vertical stretch move failed; preserving restore state. hwnd="
                . hwnd
            )
        } else
            WW_ForgetFullStretch(hwnd)
    }
}

WW_CycleFullStretch()
{
    Critical "On"
    global WW_full_stretch_windows

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        if !WW_SetNativeFullscreen(hwnd, false)
            return
        WW_RememberNormalWindowPlacement(hwnd)
        if WinGetMinMax(hwnd) != 0
            WinRestore(hwnd)

        WW_PruneFullStretchWindows()
        monitor := WindowMonitor(hwnd)
        work := WW_GetLayoutWorkArea(hwnd)
        current := WW_GetWindowLayoutRectangle(hwnd)
        original := current
        mode := "height"

        if WW_full_stretch_windows.Has(hwnd) {
            saved := WW_full_stretch_windows[hwnd]
            if WW_IsStretchStateCurrent(hwnd, saved, monitor, work)
                && WW_RectanglesMatch(saved["applied"], current, 3) {
                original := saved["original"]
                mode := saved["mode"] = "height" ? "width" : "height"
            } else
                WW_full_stretch_windows.Delete(hwnd)
        }

        target := WW_FullStretchRectangle(original, work, mode)
        if !WW_MoveWindowToVisibleRectangle(hwnd, target)
            return

        WW_ForgetHorizontalStretch(hwnd)
        WW_ForgetVerticalStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_full_stretch_windows[hwnd] := Map(
            "pid", WinGetPID(hwnd), "monitor", monitor, "work_area", work,
            "original", original, "mode", mode,
            "applied", WW_GetWindowLayoutRectangle(hwnd)
        )
    }
    catch Error as failure
        WW_DebugError("Cycle full stretch", failure)
}

WW_ForgetFullStretch(hwnd)
{
    global WW_full_stretch_windows
    if WW_full_stretch_windows.Has(hwnd)
        WW_full_stretch_windows.Delete(hwnd)
}

WW_PruneFullStretchWindows()
{
    global WW_full_stretch_windows
    for hwnd, saved in WW_full_stretch_windows.Clone()
        if !WW_WindowStateMatchesProcess(hwnd, saved)
            WW_full_stretch_windows.Delete(hwnd)
}

WW_ResetWindowStretch()
{
    Critical "On"

    global WW_horizontal_stretch_windows
    global WW_vertical_stretch_windows

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    global WW_full_stretch_windows
    if WW_full_stretch_windows.Has(hwnd) {
        saved := WW_full_stretch_windows[hwnd]
        if WW_IsStretchStateCurrent(hwnd, saved)
            && WW_MoveWindowToVisibleRectangle(hwnd, saved["original"])
            WW_ForgetFullStretch(hwnd)
        else if !WW_IsStretchStateCurrent(hwnd, saved)
            WW_ForgetFullStretch(hwnd)
        return
    }

    current_monitor := WindowMonitor(hwnd)

    ; Restore vertical stretch first. Horizontal restore preserves the resulting
    ; Y/height, so both axes can be reset independently in one command.
    if WW_vertical_stretch_windows.Has(hwnd) {
        vertical_state := WW_vertical_stretch_windows[hwnd]

        if !WW_IsStretchStateCurrent(hwnd, vertical_state, current_monitor) {
            WW_ForgetVerticalStretch(hwnd)
            WW_DebugLog("Discarded stale vertical stretch state. hwnd=" hwnd)
        } else if WW_MoveWindowToVisibleVerticalBounds(hwnd, vertical_state["original_top"],
            vertical_state["original_bottom"]) {
            WW_ForgetVerticalStretch(hwnd)
        } else {
            WW_DebugLog(
                "Vertical stretch reset failed; preserving state. hwnd="
                . hwnd
            )
        }
    }

    if !WW_horizontal_stretch_windows.Has(hwnd)
        return

    horizontal_state := WW_horizontal_stretch_windows[hwnd]

    if !WW_IsStretchStateCurrent(hwnd, horizontal_state, current_monitor) {
        WW_ForgetHorizontalStretch(hwnd)
        WW_DebugLog("Discarded stale horizontal stretch state. hwnd=" hwnd)
        return
    }

    if !WW_GetHorizontalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
        &visible_left, &visible_right, &inset_left, &inset_right) {
        WW_DebugLog(
            "Horizontal stretch reset could not read geometry; "
            . "preserving state. hwnd=" . hwnd
        )
        return
    }

    ; Only restore edges that are actually stretched. The opposite live edge is
    ; left untouched if only one side was stretched.
    target_visible_left := (horizontal_state["left_stretched"] ? horizontal_state["original_left"]
        : visible_left)

    target_visible_right := (horizontal_state["right_stretched"]
        ? horizontal_state["original_right"] : visible_right)

    if WW_MoveWindowToVisibleHorizontalBounds(hwnd, target_visible_left, target_visible_right) {
        WW_ForgetHorizontalStretch(hwnd)
    } else {
        WW_DebugLog(
            "Horizontal stretch reset failed; preserving state. hwnd="
            . hwnd
        )
    }
}


WW_ToggleHorizontalStretch(side)
{
    Critical "On"

    global WW_horizontal_stretch_windows

    if side != "left" && side != "right"
        return

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if !WW_SetNativeFullscreen(hwnd, false)
            return
        WW_RememberNormalWindowPlacement(hwnd)
        WW_PruneHorizontalStretchWindows()

        if WinGetMinMax(window) != 0 {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !WW_GetHorizontalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
            &visible_left, &visible_right, &inset_left, &inset_right) {
            return
        }

        monitor_handle := WindowMonitor(hwnd)

        WW_GetWindowMonitorWorkArea(hwnd, &work_left, &work_top, &work_right, &work_bottom)

        if !WW_horizontal_stretch_windows.Has(hwnd)
            || !WW_IsStretchStateCurrent(hwnd, WW_horizontal_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            ; Save visible frame edges, not the raw HWND bounds. Windows 11's
            ; invisible resize border can extend beyond what the user sees.
            WW_horizontal_stretch_windows[hwnd] := Map("pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_left", visible_left, "original_right", visible_right,
                "left_stretched", false, "right_stretched", false)
        }

        state := WW_horizontal_stretch_windows[hwnd]
        collision_edge := 0
        ; Restoring a saved edge does not need a desktop-wide obstacle scan.
        if !state[side "_stretched"] {
            obstacles := WW_GetHorizontalStretchObstacles(hwnd, monitor_handle)
            active_rect := WW_GetWindowLayoutRectangle(hwnd)
            collision_edge := WW_GetCollisionLimitedEdge(
                side, active_rect, obstacles, side = "left" ? work_left : work_right
            )
        }

        if side = "left" {
            next_stretched := !state["left_stretched"]
            original_edge := (state["left_stretched"] ? state["original_left"] : visible_left)

            target_visible_left := (next_stretched ? collision_edge : original_edge)

            ; Left stretch owns only the left edge. Preserve the live right edge,
            ; including any active right stretch or manual resize.
            target_visible_right := visible_right
        } else {
            next_stretched := !state["right_stretched"]
            original_edge := (state["right_stretched"] ? state["original_right"] : visible_right)

            ; Right stretch owns only the right edge. Preserve the live left edge,
            ; including any active left stretch or manual resize.
            target_visible_left := visible_left

            target_visible_right := (next_stretched ? collision_edge : original_edge)
        }

        if next_stretched
            && Abs(target_visible_left - visible_left) <= 1
            && Abs(target_visible_right - visible_right) <= 1
        {
            if !state["left_stretched"] && !state["right_stretched"]
                WW_ForgetHorizontalStretch(hwnd)
            return
        }

        ; Do not mutate or discard restore state until the geometry move succeeds.
        ; Otherwise a transient move failure can leave the window stretched with
        ; no remembered edge to restore.
        if !WW_MoveWindowToVisibleHorizontalBounds(hwnd, target_visible_left, target_visible_right
        ) {
            WW_DebugLog(
                "Horizontal stretch toggle failed; preserving state. hwnd="
                . hwnd . " side=" . side
            )
            return
        }

        WW_ForgetFullStretch(hwnd)
        if side = "left" {
            state["original_left"] := original_edge
            state["left_stretched"] := next_stretched
        } else {
            state["original_right"] := original_edge
            state["right_stretched"] := next_stretched
        }

        if !state["left_stretched"] && !state["right_stretched"]
            WW_ForgetHorizontalStretch(hwnd)
    }
}


WW_GetHorizontalStretchObstacles(active_hwnd, monitor_handle)
{
    obstacles := []
    for hwnd in WinGetList() {
        if hwnd = active_hwnd || !IsSwitchableWindow(hwnd)
            continue
        candidate_monitor := WindowMonitor(hwnd)
        if candidate_monitor != monitor_handle
            continue
        try obstacles.Push(WW_GetWindowLayoutRectangle(hwnd))
    }
    return obstacles
}

WW_GetHorizontalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height, &visible_left,
    &visible_right, &inset_left, &inset_right)
{
    if !(frame := GetWindowFrame(hwnd))
        return false
    raw_x := frame.rawX, raw_y := frame.rawY, raw_width := frame.rawWidth, raw_height := frame.rawHeight
    visible_left := frame.x, visible_right := frame.x + frame.width
    inset_left := frame.left, inset_right := frame.right
    return true
}

WW_GetVerticalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height, &visible_top,
    &visible_bottom, &inset_top, &inset_bottom)
{
    if !(frame := GetWindowFrame(hwnd))
        return false
    raw_x := frame.rawX, raw_y := frame.rawY, raw_width := frame.rawWidth, raw_height := frame.rawHeight
    visible_top := frame.y, visible_bottom := frame.y + frame.height
    inset_top := frame.top, inset_bottom := frame.bottom
    return true
}


WW_MoveWindowToVisibleHorizontalBounds(hwnd, target_visible_left, target_visible_right)
{
    SuiteWindowOwnership.Claim(hwnd)
    target_visible_width :=
        target_visible_right - target_visible_left

    if target_visible_width <= 0
        return false

    if !WW_GetHorizontalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
        &visible_left, &visible_right, &inset_left, &inset_right) {
        return false
    }

    raw_target_x := target_visible_left - inset_left
    raw_target_width := (target_visible_width + inset_left + inset_right)

    if raw_target_width <= 0
        return false

    try WinMove(raw_target_x, raw_y, raw_target_width, raw_height, "ahk_id " hwnd)
    catch {
        return false
    }

    ; Fixed-size and size-constrained apps may accept WinMove but ignore the
    ; requested width. Verify both edges before committing the stretch state.
    Loop 3 {
        Sleep 10
        if WW_GetHorizontalStretchGeometry(hwnd, &check_x, &check_y, &check_width, &check_height,
            &check_left, &check_right, &check_inset_left, &check_inset_right) {
            if Abs(check_left - target_visible_left) <= 2
                && Abs(check_right - target_visible_right) <= 2
            {
                return true
            }
        }
    }

    ; Roll back a partially accepted resize instead of moving the opposite edge.
    try WinMove(raw_x, raw_y, raw_width, raw_height, hwnd)
    return false
}


WW_MoveWindowToVisibleVerticalBounds(hwnd, target_visible_top, target_visible_bottom,
    render_overscan := 0)
{
    SuiteWindowOwnership.Claim(hwnd)
    effective_top := target_visible_top - render_overscan
    effective_bottom := target_visible_bottom + render_overscan
    if effective_bottom <= effective_top
        return false

    if !WW_GetVerticalStretchGeometry(hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
        &visible_top, &visible_bottom, &inset_top, &inset_bottom) {
        return false
    }

    target_height := effective_bottom - effective_top + inset_top + inset_bottom
    if target_height <= 0
        return false

    try {
        WinMove(raw_x, effective_top - inset_top, raw_width, target_height, hwnd)

        ; Keep the existing one-pixel overscan, but check the final correction too.
        ; A resizable app can still impose a minimum or maximum height.
        Loop 4 {
            Sleep 10
            if !WW_GetVerticalStretchGeometry(hwnd, &check_x, &check_y, &check_width, &check_height,
                &check_top, &check_bottom, &check_inset_top, &check_inset_bottom) {
                break
            }

            top_error := effective_top - check_top
            bottom_error := effective_bottom - check_bottom
            if top_error = 0 && bottom_error = 0
                return true
            if A_Index = 4
                break

            corrected_height := check_height + bottom_error - top_error
            if corrected_height <= 0
                break
            WinMove(check_x, check_y + top_error, check_width, corrected_height, hwnd)
        }
    }
    catch Error as err {
        WW_DebugError("Move vertical stretch bounds", err)
    }

    ; Match horizontal stretch: roll back a partial resize instead of reporting
    ; success and discarding the only restore state for a rejected rectangle.
    try WinMove(raw_x, raw_y, raw_width, raw_height, hwnd)
    return false
}


WW_ForgetVerticalStretch(hwnd)
{
    global WW_vertical_stretch_windows

    try WW_vertical_stretch_windows.Delete(hwnd)
}

WW_PruneVerticalStretchWindows()
{
    global WW_vertical_stretch_windows

    stale_hwnds := []

    for hwnd, saved in WW_vertical_stretch_windows {
        if !WW_WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }

    for hwnd in stale_hwnds
        WW_ForgetVerticalStretch(hwnd)
}

WW_ForgetHorizontalStretch(hwnd)
{
    global WW_horizontal_stretch_windows

    try WW_horizontal_stretch_windows.Delete(hwnd)
}

WW_PruneHorizontalStretchWindows()
{
    global WW_horizontal_stretch_windows

    stale_hwnds := []

    for hwnd, saved in WW_horizontal_stretch_windows {
        if !WW_WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }

    for hwnd in stale_hwnds
        WW_ForgetHorizontalStretch(hwnd)
}

; =============================================================================
; placement state and geometry matching
; =============================================================================

WW_GetPlacementTarget(&fresh_entry)
{
    global WW_last_minimized_hwnd
    fresh_entry := !!WW_last_minimized_hwnd
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
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_full_stretch_windows
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_full_stretch_windows] {
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
    WW_ForgetHorizontalStretch(hwnd)
    WW_ForgetVerticalStretch(hwnd)
    WW_ForgetFullStretch(hwnd)
    if WinGetMinMax(hwnd) != 0
        WinRestore(hwnd)
}

WW_IsStretchStateCurrent(hwnd, saved, monitor_handle := 0, work_area := 0)
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
