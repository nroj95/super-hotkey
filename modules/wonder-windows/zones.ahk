; Wonder Windows implementation. Launch the suite, not this file.

; =============================================================================
; zone cycling
; =============================================================================
; A session walks one zone sequence while any modifier stays held. The first
; key picks the walk: from the left, or its mirror image from the right. The
; other key steps back. Releasing every modifier starts the next session over.

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

WW_StartZoneSession(hwnd, pid, work_area, unit, direction)
{
    from_right := direction = "up"
    return {hwnd: hwnd, pid: pid, work_area: work_area, index: 0, from_right: from_right,
        zones: WW_BuildZoneSequence(work_area, unit, from_right)}
}

; The key that started the session steps forward; the other one steps back.
WW_AdvanceZoneSession(session, direction, minimum)
{
    backwards := (direction = "up") != session.from_right
    session.index := WW_GetNextFittingIndex(session.index, session.zones, minimum, backwards)
    return session.index
}

WW_CycleZone(direction)
{
    global WW_zone_cycle, WW_zone_cycle_unit
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return

    try {
        work_area := WW_GetLayoutWorkArea(hwnd)
        pid := WinGetPID(hwnd)
        session := WW_zone_cycle
        if !IsObject(session) || session.hwnd != hwnd || session.pid != pid
            || !WW_RectanglesMatch(session.work_area, work_area, 0) {
            session := WW_StartZoneSession(hwnd, pid, work_area, WW_zone_cycle_unit, direction)
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
