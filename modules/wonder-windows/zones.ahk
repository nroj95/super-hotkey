; Wonder Windows zone cycling and the zone layouts each display uses.

; =============================================================================
; zone cycling
; =============================================================================
; A session walks one zone sequence while any modifier stays held. The first
; zone is on the side the key names: down/Left walks from the left fourth,
; up/Right walks the mirror image from the right fourth. The key that started
; the session keeps going; the other one steps back, wrapping to the last zone.
; Releasing every modifier starts the next session over. The plain keys walk
; the zones that span the full height; while a walk runs, their Shift twins
; walk the split ones page by page, each page's rows top to bottom, whichever
; way the keys go along a row. Shift with the key that started the walk
; enters the top row at the column the window is in, and with the other key
; the bottom row; the key that entered walks on, and the other one retraces.

; Zone groups, each left to right as left space : width : right space.
WW_GetZoneGroups(unit)
{
    switch unit {
        case "fourths":
            return [[[0, 1, 3], [1, 1, 2], [2, 1, 1], [3, 1, 0]], [[0, 2, 2], [1, 2, 1], [2, 2, 0]]]
        case "thirds":
            return [[[0, 1, 2], [1, 1, 1], [2, 1, 0]], [[0, 2, 1], [1, 2, 0]]]
        case "sixths":
            return [[[0, 1, 5], [1, 1, 4], [2, 1, 3], [3, 1, 2], [4, 1, 1], [5, 1, 0]],
                [[0, 2, 4], [2, 2, 2], [4, 2, 0]]]
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
; A layout is a preset ID or a custom line. Presets walk columns: corners is
; the halves (its ID from when it was named Halves and corners), thirds adds
; the two-thirds, fourths the halves and sixths the thirds, each then split
; in upper and lower halves. On a portrait display a preset is turned 90
; degrees, so Left starts at the top and Right at the bottom. A custom line
; lists pages separated by > ("and then"), rows by / and the parts of a row
; by :, as relative sizes: 1:1 / 1:1:1 is halves over thirds. Whitespace is
; ignored, and decimals take . or ,. Custom lines are never turned.

class WW_ZoneLayouts {
    static Presets := [["corners", "Halves"], ["thirds", "Thirds, then two-thirds"],
        ["fourths", "Fourths, then halves"], ["sixths", "Sixths, then thirds"]]
    ; What a portrait list offers; fourths and sixths make bands too short.
    static Portrait := ["corners", "thirds"]

    ; The preset IDs a landscape or portrait list offers, in order.
    static Offered(orientation) {
        if orientation = "portrait"
            return this.Portrait
        ids := []
        for preset in this.Presets
            ids.Push(preset[1])
        return ids
    }

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

; The zones a layout gives on a work area, in cycle order. On a portrait
; work area a preset is turned 90 degrees: the columns of the transposed
; area, transposed back into bands.
WW_BuildLayoutZones(work_area, layout, from_right := false)
{
    if !WW_ZoneLayouts.IsPreset(layout)
        return WW_BuildCustomZones(work_area, WW_ParseZoneLine(layout), from_right)
    if !WW_IsTurnedLayout(work_area, layout)
        return WW_BuildPresetZones(work_area, layout, from_right)
    bands := []
    for zone in WW_BuildPresetZones([work_area[2], work_area[1], work_area[4], work_area[3]], layout, from_right)
        bands.Push([zone[2], zone[1], zone[4], zone[3]])
    return bands
}

WW_BuildPresetZones(work_area, layout, from_right)
{
    if layout = "corners"
        return WW_BuildCustomZones(work_area, WW_ParseZoneLine("1:1 > 1:1 / 1:1"), from_right)
    return WW_BuildZoneSequence(work_area, layout, from_right)
}

; Whether a layout is a preset turned for a portrait work area.
WW_IsTurnedLayout(work_area, layout)
{
    return WW_ZoneLayouts.IsPreset(layout) && work_area[4] - work_area[2] > work_area[3] - work_area[1]
}

; A saved layout that is a preset or a custom line that still reads.
WW_IsUsableZoneLayout(layout)
{
    if WW_ZoneLayouts.IsPreset(layout)
        return true
    try return !!WW_ParseZoneLine(layout).Length
    return false
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
; orientation, or its default.
WW_DisplayZoneLayout(monitor_handle)
{
    global WW_zone_layouts
    key := WW_DisplayOrientationKey(monitor_handle)
    if WW_zone_layouts.Has(key) && WW_IsUsableZoneLayout(WW_zone_layouts[key])
        return WW_zone_layouts[key]
    return WW_DefaultZoneLayout(key, WW_MonitorLogicalSize(monitor_handle))
}

; The layout a display left on its default uses in an orientation (from its
; device|orientation key), by its size in logical pixels, Windows' scaling
; undone. size is [width, height] when known; otherwise the device is
; looked up. legacy honours Cycle=thirds from earlier versions in landscape.
WW_DefaultZoneLayout(key, size := 0, legacy := true)
{
    global WW_zone_landscape_default
    portrait := InStr(key, "|portrait")
    if legacy && !portrait && WW_zone_landscape_default != ""
        return WW_zone_landscape_default
    if !IsObject(size)
        size := WW_DeviceLogicalSize(SubStr(key, 1, InStr(key, "|", , -1) - 1))
    if !IsObject(size)
        return portrait ? "thirds" : "fourths"
    long := Max(size[1], size[2]), short := Min(size[1], size[2])
    return portrait ? WW_SizeDefaultZoneLayout(short, long) : WW_SizeDefaultZoneLayout(long, short)
}

; The default for a display of width x height logical pixels. Height is
; scarcer than width, since most content scrolls down, so portrait gets
; thirds only from 2400 px tall.
WW_SizeDefaultZoneLayout(width, height)
{
    if height > width
        return height < 2400 ? "corners" : "thirds"
    return width < 1700 ? "corners" : width < 2400 ? "thirds" : width < 4400 ? "fourths" : "sixths"
}

; A display's [width, height] in logical pixels, from a handle or a device
; name; 0 when the device is gone.
WW_MonitorLogicalSize(monitor_handle)
{
    bounds := CallWithDpiContext(-3, MonitorRects, monitor_handle).monitor
    dpi := WW_MonitorDpi(monitor_handle)
    return [(bounds[3] - bounds[1]) * 96 / dpi, (bounds[4] - bounds[2]) * 96 / dpi]
}

WW_DeviceLogicalSize(device)
{
    loop MonitorGetCount() {
        if MonitorGetName(A_Index) != device
            continue
        MonitorGetPixels(A_Index, &left, &top, &right, &bottom)
        point := ((left + right) // 2 & 0xFFFFFFFF) | ((top + bottom) // 2 << 32)
        try return WW_MonitorLogicalSize(PhysicalDllCall("MonitorFromPoint", "int64", point, "uint", 2, "ptr"))
    }
    return 0
}

WW_MonitorDpi(monitor_handle)
{
    dpi_x := 96, dpi_y := 96
    try PhysicalDllCall("shcore\GetDpiForMonitor", "ptr", monitor_handle, "int", 0, "uint*", &dpi_x, "uint*", &dpi_y)
    return dpi_x || 96
}

WW_StartZoneSession(hwnd, pid, work_area, layout, direction)
{
    turned := WW_IsTurnedLayout(work_area, layout)
    walks := WW_SplitZoneWalks(WW_BuildLayoutZones(work_area, layout, direction = "up"), work_area, turned)
    return {hwnd: hwnd, pid: pid, work_area: work_area, layout: layout, turned: turned, index: 0,
        direction: direction,
        main: walks.main, split: walks.split, back: walks.back, splitting: false, split_direction: direction,
        zones: walks.main}
}

; A layout's zones as walks. main holds the zones that span the work area's
; full height, or its full width for rows, in the layout's order; every zone
; when none does. split holds the rest in the layout's order: page by page,
; such as the fourths, then the halves, each page's rows top to bottom.
; back is the order for a split walk entered with the other key: the pages
; in reverse, but still each page's rows top to bottom, each row read
; backwards, the way a line of text is followed by the one below whichever
; way you read it.
WW_SplitZoneWalks(zones, work_area, rows := false, tolerance := 2)
{
    ; Rows are columns turned: compare widths and left edges instead.
    along := rows ? 1 : 2
    full := work_area[along + 2] - work_area[along]
    main := [], split := []
    for zone in zones
        (Abs(zone[along + 2] - full) <= tolerance ? main : split).Push(zone)
    ; A row is a run of zones on one edge; a page starts where the edge
    ; goes back up, since each page lists its rows top to bottom.
    pages := []
    for zone in split {
        if !pages.Length || zone[along] < previous - tolerance
            pages.Push([[]])
        else if Abs(zone[along] - previous) > tolerance
            pages[pages.Length].Push([])
        page := pages[pages.Length]
        page[page.Length].Push(zone)
        previous := zone[along]
    }
    back := []
    loop pages.Length
        for row in pages[pages.Length - A_Index + 1]
            loop row.Length
                back.Push(row[row.Length - A_Index + 1])
    return {main: main.Length ? main : zones, split: split, back: back}
}

; Whether two [x, y, width, height] zones cover the same span across the
; walk: the same left and right edges, or top and bottom ones for rows.
WW_SameSpan(first, second, across, tolerance := 2)
{
    return Abs(first[across] - second[across]) <= tolerance
        && Abs(first[across] + first[across + 2] - second[across] - second[across + 2]) <= tolerance
}

; The key that started the walk goes forward; the other steps back and
; retraces it. In the split walk, the key that entered it goes forward.
WW_AdvanceZoneSession(session, direction, minimum)
{
    backwards := direction != (session.splitting ? session.split_direction : session.direction)
    session.index := WW_GetNextFittingIndex(session.index, session.zones, minimum, backwards)
    return session.index
}

; Switching between the walks keeps the column. The key that started the
; walk enters the split walk at the column's top and walks it in the layout's
; order; the other key (backwards) enters at its bottom and walks the back
; order. Either way the entering key goes on in that order and the other key
; retraces it. The main walk returns to the full zone over the column.
; Returns the index to show, 0 when the other walk has nothing there.
WW_SwitchZoneWalk(session, split, minimum, direction)
{
    current := session.index ? session.zones[session.index] : 0
    across := session.turned ? 2 : 1
    backwards := direction != session.direction
    session.splitting := split
    session.split_direction := direction
    session.zones := !split ? session.main : backwards ? session.back : session.split
    session.index := 0
    if !IsObject(current)
        return 0
    entered := 0
    for zone in split ? session.split : session.main
        if WW_SameSpan(current, zone, across) && WW_LayoutFitsMinimum(zone, minimum) {
            entered := zone
            if !split || !backwards
                break
        }
    for index, zone in session.zones
        if zone = entered
            session.index := index
    return session.index
}

; Win + Left/Right and scroll walk the full-height zones; their Shift twins
; walk the split zones, only while a walk runs (the zone-cycling scope).
WW_CycleZone(direction, split := false)
{
    global WW_zone_cycle
    Critical "On"
    if split && !IsObject(WW_zone_cycle)
        return
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
            if split
                return
            session := WW_StartZoneSession(hwnd, pid, work_area, layout, direction)
            WW_zone_cycle := session
            SetTimer(WW_WatchZoneCycleRelease, 50)
        }
        minimum := WW_GetMinimumVisibleSize(hwnd)
        if split != session.splitting && WW_SwitchZoneWalk(session, split, minimum, direction)
            index := session.index
        else if session.zones.Length
            index := WW_AdvanceZoneSession(session, direction, minimum)
        else
            return
        WW_ApplyTrackedLayout(hwnd, "zones", work_area, session.zones, index)
    }
    catch Error as err {
        WW_DebugError("Cycle zones", err)
    }
}

; The zone-cycling input scope: true while a walk runs, so the split walk's
; Win + Shift + Left/Right reach Windows the rest of the time.
WW_IsCyclingZones(*)
{
    global WW_zone_cycle
    return IsObject(WW_zone_cycle)
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
