; Wonder Windows: geometry, ownership, tiles, stacking, stack and expanded-window
; cycling, and fullscreen detection.
; Disposable preferences, dry-run inputs and test-owned windows only.
class WonderWindowsChecks {
    static Run() {
        this.GeometryAndOwnership()
        this.OversizedTile()
        this.MoveOntoZone()
        this.FullscreenDetection()
        this.ExpandedWindowCycle()
        this.MonitorWindowCycle()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

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
            vertical := WW_GetCollisionLimitedVerticalBounds([100, 200, 300, 200],
                [[100, 0, 300, 150], [100, 550, 300, 100], [600, 300, 200, 100]], 0, 900)
            this.Assert(vertical[1] = 150 && vertical[2] = 550,
                "vertical extension stops at upper and lower obstacles")
            ; A neighbor on the left, one above the stretched span and one to the right.
            neighbors := [[0, 200, 50, 200], [200, 0, 200, 120], [700, 100, 100, 600]]
            this.Assert(WW_RectanglesMatch(
                WW_NeighborStretchRectangle([100, 200, 300, 200], neighbors, [0, 0, 900, 1100], "across"),
                [50, 200, 650, 200], 0),
                "stretching across stops at the nearest windows on the left and right")
            this.Assert(WW_RectanglesMatch(
                WW_NeighborStretchRectangle([100, 200, 300, 200], neighbors, [0, 0, 900, 1100], "fill"),
                [50, 120, 650, 980], 0),
                "filling also stops at windows above and below the stretched span")
            this.Assert(WW_RectanglesMatch(
                WW_NeighborStretchRectangle([100, 200, 300, 200], [], [0, 0, 900, 1100], "fill"),
                [0, 0, 900, 1100], 0),
                "without neighbors, filling reaches the work area's edges")
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
            this.Assert(thirds.Length = 9 && WW_RectanglesMatch(thirds[2], [533, 0, 534, 900], 0)
                && WW_RectanglesMatch(thirds[4], [0, 0, 533, 450], 0)
                && WW_RectanglesMatch(thirds[9], [1067, 450, 533, 450], 0),
                "thirds skip the halves")
            mirrored := WW_BuildZoneSequence(work, "fourths", true)
            this.Assert(WW_RectanglesMatch(mirrored[1], [1200, 0, 400, 900], 0)
                && WW_RectanglesMatch(mirrored[5], [800, 0, 800, 900], 0)
                && WW_RectanglesMatch(mirrored[21], [0, 450, 800, 450], 0),
                "starting from the right mirrors the walk")
            session := WW_StartZoneSession(1, 2, work, "fourths", "down")
            steps := []
            for direction in ["down", "down", "up", "up", "up"]
                steps.Push(WW_AdvanceZoneSession(session, direction, [0, 0]))
            this.Assert(steps[1] = 1 && steps[2] = 2 && steps[3] = 1 && steps[4] = 21 && steps[5] = 20,
                "the other key steps back one zone, wrapping at the ends")
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
                    [800, 450, 800, 450], 0),
                "Left then Right reaches the lower-right half in two presses")
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
                "Win + Down restores placed, maximized and fullscreen windows before minimizing")
            session := WW_StartZoneSession(1, 2, work, "fourths", "down")
            this.Assert(WW_AdvanceZoneSession(session, "down", [600, 0]) = 5,
                "zones an app cannot shrink to are skipped")
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[100, 0, 200, 300]], 0) = 300,
                "horizontal stretch stops at the nearest facing edge")
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[450, 0, 200, 300]], 0) = 0,
                "pre-existing overlap does not collapse a stretched window")
            window := SuiteGui("+ToolWindow", "Owned test window")
            try {
                this.Assert(SuiteWindowOwnership.IsSuiteSurface(window.Hwnd),
                    "private suite tool windows are recognized")
                this.Assert(!SuiteWindowOwnership.AllowsWonderWindows(window.Hwnd),
                    "private suite tool windows are excluded from Wonder Windows")
                this.Assert(IsIgnoredByCascade(window.Hwnd), "suite GUI is marked before it can be cascaded")
                SuiteWindowOwnership.Claim(window.Hwnd)
                this.Assert(SuiteWindowOwnership.IsManual(window.Hwnd), "manual geometry ownership is recorded per HWND and process")
                global WW_stretched_windows, WW_normal_window_placements
                WW_stretched_windows[window.Hwnd] := Map("pid", WindowProcessId(window.Hwnd))
                WW_normal_window_placements[window.Hwnd] := Map("pid", WindowProcessId(window.Hwnd))
                this.Assert(SuiteWindowOwnership.Release(window.Hwnd) && !SuiteWindowOwnership.IsManual(window.Hwnd),
                    "explicit adoption releases manual ownership")
                this.Assert(!WW_stretched_windows.Has(window.Hwnd),
                    "adoption discards stretch cleanup that would otherwise undo the new cascade")
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
        this.Assert(WW_WindowsStack([100, 100, 800, 600], [140, 120, 800, 600])
            && !WW_WindowsStack([0, 0, 640, 1080], [640, 0, 640, 1080])
            && !WW_WindowsStack([0, 0, 960, 1080], maximized)
            && !WW_WindowsStack([0, 0, 640, 1080], maximized)
            && !WW_WindowsStack([0, 0, 200, 150], [0, 0, 800, 600]),
            "only windows sharing most of each other's area stack")

        ; Explorer over Terminal on the left, VS Code over Firefox in the middle,
        ; a lone window on the right and a maximized window behind them all.
        stacks := WW_GroupWindowStacks([
            {hwnd: 201, rect: [0, 0, 640, 1080]}, {hwnd: 301, rect: [640, 0, 640, 1080]},
            {hwnd: 202, rect: [10, 20, 630, 1060]}, {hwnd: 401, rect: [1280, 0, 640, 1080]},
            {hwnd: 302, rect: [640, 0, 640, 1080]}, {hwnd: 501, rect: maximized}])
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
            {hwnd: 501, rect: maximized}]
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
