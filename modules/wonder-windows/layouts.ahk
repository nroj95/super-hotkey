; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; window stretch
; =============================================================================

WW_StretchWindowVertically()
{
    Critical "On"

    global WW_borderless_windows
    global WW_vertical_stretch_windows

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        WW_RememberNormalWindowPlacement(hwnd)
        WW_PruneVerticalStretchWindows()

        ; Special states do not have reliable ordinary-window geometry.
        if WW_borderless_windows.Has(hwnd) {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WW_RestoreBorderlessWindow(hwnd, false, true)
        } else if WinGetMinMax(window) != 0 {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !WW_GetVerticalStretchGeometry(
            hwnd,
            &raw_x,
            &raw_y,
            &raw_width,
            &raw_height,
            &visible_top,
            &visible_bottom,
            &inset_top,
            &inset_bottom
        ) {
            return
        }

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

        if !WW_vertical_stretch_windows.Has(hwnd)
            || !WW_IsStretchStateCurrent(hwnd, WW_vertical_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            WW_vertical_stretch_windows[hwnd] := Map(
                "pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_top", visible_top,
                "original_bottom", visible_bottom
            )
        }

        if !WW_MoveWindowToVisibleVerticalBounds(
            hwnd,
            work_top,
            work_bottom,
            1
        ) {
            WW_DebugLog(
                "Vertical stretch move failed; preserving restore state. hwnd="
                . hwnd
            )
        }
    }
}

WW_ResetWindowStretch()
{
    Critical "On"

    global WW_horizontal_stretch_windows
    global WW_vertical_stretch_windows

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    current_monitor := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2, ; MONITOR_DEFAULTTONEAREST
        "ptr"
    )

    ; Restore vertical stretch first. Horizontal restore preserves the resulting
    ; Y/height, so both axes can be reset independently in one command.
    if WW_vertical_stretch_windows.Has(hwnd) {
        vertical_state := WW_vertical_stretch_windows[hwnd]

        if !WW_IsStretchStateCurrent(hwnd, vertical_state, current_monitor) {
            WW_ForgetVerticalStretch(hwnd)
            WW_DebugLog("Discarded stale vertical stretch state. hwnd=" hwnd)
        } else if WW_MoveWindowToVisibleVerticalBounds(
            hwnd,
            vertical_state["original_top"],
            vertical_state["original_bottom"]
        ) {
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

    if !WW_GetHorizontalStretchGeometry(
        hwnd,
        &raw_x,
        &raw_y,
        &raw_width,
        &raw_height,
        &visible_left,
        &visible_right,
        &inset_left,
        &inset_right
    ) {
        WW_DebugLog(
            "Horizontal stretch reset could not read geometry; "
            . "preserving state. hwnd=" . hwnd
        )
        return
    }

    ; Only restore edges that are actually stretched. The opposite live edge is
    ; left untouched if only one side was stretched.
    target_visible_left := (
        horizontal_state["left_stretched"]
        ? horizontal_state["original_left"]
        : visible_left
    )

    target_visible_right := (
        horizontal_state["right_stretched"]
        ? horizontal_state["original_right"]
        : visible_right
    )

    if WW_MoveWindowToVisibleHorizontalBounds(
        hwnd,
        target_visible_left,
        target_visible_right
    ) {
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

    global WW_borderless_windows
    global WW_horizontal_stretch_windows

    if side != "left" && side != "right"
        return

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        WW_RememberNormalWindowPlacement(hwnd)
        WW_PruneHorizontalStretchWindows()

        ; Special window states do not have reliable normal geometry for a
        ; horizontal toggle. Restore them first and begin a fresh stretch state.
        if WW_borderless_windows.Has(hwnd) {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WW_RestoreBorderlessWindow(hwnd, false, true)
        } else if WinGetMinMax(window) != 0 {
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !WW_GetHorizontalStretchGeometry(
            hwnd,
            &raw_x,
            &raw_y,
            &raw_width,
            &raw_height,
            &visible_left,
            &visible_right,
            &inset_left,
            &inset_right
        ) {
            return
        }

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

        if !WW_horizontal_stretch_windows.Has(hwnd)
            || !WW_IsStretchStateCurrent(hwnd, WW_horizontal_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            ; Save visible frame edges, not the raw HWND bounds. Windows 11's
            ; invisible resize border can extend beyond what the user sees.
            WW_horizontal_stretch_windows[hwnd] := Map(
                "pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_left", visible_left,
                "original_right", visible_right,
                "left_stretched", false,
                "right_stretched", false
            )
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
            original_edge := (
                state["left_stretched"]
                ? state["original_left"]
                : visible_left
            )

            target_visible_left := (
                next_stretched
                ? collision_edge
                : original_edge
            )

            ; Left stretch owns only the left edge. Preserve the live right edge,
            ; including any active right stretch or manual resize.
            target_visible_right := visible_right
        } else {
            next_stretched := !state["right_stretched"]
            original_edge := (
                state["right_stretched"]
                ? state["original_right"]
                : visible_right
            )

            ; Right stretch owns only the right edge. Preserve the live left edge,
            ; including any active left stretch or manual resize.
            target_visible_left := visible_left

            target_visible_right := (
                next_stretched
                ? collision_edge
                : original_edge
            )
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
        if !WW_MoveWindowToVisibleHorizontalBounds(
            hwnd,
            target_visible_left,
            target_visible_right
        ) {
            WW_DebugLog(
                "Horizontal stretch toggle failed; preserving state. hwnd="
                . hwnd . " side=" . side
            )
            return
        }

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
        if hwnd = active_hwnd || !WW_IsWindowToggleCandidate(hwnd)
            continue
        candidate_monitor := DllCall(
            "MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr"
        )
        if candidate_monitor != monitor_handle
            continue
        try obstacles.Push(WW_GetWindowLayoutRectangle(hwnd))
    }
    return obstacles
}

WW_GetHorizontalStretchGeometry(
    hwnd,
    &raw_x,
    &raw_y,
    &raw_width,
    &raw_height,
    &visible_left,
    &visible_right,
    &inset_left,
    &inset_right
)
{
    try WinGetPos(
        &raw_x,
        &raw_y,
        &raw_width,
        &raw_height,
        "ahk_id " hwnd
    )
    catch {
        return false
    }

    if raw_width <= 0 || raw_height <= 0
        return false

    if WW_GetVisibleWindowBounds(
        hwnd,
        &visible_x,
        &visible_y,
        &visible_width,
        &visible_height
    ) {
        visible_left := visible_x
        visible_right := visible_x + visible_width
    } else {
        ; DWM frame bounds are normally available. Fall back to the raw HWND
        ; rectangle so the stretch still works on windows without them.
        visible_left := raw_x
        visible_right := raw_x + raw_width
    }

    inset_left := visible_left - raw_x
    inset_right := (raw_x + raw_width) - visible_right

    return true
}

WW_GetVerticalStretchGeometry(
    hwnd,
    &raw_x,
    &raw_y,
    &raw_width,
    &raw_height,
    &visible_top,
    &visible_bottom,
    &inset_top,
    &inset_bottom
)
{
    try WinGetPos(
        &raw_x,
        &raw_y,
        &raw_width,
        &raw_height,
        "ahk_id " hwnd
    )
    catch {
        return false
    }

    if raw_width <= 0 || raw_height <= 0
        return false

    if WW_GetVisibleWindowBounds(
        hwnd,
        &visible_x,
        &visible_y,
        &visible_width,
        &visible_height
    ) {
        visible_top := visible_y
        visible_bottom := visible_y + visible_height
    } else {
        visible_top := raw_y
        visible_bottom := raw_y + raw_height
    }

    inset_top := visible_top - raw_y
    inset_bottom := (raw_y + raw_height) - visible_bottom

    return true
}


WW_MoveWindowToVisibleHorizontalBounds(
    hwnd,
    target_visible_left,
    target_visible_right
)
{
    SuiteWindowOwnership.Claim(hwnd)
    target_visible_width :=
        target_visible_right - target_visible_left

    if target_visible_width <= 0
        return false

    if !WW_GetHorizontalStretchGeometry(
        hwnd,
        &raw_x,
        &raw_y,
        &raw_width,
        &raw_height,
        &visible_left,
        &visible_right,
        &inset_left,
        &inset_right
    ) {
        return false
    }

    raw_target_x := target_visible_left - inset_left
    raw_target_width := (
        target_visible_width
        + inset_left
        + inset_right
    )

    if raw_target_width <= 0
        return false

    try WinMove(
        raw_target_x,
        raw_y,
        raw_target_width,
        raw_height,
        "ahk_id " hwnd
    )
    catch {
        return false
    }

    ; Fixed-size and size-constrained apps may accept WinMove but ignore the
    ; requested width. Verify both edges before committing the stretch state.
    Loop 3 {
        Sleep 10
        if WW_GetHorizontalStretchGeometry(
            hwnd, &check_x, &check_y, &check_width, &check_height,
            &check_left, &check_right, &check_inset_left, &check_inset_right
        ) {
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


WW_MoveWindowToVisibleVerticalBounds(
    hwnd,
    target_visible_top,
    target_visible_bottom,
    render_overscan := 0
)
{
    SuiteWindowOwnership.Claim(hwnd)
    effective_top := target_visible_top - render_overscan
    effective_bottom := target_visible_bottom + render_overscan
    if effective_bottom <= effective_top
        return false

    if !WW_GetVerticalStretchGeometry(
        hwnd, &raw_x, &raw_y, &raw_width, &raw_height,
        &visible_top, &visible_bottom, &inset_top, &inset_bottom
    ) {
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
            if !WW_GetVerticalStretchGeometry(
                hwnd, &check_x, &check_y, &check_width, &check_height,
                &check_top, &check_bottom, &check_inset_top, &check_inset_bottom
            ) {
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

WW_RestoreAllVerticalStretches()
{
    global WW_vertical_stretch_windows

    windows := []

    for hwnd in WW_vertical_stretch_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue

        state := WW_vertical_stretch_windows[hwnd]

        current_monitor := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        if !WW_IsStretchStateCurrent(hwnd, state, current_monitor)
            continue

        original_visible_height :=
            state["original_bottom"] - state["original_top"]

        if original_visible_height > 0
            WW_MoveWindowToVisibleVerticalBounds(
                hwnd,
                state["original_top"],
                state["original_bottom"]
            )
    }

    WW_vertical_stretch_windows := Map()
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

WW_RestoreAllHorizontalStretches()
{
    global WW_horizontal_stretch_windows

    windows := []

    for hwnd in WW_horizontal_stretch_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue

        state := WW_horizontal_stretch_windows[hwnd]

        current_monitor := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        ; If another action already moved the window to another monitor, do not
        ; pull it back across monitors during script cleanup.
        if !WW_IsStretchStateCurrent(hwnd, state, current_monitor)
            continue

        try {
            if !WW_GetHorizontalStretchGeometry(
                hwnd,
                &raw_x,
                &raw_y,
                &raw_width,
                &raw_height,
                &visible_left,
                &visible_right,
                &inset_left,
                &inset_right
            ) {
                continue
            }

            ; Cleanup owns only the edges this script actually stretched. Keep a
            ; manual change to the opposite edge, just like Win+Shift+Down does.
            restore_left := state["left_stretched"] ? state["original_left"] : visible_left
            restore_right := state["right_stretched"] ? state["original_right"] : visible_right
            if restore_right > restore_left
                WW_MoveWindowToVisibleHorizontalBounds(hwnd, restore_left, restore_right)
        }
    }

    WW_horizontal_stretch_windows := Map()
}


; =============================================================================
; side-layout cycle and top/bottom tiles
; =============================================================================

WW_CycleWindowSnap(side)
{
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := WW_GetLayoutWorkArea(hwnd)
        family := "side-" side
        layouts := []
        for ratios in WW_GetSideCycleRatios(side)
            layouts.Push(WW_BuildRatioLayout(work_area, ratios))

        index := fresh_entry ? 0 : WW_FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        target_index := WW_GetNextCycleIndex(index, layouts.Length)
        WW_ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
    }
    catch Error as err {
        WW_DebugError("Cycle side layout", err)
    }
}

WW_PlaceCornerTile(position)
{
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        parts := StrSplit(position, "-")
        if parts.Length != 2
            throw ValueError("Unknown corner tile: " position)
        vertical_position := parts[1]
        side := parts[2]
        work_area := WW_GetLayoutWorkArea(hwnd)
        side_ratios := WW_GetSideCycleRatios(side)
        layouts := [
            WW_BuildRatioLayout(work_area, side_ratios[1], vertical_position),
            WW_BuildRatioLayout(work_area, side_ratios[2], vertical_position)
        ]
        family := "corner-" position
        index := fresh_entry ? 0 : WW_FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        WW_ApplyTrackedLayout(hwnd, family, work_area, layouts, WW_GetNextCycleIndex(index, 2))
    }
    catch Error as err {
        WW_DebugError("Place corner tile", err)
    }
}

WW_PlaceCenterTile(vertical_position)
{
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := WW_GetLayoutWorkArea(hwnd)
        family := "center-" vertical_position
        layouts := [
            WW_BuildRatioLayout(work_area, [2, 4, 2], vertical_position),
            WW_BuildRatioLayout(work_area, [2, 2, 4], vertical_position),
            WW_BuildRatioLayout(work_area, [4, 2, 2], vertical_position)
        ]
        index := fresh_entry ? 0 : WW_FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        next_side := WW_GetNextCenterTileSide(hwnd, vertical_position)
        target_index := index = 1 ? (next_side = "left" ? 2 : 3) : 1

        if !WW_ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
            return

        ; Each window remembers an independent next narrow side for top and
        ; bottom. Switching shortcuts does not restart every narrow tile at left.
        if target_index = 2 || (target_index = 1 && index = 2)
            WW_SetNextCenterTileSide(hwnd, vertical_position, "right")
        else if target_index = 3 || (target_index = 1 && index = 3)
            WW_SetNextCenterTileSide(hwnd, vertical_position, "left")
    }
    catch Error as err {
        WW_DebugError("Place center tile", err)
    }
}

; =============================================================================
; placement state and geometry matching
; =============================================================================

WW_GetPlacementTarget(&fresh_entry)
{
    global WW_last_minimized_hwnd, WW_borderless_windows
    fresh_entry := !!WW_last_minimized_hwnd
    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return 0

    try {
        if !WW_IsWindowToggleCandidate(hwnd)
            return 0
        if WW_borderless_windows.Has(hwnd) || WinGetMinMax(hwnd) != 0
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

WW_GetLayoutWorkArea(hwnd)
{
    WW_GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
    return [left, top, right, bottom]
}

WW_GetWindowLayoutRectangle(hwnd)
{
    if !WW_GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
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
    if !WW_MoveWindowToVisibleRectangle(hwnd, layouts[target_index])
        return false

    ; Store the actual result: an app may enforce a minimum size larger than a
    ; quarter-screen tile. That must not strand the cycle on its first step.
    WW_layout_cycle_windows[hwnd] := Map(
        "pid", WinGetPID(hwnd),
        "family", family,
        "work_area", work_area,
        "index", target_index,
        "actual_rect", WW_GetWindowLayoutRectangle(hwnd)
    )
    return true
}

WW_GetNextCenterTileSide(hwnd, vertical_position)
{
    global WW_center_tile_next_sides
    process_id := WinGetPID(hwnd)
    if !WW_center_tile_next_sides.Has(hwnd)
        || WW_center_tile_next_sides[hwnd]["pid"] != process_id
    {
        WW_center_tile_next_sides[hwnd] := Map(
            "pid", process_id, "top", "left", "bottom", "left"
        )
    }
    return WW_center_tile_next_sides[hwnd][vertical_position]
}

WW_SetNextCenterTileSide(hwnd, vertical_position, side)
{
    global WW_center_tile_next_sides
    WW_GetNextCenterTileSide(hwnd, vertical_position)
    WW_center_tile_next_sides[hwnd][vertical_position] := side
}

WW_ForgetWindowLayoutCycle(hwnd)
{
    global WW_layout_cycle_windows
    try WW_layout_cycle_windows.Delete(hwnd)
}

WW_PruneLayoutStates()
{
    global WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements
    for states in [WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements] {
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
    SuiteWindowOwnership.Claim(hwnd)
    global WW_borderless_windows
    WW_RememberNormalWindowPlacement(hwnd)
    WW_ForgetHorizontalStretch(hwnd)
    WW_ForgetVerticalStretch(hwnd)

    if WW_borderless_windows.Has(hwnd) {
        WW_RestoreBorderlessWindow(hwnd, false, true)
        return
    }
    if WinGetMinMax(hwnd) != 0
        WinRestore(hwnd)
}

WW_IsStretchStateCurrent(hwnd, saved, monitor_handle := 0, work_area := 0)
{
    if !WW_WindowStateMatchesProcess(hwnd, saved)
        return false
    try {
        if !monitor_handle
            monitor_handle := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if !work_area
            work_area := WW_GetLayoutWorkArea(hwnd)
        return saved["monitor"] = monitor_handle
            && WW_RectanglesMatch(saved["work_area"], work_area, 0)
    }
    catch {
        return false
    }
}
