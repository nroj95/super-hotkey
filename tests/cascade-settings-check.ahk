; Disposable preferences and test-owned overlays; no real window adoption or input.
class CascadeSettingsChecks {
    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static Run() {
        this.Policy()
        this.Settings()
        this.Guides()
    }

    static Policy() {
        global cascade_gesture_key, cascade_target_display, cascade_displays, cascade_history
        global cascade_auto_placement_enabled, cascade_opt_in_intent, cascade_titlebar_click
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-policy")
        app.modules["cascade-kingdom"] := CascadeKingdomModule(app)
        previousCritical := Critical("On")
        try {
            for automatic in [false, true]
                for held in [false, true]
                    this.Assert(CascadeShouldLaunch(automatic, held) = (automatic != held),
                        "cascade launch override: automatic=" automatic ", held=" held)
            for key in ["CapsLock", "Pause"] {
                cascade_gesture_key := key
                layer := key = "Pause" ? "pause" : "caps"
                for moduleEnabled in [false, true] {
                    app.activeModules["secret-layers"] := moduleEnabled
                    for layerEnabled in [false, true] {
                        app.activeLayers[layer] := layerEnabled
                        this.Assert(CascadeGestureEnabled() = (moduleEnabled && layerEnabled),
                            "cascade gesture requires its module and selected layer: " key)
                    }
                }
                app.activeLayers[layer] := true
            }
            cascade_gesture_key := "CapsLock"
            app.activeModules["secret-layers"] := true
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
            this.Assert(ResolveCascadePlacementMonitor({monitor_device: "left"}, 1) = 2,
                "queued launches use the configured destination, not their source")
            cascade_displays := Map(1, {device: "right"}, 2, {device: "left"})
            this.Assert(ResolveCascadeDestination(2) = 1,
                "the selected destination follows device name through index changes")
            cascade_target_display := "disconnected"
            this.Assert(!ResolveCascadeDestination(1)
                && !ResolveCascadePlacementMonitor({monitor_device: "right"}, 1),
                "a disconnected selected display never redirects onto another screen")
            cascade_target_display := "right"
            cascade_auto_placement_enabled := false
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: true}
            this.Assert(CascadeTakeOptInMonitor(11, &reason) = 1
                && reason = "gesture-launch" && !IsObject(cascade_opt_in_intent),
                "a captured opt-in redirects once after the key is released")
            cascade_auto_placement_enabled := true
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: false}
            this.Assert(!CascadeTakeOptInMonitor(11, &reason)
                && reason = "gesture-opt-out" && !IsObject(cascade_opt_in_intent),
                "a captured opt-out suppresses both cascading and relocation")
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: false}
            app.activeLayers["caps"] := false
            this.Assert(CascadeTakeOptInMonitor(11) = 1 && !IsObject(cascade_opt_in_intent),
                "disabling the selected layer ignores its gesture but preserves automatic mode")
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: true}
            cascade_titlebar_click := {hwnd: 10}
            app.CancelInputs()
            this.Assert(!IsObject(cascade_opt_in_intent) && !IsObject(cascade_titlebar_click),
                "input cancellation expires launch and caption gestures")
        }
        finally {
            InitializeCascadeState()
            Critical(previousCritical)
        }
    }

    static Settings() {
        global cascade_gesture_key, cascade_target_display, cascade_drop_guide_color_name
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
            this.Assert(window["cascadeKey"].Text = "CapsLock"
                && window["activeColor"].Text = "Yellow"
                && window["inactiveColor"].Text = "White"
                && window["guideColor"].Text = "Pink"
                && focus_corner_active_slot_alpha = 255
                && focus_corner_inactive_slot_alpha = 128,
                "cascade settings default to Yellow/White/Pink and 50% inactive opacity")
            window["cascadeKey"].Choose("Pause")
            window["guideColor"].Choose("Cyan")
            window["autoCascade"].Value := true
            ; Use a real device, not the dropdown index, in the saved preference.
            window["display"].Choose(2)
            expectedDisplay := cascade.displayChoices[2]
            cascade.SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && IniRead(path, "Controls", "CascadeKey") = "Pause"
                && IniRead(path, "Controls", "Display") = expectedDisplay
                && IniRead(path, "DropGuides", "Color") = "Cyan",
                "Apply persists the cascade key, destination device and guide color")
            InitializeCascadeState()
            this.Assert(cascade_gesture_key = "Pause" && cascade_target_display = expectedDisplay
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
                    && WinGetTransparent(window.Hwnd) = 255 && IsIgnoredByWindowCascade(window.Hwnd),
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
}
