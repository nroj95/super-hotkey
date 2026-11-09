; Wonder Windows zone mode.

; =============================================================================
; zone mode
; =============================================================================
; Win + Left or Right starts zone mode, which lasts while any modifier stays
; held. Like Windows, it puts the window against that side, but at its own
; width, or the closest zone width when it is not on a stop; its height stays
; when it is on the grid, otherwise it snaps to the closest one at the place
; overlapping it most. A maximized, fullscreen or full-width window becomes
; that half, as in Windows. In zone mode the window is a span of the work area, kept as fractions
; [x0, x1] and [y0, y1], and it sits only where both its edges land on stops:
; halves, and the pairs Settings turns on for that side of the display, long or
; short, by default fourths and thirds. So a half sits left, in the middle or
; right, a third left, middle or right, and windows always fit together.
; - Left and Right slide it to the next place for its size. Past the side,
;   they move it to the next display that way, onto the facing side, wrapping
;   from the last display to the first, as Windows does.
; - Up and Down split a full-height window into its top or bottom half, as
;   Windows does, then slide it the same way. Past the top or bottom, they
;   move it to a display touching that edge, onto its facing side; there is
;   no wrapping, so with displays side by side nothing happens.
; - Shift + an arrow makes it one size bigger or smaller and snaps it into the
;   place for that size that overlaps it most, ties going toward the arrow.
;   Toward a side it hugs it shrinks, away from it it grows; a window as wide
;   or tall as the display shrinks toward the arrow; one in the middle grows.
;   Grown to the whole work area it is maximized, and shrinking restores it.
; Plain arrows move and Shift arrows resize. Up, Down and the Shift arrows
; answer only in zone mode (the zone-cycling scope), so outside it Win + Up and
; Down maximize and restore, Win + Shift + Up and Down toggle full height and
; width, and Windows keeps Win + Shift + Left and Right.

; Where an edge may stop along the display's long or short side, as a
; fraction of the work area, from the pairs Settings turns on.
WW_ZoneLadder(long := true)
{
    global WW_zone_stops
    stops := WW_zone_stops[long ? "long" : "short"]
    return WW_BuildZoneLadder(stops["sixths"], stops["fourths"], stops["thirds"])
}

; A ladder with halves and full, and each pair that is on: sixths (1/6 and
; 5/6), fourths (1/4 and 3/4) and thirds (1/3 and 2/3). Pairs keep it
; symmetric, so windows on either side always fit together.
WW_BuildZoneLadder(sixths, fourths, thirds)
{
    low := [], high := []
    for pair in [[sixths, 1/6], [fourths, 1/4], [thirds, 1/3]]
        if pair[1]
            low.Push(pair[2]), high.InsertAt(1, 1 - pair[2])
    ladder := [0]
    ladder.Push(low*)
    ladder.Push(1 / 2)
    ladder.Push(high*)
    ladder.Push(1)
    return ladder
}

; Win + Left or Right: zone mode from the window's own size, then a step
; sideways.
WW_ZoneSide(side)
{
    global WW_zone_cycle
    Critical "On"
    hwnd := WW_GetPlacementTarget(&fresh_entry)
    if !hwnd
        return
    try {
        session := WW_CurrentZoneSession(hwnd)
        if !IsObject(session) {
            session := {hwnd: hwnd, pid: WinGetPID(hwnd), work_area: WW_GetLayoutWorkArea(hwnd),
                x0: side = "left" ? 0 : 1 / 2, x1: side = "left" ? 1 / 2 : 1, y0: 0, y1: 1}
            WW_zone_cycle := session
            SetTimer(WW_WatchZoneCycleRelease, 50)
            ; A maximized or fullscreen window was just restored: it starts at
            ; a half, as in Windows. Any other starts from its own size.
            if !fresh_entry {
                start := WW_ZoneStart(WW_GetWindowLayoutRectangle(hwnd), session.work_area, side,
                    WW_ZoneAxisLadder(session, false), WW_ZoneAxisLadder(session, true))
                session.x0 := start.x[1], session.x1 := start.x[2]
                session.y0 := start.y[1], session.y1 := start.y[2]
            }
            WW_ApplyZoneSession(session)
            return
        }
        width := session.x1 - session.x0
        left_edge := WW_ZoneSlide(session.x0, width, side, WW_ZoneAxisLadder(session, false))
        if left_edge = "" {
            ; Past the side: on to the next display that way, as Windows does,
            ; onto its facing side, wrapping at the last display.
            lefts := []
            loop MonitorGetCount() {
                MonitorGetPixels(A_Index, &left)
                lefts.Push(left)
            }
            target := WW_NeighborDisplay(WindowMonitorIndex(hwnd), side, lefts)
            if !target
                return
            MonitorGetWorkAreaPixels(target, &left, &top, &right, &bottom)
            session.work_area := [left, top, right, bottom]
            left_edge := side = "left" ? 1 - width : 0
        }
        session.x0 := left_edge, session.x1 := left_edge + width
        WW_ApplyZoneSession(session)
    }
    catch Error as err
        WW_DebugError("Zone side", err)
}

; Where zone mode starts for a window at rect ([x, y, width, height]) on area
; ([left, top, right, bottom]) when Win + side starts it: {x, y}, each span as
; fractions of the area. The width snaps to the closest size, its own when it
; is on a stop, against that side, a full width becoming a half. The height
; stays when it is on the grid, its size and place on the stops within a few
; pixels, and otherwise snaps to the closest size at the place overlapping it
; most.
WW_ZoneStart(rect, area, side, across, down)
{
    width := area[3] - area[1], height := area[4] - area[2]
    x := [(rect[1] - area[1]) / width, (rect[1] + rect[3] - area[1]) / width]
    y := [(rect[2] - area[2]) / height, (rect[2] + rect[4] - area[2]) / height]
    size := WW_ClosestZoneSize(x[2] - x[1], across)
    if size >= 0.999
        size := 1 / 2
    x := side = "left" ? [0, size] : [1 - size, 1]
    rows := WW_ZoneGridSpan(y, down, 8 / height)
    if !IsObject(rows) {
        size := WW_ClosestZoneSize(y[2] - y[1], down)
        best := 0, best_overlap := -1
        for place in WW_ZonePlaces(size, down) {
            overlap := Min(y[2], place + size) - Max(y[1], place)
            if overlap > best_overlap + 0.0001
                best := place, best_overlap := overlap
        }
        rows := [best, best + size]
    }
    return {x: x, y: rows}
}

; The grid span a span already sits on: a size on the ladder at one of its
; places, both within tolerance. 0 when it is off the grid.
WW_ZoneGridSpan(span, ladder, tolerance)
{
    for size in ladder {
        if size <= 0 || Abs(size - (span[2] - span[1])) > tolerance * 2
            continue
        for place in WW_ZonePlaces(size, ladder)
            if Abs(place - span[1]) <= tolerance
                return [place, place + size]
    }
    return 0
}

; The ladder size nearest size, never 0.
WW_ClosestZoneSize(size, ladder)
{
    best := 1
    for stop in ladder
        if stop > 0 && Abs(stop - size) < Abs(best - size)
            best := stop
    return best
}

; The ladder along one of the session display's sides: its long side's
; stops or its short side's.
WW_ZoneAxisLadder(session, vertical)
{
    area := session.work_area
    return WW_ZoneLadder(vertical != (area[3] - area[1] >= area[4] - area[2]))
}

; Where a span of size may start: every stop from which it also ends on a
; stop. A size off the ladder, as after Settings drop a pair, steps by its
; own size instead, the last place lining up with the far side.
WW_ZonePlaces(size, ladder)
{
    places := []
    for stop in ladder
        for other in ladder
            if Abs(stop + size - other) < 0.001 && stop + size <= 1.001
                places.Push(stop)
    if places.Length
        return places
    position := 0
    while position <= 1 - size + 0.001 {
        places.Push(position)
        position += size
    }
    if Abs(places[places.Length] - (1 - size)) > 0.001
        places.Push(1 - size)
    return places
}

; The start a span at start, size long, slides to one place that way: left
; or up ("left") or right or down. "" when it already hugs that side.
WW_ZoneSlide(start, size, side, ladder := WW_ZoneLadder())
{
    places := WW_ZonePlaces(size, ladder)
    loop places.Length {
        place := places[side = "left" ? places.Length - A_Index + 1 : A_Index]
        if side = "left" ? place < start - 0.001 : place > start + 0.001
            return place
    }
    return ""
}

; The display next to monitor on that side (an index into lefts, each
; display's left edge), wrapping from the last to the first; 0 with one.
WW_NeighborDisplay(monitor, side, lefts)
{
    order := WW_DisplayOrderFrom(monitor, lefts)
    if order.Length < 2
        return 0
    return side = "right" ? order[2] : order[order.Length]
}

; Win + Up or Down in zone mode: a half from full height, then a slide.
WW_ZoneRow(direction)
{
    Critical "On"
    session := WW_CurrentZoneSession(WW_GetWindowControlTarget())
    if !IsObject(session)
        return
    try {
        span := WW_ZoneRowSpan([session.y0, session.y1], direction, WW_ZoneAxisLadder(session, true))
        if !IsObject(span) {
            ; Past the top or bottom: on to a display touching that edge, onto
            ; its facing side; with none there, nothing happens.
            rect := WW_ZoneSessionRectangle(session)
            displays := []
            loop MonitorGetCount() {
                MonitorGetPixels(A_Index, &left, &top, &right, &bottom)
                displays.Push([left, top, right, bottom])
            }
            target := WW_VerticalNeighborDisplay(WindowMonitorIndex(session.hwnd), displays,
                rect[1], rect[1] + rect[3], direction)
            if !target
                return
            MonitorGetWorkAreaPixels(target, &left, &top, &right, &bottom)
            session.work_area := [left, top, right, bottom]
            height := session.y1 - session.y0
            span := direction = "up" ? [1 - height, 1] : [0, height]
        }
        session.y0 := span[1], session.y1 := span[2]
        WW_ApplyZoneSession(session)
    }
    catch Error as err
        WW_DebugError("Zone row", err)
}

; The display above ("up") or below monitor (indexes into displays, each
; [left, top, right, bottom]) that touches its edge and overlaps the window's
; columns, from left to right, the most; 0 when there is none. Never wraps.
WW_VerticalNeighborDisplay(monitor, displays, left, right, direction)
{
    if !monitor || monitor > displays.Length
        return 0
    current := displays[monitor]
    best := 0, best_overlap := 0
    for index, display in displays {
        if index = monitor
            continue
        touches := direction = "up" ? Abs(display[4] - current[2]) <= 2 : Abs(display[2] - current[4]) <= 2
        overlap := Min(right, display[3]) - Max(left, display[1])
        if touches && overlap > best_overlap
            best := index, best_overlap := overlap
    }
    return best
}

; A vertical span after Up ("up") or Down: full height splits into the top or
; bottom half, and anything shorter slides to its next place. 0 when it
; already hugs that edge.
WW_ZoneRowSpan(span, direction, ladder := WW_ZoneLadder())
{
    if span[1] <= 0.001 && span[2] >= 0.999
        return direction = "up" ? [0, 1 / 2] : [1 / 2, 1]
    height := span[2] - span[1]
    top := WW_ZoneSlide(span[1], height, direction = "up" ? "left" : "right", ladder)
    return top = "" ? 0 : [top, top + height]
}

; Win + Shift + an arrow in zone mode: one size bigger or smaller.
WW_ZoneEdge(direction)
{
    Critical "On"
    session := WW_CurrentZoneSession(WW_GetWindowControlTarget())
    if !IsObject(session)
        return
    try {
        vertical := direction = "up" || direction = "down"
        toward_start := direction = "left" || direction = "up"
        span := WW_ZoneEdgeSpan(vertical ? [session.y0, session.y1] : [session.x0, session.x1], toward_start,
            WW_ZoneAxisLadder(session, vertical))
        if !IsObject(span)
            return
        if vertical
            session.y0 := span[1], session.y1 := span[2]
        else
            session.x0 := span[1], session.x1 := span[2]
        WW_ApplyZoneSession(session)
    }
    catch Error as err
        WW_DebugError("Zone edge", err)
}

; A span [start, end] one size bigger or smaller after Shift with an arrow
; toward the start (left or up) or the end, snapped into the place for its new
; size that overlaps it most, ties going toward the arrow. Hugging one side,
; the arrow toward it shrinks and the other grows; spanning both, it shrinks;
; in the middle, it grows. 0 when no size is left that way.
WW_ZoneEdgeSpan(span, toward_start, ladder := WW_ZoneLadder())
{
    at_start := span[1] <= 0.001, at_end := span[2] >= 0.999
    grows := at_start && at_end ? false : at_start ? !toward_start : at_end ? toward_start : true
    size := WW_ZoneLadderStep(span[2] - span[1], !grows, ladder)
    if size = "" || size <= 0.001
        return 0
    best := "", best_overlap := -1
    for place in WW_ZonePlaces(size, ladder) {
        overlap := Min(span[2], place + size) - Max(span[1], place)
        ; Places come left to right: a tie keeps the first toward the start,
        ; or moves on to the last toward the end.
        if overlap > best_overlap + 0.0001 || !toward_start && Abs(overlap - best_overlap) <= 0.0001
            best := place, best_overlap := overlap
    }
    return [best, best + size]
}

; The next ladder value below (down) or above a value, or "".
WW_ZoneLadderStep(value, down, ladder)
{
    loop ladder.Length {
        step := ladder[down ? ladder.Length - A_Index + 1 : A_Index]
        if down ? step < value - 0.001 : step > value + 0.001
            return step
    }
    return ""
}

; The running session for hwnd, or 0 when there is none or it no longer fits.
WW_CurrentZoneSession(hwnd)
{
    global WW_zone_cycle
    session := WW_zone_cycle
    if !hwnd || !IsObject(session) || session.hwnd != hwnd
        return 0
    try {
        if WinGetPID(hwnd) = session.pid && WW_RectanglesMatch(session.work_area, WW_GetLayoutWorkArea(hwnd), 0)
            return session
    }
    return 0
}

; The session's span as a rectangle on its work area.
WW_ZoneSessionRectangle(session)
{
    area := session.work_area
    width := area[3] - area[1], height := area[4] - area[2]
    left := area[1] + Round(width * session.x0), top := area[2] + Round(height * session.y0)
    return [left, top, area[1] + Round(width * session.x1) - left, area[2] + Round(height * session.y1) - top]
}

; Places the window on its span. A span covering the whole work area makes it
; truly maximized, so stacks, the big-window cycle, the focus outline and
; cascades treat it as one; a smaller span un-maximizes it first.
WW_ApplyZoneSession(session)
{
    hwnd := session.hwnd
    full := session.x0 <= 0.001 && session.x1 >= 0.999 && session.y0 <= 0.001 && session.y1 >= 0.999
    if WinGetMinMax(hwnd) = 1 {
        if full && WW_RectanglesMatch(session.work_area, WW_GetLayoutWorkArea(hwnd), 0)
            return
        WinRestore(hwnd)
    }
    ; Move first, so a window maximizes on the display its span is on.
    WW_ApplyTrackedLayout(hwnd, "zones", session.work_area, [WW_ZoneSessionRectangle(session)], 1)
    if full {
        WW_ForgetWindowLayoutCycle(hwnd)
        WinMaximize(hwnd)
    }
}

; The zone-cycling input scope: true while zone mode runs.
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
