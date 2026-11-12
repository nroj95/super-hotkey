; Wonder Windows: geometry, ownership, tiles, stacking, stack and expanded-window
; cycling, fullscreen detection, and Win + M, Win + Home and Win + D with their restore.
; Disposable preferences, dry-run inputs and test-owned windows only.
class WonderWindowsChecks {
    static Run() {
        this.GeometryAndOwnership()
        this.OversizedTile()
        this.MoveOntoZone()
        this.FullscreenDetection()
        this.ExpandedWindowCycle()
        this.MonitorWindowCycle()
        this.MinimizeAll()
        this.NormalSizeAndResize()
        this.ZoneMode()
        this.RefusedZoneSize()
        this.LooseAxisSnaps()
    }

    ; A half-height window between the rows, resized with Win + Shift + Right:
    ; Win + Up snaps it to the top half even with no step left above.
    static LooseAxisSnaps() {
        window := SuiteGui("+Resize -DPIScale", "Loose axis check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w400 h300")
            hwnd := window.Hwnd
            area := WW_GetLayoutWorkArea(hwnd)
            height := area[4] - area[2]
            WW_MoveWindowToVisibleRectangle(hwnd, [area[1] + 200, area[2] + Round(height * 0.22), 400, Round(height / 2)])
            ActivateWindow(hwnd)
            WW_EndZoneCycle()
            WW_ZoneEdge("right")
            WW_ZoneRow("up")
            rect := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(rect[2] - area[2]) <= 3 && Abs(rect[4] - height / 2) <= 3,
                "Win + Up after a Win + Shift resize snaps a window between the rows to the top half")
        }
        finally {
            WW_EndZoneCycle()
            window.Destroy()
        }
    }

    ; An app wider than a third at its minimum, as Steam is, steps by the
    ; width it really has, never by thirds or fourths it can't fit.
    static RefusedZoneSize() {
        window := SuiteGui("+Resize -DPIScale", "Refused zone size check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w300 h300")
            hwnd := window.Hwnd
            area := WW_GetLayoutWorkArea(hwnd)
            width := area[3] - area[1]
            window.Opt("+MinSize" Round(width * 0.4) "x")
            window.Move(, , Round(width * 0.4))
            ActivateWindow(hwnd)
            WW_EndZoneCycle()
            WW_ZoneSide("left")
            first := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(first[1] - area[1]) <= 2 && first[3] > width / 3 + 8,
                "a window too wide for a third stays wider, against the left")
            WW_ZoneEdge("left")
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), first, 3),
                "Win + Shift + Left on it changes nothing")
            WW_ZoneSide("right")
            this.Assert(Abs(WW_GetWindowLayoutRectangle(hwnd)[1] - (area[1] + first[3])) <= 3,
                "Right steps it by its own width, not by a third or a fourth")
            WW_ZoneSide("right")
            last := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(last[1] + last[3] - area[3]) <= 3 && Abs(last[3] - first[3]) <= 3,
                "and the next Right puts it flush with the right side")
        }
        finally {
            WW_EndZoneCycle()
            window.Destroy()
        }
    }

    ; Zone mode: Win + Left/Right give a half, then while it runs Left/Right
    ; flip sides, Up/Down step through Windows' quarters and the Shift arrows
    ; move the free edge along one ladder.
    static ZoneMode() {
        SpanIs(span, first, last) => IsObject(span) && Abs(span[1] - first) < 0.001 && Abs(span[2] - last) < 0.001
        this.Assert(SpanIs(WW_ZoneRowSpan([0, 1], "down"), 0.5, 1) && SpanIs(WW_ZoneRowSpan([0, 1], "up"), 0, 0.5)
            && SpanIs(WW_ZoneRowSpan([0.5, 1], "up"), 0.25, 0.75) && SpanIs(WW_ZoneRowSpan([0.25, 0.75], "up"), 0, 0.5)
            && !WW_ZoneRowSpan([0, 0.5], "up") && !WW_ZoneRowSpan([0.5, 1], "down"),
            "Up and Down split a full-height window into a half, then slide it through bottom, middle and top")
        this.Assert(SpanIs(WW_ZoneRowSpan([0, 1 / 3], "down"), 0.3333, 0.6667)
            && SpanIs(WW_ZoneRowSpan([1 / 3, 2 / 3], "down"), 0.6667, 1),
            "a third slides through the top, middle and bottom rows")
        this.Assert(SpanIs(WW_ZoneEdgeSpan([0, 0.5], true), 0, 0.3333) && SpanIs(WW_ZoneEdgeSpan([0, 0.5], false), 0, 0.6667)
            && SpanIs(WW_ZoneEdgeSpan([0.5, 1], false), 0.6667, 1) && SpanIs(WW_ZoneEdgeSpan([0.5, 1], true), 0.3333, 1),
            "Shift moves the free edge, shrinking toward the side the window hugs and growing away from it")
        fine := WW_BuildZoneLadder(true, true, true)
        this.Assert(SpanIs(WW_ZoneEdgeSpan([0, 1 / 6], false, fine), 0, 0.25) && !WW_ZoneEdgeSpan([0, 1 / 6], true, fine)
            && SpanIs(WW_ZoneEdgeSpan([0, 5 / 6], false, fine), 0, 1),
            "with sixths on, the ladder runs from a sixth to full, without fifths")
        short := WW_ZoneLadder(false)
        this.Assert(SpanIs(WW_ZoneEdgeSpan([0, 1 / 2], false, short), 0, 0.6667)
            && SpanIs(WW_ZoneEdgeSpan([0, 2 / 3], false, short), 0, 1) && !WW_ZoneEdgeSpan([0, 1 / 3], true, short),
            "the short side's ladder runs from a third to full, so a half grows to full in two steps")
        halves := ""
        for place in WW_ZonePlaces(1 / 2, short)
            halves .= Round(place * 12) " "
        this.Assert(halves = "0 6 ", "along the short side a half sits at the top or bottom, never in between")
        Ladder(sixths, fourths, thirds) {
            text := ""
            for stop in WW_BuildZoneLadder(sixths, fourths, thirds)
                text .= Round(stop * 12) " "
            return text
        }
        this.Assert(Ladder(true, true, true) = "0 2 3 4 6 8 9 10 12 " && Ladder(false, false, true) = "0 4 6 8 12 "
            && Ladder(false, false, false) = "0 6 12 ",
            "each stop pair that is on adds both its stops, keeping halves and full")
        this.Assert(SpanIs(WW_ZoneEdgeSpan([0, 1], true, fine), 0, 0.8333) && SpanIs(WW_ZoneEdgeSpan([0, 1], false, fine), 0.1667, 1),
            "a full span moves whichever edge can go that way")
        this.Assert(SpanIs(WW_ZoneEdgeSpan(WW_ZoneEdgeSpan([0, 0.5], true), true), 0, 0.25),
            "each press steps one rung: a half, a third, a fourth")
        this.Assert(SpanIs(WW_ZoneEdgeSpan([1 / 3, 2 / 3], true), 0.25, 0.75)
            && SpanIs(WW_ZoneEdgeSpan([1 / 3, 2 / 3], false), 0.25, 0.75),
            "a middle third grows to the middle half, the place overlapping it most")
        this.Assert(SpanIs(WW_ZoneEdgeSpan([0.25, 0.75], true), 0, 0.6667)
            && SpanIs(WW_ZoneEdgeSpan([0.25, 0.75], false), 0.3333, 1)
            && SpanIs(WW_ZoneEdgeSpan([0.25, 0.5], false), 0.3333, 0.6667)
            && SpanIs(WW_ZoneEdgeSpan([0, 1], false), 0.25, 1),
            "a tie goes toward the arrow, a middle fourth grows to the middle third, and a full span shrinks toward the arrow")
        places := ""
        for place in WW_ZonePlaces(1 / 2, WW_ZoneLadder())
            places .= Round(place * 12) " "
        this.Assert(places = "0 3 6 ", "a half sits left, in the middle or right, where both its edges land on stops")
        this.Assert(WW_ZoneSlide(0, 1 / 2, "right") = 1 / 4 && WW_ZoneSlide(1 / 4, 1 / 2, "right") = 1 / 2
            && WW_ZoneSlide(1 / 2, 1 / 2, "right") = ""
            && Abs(WW_ZoneSlide(0, 1 / 3, "right") - 1 / 3) < 0.001 && Abs(WW_ZoneSlide(1 / 3, 1 / 3, "right") - 2 / 3) < 0.001
            && WW_ZoneSlide(0, 1 / 3, "left") = "" && Abs(WW_ZoneSlide(0, 2 / 3, "right") - 1 / 3) < 0.001,
            "Left and Right slide a window through its places: a half via the middle, a third through three columns")
        lefts := [0, 1920, -1920]
        this.Assert(WW_NeighborDisplay(1, "right", lefts) = 2 && WW_NeighborDisplay(1, "left", lefts) = 3
            && WW_NeighborDisplay(2, "right", lefts) = 3 && WW_NeighborDisplay(3, "left", lefts) = 2
            && !WW_NeighborDisplay(1, "left", [0]),
            "the next display that way wraps from the last to the first, and one display has none")
        ; A laptop under a monitor, a second monitor beside it, nothing above.
        displays := [[0, 0, 2560, 1440], [2560, 0, 5120, 1440], [400, 1440, 1936, 2304]]
        this.Assert(WW_VerticalNeighborDisplay(1, displays, 500, 1300, "down") = 3
            && WW_VerticalNeighborDisplay(3, displays, 500, 1300, "up") = 1
            && !WW_VerticalNeighborDisplay(1, displays, 500, 1300, "up")
            && !WW_VerticalNeighborDisplay(2, displays, 2600, 3000, "down"),
            "Up and Down find the display touching that edge under the window, never wrapping")
        this.Assert(!WW_VerticalNeighborDisplay(1, displays, 2000, 2500, "down")
            && !WW_VerticalNeighborDisplay(1, [[0, 0, 2560, 1440], [2560, 0, 5120, 1440]], 0, 1280, "down"),
            "a window not over the lower display, or displays side by side, have nothing below")

        ; Starting zone mode puts a window against that side at its own size,
        ; or the closest zone size.
        area := [0, 0, 1200, 800], across := WW_BuildZoneLadder(false, true, true), down := WW_BuildZoneLadder(false, false, true)
        start := WW_ZoneStart([800, 0, 400, 800], area, "left", across, down)
        this.Assert(SpanIs(start.x, 0, 0.3333) && SpanIs(start.y, 0, 1),
            "Win + Left puts a right third against the left side, still a third")
        start := WW_ZoneStart([600, 0, 600, 400], area, "left", across, down)
        this.Assert(SpanIs(start.x, 0, 0.5) && SpanIs(start.y, 0, 0.5),
            "a top-right quarter becomes the top-left quarter, keeping its row")
        start := WW_ZoneStart([300, 100, 456, 480], area, "left", across, down)
        this.Assert(SpanIs(start.x, 0, 0.3333) && SpanIs(start.y, 0, 0.6667),
            "a loose window snaps to the closest width against that side and the closest height")
        start := WW_ZoneStart([0, 100, 1200, 500], area, "right", across, down)
        this.Assert(SpanIs(start.x, 0.5, 1),
            "a full-width window becomes that half, as in Windows")

        window := SuiteGui("+Resize", "Zone mode check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w400 h300")
            hwnd := window.Hwnd
            ActivateWindow(hwnd)
            WW_EndZoneCycle()
            area := WW_GetLayoutWorkArea(hwnd)
            width := area[3] - area[1], height := area[4] - area[2]
            near(rect, expected) => WW_RectanglesMatch(rect, expected, 6)
            WW_ZoneRow("down")
            this.Assert(!WW_IsCyclingZones() && WinGetMinMax(hwnd) = 0,
                "outside zone mode, its row keys do nothing")
            WinMaximize(hwnd)
            WW_ZoneSide("left")
            this.Assert(WW_IsCyclingZones() && near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2], width / 2, height]),
                "Win + Left on a maximized window gives the left half and starts zone mode")
            WW_ZoneRow("down")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2] + height / 2, width / 2, height / 2]),
                "Down makes it the bottom-left quarter")
            WW_ZoneSide("right")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1] + width / 4, area[2] + height / 2, width / 2, height / 2]),
                "Right slides it to the middle of the row")
            WW_ZoneSide("right")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1] + width / 2, area[2] + height / 2, width / 2, height / 2]),
                "and again to the bottom-right quarter")
            WW_ZoneRow("up")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1] + width / 2, area[2], width / 2, height / 2]),
                "Up slides the quarter straight to the top-right")
            WW_EndZoneCycle()
            WW_ZoneSide("left")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2], width / 2, height / 2]),
                "a new zone mode puts a zoned window against the arrow's side at its own size")
            WW_EndZoneCycle()
            WinMaximize(hwnd)
            WW_ZoneSide("right")
            WW_ZoneEdge("left")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1] + width / 3, area[2], width * 2 / 3, height]),
                "Shift + Left grows a right half to two-thirds")
            WW_ZoneSide("left")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2], width * 2 / 3, height]),
                "Left slides it back to the left side at the same width")
            ; Grown to the whole display it is really maximized, and shrinking
            ; in the same zone mode restores it.
            WW_EndZoneCycle()
            WinMaximize(hwnd)
            WW_ZoneSide("left")
            loop 3
                WW_ZoneEdge("right")
            this.Assert(WinGetMinMax(hwnd) = 1, "a zone grown to the whole display is maximized")
            WW_ZoneEdge("left")
            this.Assert(WinGetMinMax(hwnd) = 0
                && near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2], width * 3 / 4, height]),
                "and shrinking it in the same zone mode restores it to three-quarters")
            WW_EndZoneCycle()
            WinMaximize(hwnd)
            WW_ZoneSide("right")
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [area[1] + width / 2, area[2], width / 2, height]),
                "a maximized window starts over at a half")
            if MonitorGetCount() > 1 {
                start := WindowMonitorIndex(hwnd)
                WW_ZoneSide("right")
                moved := WW_GetLayoutWorkArea(hwnd)
                this.Assert(WindowMonitorIndex(hwnd) != start && near(WW_GetWindowLayoutRectangle(hwnd),
                    [moved[1], moved[2], (moved[3] - moved[1]) / 2, moved[4] - moved[2]]),
                    "Right again on a right half moves it to the next display's left half")
                WW_ZoneSide("left")
                this.Assert(WindowMonitorIndex(hwnd) = start, "and Left brings it back")
            }
            WW_RestoreToNormalSize()
        }
        finally {
            WW_EndZoneCycle()
            window.Destroy()
        }
    }

    ; Win + Down takes a window back to normal size without minimizing, also
    ; after a restart; Win + Up maximizes without placing the window by hand;
    ; Win + Shift + an arrow resizes one axis from anywhere and starts zone mode,
    ; whose next move snaps the other axis; Win + Alt + Enter toggles full
    ; height; zone mode moves alone place a window outside a cascade for good.
    static NormalSizeAndResize() {
        window := SuiteGui("+Resize", "Normal size check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w400 h300")
            hwnd := window.Hwnd
            ActivateWindow(hwnd)
            WW_EndZoneCycle()
            original := WW_GetWindowLayoutRectangle(hwnd)
            area := WW_GetLayoutWorkArea(hwnd)
            width := area[3] - area[1], height := area[4] - area[2]
            near(rect, expected) => WW_RectanglesMatch(rect, expected, 6)
            WW_ZoneEdge("right")
            placed := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(WW_IsCyclingZones() && Abs(placed[3] - original[3]) > 3
                && Abs(placed[2] - original[2]) <= 1 && Abs(placed[4] - original[4]) <= 1,
                "Win + Shift + Right resizes a loose window's width only and starts zone mode")
            WW_ZoneRow("down")
            moved := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(moved[1] - placed[1]) <= 1 && Abs(moved[3] - placed[3]) <= 1 && moved[2] > placed[2] + 3
                && IsObject(WW_ZoneGridSpan([(moved[2] - area[2]) / height, (moved[2] + moved[4] - area[2]) / height],
                    WW_ZoneLadder(width < height), 8 / height)),
                "in that zone mode, Down snaps the height to the grid and moves it down, leaving the width")
            placed := moved
            WW_ZoneEdge("down")
            resized := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(resized[4] - placed[4]) > 3
                && Abs(resized[1] - placed[1]) <= 1 && Abs(resized[3] - placed[3]) <= 1,
                "Win + Shift + Down resizes its height only, leaving the width and left edge")
            WW_EndZoneCycle()
            returned := []
            handler := (hwnd, shape) => returned.Push(hwnd)
            SuiteWindowOwnership.OnReturn(handler)
            try WW_RestoreToNormalSize()
            finally SuiteWindowOwnership.OffReturn(handler)
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), original, 3) && WinGetMinMax(hwnd) = 0
                && !SuiteWindowOwnership.IsManual(hwnd) && returned.Length = 1 && returned[1] = hwnd,
                "Win + Down takes it back to normal size, handing a lent cascade window back")
            WW_RestoreToNormalSize()
            this.Assert(WinGetMinMax(hwnd) = 0, "Win + Down never minimizes a window at normal size")
            WW_ToggleFullHeight()
            this.Assert(near(WW_GetWindowLayoutRectangle(hwnd), [original[1], area[2], original[3], height]),
                "Win + Alt + Enter stretches a window to full height, keeping its width and left edge")
            returned := []
            SuiteWindowOwnership.OnReturn(handler)
            try WW_ToggleFullHeight()
            finally SuiteWindowOwnership.OffReturn(handler)
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), original, 3)
                && !SuiteWindowOwnership.IsManual(hwnd) && returned.Length = 1 && returned[1] = hwnd,
                "Win + Alt + Enter again takes it back to its original shape, handing a lent cascade window back")
            WW_ZoneEdge("right")
            WW_EndZoneCycle()
            zoned := WW_GetWindowLayoutRectangle(hwnd)
            WW_ToggleFullHeight()
            WW_ToggleFullHeight()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), zoned, 3) && SuiteWindowOwnership.IsManual(hwnd),
                "full height from a zone goes back to that zone")
            WW_RestoreToNormalSize()
            WW_ZoneSide("left")
            moved := WW_GetWindowLayoutRectangle(hwnd)
            WW_EndZoneCycle()
            WW_RestoreToNormalSize()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), moved, 3) && !SuiteWindowOwnership.IsManual(hwnd),
                "Win + Down leaves a window outside a cascade where zone mode only moved it")
            WW_ZoneSide("right")
            moved := WW_GetWindowLayoutRectangle(hwnd)
            WW_ZoneEdge("left")
            WW_EndZoneCycle()
            WW_RestoreToNormalSize()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), moved, 3) && !SuiteWindowOwnership.IsManual(hwnd),
                "after a move and a resize, Win + Down goes back to where the move left it")
            ; After a restart, a lent window is held again but its normal
            ; rectangle is gone.
            SuiteWindowOwnership.Claim(hwnd)
            returned := []
            SuiteWindowOwnership.OnReturn(handler)
            try WW_RestoreToNormalSize()
            finally SuiteWindowOwnership.OffReturn(handler)
            this.Assert(!SuiteWindowOwnership.IsManual(hwnd) && returned.Length = 1 && returned[1] = hwnd
                && WinGetMinMax(hwnd) = 0,
                "Win + Down hands back a window still held after a restart, without its normal rectangle")
            WW_MaximizeWindowTarget()
            this.Assert(WinGetMinMax(hwnd) = 1 && !SuiteWindowOwnership.IsManual(hwnd),
                "Win + Up maximizes without placing the window by hand, so a cascade keeps it")
            WW_ToggleFullHeight()
            this.Assert(WinGetMinMax(hwnd) = 1, "Win + Alt + Enter leaves a maximized window maximized")
            WW_ZoneEdge("left")
            this.Assert(WinGetMinMax(hwnd) = 0
                && near(WW_GetWindowLayoutRectangle(hwnd), [area[1], area[2], width * 3 / 4, height]),
                "Win + Shift + Left shrinks a maximized window from its full size, against the left")
            this.Assert(WW_IsCyclingZones(), "and starts zone mode")
            WW_EndZoneCycle()
            WW_RestoreToNormalSize()
        }
        finally {
            WW_EndZoneCycle()
            window.Destroy()
        }
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    ; Only two test windows are passed in, so no real window is minimized.
    static MinimizeAll() {
        global WW_minimized_all
        WW_minimized_all := Map()
        windows := []
        Minimized(window) => WinGetMinMax("ahk_id " window.Hwnd) = -1
        WaitFor(condition) {
            Loop 40 {
                if condition()
                    return
                Sleep 25
            }
        }
        try {
            Loop 2 {
                window := SuiteGui("+Resize", "Minimize all check " A_Index)
                SuiteWindowOwnership.AllowArranging(window)
                window.Show("NA x" (120 + A_Index * 40) " y" (120 + A_Index * 40) " w320 h200")
                windows.Push(window)
            }
            front := [windows[2].Hwnd, windows[1].Hwnd]
            ; Win + M usually minimizes the window the user is in.
            ActivateWindow(windows[2].Hwnd)
            monitor := WindowMonitorIndex(windows[1].Hwnd)
            device := MonitorGetName(monitor)
            other := MonitorGetCount() > 1 ? Mod(monitor, MonitorGetCount()) + 1 : 0
            if other {
                WW_MinimizeAllWindows(front, other)
                this.Assert(!Minimized(windows[1]) && !Minimized(windows[2])
                    && !WW_minimized_all.Get(MonitorGetName(other), []).Length,
                    "Win + M leaves windows on other displays alone")
            }
            WW_MinimizeAllWindows(front, monitor)
            WaitFor(() => Minimized(windows[1]) && Minimized(windows[2]))
            remembered := WW_minimized_all.Get(device, [])
            this.Assert(Minimized(windows[1]) && Minimized(windows[2]) && remembered.Length = 2
                && remembered[1].hwnd = windows[2].Hwnd,
                "Win + M minimizes every window on its display and remembers them front to back")
            this.Assert(DllCall("GetForegroundWindow", "ptr") = DllCall("GetShellWindow", "ptr"),
                "after Win + M focus rests on the desktop, never another display's window")
            WW_MinimizeAllWindows(front, monitor)
            this.Assert(WW_minimized_all.Get(device, []).Length = 2,
                "a Win + M with nothing left to minimize keeps what Win + Shift + M restores")
            if other {
                WW_RestoreAllWindows(other)
                this.Assert(Minimized(windows[1]) && WW_minimized_all.Get(device, []).Length = 2,
                    "Win + Shift + M on another display leaves this display's windows minimized")
            }
            WW_RestoreAllWindows(monitor)
            WaitFor(() => !Minimized(windows[1]) && !Minimized(windows[2]))
            this.Assert(!Minimized(windows[1]) && !Minimized(windows[2]) && !WW_minimized_all.Has(device),
                "Win + Shift + M brings every window on its display back")
            ActivateWindow(windows[2].Hwnd)
            WW_MinimizeOtherWindows(front)
            WaitFor(() => Minimized(windows[1]))
            remembered := WW_minimized_all.Get(device, [])
            this.Assert(Minimized(windows[1]) && !Minimized(windows[2]) && remembered.Length = 1
                && remembered[1].hwnd = windows[1].Hwnd
                && DllCall("GetForegroundWindow", "ptr") = windows[2].Hwnd,
                "Win + Home minimizes the other windows on its display and keeps the active one")
            WW_MinimizeOtherWindows(front)
            this.Assert(Minimized(windows[1]) && WW_minimized_all.Get(device, []).Length = 1,
                "a Win + Home with nothing left to minimize keeps what it minimized")
            WW_RestoreOtherWindows()
            WaitFor(() => !Minimized(windows[1]))
            this.Assert(!Minimized(windows[1]) && !WW_minimized_all.Has(device)
                && DllCall("GetForegroundWindow", "ptr") = windows[2].Hwnd,
                "Win + Shift + Home brings them back behind the active window")
            ; Win + D also reaches a window on the other display, remembered there.
            if other {
                MonitorGetWorkArea(other, &left, &top)
                WinMove(left + 100, top + 100, , , windows[1].Hwnd)
            }
            WW_MinimizeEveryDisplay(front)
            WaitFor(() => Minimized(windows[1]) && Minimized(windows[2]))
            this.Assert(Minimized(windows[1]) && Minimized(windows[2])
                && WW_minimized_all.Get(device, []).Length = (other ? 1 : 2)
                && (!other || WW_minimized_all.Get(MonitorGetName(other), []).Length = 1)
                && DllCall("GetForegroundWindow", "ptr") = DllCall("GetShellWindow", "ptr"),
                "Win + D minimizes every display's windows into that display's memory")
            WW_RestoreEveryDisplay()
            WaitFor(() => !Minimized(windows[1]) && !Minimized(windows[2]))
            this.Assert(!Minimized(windows[1]) && !Minimized(windows[2]) && !WW_minimized_all.Has(device),
                "Win + Shift + D brings every display's windows back")
        }
        finally {
            WW_minimized_all := Map()
            for window in windows
                window.Destroy()
        }
    }

    ; Apply a fixture's changed frame styles (SWP_FRAMECHANGED without moving).
    static RefreshFrame(hwnd) => DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
        "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37, "int")

    static GeometryAndOwnership() {
        app := SuiteApplication(true, SuiteChecks.directory "\geometry")
        app.InitializeCatalog()
        try {
            top :=WW_BuildRatioLayout([-1001, -501, 0, 500], [0, 4, 4], "top")
            bottom := WW_BuildRatioLayout([-1001, -501, 0, 500], [0, 4, 4], "bottom")
            this.Assert(top[1] = -1001 && top[2] + top[4] = bottom[2]
                && bottom[2] + bottom[4] = 500, "odd negative-coordinate layouts retain exact shared boundaries")
            this.Assert(WW_GetNextCycleIndex(4, 4) = 1 && WW_GetNextCycleIndex(1, 4, true) = 4
                && WW_GetNextCycleIndex(0, 4) = 1 && WW_GetNextCycleIndex(0, 4, true) = 4,
                "layout cycling wraps in both directions and starts from either end")
            this.Assert(WW_DirectionalScore(-80, 0, "left") = 80
                && WW_DirectionalScore(80, 0, "left") = -1
                && WW_DirectionalScore(80, 30, "right") = 140
                && WW_DirectionalScore(0, -60, "up") = 60
                && WW_DirectionalScore(0, 60, "down") = 60,
                "moving onto a window selects only windows on the requested side")
            this.Assert(WW_NextMaximizeCycleIndex(false, false, 0) = 0,
                "Win + Up maximizes a normal window first")
            this.Assert(WW_NextMaximizeCycleIndex(false, true, 0) = 1,
                "Win + Up advances maximized to upper half")
            this.Assert(WW_NextMaximizeCycleIndex(false, false, 1) = 2,
                "Win + Up advances upper half to lower half")
            this.Assert(WW_NextMaximizeCycleIndex(false, false, 2) = 0,
                "Win + Up advances lower half to maximized")
            this.Assert(WW_NextMaximizeCycleIndex(true, true, 0) = 0,
                "Win + Up exits native fullscreen to maximized")
            this.Assert(WW_RectanglesMatch(
                WW_FitAcceptedRectangle([100, 150, 800, 500], [100, 150, 800, 500], [0, 0, 1600, 900]),
                [100, 150, 800, 500], 0),
                "best-effort placement does not alter a fitting destination")
            this.Assert(WW_RectanglesMatch(
                WW_FitAcceptedRectangle([900, 600, 400, 300], [900, 600, 820, 520], [0, 0, 1600, 900]),
                [780, 380, 820, 520], 0),
                "size-constrained placements keep accepted dimensions on-screen")
            this.Assert(WW_RectanglesMatch(
                WW_FitAcceptedRectangle([-100, -80, 400, 300], [-100, -80, 820, 520], [-1600, -900, 0, 0]),
                [-820, -520, 820, 520], 0),
                "best-effort placement handles negative desktop coordinates")
            this.Assert(!IsObject(WW_FitAcceptedRectangle([100, 100, 400, 300],
                [100, 100, 1800, 300], [0, 0, 1600, 900])),
                "unfittable window dimensions require a placement rollback")
            this.Assert(WW_RectanglesMatch(
                WW_FitAcceptedRectangle([1200, 0, 400, 450], [1200, 0, 600, 500], [0, 0, 1600, 900]),
                [1000, 0, 600, 500], 0)
                && WW_RectanglesMatch(
                WW_FitAcceptedRectangle([0, 450, 400, 450], [0, 450, 600, 520], [0, 0, 1600, 900]),
                [0, 380, 600, 520], 0),
                "a tile too small for its app grows inward instead of off-screen")
            side := [[0, 0, 400, 1000], [0, 0, 800, 1000], [400, 0, 400, 1000], [400, 0, 800, 1000]]
            this.Assert(WW_GetNextFittingIndex(0, side, [600, 500]) = 2
                && WW_GetNextFittingIndex(2, side, [600, 500]) = 4
                && WW_GetNextFittingIndex(4, side, [600, 500]) = 2
                && WW_GetNextFittingIndex(1, side, [0, 0]) = 2,
                "layout cycles skip sizes an app refuses and keep the rest")
            this.Assert(WW_GetNextFittingIndex(2, [[0, 0, 400, 500], [0, 0, 800, 500]], [600, 400]) = 2
                && WW_GetNextFittingIndex(1, side, [900, 500]) = 2
                && WW_GetNextFittingIndex(0, side, [900, 500]) = 1,
                "a single fitting size repeats; when none fits the normal cycle continues")
            ; Two displays: a left column split top/bottom (hwnds 40 and 30), a
            ; right column (10) and two windows stacked exactly (60 and 20).
            entries := [{hwnd: 10, monitor: 0, x: 960, y: 0},
                {hwnd: 60, monitor: 1920, x: 1920, y: 0},
                {hwnd: 30, monitor: 0, x: 3, y: 540},
                {hwnd: 20, monitor: 1920, x: 1920, y: 0},
                {hwnd: 40, monitor: 0, x: 0, y: 0}]
            order := ""
            for entry in WW_SortFocusEntries(entries)
                order .= entry.hwnd " "
            this.Assert(order = "40 30 10 20 60 ",
                "focus cycles displays, then columns, then top to bottom")
            ; Activating a stacked window must not change its place in the cycle.
            entries.RemoveAt(4), entries.InsertAt(1, {hwnd: 20, monitor: 1920, x: 1920, y: 0})
            order := ""
            for entry in WW_SortFocusEntries(entries)
                order .= entry.hwnd " "
            this.Assert(order = "40 30 10 20 60 ",
                "stacked windows keep their order when one comes to the front")
            this.Assert(WW_IsAtNormalPlacement(0, false, false)
                && !WW_IsAtNormalPlacement(1, false, false)
                && !WW_IsAtNormalPlacement(0, true, false)
                && !WW_IsAtNormalPlacement(0, false, true),
                "Win + Down takes placed, maximized and fullscreen windows back to normal size; others are already there")
            cycle := [101, 102, 103]
            this.Assert(WW_NextMonitorCycleWindow(cycle, 101, 101, true) = 103
                && WW_NextMonitorCycleWindow(cycle, 103, 103, true) = 102
                && WW_NextMonitorCycleWindow(cycle, 0, 0, true) = 103,
                "Win + Shift + PgUp walks the stack order backwards, wrapping to the end")
            window := SuiteGui("+ToolWindow", "Owned test window")
            try {
                this.Assert(SuiteWindowOwnership.IsSuiteSurface(window.Hwnd),
                    "private suite tool windows are recognized")
                this.Assert(!SuiteWindowOwnership.AllowsWonderWindows(window.Hwnd),
                    "private suite tool windows are excluded from Wonder Windows")
                this.Assert(IsIgnoredByCascade(window.Hwnd), "suite GUI is marked before it can be cascaded")
                SuiteWindowOwnership.Claim(window.Hwnd)
                this.Assert(SuiteWindowOwnership.IsManual(window.Hwnd), "manual geometry ownership is recorded per HWND and process")
                global WW_normal_window_placements
                WW_normal_window_placements[window.Hwnd] := Map("pid", WindowProcessId(window.Hwnd))
                this.Assert(SuiteWindowOwnership.Release(window.Hwnd) && !SuiteWindowOwnership.IsManual(window.Hwnd),
                    "explicit adoption releases manual ownership")
                this.Assert(!WW_normal_window_placements.Has(window.Hwnd),
                    "adoption starts a fresh manual-restore history")
                returned := []
                handler := (hwnd, shape) => returned.Push({hwnd: hwnd, shape: shape})
                SuiteWindowOwnership.OnReturn(handler)
                try {
                    this.Assert(!SuiteWindowOwnership.Return(window.Hwnd) && !returned.Length,
                        "a window never placed by hand has nothing to return")
                    SuiteWindowOwnership.Claim(window.Hwnd)
                    shape := CaptureWindowShape(window.Hwnd)
                    this.Assert(SuiteWindowOwnership.Return(window.Hwnd, shape)
                        && !SuiteWindowOwnership.IsManual(window.Hwnd)
                        && returned.Length = 1 && returned[1].hwnd = window.Hwnd && returned[1].shape = shape,
                        "returning a window to its original shape ends manual ownership and tells the lender where it was")
                }
                finally SuiteWindowOwnership.OffReturn(handler)
                SuiteWindowOwnership.Claim(window.Hwnd)
                DllCall("RemovePropW", "ptr", window.Hwnd, "str", SuiteWindowOwnership.marker, "ptr")
                this.Assert(!SuiteWindowOwnership.IsManual(window.Hwnd), "a lost per-window marker invalidates cached manual ownership")
            }
            finally window.Destroy()
            ; A plain window, unlike a suite GUI, carries no cascade exclusion of its own.
            window := Gui("+Resize", "Manual drag fixture")
            try {
                window.Show("NA x60 y60 w400 h300")
                SuiteWindowOwnership.Claim(window.Hwnd)
                this.Assert(!IsPlausibleTopLevelWindow(window.Hwnd) && !IsCascadeWindow(window.Hwnd)
                    && IsPlausibleTopLevelWindow(window.Hwnd, true) && IsCascadeWindow(window.Hwnd, true),
                    "drags track windows positioned by hand while automatic placement leaves them alone")
                SuiteWindowOwnership.Release(window.Hwnd, false)
            }
            finally window.Destroy()
            guiProbe := SuiteGui("+Resize", "Wonder Windows GUI eligibility test")
            try {
                SuiteWindowOwnership.AllowArranging(guiProbe)
                guiProbe.Show("NA w600 h400")
                this.Assert(SuiteWindowOwnership.AllowsWonderWindows(guiProbe.Hwnd)
                    && IsSwitchableWindow(guiProbe.Hwnd),
                    "normal suite GUIs are Wonder Windows candidates")
                this.Assert(!WW_IsNativeFullscreen(guiProbe.Hwnd),
                    "ordinary suite GUI is not mistaken for native fullscreen")
                ; A large window may occupy a smaller logical zone.
                guiActual := WW_GetWindowLayoutRectangle(guiProbe.Hwnd)
                guiZone := [guiActual[1], guiActual[2],
                    Max(50, guiActual[3] - 130), Max(50, guiActual[4] - 90)]
                WW_SaveLogicalZone(guiProbe.Hwnd, guiZone)
                this.Assert(WW_RectanglesMatch(WW_GetLogicalZone(guiProbe.Hwnd), guiZone, 0),
                    "oversized GUI retains its logical zone")
                global WW_logical_zones
                this.Assert(WW_logical_zones.Has(guiProbe.Hwnd)
                    && WW_RectanglesMatch(WW_logical_zones[guiProbe.Hwnd]["applied"], guiActual, 2),
                    "logical zone and actual GUI rectangle stay separate")
                ; A recycled HWND must not inherit the previous window's zone.
                DllCall("RemovePropW", "ptr", guiProbe.Hwnd,
                    "str", "nroj.SuperHotkey.LogicalZone", "ptr")
                this.Assert(WW_RectanglesMatch(WW_GetLogicalZone(guiProbe.Hwnd), guiActual, 2)
                    && !WW_logical_zones.Has(guiProbe.Hwnd),
                    "reopened GUI without the zone marker inherits no stale logical zone")
                WW_SaveLogicalZone(guiProbe.Hwnd, guiZone)
                WW_logical_zones[0] := Map("pid", 0)
                WW_PruneLogicalZones()
                this.Assert(!WW_logical_zones.Has(0),
                    "dead windows do not retain logical zone records")
                ; Manual resizing must forget stale zones rather than spreading them.
                WinGetPos(&gX, &gY, &gW, &gH, guiProbe.Hwnd)
                WinMove(gX, gY, gW + 70, gH, guiProbe.Hwnd)
                Sleep 40
                this.Assert(WW_RectanglesMatch(WW_GetLogicalZone(guiProbe.Hwnd),
                    WW_GetWindowLayoutRectangle(guiProbe.Hwnd), 2)
                    && !WW_logical_zones.Has(guiProbe.Hwnd),
                    "manual GUI resize invalidates its remembered logical zone")
                this.Assert(IsIgnoredByCascade(guiProbe.Hwnd),
                    "Cascade Kingdom continues to ignore normal suite GUIs")
                DllCall("SetPropW", "ptr", guiProbe.Hwnd, "str", "nroj.PaperPad.Notepad3Window", "ptr", 1, "int")
                this.Assert(SuiteWindowOwnership.AllowsWonderWindows(guiProbe.Hwnd),
                    "marked Paper Pad editor windows remain eligible")
            }
            finally guiProbe.Destroy()
            event := {phase: "down", actionId: "wonder-windows.maximize", slot: 1,
                foregroundHwnd: 0, key: "sc148", layer: "normal", modifiers: 8, oneShot: false}
            app.modules["wonder-windows"].Event(event)
            this.Assert(InStr(SuiteState.Log.Read(), "dry run: wonder-windows.maximize"),
                "Wonder Windows dry-run callbacks do not move real windows")
            ; Two taps that arrive together, as after a slow move, both count.
            wonder := app.modules["wonder-windows"]
            wonder.DefineProp("CanRun", {Call: (self) => true})
            app.dryRun := false
            try {
                tap := {phase: "down", actionId: "wonder-windows.zones-from-left", slot: 2,
                    foregroundHwnd: 0, key: "sc14D", layer: "normal", modifiers: 8, oneShot: false}
                wonder.Event(tap)
                right := tap.Clone()
                right.actionId := "wonder-windows.zones-from-right"
                wonder.Event(right)
                wonder.Event(tap.Clone())
                SetTimer(wonder.drainCallback, 0)
                order := []
                for token, job in wonder.pending
                    order.Push(job.event.actionId)
                this.Assert(order.Length = 3 && order[1] = tap.actionId && order[2] = right.actionId
                    && order[3] = tap.actionId, "quick taps all count and drain in the order pressed")
                wonder.CancelWork()
                notch := tap.Clone()
                notch.key := "WheelDown"
                wonder.Event(notch)
                wonder.Event(notch.Clone())
                SetTimer(wonder.drainCallback, 0)
                this.Assert(wonder.pending.Count = 1, "a fast wheel spin keeps one step")
            }
            finally {
                app.dryRun := true
                wonder.CancelWork()
            }
        }
        finally app.manager.Stop()
    }

    ; Apps such as Discord refuse a quarter-screen tile. They must grow toward
    ; the middle of the display instead of past its edges.
    static OversizedTile() {
        global WW_layout_cycle_windows
        if !IsSet(WW_layout_cycle_windows)
            WW_InitializeState()
        app := SuiteApplication(true, SuiteChecks.directory "\release-oversized-tile")
        window := SuiteGui("+Resize -DPIScale", "Oversized tile target")
        try {
            window.Show("NA w300 h200")
            work_area := WW_GetLayoutWorkArea(window.Hwnd)
            for position, ratios in Map("top-right", [3, 1, 0, "top"], "bottom-right", [3, 1, 0, "bottom"],
                "bottom-left", [0, 1, 3, "bottom"]) {
                tile := WW_BuildRatioLayout(work_area, ratios, ratios[4])
                window.Opt("+MinSize" (tile[3] + 200) "x" (tile[4] + 150))
                minimum := WW_GetMinimumVisibleSize(window.Hwnd)
                this.Assert(minimum[1] >= tile[3] + 200 && minimum[2] >= tile[4] + 150,
                    "the app's minimum size is known before the " position " tile moves it")
                WW_ApplyTrackedLayout(window.Hwnd, "corner-" position, work_area, [tile], 1)
                rect := WW_GetWindowLayoutRectangle(window.Hwnd)
                this.Assert(rect[3] > tile[3] && rect[4] > tile[4]
                    && rect[1] >= work_area[1] - 2 && rect[2] >= work_area[2] - 2
                    && rect[1] + rect[3] <= work_area[3] + 2 && rect[2] + rect[4] <= work_area[4] + 2,
                    "an app larger than its " position " tile grows inward and stays on-screen")
            }
        }
        finally {
            SuiteWindowOwnership.Release(window.Hwnd, false)
            window.Destroy()
        }
    }

    static MoveOntoZone() {
        windows := []
        try {
            Loop 2 {
                window := SuiteGui("+Resize", "Hardening move onto " A_Index)
                windows.Push(window)
                window.Show("NA x" (60 + 340 * (A_Index - 1)) " y80 w300 h220")
            }
            source := windows[1].Hwnd
            target := windows[2].Hwnd
            targetVisible := WW_GetWindowLayoutRectangle(target)
            this.Assert(WW_MoveWindowToZone(source, WW_GetLogicalZone(target)),
                "moving onto a window reports success")
            this.Assert(WW_WindowMatchesVisibleRectangle(source, targetVisible),
                "the moved window takes its neighbor's visible rectangle")
            this.Assert(WW_WindowMatchesVisibleRectangle(target, targetVisible),
                "the neighbor stays where it is")

            WinGetPos(&x, &y, &width, &height, source)
            raw := [x, y, width, height]
            visible := WW_GetWindowLayoutRectangle(source)
            WinMove(x + 70, y + 60, , , source)
            this.Assert(WW_RestoreWindowRectangle(source, raw, visible),
                "rollback restores a moved window")
            windows[1].Destroy()
            this.Assert(!WW_RestoreWindowRectangle(source, raw, visible),
                "rollback reports failure when the window has closed")
        }
        finally {
            for window in windows {
                try window.Destroy()
            }
        }
    }

    static FullscreenDetection() {
        ; Chrono Trigger's window on a 2560 x 1440 display grew from 2592 to
        ; 2772 px wide over a few restores; the other display was to its left.
        display := [0, 0, 2560, 1440]
        left := [[-2560, 0, 0, 1440]], right := [[2560, 0, 5120, 1440]]
        this.Assert(WW_RectCoversMonitor([0, 0, 2560, 1440], display, left)
            && WW_RectCoversMonitor([1, -1, 2559, 1441], display, left),
            "a window matching its display within rounding fills it")
        this.Assert(WW_RectCoversMonitor([-1, -1, 2591, 1459], display, left)
            && WW_RectCoversMonitor([-1, -1, 2771, 1459], display, left),
            "a borderless game overhanging into no other display fills it, however far")
        this.Assert(WW_RectCoversMonitor([-1, -1, 2591, 1459], display, right)
            && !WW_RectCoversMonitor([-1, -1, 2771, 1459], display, right),
            "overhang onto a neighbouring display is allowed only up to 1/16 of the display")
        this.Assert(!WW_RectCoversMonitor([0, 0, 2560, 1400], display, left)
            && !WW_RectCoversMonitor([8, 0, 2560, 1440], display, left),
            "a window short of any display edge, such as a maximized one above the taskbar, does not")
        this.Assert(!WW_RectCoversMonitor([-2560, 0, 2560, 1440], display, left),
            "a window stretched over both displays does not fill either")

        placement := Buffer(44, 0)
        monitorInfo := Buffer(40, 0)
        NumPut("int", -1920, "int", -1080, "int", 0, "int", 0, monitorInfo, 4)
        NumPut("int", -1880, "int", -1040, "int", 0, "int", 0, monitorInfo, 20)
        NumPut("int", -1960, "int", -1120, "int", -40, "int", -40, placement, 28)
        this.Assert(WW_WindowPlacementFillsPhysicalMonitor(placement, monitorInfo, []),
            "minimized fullscreen geometry accounts for workspace offsets and negative monitors")
        NumPut("int", -140, placement, 36)
        this.Assert(!WW_WindowPlacementFillsPhysicalMonitor(placement, monitorInfo, []),
            "a smaller restore rectangle is not fullscreen")
        NumPut("int", -1961, "int", -1121, "int", 172, "int", -21, placement, 28)
        this.Assert(WW_WindowPlacementFillsPhysicalMonitor(placement, monitorInfo, []),
            "a minimized borderless game that overhangs its display stays fullscreen")

        WW_RunWindowCommand(ObjBindMethod(this, "FullscreenDetectionWindows"))
    }

    static ExpandedWindowCycle() {
        cycle := [101, 102, 103]
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 101, 0) = 102
            && WW_NextMaximizedFullscreenWindow(cycle, 103, 0) = 101,
            "the expanded-window cycle loops with no all-minimized step")
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 101, 0, true) = 103
            && WW_NextMaximizedFullscreenWindow(cycle, 102, 0, true) = 101,
            "Shift steps the expanded-window cycle back")
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 999, 102) = 102
            && WW_NextMaximizedFullscreenWindow(cycle, 999, 102, true) = 102,
            "from another window the cycle brings back the big window shown last")
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 999, 0) = 101
            && WW_NextMaximizedFullscreenWindow(cycle, 999, 0, true) = 103
            && WW_NextMaximizedFullscreenWindow(cycle, 999, 888) = 101,
            "without a last window here the cycle starts at its first, or its last going back")
        this.Assert(WW_NextMaximizedFullscreenWindow([101], 101, 101) = 101,
            "a single big window stays out")
    }

    static MonitorWindowCycle() {
        cycle := [101, 102, 103]
        this.Assert(WW_NextMonitorCycleWindow(cycle, 101, 101) = 102
            && WW_NextMonitorCycleWindow(cycle, 102, 102) = 103
            && WW_NextMonitorCycleWindow(cycle, 103, 103) = 101,
            "monitor cycling visits every window and wraps around")
        this.Assert(WW_NextMonitorCycleWindow(cycle, 102, 101) = 103
            && WW_NextMonitorCycleWindow(cycle, 103, 101) = 102,
            "a refused target is stepped past without returning to the active window")
        this.Assert(WW_NextMonitorCycleWindow([101], 101, 101) = 0
            && WW_NextMonitorCycleWindow([], 0, 0) = 0,
            "a display with no other window has no target")

        ; Display 1 is in the middle, 2 on the right and 3 on the left.
        lefts := [0, 1920, -1920]
        order := WW_DisplayOrderFrom(1, lefts)
        this.Assert(order.Length = 3 && order[1] = 1 && order[2] = 2 && order[3] = 3,
            "focus after a minimize tries the window's display, then the next to the right")
        order := WW_DisplayOrderFrom(2, lefts)
        this.Assert(order[1] = 2 && order[2] = 3 && order[3] = 1,
            "the rightmost display wraps around to the leftmost")
        order := WW_DisplayOrderFrom(0, lefts)
        this.Assert(order[1] = 3 && order[2] = 1 && order[3] = 2,
            "an unknown display starts at the leftmost")

        ; Activating 102 moves it to the front; its place in the cycle stays.
        merged := WW_MergeCycleOrder(cycle, [102, 104, 101, 103])
        this.Assert(merged.Length = 4 && merged[1] = 101 && merged[2] = 102
            && merged[3] = 103 && merged[4] = 104,
            "cycle order survives Z-order changes and appends new windows")
        merged := WW_MergeCycleOrder(cycle, [103, 101])
        this.Assert(merged.Length = 2 && merged[1] = 101 && merged[2] = 103,
            "closed, minimized and moved windows leave the cycle")

        display := [-1920, 0, 1920, 1080]
        this.Assert(WW_IntersectionArea([-100, 500, 400, 300], display) = 30000
            && !WW_IntersectionArea([-32000, -32000, 160, 28], display)
            && !WW_IntersectionArea([0, 0, 400, 300], display)
            && !WW_IntersectionArea([-500, 200, 0, 0], display),
            "only windows sharing area with the display count as on it")

        maximized := [0, 0, 1920, 1080]
        tile(rect) => ({rect: rect, full: false})
        this.Assert(WW_WindowsStack(tile([100, 100, 800, 600]), tile([140, 120, 800, 600]))
            && !WW_WindowsStack(tile([0, 0, 640, 1080]), tile([640, 0, 640, 1080]))
            && !WW_WindowsStack(tile([0, 0, 200, 150]), tile([0, 0, 800, 600]))
            && !WW_WindowsStack(tile([0, 0, 800, 600]), tile([400, 0, 800, 600])),
            "windows of one size stack when they share most of their area")
        this.Assert(WW_WindowsStack(tile([0, 0, 480, 1080]), tile([0, 0, 960, 1080]))
            && WW_WindowsStack(tile([0, 0, 960, 1080]), tile([4, 0, 476, 1080]))
            && WW_WindowsStack(tile([480, 0, 480, 1080]), tile([0, 0, 960, 1080])),
            "a fourth on a half stacks, either side, gaps between zones included")
        this.Assert(!WW_WindowsStack(tile([0, 0, 960, 1080]), {rect: maximized, full: true})
            && !WW_WindowsStack({rect: maximized, full: true}, tile([0, 0, 480, 1080]))
            && !WW_WindowsStack(tile([0, 0, 640, 1080]), {rect: maximized, full: true}),
            "halves, thirds and fourths in front of a maximized window stay apart")

        ; Explorer over Terminal on the left, VS Code over Firefox in the middle,
        ; a lone window on the right and a maximized window behind them all.
        stacks := WW_GroupWindowStacks([
            {hwnd: 201, rect: [0, 0, 640, 1080]}, {hwnd: 301, rect: [640, 0, 640, 1080]},
            {hwnd: 202, rect: [10, 20, 630, 1060]}, {hwnd: 401, rect: [1280, 0, 640, 1080]},
            {hwnd: 302, rect: [640, 0, 640, 1080]}, {hwnd: 501, rect: maximized, full: true}])
        this.Assert(stacks.Length = 4
            && stacks[1].Length = 2 && stacks[1][1] = 201 && stacks[1][2] = 202
            && stacks[2].Length = 2 && stacks[2][1] = 301 && stacks[2][2] = 302
            && stacks[3].Length = 1 && stacks[3][1] = 401
            && stacks[4].Length = 1 && stacks[4][1] = 501,
            "stacks group overlapping windows front to back and leave lone windows apart")
        stacks := WW_GroupWindowStacks([{hwnd: 601, rect: [0, 0, 800, 600]},
            {hwnd: 603, rect: [400, 0, 800, 600]}, {hwnd: 602, rect: [200, 0, 800, 600]}])
        this.Assert(stacks.Length = 1 && stacks[1].Length = 3
            && stacks[1][1] = 601 && stacks[1][2] = 603 && stacks[1][3] = 602,
            "a window linking two others joins them into one stack")

        ; Focus stepping sees each stack once, as its front window, but keeps
        ; the active window even when something stacks in front of it.
        entries := [{hwnd: 201, rect: [0, 0, 640, 1080]}, {hwnd: 301, rect: [640, 0, 640, 1080]},
            {hwnd: 202, rect: [10, 20, 630, 1060]}, {hwnd: 302, rect: [640, 0, 640, 1080]},
            {hwnd: 501, rect: maximized, full: true}]
        order := ""
        for entry in WW_FrontFocusEntries(entries, 201)
            order .= entry.hwnd " "
        this.Assert(order = "201 301 501 ", "focus stepping skips windows hidden in a stack")
        order := ""
        for entry in WW_FrontFocusEntries(entries, 302)
            order .= entry.hwnd " "
        this.Assert(order = "201 301 302 501 ", "focus stepping keeps the active window")
    }

    static FullscreenDetectionWindows() {
        windows := []
        try {
            Loop 2 {
                window := SuiteGui("+Resize -DPIScale", "Fullscreen fixture " A_Index)
                windows.Push(window)
                SuiteWindowOwnership.AllowArranging(window)
                window.Show("NA x60 y60 w320 h220")
            }
            normal := windows[1].Hwnd
            fullscreen := windows[2].Hwnd
            WinMinimize(normal)
            this.Assert(!IsSwitchableWindow(normal) && IsSwitchableWindow(normal, true),
                "window commands exclude minimized windows unless asked to include them")
            WinRestore(normal)
            this.Assert(!WW_IsNativeFullscreen(normal), "an ordinary window is not native fullscreen")

            ; A native-style borderless fixture.
            WinSetStyle((WinGetStyle(fullscreen) & ~0xC40000) | 0x80000000, fullscreen)
            WinSetExStyle(WinGetExStyle(fullscreen) & ~0x300, fullscreen)
            WonderWindowsChecks.RefreshFrame(fullscreen)
            WW_GetWindowMonitorBounds(fullscreen, &left, &top, &right, &bottom)
            WinMove(left, top, right - left, bottom - top, fullscreen)
            this.Assert(WW_IsNativeFullscreen(fullscreen), "borderless fixture is native fullscreen")

            maximized := windows[1].Hwnd
            WinMaximize(maximized)
            WinMinimize(maximized)
            WinMinimize(fullscreen)
            this.Assert(WW_IsMaximizedOrFullscreen(maximized) && WW_IsMaximizedOrFullscreen(fullscreen),
                "minimized windows that restore maximized or fullscreen count as big windows")

            ; Only explicit test-owned handles reach the executor; never enumerate the desktop.
            cycle := [maximized, fullscreen]
            this.Assert(WW_ShowMaximizedFullscreenWindow(cycle, maximized)
                && WinGetMinMax(maximized) = 1 && WinGetMinMax(fullscreen) = -1,
                "the cycle restores a maximized window and leaves the other big window minimized")
            this.Assert(WW_ShowMaximizedFullscreenWindow(cycle, fullscreen)
                && WinGetMinMax(maximized) = -1 && WW_IsNativeFullscreen(fullscreen),
                "showing the fullscreen window minimizes the maximized one")
        }
        finally {
            for window in windows {
                try window.Destroy()
            }
        }
    }
}
