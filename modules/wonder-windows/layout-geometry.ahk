; Wonder Windows ratio layouts and rectangle helpers.

; =============================================================================
; ratio layouts
; =============================================================================
; All ratios below are left space : window width : right space.

WW_BuildRatioLayout(work_area, ratios, vertical_position := "full")
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

WW_GetNextCycleIndex(current_index, count, backwards := false)
{
    if count < 1
        throw ValueError("A cycle must contain at least one item.")
    if current_index < 1 || current_index > count
        return backwards ? count : 1
    if backwards
        return current_index = 1 ? count : current_index - 1
    return current_index = count ? 1 : current_index + 1
}

; Apps such as Discord cannot shrink to every layout, so their cycles skip the
; ones they refuse. When none fits, the normal step is placed as best it can.
WW_GetNextFittingIndex(current_index, layouts, minimum, backwards := false)
{
    candidate := current_index
    Loop layouts.Length {
        candidate := WW_GetNextCycleIndex(candidate, layouts.Length, backwards)
        if WW_LayoutFitsMinimum(layouts[candidate], minimum)
            return candidate
    }
    return WW_GetNextCycleIndex(current_index, layouts.Length, backwards)
}

WW_LayoutFitsMinimum(layout, minimum, tolerance := 2)
{
    return minimum[1] <= layout[3] + tolerance && minimum[2] <= layout[4] + tolerance
}

WW_RectanglesMatch(first, second, tolerance := 4)
{
    Loop 4 {
        if Abs(first[A_Index] - second[A_Index]) > tolerance
            return false
    }
    return true
}

; Keep a window's accepted dimensions, placing it inside the work area as near
; as possible to the destination's top-left corner. Refuse truly unfittable sizes.
WW_FitAcceptedRectangle(destination, accepted, work_area)
{
    width := accepted[3]
    height := accepted[4]
    left := work_area[1]
    top := work_area[2]
    right := work_area[3]
    bottom := work_area[4]

    if width <= 0 || height <= 0 || right <= left || bottom <= top
        || width > right - left || height > bottom - top
        return 0

    x := Max(left, Min(destination[1], right - width))
    y := Max(top, Min(destination[2], bottom - height))
    return [x, y, width, height]
}
