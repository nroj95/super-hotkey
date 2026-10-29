; Cascade Kingdom: destinations, settings, stabilization, drop guides, focus tabs and adoption.
; Disposable preferences, dry-run inputs and test-owned windows only.
class CascadeChecks {
    static Run() {
        this.LiveCascadeSettings()
        this.PlacementStabilization()
        this.FocusTabDpi()
        WW_RunWindowCommand(ObjBindMethod(this, "MaximizedAdoption"))
        this.Policy()
        this.Settings()
        this.Guides()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static Policy() {
        global cascade_target_display, cascade_displays, cascade_history
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-policy")
        app.modules["cascade-kingdom"] := CascadeKingdomModule(app)
        previousCritical := Critical("On")
        try {
            cascade_displays := Map(1, {device: "left"}, 2, {device: "right"})
            this.Assert(ResolveCascadeDestination(2) = 2,
                "All displays retains the requested destination")
            this.Assert(!cascade_history.Count && HasCascadeDropDestination(1)
                && HasCascadeDropDestination(2),
                "empty cascades allow dropping onto either display")
            cascade_target_display := "right"
            this.Assert(ResolveCascadeDestination(1) = 2 && CascadeDisplayAllowed(2)
                && !CascadeDisplayAllowed(1),
                "a single display redirects adoption and excludes other drop zones")
            this.Assert(!HasCascadeDropDestination(1) && HasCascadeDropDestination(2),
                "an excluded display cannot remain a drag destination")
            cascade_displays := Map(1, {device: "right"}, 2, {device: "left"})
            this.Assert(ResolveCascadeDestination(2) = 1,
                "the selected destination follows device name through index changes")
            cascade_target_display := "disconnected"
            this.Assert(!ResolveCascadeDestination(1),
                "a disconnected selected display never redirects onto another screen")
        }
        finally {
            InitializeCascadeState()
            Critical(previousCritical)
        }
    }

    static Settings() {
        global cascade_target_display, cascade_drop_guide_color_name
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
            this.Assert(window["activeColor"].Text = "Yellow"
                && window["inactiveColor"].Text = "White"
                && window["guideColor"].Text = "Pink"
                && focus_corner_active_slot_alpha = 255
                && focus_corner_inactive_slot_alpha = 128,
                "cascade settings default to Yellow/White/Pink and 50% inactive opacity")
            window["guideColor"].Choose("Cyan")
            ; Use a real device, not the dropdown index, in the saved preference.
            window["display"].Choose(2)
            expectedDisplay := cascade.displayChoices[2]
            cascade.SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && IniRead(path, "Controls", "Display") = expectedDisplay
                && IniRead(path, "DropGuides", "Color") = "Cyan",
                "Apply persists the destination device and guide color")
            InitializeCascadeState()
            this.Assert(cascade_target_display = expectedDisplay
                && cascade_drop_guide_color_name = "Cyan",
                "cascade choices survive state initialization")
            app.Settings.ResetModulePreferences(Map("cascade-kingdom", cascade.resetSections))
            this.Assert(IniRead(path, "DropGuides", "Color", "missing") = "missing",
                "factory reset includes the new guide preference")
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
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        global focus_corner_active_slot_color, focus_corner_inactive_slot_color
        global cascade_history
        app := SuiteApplication(true, SuiteChecks.directory "\live-cascade-settings")
        app.InitializeCatalog()
        manager := app.manager
        previous := {visible: focus_corner_visible,
            activeName: focus_corner_active_slot_color_name,
            inactiveName: focus_corner_inactive_slot_color_name,
            activeColor: focus_corner_active_slot_color,
            inactiveColor: focus_corner_inactive_slot_color}
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowModuleSettings("cascade-kingdom")
            settings := app.ui.windows["settings:cascade-kingdom"]
            expectedVisible := !previous.visible
            activeName := previous.activeName = "Pink" ? "Green" : "Pink"
            inactiveName := previous.inactiveName = "Blue" ? "Grey" : "Blue"
            settings["tabs"].Value := expectedVisible
            settings["activeColor"].Choose(activeName)
            settings["inactiveColor"].Choose(inactiveName)
            existingHistorySize := cascade_history.Count
            this.Assert(app.ui.pageFooters[settings.Hwnd].buttons[1].button.Text = "Apply",
                "Cascade Kingdom Settings use Apply without restart")
            app.modules["cascade-kingdom"].SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && focus_corner_visible = expectedVisible
                && focus_corner_active_slot_color_name = activeName
                && focus_corner_inactive_slot_color_name = inactiveName
                && focus_corner_active_slot_color = focus_tab_color_presets[activeName]
                && focus_corner_inactive_slot_color = focus_tab_color_presets[inactiveName],
                "Cascade Kingdom applies focus-tab preferences without reload")
            this.Assert(IniRead(path, "FocusTabs", "Visible") = (expectedVisible ? "1" : "0")
                && IniRead(path, "FocusTabs", "ActiveSlotColor") = activeName
                && IniRead(path, "FocusTabs", "InactiveSlotColor") = inactiveName,
                "Cascade Kingdom persists its focus-tab preferences")
            this.Assert(cascade_history.Count = existingHistorySize,
                "applying Cascade Kingdom preferences preserves in-memory cascade history")
        }
        finally {
            focus_corner_visible := previous.visible
            focus_corner_active_slot_color_name := previous.activeName
            focus_corner_inactive_slot_color_name := previous.inactiveName
            focus_corner_active_slot_color := previous.activeColor
            focus_corner_inactive_slot_color := previous.inactiveColor
            if IsObject(app.ui)
                app.ui.CloseAll()
            manager.Stop()
        }
    }

    static PlacementStabilization() {
        global cascade_history, placement_reservations, placement_stabilization_generations
        global placement_stabilize_retry_ms
        app := SuiteApplication(true, SuiteChecks.directory "\placement-stabilization")
        InitializeCascadeState()
        source := SuiteGui("+Resize", "Stabilization source")
        target := SuiteGui("+Resize", "Stabilization target")
        previousCritical := Critical("On")
        try {
            SuiteShowCentered(source, 320, 240)
            SuiteShowCentered(target, 340, 260)
            sourceMonitor := GetMonitorForWindow(source.Hwnd)
            WinMinimize(source.Hwnd)
            this.Assert(WindowMonitorIndex(source.Hwnd) = sourceMonitor,
                "a minimized window retains its restored monitor")
            WinRestore(source.Hwnd)

            this.Assert(ShouldCorrectCascadeMonitorPromptly(false, 1, 2, 0),
                "equal-DPI wrong-monitor placement gets a prompt correction")
            this.Assert(ShouldCorrectCascadeMonitorPromptly(false, 2, 1, 2)
                && !ShouldCorrectCascadeMonitorPromptly(false, 2, 1, 3),
                "prompt monitor corrections stop after three attempts")
            this.Assert(!ShouldCorrectCascadeMonitorPromptly(false, 2, 2, 0)
                && !ShouldCorrectCascadeMonitorPromptly(false, 0, 2, 0),
                "same-monitor or unknown geometry retains the passive backoff")
            this.Assert(ShouldCorrectCascadeMonitorPromptly(true, 2, 2, 0),
                "DPI transitions retain their prompt correction path")
            this.Assert(GetCascadeConfirmationDelay(true, 0) = placement_stabilize_retry_ms
                && !GetCascadeConfirmationDelay(true, 1) && !GetCascadeConfirmationDelay(false, 0),
                "only a DPI transfer gets one bounded confirmation")

            ; Simulate a placed member. The ignore marker is removed only from
            ; this fixture, never from a personal window.
            app.dryRun := false
            DllCall("RemovePropW", "ptr", target.Hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr")
            GetVisibleWindowBounds(target.Hwnd, &x, &y, &width, &height)
            cascade_history[sourceMonitor] := [target.Hwnd]
            placement_stabilization_generations[target.Hwnd] := 101
            placement_reservations[target.Hwnd] := Map("monitor", sourceMonitor, "x", x, "y", y)
            StabilizePlacedWindow(target.Hwnd, x, y, width, height, 101, 500)
            this.Assert(!placement_stabilization_generations.Has(target.Hwnd)
                && !placement_reservations.Has(target.Hwnd),
                "a matching stabilization check releases its reservation")
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 101, 500)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && afterWidth = width && afterHeight = height,
                "an expired stabilization callback cannot move a window")
            cascade_history.Clear()
            placement_stabilization_generations[target.Hwnd] := 102
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 102, 500)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && !placement_stabilization_generations.Has(target.Hwnd),
                "stabilization never moves a window that left the cascade")
        }
        finally {
            app.stopping := true
            app.dryRun := true
            InitializeCascadeState()
            SuiteSizeGrip.Detach(source)
            source.Destroy()
            SuiteSizeGrip.Detach(target)
            target.Destroy()
            SetTimer(RunQueuedFocusCornerUpdate, 0)
            Critical(previousCritical)
        }
    }

    static FocusTabDpi() {
        global focus_corner_overlays
        app := SuiteApplication(true, SuiteChecks.directory "\release-focus-tabs")
        InitializeCascadeState()
        window := SuiteGui("+Resize", "Release focus-tab target")
        previousCritical := Critical("On")
        try {
            window.Show("NA w300 h200")
            app.dryRun := false
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(focus_corner_overlays.Has(window.Hwnd)
                && focus_corner_overlays[window.Hwnd].dpi = 144,
                "focus tabs use the DPI supplied by the validated rendering snapshot")
            overlay := focus_corner_overlays[window.Hwnd]
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(focus_corner_overlays[window.Hwnd] = overlay,
                "unchanged focus-tab rendering reuses its GUI")
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 96)
            this.Assert(overlay.dpi = 96, "a changed DPI snapshot updates the existing focus tab")
        }
        finally {
            DestroyFocusCornerOverlay(window.Hwnd)
            SuiteSizeGrip.Detach(window)
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
        global cascade_window_drag, pending_adoption_undo
        global cascade_displays
        app := SuiteApplication(true, SuiteChecks.directory "\maximized-adoption")
        InitializeCascadeState()
        window := SuiteGui("+Resize -DPIScale", "Maximized adoption fixture")
        previousCritical := Critical("On")
        try {
            ; Stay in dry run: no hooks, desktop discovery or real adoption.
            ; Only the test-owned window is restored/moved by the undo check.
            ; Populate display geometry without starting hooks or discovery.
            cascade_displays := ReadCascadeDisplays().displays
            window.Show("x60 y60 w320 h220")
            hwnd := window.Hwnd
            original := CaptureWindowPlacement(hwnd)
            WinMaximize(hwnd)
            WinActivate(hwnd)
            this.Assert(!!WinWaitActive(hwnd, , 1),
                "maximized adoption fixture owns foreground")
            this.Assert(ActiveWindowBlocksCascadeCommands()
                && !ActiveWindowBlocksCascadeCommands(true),
                "only explicit adoption bypasses the maximized-window command guard")
            cascade_window_drag := {}
            this.Assert(ActiveWindowBlocksCascadeCommands(true),
                "maximized adoption still respects an active native drag")
            cascade_window_drag := 0

            pending_adoption_undo := CaptureAdoptionUndoSnapshot(hwnd)
            this.Assert(IsObject(pending_adoption_undo)
                && IsObject(pending_adoption_undo["maximized_placement"]),
                "maximized adoption snapshots native placement before restoring")
            WinRestore(hwnd)
            WinMove(100, 100, 420, 280, hwnd)
            this.Assert(UndoPendingAdoption() && WinGetMinMax(hwnd) = 1,
                "adoption undo restores maximized state")
            restored := CaptureWindowPlacement(hwnd)
            sameRectangle := true
            for offset in [28, 32, 36, 40]
                sameRectangle := sameRectangle
                    && NumGet(original, offset, "int") = NumGet(restored, offset, "int")
            this.Assert(sameRectangle,
                "maximized adoption undo preserves the original normal restore rectangle")

            WinRestore(hwnd)
            normalSnapshot := CaptureAdoptionUndoSnapshot(hwnd)
            this.Assert(IsObject(normalSnapshot) && !normalSnapshot["maximized_placement"],
                "normal-window adoption retains its existing geometry-only undo")

            WinSetStyle((WinGetStyle(hwnd) & ~0xC40000) | 0x80000000, hwnd)
            WinSetExStyle(WinGetExStyle(hwnd) & ~0x300, hwnd)
            WonderWindowsChecks.RefreshFrame(hwnd)
            WW_GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
            WinMove(left, top, right - left, bottom - top, hwnd)
            this.Assert(WW_IsNativeFullscreen(hwnd) && ActiveWindowBlocksCascadeCommands(true),
                "allowing maximized adoption does not bypass the fullscreen guard")
        }
        finally {
            CancelPendingAdoptionUndo()
            StopCascadeDisplays()
            InitializeCascadeState()
            try SuiteSizeGrip.Detach(window)
            window.Destroy()
            Critical(previousCritical)
        }
    }
}
