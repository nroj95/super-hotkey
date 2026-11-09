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
        this.FullSpanAndNormalSize()
        this.ZoneLayoutsAndStretch()
        this.ZoneWalks()
    }

    ; The plain zone walk covers the zones that span the full height; its
    ; Shift twin walks the split ones page by page while a walk runs, rows
    ; always top to bottom, entering the column the window is in at its top,
    ; or with the other key its bottom.
    static ZoneWalks() {
        work := [0, 0, 1920, 1080]
        Rect(zone) => zone[1] "," zone[2] "," zone[3] "," zone[4]
        walks := WW_SplitZoneWalks(WW_BuildLayoutZones(work, "fourths"), work)
        this.Assert(walks.main.Length = 7 && Rect(walks.main[1]) = "0,0,480,1080" && Rect(walks.main[7]) = "960,0,960,1080",
            "the plain walk holds the four fourths and three halves")
        this.Assert(walks.split.Length = 14 && Rect(walks.split[1]) = "0,0,480,540" && Rect(walks.split[2]) = "480,0,480,540"
            && Rect(walks.split[5]) = "0,540,480,540" && Rect(walks.split[9]) = "0,0,960,540"
            && Rect(walks.split[14]) = "960,540,960,540",
            "the split walk goes page by page: upper and lower fourths, then upper and lower halves")
        this.Assert(walks.back.Length = 14 && Rect(walks.back[1]) = "960,0,960,540" && Rect(walks.back[3]) = "0,0,960,540"
            && Rect(walks.back[4]) = "960,540,960,540" && Rect(walks.back[7]) = "1440,0,480,540"
            && Rect(walks.back[14]) = "0,540,480,540",
            "stepping back takes the pages in reverse, but each page's rows still top to bottom")
        corners := WW_SplitZoneWalks(WW_BuildLayoutZones(work, "corners"), work)
        this.Assert(corners.main.Length = 2 && Rect(corners.split[2]) = "960,0,960,540"
            && Rect(corners.split[3]) = "0,540,960,540",
            "halves and corners walks the halves, then the corners row by row")
        tall := [0, 0, 1080, 1920]
        rows := WW_SplitZoneWalks(WW_BuildLayoutZones(tall, "thirds"), tall, true)
        this.Assert(rows.main.Length = 5 && Rect(rows.main[1]) = "0,0,1080,640" && Rect(rows.main[4]) = "0,0,1080,1280"
            && Rect(rows.split[1]) = "0,0,540,640" && Rect(rows.split[2]) = "0,640,540,640",
            "turned thirds walk full-width bands, and their split walk the left halves, then the right ones")
        onlySplit := WW_SplitZoneWalks(WW_BuildLayoutZones(work, "1:1 / 1:1"), work)
        this.Assert(onlySplit.main.Length = 4 && onlySplit.split.Length = 4
            && Rect(onlySplit.split[2]) = "960,0,960,540",
            "a custom line without full-height zones walks every zone either way")
        onlyFull := WW_SplitZoneWalks(WW_BuildLayoutZones(work, "1:1:1"), work)
        this.Assert(onlyFull.main.Length = 3 && !onlyFull.split.Length, "and one without split zones has no split walk")

        window := SuiteGui("+Resize", "Zone walk check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w400 h300")
            hwnd := window.Hwnd
            ActivateWindow(hwnd)
            WW_EndZoneCycle()
            before := WW_GetWindowLayoutRectangle(hwnd)
            WW_CycleZone("down", true)
            this.Assert(!WW_IsCyclingZones() && WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), before, 2),
                "the split walk waits for a running walk")
            WW_CycleZone("down")
            WW_CycleZone("down")
            second := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(WW_IsCyclingZones(), "a walk runs the zone-cycling scope")
            WW_CycleZone("down", true)
            top := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(top[1] - second[1]) <= 4 && Abs(top[3] - second[3]) <= 4 && top[4] < second[4] * 0.75,
                "Shift picks up at the top of the column the window is in")
            WW_CycleZone("down", true)
            next := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(next[1] > top[1] && Abs(next[2] - top[2]) <= 4 && Abs(next[4] - top[4]) <= 4,
                "and goes on sideways along the top row")
            WW_CycleZone("up")
            full := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(full[1] - next[1]) <= 4 && Abs(full[3] - next[3]) <= 4 && full[4] > next[4] * 1.5,
                "without Shift, the walk returns to that column's full height")
            WW_CycleZone("up", true)
            bottom := WW_GetWindowLayoutRectangle(hwnd)
            this.Assert(Abs(bottom[1] - full[1]) <= 4 && Abs(bottom[3] - full[3]) <= 4
                && bottom[2] > full[2] + full[4] / 3 && bottom[4] < full[4] * 0.75,
                "Shift with the other key enters that column's bottom row")
            ; Win + Right, then Shift + Left again and again: from the bottom of
            ; the right fourth to the halves page, top row then bottom row, then
            ; the fourths page from the top left.
            WW_EndZoneCycle()
            WW_CycleZone("up")
            area := WW_GetLayoutWorkArea(hwnd)
            WW_CycleZone("down", true)
            seen := []
            loop 7 {
                WW_CycleZone("down", true)
                seen.Push(WW_GetWindowLayoutRectangle(hwnd))
            }
            width := area[3] - area[1], height := area[4] - area[2]
            near(value, expected) => Abs(value - expected) <= 6
            this.Assert(near(seen[1][1], area[1]) && near(seen[1][2], area[2]) && near(seen[1][3], width / 2)
                && near(seen[3][1], area[3] - width / 2) && near(seen[3][2], area[2])
                && near(seen[4][1], area[1]) && near(seen[4][2], area[2] + height / 2) && near(seen[4][3], width / 2)
                && near(seen[7][1], area[1]) && near(seen[7][2], area[2]) && near(seen[7][3], width / 4),
                "stepping back walks the halves page top row then bottom row, then the fourths from the top left")
            ; The opposite key retraces: Win + Right, Shift + Left into the bottom
            ; right, four more to the bottom-left half, then Shift + Right goes
            ; back to the top-right half, and Left and Right keep swapping them.
            WW_EndZoneCycle()
            WW_CycleZone("up")
            WW_CycleZone("down", true)
            loop 4
                WW_CycleZone("down", true)
            bottomLeft := WW_GetWindowLayoutRectangle(hwnd)
            retraced := true
            loop 2 {
                WW_CycleZone("up", true)
                retraced := retraced && WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), seen[3], 4)
                WW_CycleZone("down", true)
                retraced := retraced && WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), bottomLeft, 4)
            }
            this.Assert(retraced && WW_RectanglesMatch(bottomLeft, seen[4], 4),
                "the other key retraces the last step, so the top-right and bottom-left halves swap back and forth")
        }
        finally {
            WW_EndZoneCycle()
            window.Destroy()
        }
    }

    ; Win + Shift + Up steps full height, full width and back; Win + Shift + Down
    ; stretches into free space and back; Win + Down takes a window back to
    ; normal size without minimizing; Win + Up maximizes without placing the
    ; window by hand.
    static FullSpanAndNormalSize() {
        window := SuiteGui("+Resize", "Full span check")
        try {
            SuiteWindowOwnership.AllowArranging(window)
            window.Show("NA x200 y200 w400 h300")
            hwnd := window.Hwnd
            ActivateWindow(hwnd)
            original := WW_GetWindowLayoutRectangle(hwnd)
            work := WW_GetLayoutWorkArea(hwnd)
            WW_CycleFullSpan()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd),
                [original[1], work[2], original[3], work[4] - work[2]], 3),
                "Win + Shift + Up first stretches to full height, keeping width and left edge")
            WW_CycleFullSpan()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd),
                [work[1], original[2], work[3] - work[1], original[4]], 3),
                "then to full width, keeping its height and top")
            returned := []
            handler := (hwnd, shape) => returned.Push(hwnd)
            SuiteWindowOwnership.OnReturn(handler)
            try WW_CycleFullSpan()
            finally SuiteWindowOwnership.OffReturn(handler)
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), original, 3)
                && !SuiteWindowOwnership.IsManual(hwnd) && returned.Length = 1 && returned[1] = hwnd,
                "then puts the window back as it was, handing a lent cascade window back like Win + Down")
            WW_CycleFullSpan()
            WW_RestoreToNormalSize()
            this.Assert(WW_RectanglesMatch(WW_GetWindowLayoutRectangle(hwnd), original, 3)
                && WinGetMinMax(hwnd) = 0,
                "Win + Down takes a full-height window back to normal size")
            WW_RestoreToNormalSize()
            this.Assert(WinGetMinMax(hwnd) = 0, "Win + Down never minimizes a window at normal size")
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
            WW_RestoreToNormalSize()
            this.Assert(WinGetMinMax(hwnd) = 0, "Win + Down takes a maximized window back to normal size")
        }
        finally window.Destroy()
    }

    ; Zone layouts: presets, rows turned 90 degrees, custom lines and the
    ; largest free rectangle Win + Shift + Down fills.
    static ZoneLayoutsAndStretch() {
        work := [0, 0, 1200, 800]
        Rect(zone) => zone[1] "," zone[2] "," zone[3] "," zone[4]
        corners := WW_BuildLayoutZones(work, "corners")
        this.Assert(corners.Length = 6 && Rect(corners[1]) = "0,0,600,800" && Rect(corners[3]) = "0,0,600,400"
            && Rect(corners[6]) = "600,400,600,400",
            "halves and corners walks the halves, then the corners row by row")
        right := WW_BuildLayoutZones(work, "corners", true)
        this.Assert(Rect(right[1]) = "600,0,600,800" && Rect(right[3]) = "600,0,600,400",
            "from the right, each row starts at its right edge")
        rows := WW_BuildLayoutZones([0, 0, 800, 1200], "thirds")
        this.Assert(rows.Length = 15 && Rect(rows[1]) = "0,0,800,400" && Rect(rows[3]) = "0,800,800,400"
            && Rect(rows[4]) = "0,0,800,800" && Rect(rows[6]) = "0,0,400,400",
            "on a portrait display a preset is turned: bands from the top, then their left and right halves")
        halves := WW_BuildLayoutZones([0, 0, 800, 1200], "corners")
        this.Assert(Rect(halves[1]) = "0,0,800,600" && Rect(halves[2]) = "0,600,800,600",
            "turned halves are the top and bottom half")
        this.Assert(Rect(WW_BuildLayoutZones([0, 0, 800, 1200], "1:1")[1]) = "0,0,400,1200",
            "custom lines are never turned")
        this.Assert(WW_SizeDefaultZoneLayout(1536, 864) = "corners" && WW_SizeDefaultZoneLayout(1920, 1080) = "thirds"
            && WW_SizeDefaultZoneLayout(2560, 1440) = "fourths" && WW_SizeDefaultZoneLayout(3440, 1440) = "fourths"
            && WW_SizeDefaultZoneLayout(5120, 1440) = "sixths",
            "a landscape display's default follows its width: halves, thirds, fourths, then sixths")
        this.Assert(WW_SizeDefaultZoneLayout(1080, 1920) = "corners" && WW_SizeDefaultZoneLayout(1440, 2560) = "thirds"
            && WW_DefaultZoneLayout("test|portrait", [2560, 1440], false) = "thirds"
            && WW_DefaultZoneLayout("test|landscape", [1440, 2560], false) = "fourths",
            "a portrait display's default follows its height, and each orientation reads the display's long side")
        portrait := WW_ZoneLayouts.Offered("portrait"), landscape := WW_ZoneLayouts.Offered("landscape")
        this.Assert(portrait.Length = 2 && portrait[1] = "corners" && portrait[2] = "thirds" && landscape.Length = 4,
            "a portrait list offers halves and thirds, a landscape list all four presets")
        this.Assert(!WW_IsUsableZoneLayout("rows-thirds") && WW_IsUsableZoneLayout("sixths")
            && WW_IsUsableZoneLayout("1:1 / 1:1"),
            "a saved layout that no longer reads falls back to the default")
        custom := WW_BuildLayoutZones(work, " 1 : 2 / 1 >1,5:1.5 ")
        this.Assert(custom.Length = 5 && Rect(custom[1]) = "0,0,400,400" && Rect(custom[2]) = "400,0,800,400"
            && Rect(custom[3]) = "0,400,1200,400" && Rect(custom[4]) = "0,0,600,800",
            "a custom line takes columns, rows and pages, ignores whitespace and reads decimal commas")
        for problem in [["", "Type a layout"], ["1::1", "Row 1 has an empty part"], ["1:1 //1", "Row 2 is empty"],
            ["1:0", "Row 1 has 0"], ["1:x", "Row 1 has x"], ["1 > > 1", "Page 2 is empty"],
            ["1:1 > 1/:1", "Page 2, row 2 has an empty part"]] {
            message := ""
            try WW_ParseZoneLine(problem[1])
            catch ValueError as failure
                message := failure.Message
            this.Assert(InStr(message, problem[2]) = 1, "a broken custom line names its problem: " problem[1])
        }
        this.Assert(WW_ZoneLayouts.FromText(" Thirds, then two-thirds ") = "thirds" && WW_ZoneLayouts.FromText("1:1") = "1:1",
            "a dropdown's text names a preset or is a custom line")
        ; A window in the middle with neighbors left, above and a stack behind it.
        neighbors := [[0, 0, 200, 800], [300, 0, 600, 100], [400, 300, 300, 200]]
        this.Assert(Rect(WW_LargestFreeRectangle([400, 300, 300, 200], neighbors, work))
            = "200,100,1000,700",
            "Win + Shift + Down fills the largest gap, ignoring a window it already overlaps")
        this.Assert(Rect(WW_LargestFreeRectangle([400, 300, 300, 200], [], work)) = "0,0,1200,800",
            "without neighbors, the stretch fills the work area")
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
            work := [0, 0, 1600, 900]
            zones := WW_BuildZoneSequence(work, "fourths")
            this.Assert(zones.Length = 21
                && WW_RectanglesMatch(zones[1], [0, 0, 400, 900], 0)
                && WW_RectanglesMatch(zones[4], [1200, 0, 400, 900], 0)
                && WW_RectanglesMatch(zones[6], [400, 0, 800, 900], 0)
                && WW_RectanglesMatch(zones[8], [0, 0, 400, 450], 0)
                && WW_RectanglesMatch(zones[11], [1200, 0, 400, 450], 0)
                && WW_RectanglesMatch(zones[12], [0, 450, 400, 450], 0)
                && WW_RectanglesMatch(zones[16], [0, 0, 800, 450], 0)
                && WW_RectanglesMatch(zones[19], [0, 450, 800, 450], 0)
                && WW_RectanglesMatch(zones[21], [800, 450, 800, 450], 0),
                "fourths: full quarters and halves, then upper and lower quarters, then halves")
            thirds := WW_BuildZoneSequence(work, "thirds")
            this.Assert(thirds.Length = 15 && WW_RectanglesMatch(thirds[2], [533, 0, 534, 900], 0)
                && WW_RectanglesMatch(thirds[4], [0, 0, 1067, 900], 0)
                && WW_RectanglesMatch(thirds[6], [0, 0, 533, 450], 0)
                && WW_RectanglesMatch(thirds[15], [533, 450, 1067, 450], 0),
                "thirds, then two-thirds, then their upper and lower halves, never halves")
            sixths := WW_BuildZoneSequence(work, "sixths")
            this.Assert(sixths.Length = 27 && WW_RectanglesMatch(sixths[2], [267, 0, 266, 900], 1)
                && WW_RectanglesMatch(sixths[7], [0, 0, 533, 900], 1)
                && WW_RectanglesMatch(sixths[9], [1067, 0, 533, 900], 1),
                "sixths, then thirds, with no halves")
            mirrored := WW_BuildZoneSequence(work, "fourths", true)
            this.Assert(WW_RectanglesMatch(mirrored[1], [1200, 0, 400, 900], 0)
                && WW_RectanglesMatch(mirrored[5], [800, 0, 800, 900], 0)
                && WW_RectanglesMatch(mirrored[21], [0, 450, 800, 450], 0),
                "starting from the right mirrors the walk")
            session := WW_StartZoneSession(1, 2, work, "fourths", "down")
            steps := []
            for direction in ["down", "down", "up", "up", "up"]
                steps.Push(WW_AdvanceZoneSession(session, direction, [0, 0]))
            this.Assert(steps[1] = 1 && steps[2] = 2 && steps[3] = 1 && steps[4] = 7 && steps[5] = 6,
                "the other key steps back one zone, wrapping at the ends of the full-height walk")
            ; Each walk starts on the side its key names; one press of the other
            ; key wraps to the last zone on the opposite side.
            session := WW_StartZoneSession(1, 2, work, "fourths", "up")
            this.Assert(WW_RectanglesMatch(session.zones[WW_AdvanceZoneSession(session, "up", [0, 0])],
                    [1200, 0, 400, 900], 0)
                && WW_RectanglesMatch(session.zones[WW_AdvanceZoneSession(session, "up", [0, 0])],
                    [800, 0, 400, 900], 0)
                && WW_AdvanceZoneSession(session, "down", [0, 0]) = 1,
                "Right starts at the right fourth and Left steps back")
            session := WW_StartZoneSession(1, 2, work, "fourths", "down")
            WW_AdvanceZoneSession(session, "down", [0, 0])
            this.Assert(WW_RectanglesMatch(session.zones[WW_AdvanceZoneSession(session, "up", [0, 0])],
                    [800, 0, 800, 900], 0),
                "Left then Right reaches the right half in two presses")
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
            session := WW_StartZoneSession(1, 2, work, "fourths", "down")
            this.Assert(WW_AdvanceZoneSession(session, "down", [600, 0]) = 5,
                "zones an app cannot shrink to are skipped")
            cycle := [101, 102, 103]
            this.Assert(WW_NextMonitorCycleWindow(cycle, 101, 101, true) = 103
                && WW_NextMonitorCycleWindow(cycle, 103, 103, true) = 102
                && WW_NextMonitorCycleWindow(cycle, 0, 0, true) = 103,
                "Win + Shift + Enter walks the stack order backwards, wrapping to the end")
            window := SuiteGui("+ToolWindow", "Owned test window")
            try {
                this.Assert(SuiteWindowOwnership.IsSuiteSurface(window.Hwnd),
                    "private suite tool windows are recognized")
                this.Assert(!SuiteWindowOwnership.AllowsWonderWindows(window.Hwnd),
                    "private suite tool windows are excluded from Wonder Windows")
                this.Assert(IsIgnoredByCascade(window.Hwnd), "suite GUI is marked before it can be cascaded")
                SuiteWindowOwnership.Claim(window.Hwnd)
                this.Assert(SuiteWindowOwnership.IsManual(window.Hwnd), "manual geometry ownership is recorded per HWND and process")
                global WW_full_span_windows, WW_normal_window_placements
                WW_full_span_windows[window.Hwnd] := Map("pid", WindowProcessId(window.Hwnd))
                WW_normal_window_placements[window.Hwnd] := Map("pid", WindowProcessId(window.Hwnd))
                this.Assert(SuiteWindowOwnership.Release(window.Hwnd) && !SuiteWindowOwnership.IsManual(window.Hwnd),
                    "explicit adoption releases manual ownership")
                this.Assert(!WW_full_span_windows.Has(window.Hwnd),
                    "adoption discards a stretch that would otherwise undo the new cascade")
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
