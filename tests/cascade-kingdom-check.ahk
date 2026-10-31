; Cascade Kingdom: destinations, settings, stabilization, drop guides, focus tabs, adoption,
; compaction plans, home displays, the next-cascade order, snapped-window drags,
; mirroring and cascades kept across restarts.
; Disposable preferences, dry-run inputs and test-owned windows only.
class CascadeChecks {
    static Run() {
        this.LiveCascadeSettings()
        this.PlacementStabilization()
        this.FocusTabDpi()
        WW_RunWindowCommand(ObjBindMethod(this, "MaximizedAdoption"))
        this.SavedCascades()
        this.CompactionPlan()
        this.HomeDisplays()
        this.NextCascade()
        this.DragResize()
        this.Mirrored()
        this.ShownWindows()
        this.Policy()
        this.Settings()
        this.Guides()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    ; A mirrored cascade swaps left and right: slots and the corner a drop is judged by.
    static Mirrored() {
        normal := BuildCanonicalCascadeGeometry(0, 0, 1920, 1080).slots
        MonitorGetWorkAreaPixels(MonitorGetPrimary(), &left, &top)
        try {
            CascadeState.mirrored := true
            mirrored := BuildCanonicalCascadeGeometry(0, 0, 1920, 1080).slots
            this.Assert(mirrored.Length = normal.Length && mirrored[1][1] = normal[1][1]
                && mirrored[2][1] - mirrored[1][1] = 28 && mirrored[2][2] - mirrored[1][2] = -24,
                "a mirrored cascade has as many slots and steps up to the right from the center")
            this.Assert(mirrored[mirrored.Length][1] = 2 * normal[1][1] - normal[normal.Length][1]
                && mirrored[mirrored.Length][2] = normal[normal.Length][2],
                "and down to the left, mirroring every slot")
            target := CascadeDropTarget(left + 100, top + 100, 800)
            this.Assert(target && target.monitor = MonitorGetPrimary()
                && target.x = left + 100 + 800 - target.geometry.width,
                "a mirrored drop is judged by the window's top-right corner")
            CascadeState.mirrored := false
            target := CascadeDropTarget(left + 100, top + 100, 800)
            this.Assert(target && target.x = left + 100, "a normal drop is judged by the top-left corner")
        }
        finally CascadeState.mirrored := false
    }

    ; A window snapped to half a display, 1294 x 1395, was 2062 x 1117 before.
    static DragResize() {
        drag := {hwnd: A_ScriptHwnd, dpi: GetCascadeWindowMonitorDpi(A_ScriptHwnd), minmax: 0,
            resize: false, width: 1294, height: 1395, normal_width: 2062, normal_height: 1117}
        this.Assert(!CascadeDragIsResize(drag, 1294, 1395), "a moved window keeps its size")
        this.Assert(!CascadeDragIsResize(drag, 2062, 1117),
            "a snapped window taking back its earlier size is no resize")
        this.Assert(CascadeDragIsResize(drag, 1400, 1395), "any other size change is a resize")
        drag.resize := true
        this.Assert(CascadeDragIsResize(drag, 1294, 1395), "a press on an edge is a resize")
    }

    ; Three displays side by side, monitor 2 on the left, 1 in the middle and
    ; 3 on the right, with a fourth stacked below the right one.
    static NextCascade() {
        all := [{monitor: 2, left: -1920, top: 0}, {monitor: 1, left: 0, top: 0},
            {monitor: 3, left: 1920, top: 0}, {monitor: 4, left: 1920, top: 1080}]
        this.Assert(NextCascadeMonitor(all, 1, 0, 0) = 3, "the next cascade is the one to the right")
        this.Assert(NextCascadeMonitor(all, 3, 1920, 0) = 4, "a display below comes after the one above it")
        this.Assert(NextCascadeMonitor(all, 4, 1920, 1080) = 2, "the last cascade wraps to the leftmost")
        this.Assert(NextCascadeMonitor(all, 0, 0, 0) = 1,
            "from outside a cascade, the one on the working display comes first")
        middle := [all[1], all[3]]
        this.Assert(NextCascadeMonitor(middle, 0, 0, 0) = 3,
            "from a display without a cascade, the next one to the right comes first")
        this.Assert(NextCascadeMonitor(middle, 0, 1920, 1080) = 2,
            "from the bottom-right display without a cascade, the search wraps to the left")
        this.Assert(NextCascadeMonitor([all[2]], 1, 0, 0) = 0, "the only cascade has no next one")
        this.Assert(NextCascadeMonitor([all[2]], 0, 1920, 0) = 1,
            "the only cascade is focused from another display")
    }

    ; Display 1 is the primary; the left display may be unplugged.
    static HomeDisplays() {
        both := Map(1, {device: "RIGHT"}, 2, {device: "LEFT"})
        right := Map(1, {device: "RIGHT"})
        this.Assert(CascadeMemberDestination("LEFT", "", right, 1, &home) = 1 && home = "LEFT",
            "a window whose display is unplugged moves to the primary and remembers its home")
        this.Assert(CascadeMemberDestination("RIGHT", "LEFT", both, 1, &home) = 2 && home = "",
            "a displaced window returns home when its display reconnects")
        this.Assert(CascadeMemberDestination("RIGHT", "LEFT", right, 1, &home) = 1 && home = "LEFT",
            "a displaced window keeps its home while that display stays away")
        this.Assert(CascadeMemberDestination("RIGHT", "", both, 1, &home) = 1 && home = "",
            "a window on a display that stays has no home to return to")
        this.Assert(CascadeMemberDestination("", "", right, 1, &home) = 1 && home = "",
            "a window from an unknown display falls back without a home")
        this.Assert(this.Plan([[1, 5], [2, 6], [], []]) = "|1|2|5|6|",
            "cascades merged onto one display spread out instead of sharing slots")
    }

    static Plan(stacks, preferred := 0) {
        text := ""
        for stack in BuildStableCascadeCompactionPlan(stacks, preferred) {
            text .= "|"
            for hwnd in stack
                text .= (A_Index > 1 ? "," : "") hwnd
        }
        return text "|"
    }

    ; Stacks are front-to-back window lists per slot; numbers stand in for windows.
    static CompactionPlan() {
        this.Assert(this.Plan([[1], [2], [], [4], [5]]) = "|1|2|5|4||",
            "a minimized window's hole is filled from the last slot")
        this.Assert(this.Plan([[1], [2], [3, 5], [4], []]) = "|1|2|3|4|5|",
            "a restored window takes its slot back and the filler returns")
        this.Assert(this.Plan([[1, 6], [2], [], [4], [5]]) = "|1|2|6|4|5|",
            "a hole is filled from a deeper stack first")
        this.Assert(this.Plan([[1], [2], [], [4], [5, 3]], 3) = "|1|2|5|4|3|",
            "a dropped window keeps its slot")
        this.Assert(this.Plan([[1], [2], [], [], [3]], 3) = "|1|2|3|||",
            "a drop past the end of the cascade lands at its end")
    }

    static ShownWindows() {
        InitializeCascadeState()
        window := SuiteGui("+Resize", "Shown check")
        try {
            SuiteShowCentered(window, 320, 240)
            this.Assert(IsCascadeWindowShown(window.Hwnd), "a restored window occupies its slot")
            WinMaximize(window.Hwnd)
            maximized := IsCascadeWindowShown(window.Hwnd)
            WinRestore(window.Hwnd)
            WinMinimize(window.Hwnd)
            minimized := IsCascadeWindowShown(window.Hwnd)
            WinRestore(window.Hwnd)
            window.Hide()
            this.Assert(!maximized && !minimized && !IsCascadeWindowShown(window.Hwnd),
                "maximized, minimized and hidden windows give up their slot")
        }
        finally {
            window.Destroy()
        }
    }

    static Policy() {
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-policy")
        app.modules["cascade-kingdom"] := CascadeKingdomModule(app)
        previousCritical := Critical("On")
        try {
            CascadeState.displays := Map(1, {device: "left"}, 2, {device: "right"})
            this.Assert(ResolveCascadeDestination(2) = 2,
                "All displays retains the requested destination")
            this.Assert(!CascadeState.history.Count && CascadeDisplayAllowed(1)
                && CascadeDisplayAllowed(2),
                "empty cascades allow dropping onto either display")
            CascadeState.targetDisplay := "right"
            this.Assert(ResolveCascadeDestination(1) = 2 && CascadeDisplayAllowed(2)
                && !CascadeDisplayAllowed(1),
                "a single display redirects adoption and excludes other drop zones")
            this.Assert(!CascadeDisplayAllowed(1) && CascadeDisplayAllowed(2),
                "an excluded display cannot remain a drag destination")
            CascadeState.displays := Map(1, {device: "right"}, 2, {device: "left"})
            this.Assert(ResolveCascadeDestination(2) = 1,
                "the selected destination follows device name through index changes")
            CascadeState.targetDisplay := "disconnected"
            this.Assert(!ResolveCascadeDestination(1),
                "a disconnected selected display never redirects onto another screen")
        }
        finally {
            InitializeCascadeState()
            Critical(previousCritical)
        }
    }

    static Settings() {
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-settings")
        cascade := CascadeKingdomModule(app)
        app.modules["cascade-kingdom"] := cascade
        app.modules["paper-pad"] := PaperPadModule(app)
        app.ui := SuiteInterface(app)
        try {
            choices := app.ui.DisplayChoices("Primary")
            this.Assert(choices.values.Length = MonitorGetCount()
                && choices.values[choices.selected] = MonitorGetName(MonitorGetPrimary()),
                "Paper Pad lists each display once and defaults to the actual primary display")
            for value in choices.values
                this.Assert(value != "Primary", "the duplicate primary-display alias is not a choice")
            all := app.ui.DisplayChoices("All", true)
            this.Assert(all.values.Length = MonitorGetCount() + 1
                && all.values[all.selected] = "All" && all.names[all.selected] = "All displays",
                "Cascade Kingdom adds exactly one All displays choice")
            missing := app.ui.DisplayChoices("disconnected", true)
            this.Assert(missing.values[missing.selected] = "disconnected"
                && InStr(missing.names[missing.selected], "unavailable"),
                "missing saved displays remain visible without silently changing the preference")
            app.ui.ShowModuleSettings("cascade-kingdom")
            window := app.ui.windows["settings:cascade-kingdom"]
            this.Assert(window["inactiveColor"].Text = "White"
                && CascadeState.focusCornerActiveSlotAlpha = 255
                && CascadeState.focusCornerInactiveSlotAlpha = 128,
                "cascade settings default to White inactive tabs at 50% opacity")
            this.Assert(!window["mirrored"].Value, "cascades step to the right by default")
            window["inactiveColor"].Choose("Cyan")
            window["mirrored"].Value := true
            ; Use a real device, not the dropdown index, in the saved preference.
            window["display"].Choose(2)
            expectedDisplay := cascade.displayChoices[2]
            cascade.SaveSettings(app.ui)
            ; Mirroring queues a re-layout; these checks own no cascade to move.
            this.Assert(CascadeState.mirrored && IsCascadeDisplayTransition(),
                "mirroring applies at once and re-lays out the cascades")
            SetTimer(RefreshCascadeDisplays, 0)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && IniRead(path, "Controls", "Display") = expectedDisplay
                && IniRead(path, "Controls", "Mirrored") = "1"
                && IniRead(path, "FocusTabs", "InactiveSlotColor") = "Cyan",
                "Apply persists the destination device, mirroring and inactive tab color")
            InitializeCascadeState()
            this.Assert(CascadeState.targetDisplay = expectedDisplay && CascadeState.mirrored
                && CascadeState.focusCornerInactiveSlotColorName = "Cyan",
                "cascade choices survive state initialization")
            app.Settings.ResetModulePreferences(Map("cascade-kingdom", cascade.resetSections))
            this.Assert(IniRead(path, "FocusTabs", "InactiveSlotColor", "missing") = "missing"
                && IniRead(path, "Controls", "Mirrored", "missing") = "missing",
                "factory reset includes mirroring and the inactive tab color")
            InitializeCascadeState()
            app.ui.ShowModuleSettings("paper-pad")
            window := app.ui.windows["settings:paper-pad"]
            displays := app.modules["paper-pad"].displayChoices
            this.Assert(displays.Length = MonitorGetCount()
                && displays[window["display"].Value] = MonitorGetName(MonitorGetPrimary()),
                "the Paper Pad dropdown uses the deduplicated primary selection")
        }
        finally app.ui.CloseAll()
    }

    static LiveCascadeSettings() {
        app := SuiteApplication(true, SuiteChecks.directory "\live-cascade-settings")
        app.InitializeCatalog()
        manager := app.manager
        previous := {visible: CascadeState.focusCornerVisible,
            inactiveName: CascadeState.focusCornerInactiveSlotColorName,
            inactiveColor: CascadeState.focusCornerInactiveSlotColor}
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowModuleSettings("cascade-kingdom")
            settings := app.ui.windows["settings:cascade-kingdom"]
            expectedVisible := !previous.visible
            inactiveName := previous.inactiveName = "Blue" ? "Grey" : "Blue"
            settings["tabs"].Value := expectedVisible
            settings["inactiveColor"].Choose(inactiveName)
            existingHistorySize := CascadeState.history.Count
            this.Assert(app.ui.pageFooters[settings.Hwnd].buttons[1].button.Text = "Apply",
                "Cascade Kingdom Settings use Apply without restart")
            app.modules["cascade-kingdom"].SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && CascadeState.focusCornerVisible = expectedVisible
                && CascadeState.focusCornerInactiveSlotColorName = inactiveName
                && CascadeState.focusCornerInactiveSlotColor = CascadeState.focusTabColorPresets[inactiveName],
                "Cascade Kingdom applies focus-tab preferences without reload")
            this.Assert(IniRead(path, "FocusTabs", "Visible") = (expectedVisible ? "1" : "0")
                && IniRead(path, "FocusTabs", "InactiveSlotColor") = inactiveName,
                "Cascade Kingdom persists its focus-tab preferences")
            this.Assert(CascadeState.history.Count = existingHistorySize,
                "applying Cascade Kingdom preferences preserves in-memory cascade history")
        }
        finally {
            CascadeState.focusCornerVisible := previous.visible
            CascadeState.focusCornerInactiveSlotColorName := previous.inactiveName
            CascadeState.focusCornerInactiveSlotColor := previous.inactiveColor
            if IsObject(app.ui)
                app.ui.CloseAll()
            manager.Stop()
        }
    }

    static PlacementStabilization() {
        app := SuiteApplication(true, SuiteChecks.directory "\placement-stabilization")
        InitializeCascadeState()
        source := SuiteGui("+Resize", "Stabilization source")
        target := SuiteGui("+Resize", "Stabilization target")
        previousCritical := Critical("On")
        try {
            SuiteShowCentered(source, 320, 240)
            SuiteShowCentered(target, 340, 260)
            sourceMonitor := WindowMonitorIndex(source.Hwnd)
            WinMinimize(source.Hwnd)
            this.Assert(WindowMonitorIndex(source.Hwnd) = sourceMonitor,
                "a minimized window retains its restored monitor")
            WinRestore(source.Hwnd)

            ; Simulate a placed member. The ignore marker is removed only from
            ; this fixture, never from a personal window.
            app.dryRun := false
            DllCall("RemovePropW", "ptr", target.Hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr")
            GetVisibleWindowBounds(target.Hwnd, &x, &y, &width, &height)
            CascadeState.history[sourceMonitor] := [target.Hwnd]
            CascadeState.placementStabilizationGenerations[target.Hwnd] := 101
            CascadeState.placementReservations[target.Hwnd] := Map("monitor", sourceMonitor, "x", x, "y", y)
            StabilizePlacedWindow(target.Hwnd, x, y, width, height, 101)
            this.Assert(!CascadeState.placementStabilizationGenerations.Has(target.Hwnd)
                && !CascadeState.placementReservations.Has(target.Hwnd),
                "a matching stabilization check releases its reservation")
            CascadeState.placementStabilizationGenerations[target.Hwnd] := 103
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 103, true)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && !CascadeState.placementStabilizationGenerations.Has(target.Hwnd),
                "after its one correction, a window that is still off is left to its application")
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 101)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && afterWidth = width && afterHeight = height,
                "an expired stabilization callback cannot move a window")
            CascadeState.history.Clear()
            CascadeState.placementStabilizationGenerations[target.Hwnd] := 102
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 102)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && !CascadeState.placementStabilizationGenerations.Has(target.Hwnd),
                "stabilization never moves a window that left the cascade")
        }
        finally {
            app.stopping := true
            app.dryRun := true
            InitializeCascadeState()
            source.Destroy()
            target.Destroy()
            SetTimer(RunQueuedFocusCornerUpdate, 0)
            Critical(previousCritical)
        }
    }

    static FocusTabDpi() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-focus-tabs")
        InitializeCascadeState()
        window := SuiteGui("+Resize", "Release focus-tab target")
        previousCritical := Critical("On")
        try {
            window.Show("NA w300 h200")
            app.dryRun := false
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(CascadeState.focusCornerOverlays.Has(window.Hwnd)
                && CascadeState.focusCornerOverlays[window.Hwnd].dpi = 144,
                "focus tabs use the DPI supplied by the validated rendering snapshot")
            overlay := CascadeState.focusCornerOverlays[window.Hwnd]
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(CascadeState.focusCornerOverlays[window.Hwnd] = overlay,
                "unchanged focus-tab rendering reuses its GUI")
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 96)
            this.Assert(overlay.dpi = 96, "a changed DPI snapshot updates the existing focus tab")
            ; At 96 DPI: 54 x 24 corner tabs, 36-wide full-height ones, 2 px inside.
            WinGetPosPixels(&lx, &ly, &lw, &lh, overlay.guis[1].Hwnd)
            WinGetPosPixels(&rx, &ry, &rw, &rh, overlay.guis[2].Hwnd)
            this.Assert(lx = 48 && ly = 276 && lw = 54 && lh = 24,
                "the left focus tab sits outside the window's lower-left corner")
            this.Assert(rx = 398 && ry = 100 && rw = 54 && rh = 24,
                "the right focus tab mirrors it outside the upper-right corner")
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 96, true, true)
            WinGetPosPixels(&lx, &ly, &lw, &lh, overlay.guis[1].Hwnd)
            WinGetPosPixels(&rx, &ry, &rw, &rh, overlay.guis[2].Hwnd)
            this.Assert(lx = 66 && ly = 100 && lw = 36 && lh = 200 && rx = 398 && ry = 100 && rw = 36 && rh = 200,
                "full-height tabs run along both sides")
            this.Assert(DllCall("GetWindow", "ptr", overlay.guis[1].Hwnd, "uint", 3, "ptr") = window.Hwnd
                && DllCall("GetWindow", "ptr", overlay.guis[2].Hwnd, "uint", 3, "ptr") = overlay.guis[1].Hwnd,
                "both tabs sit directly below their window")
            this.Assert(CascadeState.focusCornerTargets.Get(overlay.guis[2].Hwnd, 0) = window.Hwnd,
                "a click on the right tab finds its window")
            CascadeState.mirrored := true
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 96)
            WinGetPosPixels(&lx, &ly, , , overlay.guis[1].Hwnd)
            WinGetPosPixels(&rx, &ry, , , overlay.guis[2].Hwnd)
            this.Assert(lx = 48 && ly = 100 && rx = 398 && ry = 276,
                "a mirrored cascade's tabs sit at the upper left and the lower right")
        }
        finally {
            CascadeState.mirrored := false
            DestroyFocusCornerOverlay(window.Hwnd)
            window.Destroy()
            app.dryRun := true
            Critical(previousCritical)
        }
    }

    static Guides() {
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-guide-tests")
        cascade := CascadeKingdomModule(app)
        MonitorGetWorkAreaPixels(MonitorGetPrimary(), &left, &top, &right, &bottom)
        slots := [[left + 30, top + 30], [left + 58, top + 54]]
        foreground := DllCall("GetForegroundWindow", "ptr")
        try {
            CascadeDropGuides.Show(slots, 96, "808080")
            this.Assert(CascadeDropGuides.windows.Length = 2, "one guide is created per visible slot")
            first := CascadeDropGuides.windows[1].Hwnd
            for window in CascadeDropGuides.windows {
                style := WinGetExStyle(window.Hwnd)
                this.Assert((style & 0x08000020) = 0x08000020
                    && WinGetTransparent(window.Hwnd) = 255 && IsIgnoredByCascade(window.Hwnd),
                    "drop guides are opaque, non-activating, click-through and excluded from adoption")
            }
            this.Assert(DllCall("GetForegroundWindow", "ptr") = foreground,
                "showing guides does not steal focus")
            region := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
            try {
                this.Assert(region && DllCall("GetWindowRgn", "ptr", first, "ptr", region, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 1, "int", 10, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 10, "int", 1, "int")
                    && !DllCall("gdi32\PtInRegion", "ptr", region, "int", 10, "int", 10, "int"),
                    "guide regions contain only the top and left strokes")
            }
            finally {
                if region
                    DllCall("gdi32\DeleteObject", "ptr", region)
            }
            CascadeDropGuides.Show(slots, 96, "808080")
            this.Assert(CascadeDropGuides.windows[1].Hwnd = first,
                "unchanged drag guides reuse their windows")
            CancelCascadeWindowDrop()
            this.Assert(!DllCall("IsWindowVisible", "ptr", first, "int"),
                "cancelling a drag hides its guides immediately")
            CascadeDropGuides.Show(slots, 144, "00BCD4")
            this.Assert(CascadeDropGuides.windows[1].Hwnd = first,
                "DPI and color changes reuse the guide windows")
            ; Mirrored: a 20 px guide marks the top-right corner of a 300 px window.
            CascadeDropGuides.Show(slots, 96, "808080", 300)
            WinGetPosPixels(&guideX, &guideY, , , first)
            region := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
            try {
                this.Assert(guideX = left + 30 + 300 - 20 && guideY = top + 30
                    && region && DllCall("GetWindowRgn", "ptr", first, "ptr", region, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 18, "int", 10, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 10, "int", 1, "int")
                    && !DllCall("gdi32\PtInRegion", "ptr", region, "int", 1, "int", 10, "int"),
                    "mirrored guides mark the top and right strokes of each slot's top-right corner")
            }
            finally {
                if region
                    DllCall("gdi32\DeleteObject", "ptr", region)
            }
            cascade.Suspend()
            this.Assert(!DllCall("IsWindowVisible", "ptr", first, "int"),
                "suspension hides all drag guides")
            CascadeDropGuides.Destroy()
            this.Assert(!DllCall("IsWindow", "ptr", first, "int") && !CascadeDropGuides.windows.Length,
                "guide cleanup destroys every owned window")
        }
        finally CascadeDropGuides.Destroy()
    }

    static MaximizedAdoption() {
        app := SuiteApplication(true, SuiteChecks.directory "\maximized-adoption")
        InitializeCascadeState()
        window := SuiteGui("+Resize -DPIScale", "Maximized adoption fixture")
        previousCritical := Critical("On")
        try {
            ; Stay in dry run: no hooks, desktop discovery or real adoption.
            ; Only the test-owned window is restored/moved by the join-position check.
            ; Populate display geometry without starting hooks or discovery.
            CascadeState.displays := ReadCascadeDisplays().displays
            window.Show("x60 y60 w320 h220")
            hwnd := window.Hwnd
            original := CaptureWindowPlacement(hwnd)
            WinMaximize(hwnd)
            WinActivate(hwnd)
            this.Assert(!!WinWaitActive(hwnd, , 1),
                "maximized adoption fixture owns foreground")
            this.Assert(ActiveWindowBlocksCascadeCommands()
                && !ActiveWindowBlocksCascadeCommands(true),
                "only commands allowed over a maximized window bypass its guard")
            CascadeState.windowDrag := {}
            this.Assert(ActiveWindowBlocksCascadeCommands(true),
                "maximized adoption still respects an active native drag")
            CascadeState.windowDrag := 0

            position := CaptureWindowShape(hwnd)
            this.Assert(IsObject(position) && IsObject(position.placement),
                "maximized adoption snapshots native placement before restoring")
            position.was_manual := false
            WinRestore(hwnd)
            WinMove(100, 100, 420, 280, hwnd)
            this.Assert(ReturnToCascadeJoinPosition(hwnd, position) && WinGetMinMax(hwnd) = 1,
                "taking a window out restores its maximized state")
            restored := CaptureWindowPlacement(hwnd)
            sameRectangle := true
            for offset in [28, 32, 36, 40]
                sameRectangle := sameRectangle
                    && NumGet(original, offset, "int") = NumGet(restored, offset, "int")
            this.Assert(sameRectangle,
                "taking a window out preserves its original normal restore rectangle")

            WinRestore(hwnd)
            normalPosition := CaptureWindowShape(hwnd)
            this.Assert(IsObject(normalPosition) && !normalPosition.placement,
                "a normal window's join position is geometry only")
            normalPosition.was_manual := false
            normalPosition.x := -100000
            this.Assert(!ReturnToCascadeJoinPosition(hwnd, normalPosition),
                "a window whose old display is gone stays where it is")

            WinSetStyle((WinGetStyle(hwnd) & ~0xC40000) | 0x80000000, hwnd)
            WinSetExStyle(WinGetExStyle(hwnd) & ~0x300, hwnd)
            WonderWindowsChecks.RefreshFrame(hwnd)
            WW_GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
            WinMove(left, top, right - left, bottom - top, hwnd)
            this.Assert(WW_IsNativeFullscreen(hwnd) && ActiveWindowBlocksCascadeCommands(true),
                "allowing maximized adoption does not bypass the fullscreen guard")
        }
        finally {
            StopCascadeDisplays()
            InitializeCascadeState()
            window.Destroy()
            Critical(previousCritical)
        }
    }

    static SavedCascades() {
        app := SuiteApplication(true, SuiteChecks.directory "\saved-cascades")
        InitializeCascadeState()
        member := SuiteGui("+Resize", "Saved cascade member")
        closed := SuiteGui("+Resize", "Saved cascade closed window")
        lent := SuiteGui("+Resize", "Saved cascade lent window")
        returned := SuiteGui("+Resize", "Saved cascade returned window")
        previousCritical := Critical("On")
        try {
            CascadeState.displays := ReadCascadeDisplays().displays
            member.Show("NA x60 y60 w320 h220")
            closed.Show("NA x80 y80 w320 h220")
            lent.Show("NA x100 y100 w320 h220")
            returned.Show("NA x120 y120 w320 h220")
            WinMaximize(member.Hwnd)
            position := CaptureWindowShape(member.Hwnd)
            position.was_manual := true
            WinRestore(member.Hwnd)
            monitor := WindowMonitorIndex(member.Hwnd)
            slot := GetCanonicalCascadeGeometry(monitor).slots[1]
            WinMovePixels(slot[1], slot[2], 400, 300, "ahk_id " member.Hwnd)
            CascadeState.history[monitor] := [member.Hwnd, closed.Hwnd]
            CascadeState.joinPositions[member.Hwnd] := position
            ; One loan is still maximized by Wonder Windows; the other is back in slot 2.
            WinMaximize(lent.Hwnd)
            slot2 := GetCanonicalCascadeGeometry(monitor).slots[2]
            WinMovePixels(slot2[1], slot2[2], 400, 300, "ahk_id " returned.Hwnd)
            device := CascadeState.displays[monitor].device
            for window in [lent, returned]
                CascadeState.lentWindows[window.Hwnd] := {pid: WinGetPID(window.Hwnd), monitor: monitor,
                    device: device, slot: 2}
            SaveCascades()

            ; A closed window and a handle now owned by another process stay out.
            closedHwnd := closed.Hwnd
            closed.Destroy()
            IniWrite(IniRead(CascadeState.statePath, "Cascades") "`n" A_ScriptHwnd "=1|"
                . CascadeState.displays[monitor].device "|", CascadeState.statePath, "Cascades")
            InitializeCascadeState()
            CascadeState.displays := ReadCascadeDisplays().displays
            RestoreSavedCascades()
            this.Assert(GetManagedCascadeMonitor(member.Hwnd) = monitor
                && !GetManagedCascadeMonitor(closedHwnd) && !GetManagedCascadeMonitor(A_ScriptHwnd),
                "a restart keeps live cascade members and skips closed or reused windows")
            restored := CascadeState.joinPositions.Has(member.Hwnd) ? CascadeState.joinPositions[member.Hwnd] : 0
            samePlacement := IsObject(restored) && IsObject(restored.placement)
                && restored.placement.Size = position.placement.Size
            if samePlacement
                Loop position.placement.Size
                    samePlacement := samePlacement && NumGet(restored.placement, A_Index - 1, "uchar")
                        = NumGet(position.placement, A_Index - 1, "uchar")
            this.Assert(samePlacement && restored.x = position.x && restored.width = position.width
                && restored.was_manual,
                "a restored member keeps its join position, maximized placement included")
            this.Assert(CascadeState.lentWindows.Has(lent.Hwnd) && CascadeState.lentWindows[lent.Hwnd].slot = 2
                && SuiteWindowOwnership.IsManual(lent.Hwnd) && !GetManagedCascadeMonitor(lent.Hwnd),
                "a restart keeps a window lent to Wonder Windows, claimed so Win + Down can return it")
            this.Assert(GetManagedCascadeMonitor(returned.Hwnd) = monitor
                && !CascadeState.lentWindows.Has(returned.Hwnd),
                "a lent window already back in a slot rejoins on restart")
        }
        finally {
            InitializeCascadeState()
            SetTimer(RunQueuedFocusCornerUpdate, 0)
            SuiteWindowOwnership.Release(lent.Hwnd, false)
            member.Destroy()
            lent.Destroy()
            returned.Destroy()
            try closed.Destroy()
            Critical(previousCritical)
        }
    }
}
