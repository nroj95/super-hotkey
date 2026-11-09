; Wonder Windows zone cycling and the zone layouts each display uses.

; =============================================================================
; zone cycling
; =============================================================================
; A session walks one zone sequence while any modifier stays held. The first
; zone is on the side the key names: down/Left walks from the left fourth,
; up/Right walks the mirror image from the right fourth. The key that started
; the session keeps going; the other one steps back, wrapping to the last zone.
; Releasing every modifier starts the next session over. Until then, zone mode
; lends Win + Up and Down to the session: they move to the zone directly above
; or below, and the walk goes on from there.

; Zone groups, each left to right as left space : width : right space.
WW_GetZoneGroups(unit)
{
    switch unit {
        case "fourths":
            return [[[0, 1, 3], [1, 1, 2], [2, 1, 1], [3, 1, 0]], [[0, 2, 2], [1, 2, 1], [2, 2, 0]]]
        case "thirds":
            return [[[0, 1, 2], [1, 1, 1], [2, 1, 0]]]
        default:
            throw ValueError("Unknown zone unit: " unit)
    }
}

; Every group at full height, then each group in the upper and lower halves:
; full fourths, full halves, upper fourths, lower fourths, upper halves, ...
WW_BuildZoneSequence(work_area, unit, from_right := false)
{
    rows := []
    for group in WW_GetZoneGroups(unit)
        rows.Push([group, "full"])
    for group in WW_GetZoneGroups(unit)
        for vertical_position in ["top", "bottom"]
            rows.Push([group, vertical_position])
    zones := []
    for row in rows
        for ratios in row[1]
            zones.Push(WW_BuildRatioLayout(work_area,
                from_right ? [ratios[3], ratios[2], ratios[1]] : ratios, row[2]))
    return zones
}

; =============================================================================
; zone layouts: presets and custom lines
; =============================================================================
; A layout is a preset ID or a custom line. Presets: fourths and thirds walk
; columns; rows-fourths and rows-thirds are the same turned 90 degrees, so
; Left starts at the top and Right at the bottom; corners is halves, then
; the four corners. A custom line lists pages separated by > ("and then"),
; rows by / and the parts of a row by :, as relative sizes: 1:1 / 1:1:1 is
; halves over thirds. Whitespace is ignored, and decimals take . or ,.

class WW_ZoneLayouts {
    static Presets := [["fourths", "Fourths, then halves"], ["thirds", "Thirds"],
        ["corners", "Halves and corners"], ["rows-fourths", "Rows of fourths, then halves"],
        ["rows-thirds", "Rows of thirds"]]

    static Name(id) {
        for preset in this.Presets
            if preset[1] = id
                return preset[2]
        return ""
    }

    ; The preset ID a dropdown's text names, or the text as a custom line.
    static FromText(text) {
        for preset in this.Presets
            if preset[2] = Trim(text)
                return preset[1]
        return Trim(text)
    }

    static IsPreset(layout) => this.Name(layout) != ""
}

; A custom line as pages of rows of positive part sizes. Throws a ValueError
; naming the first problem.
WW_ParseZoneLine(text)
{
    line := RegExReplace(StrReplace(text, ",", "."), "\s+")
    if line = ""
        throw ValueError("Type a layout, such as 1:1 / 1:1:1.")
    pages := []
    page_texts := StrSplit(line, ">")
    for page_index, page_text in page_texts {
        if page_text = ""
            throw ValueError((page_texts.Length > 1 ? "Page " page_index : "The layout") " is empty.")
        rows := []
        row_texts := StrSplit(page_text, "/")
        for row_index, row_text in row_texts {
            where := (page_texts.Length > 1 ? "Page " page_index ", row " : "Row ") row_index
            if row_text = ""
                throw ValueError(where " is empty.")
            parts := []
            for part in StrSplit(row_text, ":") {
                if part = ""
                    throw ValueError(where " has an empty part.")
                if !RegExMatch(part, "^(\d+(\.\d*)?|\.\d+)$") || Number(part) <= 0
                    throw ValueError(where " has " part ", which isn't a positive number.")
                parts.Push(Number(part))
            }
            rows.Push(parts)
        }
        pages.Push(rows)
    }
    return pages
}

; Each page's cells, rows top to bottom and each row left to right, or right
; to left with from_right. Rows share the height equally.
WW_BuildCustomZones(work_area, pages, from_right := false)
{
    left := work_area[1], top := work_area[2]
    width := work_area[3] - left, height := work_area[4] - top
    zones := []
    for rows in pages {
        for row_index, parts in rows {
            row_top := top + Round(height * (row_index - 1) / rows.Length)
            row_bottom := top + Round(height * row_index / rows.Length)
            total := 0
            for part in parts
                total += part
            cells := []
            sum := 0
            for part in parts {
                cell_left := left + Round(width * sum / total)
                sum += part
                cells.Push([cell_left, row_top, left + Round(width * sum / total) - cell_left,
                    row_bottom - row_top])
            }
            Loop cells.Length
                zones.Push(cells[from_right ? cells.Length - A_Index + 1 : A_Index])
        }
    }
    return zones
}

; The zones a layout gives on a work area, in cycle order.
WW_BuildLayoutZones(work_area, layout, from_right := false)
{
    switch layout {
        case "fourths", "thirds":
            return WW_BuildZoneSequence(work_area, layout, from_right)
        case "rows-fourths", "rows-thirds":
            ; Columns of the transposed work area, transposed back into rows.
            columns := WW_BuildZoneSequence([work_area[2], work_area[1], work_area[4], work_area[3]],
                SubStr(layout, 6), from_right)
            rows := []
            for zone in columns
                rows.Push([zone[2], zone[1], zone[4], zone[3]])
            return rows
        case "corners":
            return WW_BuildCustomZones(work_area, WW_ParseZoneLine("1:1 > 1:1 / 1:1"), from_right)
        default:
            return WW_BuildCustomZones(work_area, WW_ParseZoneLine(layout), from_right)
    }
}

; A display's device name and orientation key, such as \\.\DISPLAY1|portrait.
; Portrait means taller than wide.
WW_DisplayOrientationKey(monitor_handle)
{
    device := StrGet(ReadMonitorInfo(monitor_handle).Ptr + 40, 32, "UTF-16")
    bounds := MonitorRects(monitor_handle).monitor
    return device "|" (bounds[4] - bounds[2] > bounds[3] - bounds[1] ? "portrait" : "landscape")
}

; The layout a display uses now: its saved choice for its current
; orientation, or that orientation's default.
WW_DisplayZoneLayout(monitor_handle)
{
    global WW_zone_layouts
    key := WW_DisplayOrientationKey(monitor_handle)
    return WW_zone_layouts.Has(key) ? WW_zone_layouts[key] : WW_DefaultZoneLayout(key)
}

WW_DefaultZoneLayout(key)
{
    global WW_zone_landscape_default
    return InStr(key, "|portrait") ? "corners" : WW_zone_landscape_default
}

WW_StartZoneSession(hwnd, pid, work_area, layout, direction)
{
    return {hwnd: hwnd, pid: pid, work_area: work_area, layout: layout, index: 0, direction: direction,
        zones: WW_BuildLayoutZones(work_area, layout, direction = "up")}
}

WW_AdvanceZoneSession(session, direction, minimum)
{
    backwards := direction != session.direction
    session.index := WW_GetNextFittingIndex(session.index, session.zones, minimum, backwards)
    return session.index
}

WW_CycleZone(direction)
{
    global WW_zone_cycle
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := WW_GetLayoutWorkArea(hwnd)
        layout := WW_DisplayZoneLayout(WindowMonitor(hwnd))
        pid := WinGetPID(hwnd)
        session := WW_zone_cycle
        if !IsObject(session) || session.hwnd != hwnd || session.pid != pid || session.layout != layout
            || !WW_RectanglesMatch(session.work_area, work_area, 0) {
            session := WW_StartZoneSession(hwnd, pid, work_area, layout, direction)
            WW_zone_cycle := session
            SetTimer(WW_WatchZoneCycleRelease, 50)
        }
        index := WW_AdvanceZoneSession(session, direction, WW_GetMinimumVisibleSize(hwnd))
        WW_ApplyTrackedLayout(hwnd, "zones", work_area, session.zones, index)
    }
    catch Error as err {
        WW_DebugError("Cycle zones", err)
    }
}

; Zone mode: while Win is still held after Win + Left/Right or scroll, Win +
; Up and Down move to the zone directly above or below in the same layout,
; and the walk goes on from there; otherwise they maximize and restore.
WW_ZoneStepOr(direction, fallback)
{
    if !WW_StepZoneVertically(direction)
        fallback()
}

; True while a zone session holds the active window, even when nothing lies
; that way, so the key never falls through to maximize mid-walk.
WW_StepZoneVertically(direction)
{
    global WW_zone_cycle
    Critical "On"
    session := WW_zone_cycle
    if !IsObject(session) || !session.index
        return false
    hwnd := WW_GetWindowControlTarget()
    try {
        if hwnd != session.hwnd || WinGetPID(hwnd) != session.pid
            || !WW_RectanglesMatch(session.work_area, WW_GetLayoutWorkArea(hwnd), 0)
            return false
        index := WW_VerticalZoneIndex(session.zones, session.index, direction, WW_GetMinimumVisibleSize(hwnd))
        if index {
            session.index := index
            WW_ApplyTrackedLayout(hwnd, "zones", session.work_area, session.zones, index)
        }
    }
    catch Error as err {
        WW_DebugError("Step zone vertically", err)
    }
    return true
}

; The zone nearest above ("up") or below ("down") zones[current] whose span
; overlaps it side to side: its top or bottom half from full height, and full
; height from a half. Ties go to the closest match in width, then the walk's
; order. 0 when none fits.
WW_VerticalZoneIndex(zones, current, direction, minimum := 0)
{
    zone := zones[current]
    center := zone[2] + zone[4] / 2
    best := 0, best_distance := 0, best_match := 0
    for index, other in zones {
        if index = current || IsObject(minimum) && !WW_LayoutFitsMinimum(other, minimum)
            continue
        overlap := Min(zone[1] + zone[3], other[1] + other[3]) - Max(zone[1], other[1])
        distance := direction = "up" ? center - (other[2] + other[4] / 2) : other[2] + other[4] / 2 - center
        if overlap <= 0 || distance <= 0
            continue
        match := overlap / (Max(zone[1] + zone[3], other[1] + other[3]) - Min(zone[1], other[1]))
        if !best || distance < best_distance - 0.5
            || Abs(distance - best_distance) <= 0.5 && match > best_match
            best := index, best_distance := distance, best_match := match
    }
    return best
}

WW_ModifiersReleased()
{
    for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]
        if GetKeyState(key, "P")
            return false
    return true
}

WW_WatchZoneCycleRelease()
{
    if WW_ModifiersReleased()
        WW_EndZoneCycle()
}

WW_EndZoneCycle()
{
    global WW_zone_cycle
    WW_zone_cycle := 0
    SetTimer(WW_WatchZoneCycleRelease, 0)
}
