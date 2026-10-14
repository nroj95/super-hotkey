; Internal Win Key Overhaul module. Pure geometry; no desktop side effects.

; =============================================================================
; ratio layouts
; =============================================================================
; All ratios below are left space : window width : right space.
; The user's 2:6 and 4:4 edge splits are quarter-width and half-width windows.

GetSideCycleRatios(side)
{
    switch side {
        case "left":
            return [[0, 2, 6], [0, 4, 4], [2, 2, 4], [2, 4, 2]]
        case "right":
            return [[6, 2, 0], [4, 4, 0], [4, 2, 2], [2, 4, 2]]
        default:
            throw ValueError("Unknown side: " side)
    }
}

BuildRatioLayout(work_area, ratios, vertical_position := "full")
{
    left := work_area[1]
    top := work_area[2]
    right := work_area[3]
    bottom := work_area[4]
    work_width := right - left
    work_height := bottom - top
    total_parts := ratios[1] + ratios[2] + ratios[3]

    if work_width <= 0 || work_height <= 0
        throw ValueError("The monitor work area must have positive dimensions.")
    if ratios[1] < 0 || ratios[2] <= 0 || ratios[3] < 0
        throw ValueError("Layout ratios require a positive window width.")

    ; Round shared boundaries rather than widths so adjoining tiles meet even
    ; at odd resolutions and on monitors with negative desktop coordinates.
    target_left := left + Round(work_width * ratios[1] / total_parts)
    target_right := left + Round(work_width * (ratios[1] + ratios[2]) / total_parts)
    split_y := top + Floor(work_height / 2)

    switch vertical_position {
        case "full":
            target_top := top
            target_bottom := bottom
        case "top":
            target_top := top
            target_bottom := split_y
        case "bottom":
            target_top := split_y
            target_bottom := bottom
        default:
            throw ValueError("Unknown vertical position: " vertical_position)
    }

    return [target_left, target_top, target_right - target_left,
        target_bottom - target_top]
}

GetNextCycleIndex(current_index, count, backwards := false)
{
    if count < 1
        throw ValueError("A cycle must contain at least one item.")
    if current_index < 1 || current_index > count
        return 1
    if backwards
        return current_index = 1 ? count : current_index - 1
    return current_index = count ? 1 : current_index + 1
}

RectanglesMatch(first, second, tolerance := 4)
{
    Loop 4 {
        if Abs(first[A_Index] - second[A_Index]) > tolerance
            return false
    }
    return true
}

; =============================================================================
; collision-limited horizontal extension
; =============================================================================

GetCollisionLimitedEdge(side, active_rect, obstacles, work_edge, tolerance := 1)
{
    active_left := active_rect[1]
    active_top := active_rect[2]
    active_right := active_left + active_rect[3]
    active_bottom := active_top + active_rect[4]

    if side != "left" && side != "right"
        throw ValueError("Unknown stretch side: " side)

    ; Stretching must not shrink a window that is already partly off-screen.
    limit := side = "left" ? Min(work_edge, active_left) : Max(work_edge, active_right)

    for obstacle in obstacles {
        obstacle_left := obstacle[1]
        obstacle_top := obstacle[2]
        obstacle_right := obstacle_left + obstacle[3]
        obstacle_bottom := obstacle_top + obstacle[4]

        if obstacle[3] <= 0 || obstacle[4] <= 0
            continue
        if Min(active_bottom, obstacle_bottom) <= Max(active_top, obstacle_top)
            continue

        ; Ignore pre-existing overlap. An extension should not collapse the
        ; window just because another window already sits behind or over it.
        if side = "left" {
            if obstacle_right <= active_left + tolerance
                limit := Max(limit, Min(active_left, obstacle_right))
        } else {
            if obstacle_left >= active_right - tolerance
                limit := Min(limit, Max(active_right, obstacle_left))
        }
    }
    return limit
}
