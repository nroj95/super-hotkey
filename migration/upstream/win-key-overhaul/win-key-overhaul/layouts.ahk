; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; window stretch
; =============================================================================

StretchWindowVertically()
{
    Critical "On"

    global borderless_windows
    global vertical_stretch_windows

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        RememberNormalWindowPlacement(hwnd)
        PruneVerticalStretchWindows()

        ; Special states do not have reliable ordinary-window geometry.
        if borderless_windows.Has(hwnd) {
            ForgetHorizontalStretch(hwnd)
            ForgetVerticalStretch(hwnd)
            RestoreBorderlessWindow(hwnd, false, true)
        } else if WinGetMinMax(window) != 0 {
            ForgetHorizontalStretch(hwnd)
            ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !GetVerticalStretchGeometry(
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

        GetWindowMonitorWorkArea(
            hwnd,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        if !vertical_stretch_windows.Has(hwnd)
            || !IsStretchStateCurrent(hwnd, vertical_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            vertical_stretch_windows[hwnd] := Map(
                "pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_top", visible_top,
                "original_bottom", visible_bottom
            )
        }

        if !MoveWindowToVisibleVerticalBounds(
            hwnd,
            work_top,
            work_bottom,
            1
        ) {
            DebugLog(
                "Vertical stretch move failed; preserving restore state. hwnd="
                . hwnd
            )
        }
    }
}

ResetWindowStretch()
{
    Critical "On"

    global horizontal_stretch_windows
    global vertical_stretch_windows

    hwnd := GetWindowControlTarget()

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
    if vertical_stretch_windows.Has(hwnd) {
        vertical_state := vertical_stretch_windows[hwnd]

        if !IsStretchStateCurrent(hwnd, vertical_state, current_monitor) {
            ForgetVerticalStretch(hwnd)
            DebugLog("Discarded stale vertical stretch state. hwnd=" hwnd)
        } else if MoveWindowToVisibleVerticalBounds(
            hwnd,
            vertical_state["original_top"],
            vertical_state["original_bottom"]
        ) {
            ForgetVerticalStretch(hwnd)
        } else {
            DebugLog(
                "Vertical stretch reset failed; preserving state. hwnd="
                . hwnd
            )
        }
    }

    if !horizontal_stretch_windows.Has(hwnd)
        return

    horizontal_state := horizontal_stretch_windows[hwnd]

    if !IsStretchStateCurrent(hwnd, horizontal_state, current_monitor) {
        ForgetHorizontalStretch(hwnd)
        DebugLog("Discarded stale horizontal stretch state. hwnd=" hwnd)
        return
    }

    if !GetHorizontalStretchGeometry(
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
        DebugLog(
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

    if MoveWindowToVisibleHorizontalBounds(
        hwnd,
        target_visible_left,
        target_visible_right
    ) {
        ForgetHorizontalStretch(hwnd)
    } else {
        DebugLog(
            "Horizontal stretch reset failed; preserving state. hwnd="
            . hwnd
        )
    }
}


ToggleHorizontalStretch(side)
{
    Critical "On"

    global borderless_windows
    global horizontal_stretch_windows

    if side != "left" && side != "right"
        return

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        RememberNormalWindowPlacement(hwnd)
        PruneHorizontalStretchWindows()

        ; Special window states do not have reliable normal geometry for a
        ; horizontal toggle. Restore them first and begin a fresh stretch state.
        if borderless_windows.Has(hwnd) {
            ForgetHorizontalStretch(hwnd)
            ForgetVerticalStretch(hwnd)
            RestoreBorderlessWindow(hwnd, false, true)
        } else if WinGetMinMax(window) != 0 {
            ForgetHorizontalStretch(hwnd)
            ForgetVerticalStretch(hwnd)
            WinRestore(window)
        }

        if !GetHorizontalStretchGeometry(
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

        GetWindowMonitorWorkArea(
            hwnd,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        if !horizontal_stretch_windows.Has(hwnd)
            || !IsStretchStateCurrent(hwnd, horizontal_stretch_windows[hwnd], monitor_handle,
                [work_left, work_top, work_right, work_bottom])
        {
            ; Save visible frame edges, not the raw HWND bounds. Windows 11's
            ; invisible resize border can extend beyond what the user sees.
            horizontal_stretch_windows[hwnd] := Map(
                "pid", WinGetPID(hwnd),
                "monitor", monitor_handle,
                "work_area", [work_left, work_top, work_right, work_bottom],
                "original_left", visible_left,
                "original_right", visible_right,
                "left_stretched", false,
                "right_stretched", false
            )
        }

        state := horizontal_stretch_windows[hwnd]
        collision_edge := 0
        ; Restoring a saved edge does not need a desktop-wide obstacle scan.
        if !state[side "_stretched"] {
            obstacles := GetHorizontalStretchObstacles(hwnd, monitor_handle)
            active_rect := GetWindowLayoutRectangle(hwnd)
            collision_edge := GetCollisionLimitedEdge(
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
                ForgetHorizontalStretch(hwnd)
            return
        }

        ; Do not mutate or discard restore state until the geometry move succeeds.
        ; Otherwise a transient move failure can leave the window stretched with
        ; no remembered edge to restore.
        if !MoveWindowToVisibleHorizontalBounds(
            hwnd,
            target_visible_left,
            target_visible_right
        ) {
            DebugLog(
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
            ForgetHorizontalStretch(hwnd)
    }
}


GetHorizontalStretchObstacles(active_hwnd, monitor_handle)
{
    obstacles := []
    for hwnd in WinGetList() {
        if hwnd = active_hwnd || !IsWindowToggleCandidate(hwnd)
            continue
        candidate_monitor := DllCall(
            "MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr"
        )
        if candidate_monitor != monitor_handle
            continue
        try obstacles.Push(GetWindowLayoutRectangle(hwnd))
    }
    return obstacles
}

GetHorizontalStretchGeometry(
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

    if GetVisibleWindowBounds(
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

GetVerticalStretchGeometry(
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

    if GetVisibleWindowBounds(
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


MoveWindowToVisibleHorizontalBounds(
    hwnd,
    target_visible_left,
    target_visible_right
)
{
    target_visible_width :=
        target_visible_right - target_visible_left

    if target_visible_width <= 0
        return false

    if !GetHorizontalStretchGeometry(
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
        if GetHorizontalStretchGeometry(
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


MoveWindowToVisibleVerticalBounds(
    hwnd,
    target_visible_top,
    target_visible_bottom,
    render_overscan := 0
)
{
    effective_top := target_visible_top - render_overscan
    effective_bottom := target_visible_bottom + render_overscan
    if effective_bottom <= effective_top
        return false

    if !GetVerticalStretchGeometry(
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
            if !GetVerticalStretchGeometry(
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
        DebugError("Move vertical stretch bounds", err)
    }

    ; Match horizontal stretch: roll back a partial resize instead of reporting
    ; success and discarding the only restore state for a rejected rectangle.
    try WinMove(raw_x, raw_y, raw_width, raw_height, hwnd)
    return false
}


ForgetVerticalStretch(hwnd)
{
    global vertical_stretch_windows

    try vertical_stretch_windows.Delete(hwnd)
}

PruneVerticalStretchWindows()
{
    global vertical_stretch_windows

    stale_hwnds := []

    for hwnd, saved in vertical_stretch_windows {
        if !WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }

    for hwnd in stale_hwnds
        ForgetVerticalStretch(hwnd)
}

RestoreAllVerticalStretches()
{
    global vertical_stretch_windows

    windows := []

    for hwnd in vertical_stretch_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue

        state := vertical_stretch_windows[hwnd]

        current_monitor := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        if !IsStretchStateCurrent(hwnd, state, current_monitor)
            continue

        original_visible_height :=
            state["original_bottom"] - state["original_top"]

        if original_visible_height > 0
            MoveWindowToVisibleVerticalBounds(
                hwnd,
                state["original_top"],
                state["original_bottom"]
            )
    }

    vertical_stretch_windows := Map()
}


ForgetHorizontalStretch(hwnd)
{
    global horizontal_stretch_windows

    try horizontal_stretch_windows.Delete(hwnd)
}

PruneHorizontalStretchWindows()
{
    global horizontal_stretch_windows

    stale_hwnds := []

    for hwnd, saved in horizontal_stretch_windows {
        if !WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }

    for hwnd in stale_hwnds
        ForgetHorizontalStretch(hwnd)
}

RestoreAllHorizontalStretches()
{
    global horizontal_stretch_windows

    windows := []

    for hwnd in horizontal_stretch_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue

        state := horizontal_stretch_windows[hwnd]

        current_monitor := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        ; If another action already moved the window to another monitor, do not
        ; pull it back across monitors during script cleanup.
        if !IsStretchStateCurrent(hwnd, state, current_monitor)
            continue

        try {
            if !GetHorizontalStretchGeometry(
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
                MoveWindowToVisibleHorizontalBounds(hwnd, restore_left, restore_right)
        }
    }

    horizontal_stretch_windows := Map()
}


; =============================================================================
; side-layout cycle and top/bottom tiles
; =============================================================================

CycleWindowSnap(side)
{
    Critical "On"
    hwnd := GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := GetLayoutWorkArea(hwnd)
        family := "side-" side
        layouts := []
        for ratios in GetSideCycleRatios(side)
            layouts.Push(BuildRatioLayout(work_area, ratios))

        index := fresh_entry ? 0 : FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        target_index := GetNextCycleIndex(index, layouts.Length)
        ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
    }
    catch Error as err {
        DebugError("Cycle side layout", err)
    }
}

PlaceCornerTile(position)
{
    Critical "On"
    hwnd := GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        parts := StrSplit(position, "-")
        if parts.Length != 2
            throw ValueError("Unknown corner tile: " position)
        vertical_position := parts[1]
        side := parts[2]
        work_area := GetLayoutWorkArea(hwnd)
        side_ratios := GetSideCycleRatios(side)
        layouts := [
            BuildRatioLayout(work_area, side_ratios[1], vertical_position),
            BuildRatioLayout(work_area, side_ratios[2], vertical_position)
        ]
        family := "corner-" position
        index := fresh_entry ? 0 : FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        ApplyTrackedLayout(hwnd, family, work_area, layouts, GetNextCycleIndex(index, 2))
    }
    catch Error as err {
        DebugError("Place corner tile", err)
    }
}

PlaceCenterTile(vertical_position)
{
    Critical "On"
    hwnd := GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := GetLayoutWorkArea(hwnd)
        family := "center-" vertical_position
        layouts := [
            BuildRatioLayout(work_area, [2, 4, 2], vertical_position),
            BuildRatioLayout(work_area, [2, 2, 4], vertical_position),
            BuildRatioLayout(work_area, [4, 2, 2], vertical_position)
        ]
        index := fresh_entry ? 0 : FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
        next_side := GetNextCenterTileSide(hwnd, vertical_position)
        target_index := index = 1 ? (next_side = "left" ? 2 : 3) : 1

        if !ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
            return

        ; Each window remembers an independent next narrow side for top and
        ; bottom. Switching shortcuts does not restart every narrow tile at left.
        if target_index = 2 || (target_index = 1 && index = 2)
            SetNextCenterTileSide(hwnd, vertical_position, "right")
        else if target_index = 3 || (target_index = 1 && index = 3)
            SetNextCenterTileSide(hwnd, vertical_position, "left")
    }
    catch Error as err {
        DebugError("Place center tile", err)
    }
}

; =============================================================================
; placement state and geometry matching
; =============================================================================

GetPlacementTarget(&fresh_entry)
{
    global last_minimized_hwnd, borderless_windows
    fresh_entry := !!last_minimized_hwnd
    hwnd := GetWindowControlTarget()
    if !hwnd
        return 0

    try {
        if !IsWindowToggleCandidate(hwnd)
            return 0
        if borderless_windows.Has(hwnd) || WinGetMinMax(hwnd) != 0
            fresh_entry := true
        PruneLayoutStates()
        PrepareWindowForPlacement(hwnd)
        return hwnd
    }
    catch Error as err {
        DebugError("Prepare layout target", err)
        return 0
    }
}

GetLayoutWorkArea(hwnd)
{
    GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
    return [left, top, right, bottom]
}

GetWindowLayoutRectangle(hwnd)
{
    if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
        WinGetPos(&x, &y, &width, &height, hwnd)
    return [x, y, width, height]
}

FindCurrentLayoutIndex(hwnd, family, work_area, layouts)
{
    global layout_cycle_windows
    current_rect := GetWindowLayoutRectangle(hwnd)

    if layout_cycle_windows.Has(hwnd) {
        saved := layout_cycle_windows[hwnd]
        if saved["pid"] = WinGetPID(hwnd)
            && RectanglesMatch(saved["work_area"], work_area, 0)
            && RectanglesMatch(saved["actual_rect"], current_rect)
        {
            ; Switching arrows starts that side at 25%; it no longer walks the
            ; opposite side's cycle backwards. Other shortcut families also start
            ; their own sequence, even when a rectangle happens to be shared.
            return saved["family"] = family ? saved["index"] : 0
        }
        layout_cycle_windows.Delete(hwnd)
    }

    for index, layout in layouts {
        if RectanglesMatch(current_rect, layout)
            return index
    }
    return 0
}

ApplyTrackedLayout(hwnd, family, work_area, layouts, target_index)
{
    global layout_cycle_windows
    if !MoveWindowToVisibleRectangle(hwnd, layouts[target_index])
        return false

    ; Store the actual result: an app may enforce a minimum size larger than a
    ; quarter-screen tile. That must not strand the cycle on its first step.
    layout_cycle_windows[hwnd] := Map(
        "pid", WinGetPID(hwnd),
        "family", family,
        "work_area", work_area,
        "index", target_index,
        "actual_rect", GetWindowLayoutRectangle(hwnd)
    )
    return true
}

GetNextCenterTileSide(hwnd, vertical_position)
{
    global center_tile_next_sides
    process_id := WinGetPID(hwnd)
    if !center_tile_next_sides.Has(hwnd)
        || center_tile_next_sides[hwnd]["pid"] != process_id
    {
        center_tile_next_sides[hwnd] := Map(
            "pid", process_id, "top", "left", "bottom", "left"
        )
    }
    return center_tile_next_sides[hwnd][vertical_position]
}

SetNextCenterTileSide(hwnd, vertical_position, side)
{
    global center_tile_next_sides
    GetNextCenterTileSide(hwnd, vertical_position)
    center_tile_next_sides[hwnd][vertical_position] := side
}

ForgetWindowLayoutCycle(hwnd)
{
    global layout_cycle_windows
    try layout_cycle_windows.Delete(hwnd)
}

PruneLayoutStates()
{
    global layout_cycle_windows, center_tile_next_sides, normal_window_placements
    for states in [layout_cycle_windows, center_tile_next_sides, normal_window_placements] {
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

PrepareWindowForPlacement(hwnd)
{
    global borderless_windows
    RememberNormalWindowPlacement(hwnd)
    ForgetHorizontalStretch(hwnd)
    ForgetVerticalStretch(hwnd)

    if borderless_windows.Has(hwnd) {
        RestoreBorderlessWindow(hwnd, false, true)
        return
    }
    if WinGetMinMax(hwnd) != 0
        WinRestore(hwnd)
}

IsStretchStateCurrent(hwnd, saved, monitor_handle := 0, work_area := 0)
{
    if !WindowStateMatchesProcess(hwnd, saved)
        return false
    try {
        if !monitor_handle
            monitor_handle := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if !work_area
            work_area := GetLayoutWorkArea(hwnd)
        return saved["monitor"] = monitor_handle
            && RectanglesMatch(saved["work_area"], work_area, 0)
    }
    catch {
        return false
    }
}
