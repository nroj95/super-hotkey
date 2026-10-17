; Isolated regression checks. No physical keystrokes, personal windows or editor saves.
class SuiteUpgradeChecks {
    static scopeActive := false
    static terminalScopeActive := false
    static observerCalls := 0

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static AssertResizeGrip(window, label) {
        this.Assert(SuiteSizeGrip.handles.Has(window.Hwnd),
            "window has a native bottom-right resizing grip: " label)
        grip := SuiteSizeGrip.handles[window.Hwnd]
        this.Assert(!!DllCall("IsWindow", "ptr", grip, "int")
            && WinGetClass("ahk_id " grip) = "ScrollBar"
            && (DllCall("GetWindowLongPtrW", "ptr", grip, "int", -16, "ptr") & 0x10),
            "the resize handle uses Windows SBS_SIZEGRIP: " label)
        client := Buffer(16, 0)
        gripRect := Buffer(16, 0)
        this.Assert(!!DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", client, "int")
            && !!DllCall("GetWindowRect", "ptr", grip, "ptr", gripRect, "int"),
            "resize handle and client dimensions can be measured: " label)
        point := Buffer(8, 0)
        NumPut("int", NumGet(client, 8, "int")
            - DllCall("GetSystemMetrics", "int", 2, "int"), point, 0)
        NumPut("int", NumGet(client, 12, "int")
            - DllCall("GetSystemMetrics", "int", 3, "int"), point, 4)
        DllCall("ClientToScreen", "ptr", window.Hwnd, "ptr", point, "int")
        this.Assert(Abs(NumGet(gripRect, 0, "int") - NumGet(point, 0, "int")) <= 1
            && Abs(NumGet(gripRect, 4, "int") - NumGet(point, 4, "int")) <= 1,
            "sizing grip stays at the actual lower-right client corner: " label)
    }
    static AssertCentered(window, label) {
        rect := Buffer(16, 0)
        point := Buffer(8, 0)
        this.Assert(!!DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
            && !!DllCall("GetCursorPos", "ptr", point, "int"),
            "window geometry is available: " label)
        cursorX := NumGet(point, 0, "int")
        cursorY := NumGet(point, 4, "int")
        monitor := 1
        loop MonitorGetCount() {
            MonitorGet(A_Index, &left, &top, &right, &bottom)
            if cursorX >= left && cursorX < right && cursorY >= top && cursorY < bottom {
                monitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        x := NumGet(rect, 0, "int")
        y := NumGet(rect, 4, "int")
        w := NumGet(rect, 8, "int") - x
        h := NumGet(rect, 12, "int") - y
        expectedX := left + Floor((right - left - w) / 2)
        expectedY := top + Floor((bottom - top - h) / 2)
        this.Assert(Abs(x - expectedX) <= 2 && Abs(y - expectedY) <= 2,
            "window opens centered on the current monitor: " label)
    }

    static Route(manager, actionId, slot := 1) {
        for route in manager.routes
            if route.action.id = actionId && route.slot = slot
                return route
        throw Error("Missing test route: " actionId)
    }

    static Run() {
        this.Preferences()
        this.SettingsCheckboxes()
        this.IndependentLayers()
        this.CapsLockDoubleTap()
        this.LayerDoubleTapGestures()
        this.LayerRecordingGestures()
        this.LayerIndicatorDelay()
        this.ApplicationSuspension()
        this.DisabledModuleWarning()
        this.ScopesAndObservers()
        this.GeometryAndOwnership()
        this.ActiveShortcutVisibility()
        this.StagedKeybindings()
        this.LiveCascadeSettings()
        this.Interfaces()
    }

    static Preferences() {
        settings := SuiteSettings(SuiteChecks.directory "\upgrade-preferences")
        this.Assert(settings.layers["caps"] && settings.layers["pause"] && !settings.verbose,
            "both Secret Keys layers default on; verbose debugging defaults off")
        this.Assert(settings.capsToggleModifier = "Shift"
            && settings.capsToggleModifierChoice = "Shift",
            "Shift is the default enabled Caps Lock double-tap modifier")
        settings.Save(settings.modules, Map("caps", false, "pause", true), true)
        loaded := SuiteSettings(settings.directory)
        this.Assert(!loaded.layers["caps"] && loaded.layers["pause"] && loaded.verbose,
            "independent layers and the one global debug preference survive restart")
        settings.Save(settings.modules, settings.layers, settings.verbose, "Alt")
        this.Assert(SuiteSettings(settings.directory).capsToggleModifier = "Alt",
            "selected Caps Lock modifier survives restart")
        settings.Save(settings.modules, settings.layers, settings.verbose, "Disabled", "Alt")
        disabled := SuiteSettings(settings.directory)
        this.Assert(disabled.capsToggleModifier = "Disabled"
            && disabled.capsToggleModifierChoice = "Alt",
            "disabling Caps Lock double-tap remembers its selected modifier")
        settings.Save(settings.modules, settings.layers, settings.verbose, "Alt")
        this.Assert(SuiteSettings(settings.directory).capsToggleModifier = "Alt",
            "re-enabling Caps Lock double-tap restores its selected modifier")
        settings.Save(settings.modules, settings.layers, settings.verbose, "Shift")
        document := KB_Manifest.Read(settings.path)
        document["layers"]["pause"] := "invalid"
        KB_Manifest.WriteAtomic(settings.path, document)
        before := FileRead(settings.path)
        SuiteChecks.Rejects((*) => SuiteSettings(settings.directory), "invalid independent-layer preference is rejected")
        this.Assert(FileRead(settings.path) = before, "bad layer preferences are not silently rewritten")
        settings.Save(settings.modules)
        settings.WritePreferences("scratchpad", Map("Paths", Map("ScratchDirectory", "sentinel-folder"),
            "Window", Map("WidthPercent", 45)))
        settings.WritePreferences("scratchpad", Map("Window", Map("WidthPercent", 55)))
        path := settings.directory "\scratchpad\settings.ini"
        this.Assert(IniRead(path, "Window", "WidthPercent") = "55", "module preferences save through an atomic replacement")
        this.Assert(IniRead(path, "Paths", "ScratchDirectory") = "sentinel-folder", "preference edits preserve unrelated note paths")
        logger := SuiteLog(settings.directory "\log")
        logger.Debug("Paper Pad", "hidden diagnostic")
        logger.Error("Paper Pad", Error("always recorded"))
        this.Assert(!InStr(logger.Read(), "hidden diagnostic") && InStr(logger.Read(), "always recorded"),
            "errors remain automatic when global verbose debugging is off")
        logger.verbose := true
        logger.Debug("Wonder Windows", "visible diagnostic")
        this.Assert(InStr(logger.Read(), "visible diagnostic"), "global verbose mode enables module diagnostics")
    }

    static SettingsCheckboxes() {
        app := SuiteApplication(true, SuiteChecks.directory "\checkbox-settings")
        app.InitializeCatalog()
        app.Settings.Save(app.Settings.modules, app.Settings.layers, false, "Disabled", "Alt")
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowLayerSettings()
            window := app.ui.windows["settings:keyboard-layers"]
            this.Assert(!window["capsToggleEnabled"].Value
                && !window["capsToggleModifier"].Enabled
                && window["capsToggleModifier"].Text = "Alt",
                "disabled Caps Lock double-tap keeps its saved dropdown selection")
            window["capsToggleEnabled"].Value := true
            app.ui.UpdateSelectorEnabled(window["capsToggleModifier"], window["capsToggleEnabled"])
            this.Assert(window["capsToggleModifier"].Enabled,
                "Caps Lock double-tap checkbox enables the modifier dropdown")
            app.ui.CloseWindow("settings:keyboard-layers")
            app.ui.ShowCascadeSettings()
            window := app.ui.windows["settings:window-cascade"]
            this.Assert(window["holdToSkipEnabled"].Value
                && window["holdToSkipKey"].Enabled
                && window["holdToSkipKey"].Text = "CapsLock",
                "Cascade Kingdom hold-to-skip defaults to an enabled CapsLock selector")
            window["holdToSkipEnabled"].Value := false
            app.ui.UpdateSelectorEnabled(window["holdToSkipKey"], window["holdToSkipEnabled"])
            this.Assert(!window["holdToSkipKey"].Enabled
                && window["holdToSkipKey"].Text = "CapsLock",
                "hold-to-skip checkbox disables the dropdown without clearing its selection")
        }
        finally {
            if IsObject(app.ui)
                app.ui.CloseAll()
            manager.Stop()
        }
    }

    static IndependentLayers() {
        for flags in [[false, false], [false, true], [true, false], [true, true]] {
            label := (flags[1] ? "caps" : "no-caps") "-" (flags[2] ? "pause" : "no-pause")
            app := SuiteApplication(true, SuiteChecks.directory "\layers-" label)
            app.activeLayers := Map("caps", flags[1], "pause", flags[2])
            app.InitializeCatalog()
            manager := app.manager
            try {
                manager.SetPaused(true)
                manager.Start()
                this.Assert(IsObject(manager.client) = (flags[1] || flags[2]), "adapter presence: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Caps + Alt + K")) = "") = flags[1],
                    "Caps assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause + T")) = "") = flags[2],
                    "Pause assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("CapsLock")) = "") = !flags[1],
                    "native CapsLock ownership: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause")) = "") = !flags[2],
                    "native Pause ownership: " label)
                this.Assert(this.Route(manager, "core.keybindings", 2).enabled,
                    "ordinary Keybindings shortcut remains available: " label)
                manager.ShowSettings()
                expectedTitle := flags[1] && flags[2] ? "Keybindings"
                    : !flags[1] && !flags[2]
                        ? "Keybindings — CapsLock and Pause layers disabled"
                    : flags[1] ? "Keybindings — Pause layer disabled"
                        : "Keybindings — CapsLock layer disabled"
                this.Assert(manager.settings.Title = expectedTitle,
                    "Keybindings title explains the disabled layer state: " label)
                manager.settings["search"].Value := "open Keybindings"
                manager._RenderSettings()
                this.Assert(manager.rows[2].id = "core.keybindings",
                    "core shortcut remains visible when searching: " label)
                coreButtons := manager.visibleRows[2]
                this.Assert(InStr(coreButtons.primary.Text, "⚠") = 1 ? !flags[1] : flags[1],
                    "Caps binding receives a warning only when inactive: " label)
                this.Assert(coreButtons.secondary.Text = "Ctrl + Alt + K",
                    "ordinary fallback is never warned: " label)
                this.Assert(coreButtons.primary.Enabled,
                    "inactive bindings remain clickable for reassignment: " label)
                manager.settings["search"].Value := "show Paper Pad help"
                manager._RenderSettings()
                paperButton := manager.visibleRows[2].primary
                this.Assert(InStr(paperButton.Text, "⚠") = 1 ? !flags[2] : flags[2],
                    "Pause binding receives a warning only when inactive: " label)
                this.Assert(paperButton.Enabled,
                    "Paper Pad Help remains reassignable while Pause is unavailable: " label)
                manager._CloseSettings()
                if !flags[1] {
                    configuration := manager.GetConfiguration()
                    configuration["scratchpad.toggle"].bindings[1] := "CapsLock"
                    manager.Apply(configuration)
                    this.Assert(this.Route(manager, "scratchpad.toggle").enabled,
                        "disabled Caps prefix may be explicitly reassigned: " label)
                }
                if IsObject(manager.client) {
                    manager.client.Start()
                    this.Assert(manager.client.prefixes.Length = (flags[1] ? 1 : 0) + (flags[2] ? 2 : 0),
                        "only enabled native prefixes are installed: " label)
                    manager.client.Stop()
                }
            }
            finally manager.Stop()
        }
    }

    static LayerDoubleTapGestures() {
        global CPL
        caps := Keybindings.Parse("Caps + Caps")
        pauseBinding := Keybindings.Parse("Pause + Pause")
        this.Assert(caps.doubleTap && caps.layer = "caps" && caps.modifiers = 0
            && caps.label = "Caps + Caps"
            && Keybindings.Parse(caps.signature).signature = caps.signature,
            "Caps + Caps is an explicit, persisted double-tap shortcut")
        this.Assert(pauseBinding.doubleTap && pauseBinding.layer = "pause" && pauseBinding.modifiers = 0
            && pauseBinding.label = "Pause + Pause"
            && Keybindings.Parse(pauseBinding.signature).signature = pauseBinding.signature,
            "Pause + Pause is an explicit, persisted double-tap shortcut")
        this.Assert(!Keybindings.Parse("Caps + F1").doubleTap
            && !Keybindings.Parse("Pause + F1").doubleTap,
            "ordinary layer chords remain normal bindings")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Caps + Pause"),
            "Caps cannot use the opposite activation key as a suffix")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Pause + CapsLock"),
            "Pause cannot use the opposite activation key as a suffix")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Pause + CtrlBreak"),
            "CtrlBreak cannot duplicate the Pause double-tap gesture")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Caps + Ctrl + Caps"),
            "self-prefix double-taps cannot include extra modifiers")

        this.Assert(CPL.oneShotMs = 1400
            && CPL_DoubleTapCandidate("caps", "caps", 1500, 1499)
            && !CPL_DoubleTapCandidate("caps", "caps", 1500, 1500)
            && !CPL_DoubleTapCandidate("pause", "caps", 1500, 200)
            && !CPL_DoubleTapCandidate("", "caps", 1500, 200),
            "a second tap uses the exact 1400 ms one-shot deadline")
        layer := {started: 100, used: false, doubleTap: true}
        this.Assert(CPL_DoubleTapCompleted(layer, true, true, 340, 0, true, 250)
            && !CPL_DoubleTapCompleted(layer, true, true, 351, 0, true, 250)
            && !CPL_DoubleTapCompleted(layer, true, true, 200, 1, true, 250),
            "the second tap must be released quickly without modifiers")
        layer.used := true
        this.Assert(!CPL_DoubleTapCompleted(layer, true, true, 200, 0, true, 250),
            "using a held layer chord suppresses its double-tap shortcut")
        layer.used := false
        layer.doubleTap := false
        this.Assert(!CPL_DoubleTapCompleted(layer, true, true, 200, 0, true, 250),
            "an ordinary first tap or tap-then-hold never counts as a double-tap")
        phases := []
        CPL_DeliverDoubleTap({callback: (event) => phases.Push(event.phase)})
        this.Assert(phases.Length = 2 && phases[1] = "down" && phases[2] = "up",
            "double-tap actions dispatch one complete press after release")

        app := SuiteApplication(true, SuiteChecks.directory "\layer-self-double-taps")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            config := manager.GetConfiguration()
            config["power-hotkey.system.wake-speakers"].bindings[1] := ""
            config["scratchpad.toggle"].bindings[1] := "Caps + Caps"
            config["scratchpad.help"].bindings[2] := "Pause + Pause"
            manager.Apply(config)
            this.Assert(manager.GetConfiguration()["scratchpad.toggle"].bindings[1] = caps.signature
                && manager.GetConfiguration()["scratchpad.help"].bindings[2] = pauseBinding.signature,
                "manual self-prefix assignments save through normal Keybindings")
            this.Assert(CPL.doubleTapKeys.Has("caps") && CPL.doubleTapKeys.Has("pause")
                && !CPL.keyGroups.Has(caps.key) && !CPL.keyGroups.Has(pauseBinding.key),
                "double-tap shortcuts never register native activation-key suffix hooks")
            conflicting := manager.GetConfiguration()
            conflicting["scratchpad.help"].bindings[1] := "Caps + Caps"
            SuiteChecks.Rejects((*) => manager.Apply(conflicting),
                "two double-tap actions in the same context still conflict")
            this.Assert(manager.GetConfiguration()["scratchpad.toggle"].bindings[1] = caps.signature,
                "rejected double-tap conflict preserves the saved configuration")
        }
        finally manager.Stop()
    }

    static LayerRecordingGestures() {
        ; Verify the recorder's state transitions without actual key injection.
        for prefix in ["caps", "pause"] {
            record := {prefixDown: "", prefixDownAt: 0, prefixUsed: false,
                prefixCancel: false, armedLayer: "", armedAt: 0}
            this.Assert(Keybindings.RecordingPrefixDown(record, prefix, 100)
                && Keybindings.RecordingPrefixUp(record, prefix, 180, 0) = "armed"
                && Keybindings.RecordingOneShotLayer(record, 1579) = prefix
                && Keybindings.RecordingOneShotLayer(record, 1580) = ""
                && Keybindings.RecordingOneShotLayer(record, 1581) = "",
                prefix " tap arms one-shot recording for the next key")
            this.Assert(!Keybindings.RecordingBareKey(record, "normal", 200, 0)
                && Keybindings.RecordingBareKey(record, "normal", 1581, 0),
                prefix " one-shot Escape/Backspace are recorded, not cancelled or cleared")

            this.Assert(Keybindings.RecordingPrefixDown(record, prefix, 350)
                && record.prefixCancel
                && Keybindings.RecordingPrefixUp(record, prefix, 490, 0) = "double",
                prefix " double-tap is recognized only after second quick release")
            this.Assert(record.armedLayer = "" && record.prefixDown = "",
                prefix " double-tap consumes the one-shot state")

            Keybindings.RecordingPrefixDown(record, prefix, 600)
            Keybindings.RecordingPrefixUp(record, prefix, 680, 0)
            this.Assert(Keybindings.RecordingPrefixDown(record, prefix, 2079)
                && record.prefixCancel
                && Keybindings.RecordingPrefixUp(record, prefix, 2119, 0) = "double",
                prefix " double-tap accepts the full one-shot window")

            Keybindings.RecordingPrefixDown(record, prefix, 3000)
            Keybindings.RecordingPrefixUp(record, prefix, 3070, 0)
            this.Assert(Keybindings.RecordingPrefixDown(record, prefix, 4470)
                && !record.prefixCancel
                && Keybindings.RecordingPrefixUp(record, prefix, 4540, 0) = "armed",
                prefix " at the expired one-shot deadline a new tap begins")

            Keybindings.RecordingPrefixDown(record, prefix, 4700)
            this.Assert(record.prefixCancel
                && Keybindings.RecordingPrefixUp(record, prefix, 5000, 0) = "",
                prefix " tap then hold does not record double-tap")

            Keybindings.RecordingPrefixDown(record, prefix, 5500)
            record.prefixUsed := true
            this.Assert(Keybindings.RecordingPrefixUp(record, prefix, 5550, 0) = ""
                && record.armedLayer = "",
                prefix " hold-plus-key does not become one-shot recording")
            Keybindings.RecordingPrefixDown(record, prefix, 6000)
            this.Assert(Keybindings.RecordingPrefixUp(record, prefix, 6050, 1) = ""
                && record.armedLayer = "",
                prefix " with modifiers cannot arm a tap")
        }
    }

    static LayerIndicatorDelay() {
        global CPL
        CPL_Initialize()
        this.Assert(!CPL_HeldIndicatorReady(), "idle layers have no held indicator")
        CPL.selected := "caps"
        caps := CPL.layers["caps"]
        caps.down := true
        caps.started := CPL_Now()
        this.Assert(!CPL_HeldIndicatorReady(), "initial Caps press hides held indicator")
        caps.started := CPL_Now() - CPL.tapMaxMs + 50
        this.Assert(!CPL_HeldIndicatorReady(), "quick Caps tap hides held indicator")
        caps.started := CPL_Now() - CPL.tapMaxMs - 50
        this.Assert(CPL_HeldIndicatorReady(), "held Caps passes tap threshold")
        caps.down := false
        this.Assert(!CPL_HeldIndicatorReady(), "Caps release cancels held indicator")
        CPL.selected := "pause"
        pauseLayer := CPL.layers["pause"]
        pauseLayer.down := true
        pauseLayer.started := CPL_Now() - CPL.tapMaxMs - 50
        this.Assert(CPL_HeldIndicatorReady(), "held Pause passes tap threshold")
        CPL.selected := ""
        this.Assert(!CPL_HeldIndicatorReady(), "clearing Pause removes held indicator")
    }

    static CapsLockDoubleTap() {
        for choice in ["Shift", "Ctrl", "Alt"] {
            vk := Map("Shift", 0xA0, "Ctrl", 0xA2, "Alt", 0xA4)[choice]
            sc := Map("Shift", 0x02A, "Ctrl", 0x01D, "Alt", 0x038)[choice]
            detector := CapsLockModifierToggle(choice)
            detector.HandleDown(vk, sc, 100, false)
            this.Assert(!detector.HandleUp(vk, sc, 150, false),
                "first " choice " tap does not toggle Caps Lock")
            detector.HandleDown(vk, sc, 260, false)
            this.Assert(detector.HandleUp(vk, sc, 300, false),
                "second " choice " tap toggles Caps Lock")
            detector.HandleDown(vk, sc, 500, false)
            detector.HandleUp(vk, sc, 550, false)
            detector.HandleDown(0x41, 0x01E, 560, false)
            detector.HandleUp(0x41, 0x01E, 575, false)
            detector.HandleDown(vk, sc, 640, false)
            this.Assert(!detector.HandleUp(vk, sc, 680, false),
                "typing between " choice " taps cancels the sequence")
            detector.Reset()
            detector.HandleDown(vk, sc, 800, true)
            this.Assert(!detector.HandleUp(vk, sc, 840, false),
                "modifier chords do not start a double-tap")
            detector.HandleDown(vk, sc, 1000, false)
            detector.HandleUp(vk, sc, 1060, false)
            detector.HandleDown(vk, sc, 1500, false)
            this.Assert(!detector.HandleUp(vk, sc, 1540, false),
                "slow " choice " double-taps do not toggle")
            detector.Reset()
            detector.HandleDown(vk, sc, 1800, false)
            detector.HandleDown(vk, sc, 1820, false)
            detector.HandleUp(vk, sc, 1850, false)
            detector.HandleDown(vk, sc, 1950, false)
            this.Assert(detector.HandleUp(vk, sc, 1990, false),
                "key repeat does not count as a separate tap")
            detector.Stop()
        }
        SuiteChecks.Rejects((*) => CapsLockModifierToggle("CapsLock"),
            "CapsLock cannot be its own double-tap modifier")
    }

    static StagedKeybindings() {
        app := SuiteApplication(true, SuiteChecks.directory "\staged-keybindings")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            before := manager.GetConfiguration()["core.keybindings"].bindings[2]
            replacement := Keybindings.Parse("Ctrl + Alt + F11").signature
            this.Assert(before != replacement, "staged regression binding differs from the saved default")
            beforeFile := FileRead(manager.path, "UTF-8")
            manager.ShowSettings()
            candidate := manager._CloneConfiguration(manager.settingsDraft)
            candidate["core.keybindings"].bindings[2] := replacement
            manager._StageConfiguration(candidate)
            this.Assert(manager.settingsApply.Enabled
                && manager.settingsDraft["core.keybindings"].bindings[2] = replacement
                && manager.GetConfiguration()["core.keybindings"].bindings[2] = before
                && FileRead(manager.path, "UTF-8") = beforeFile,
                "editing stages hotkeys without changing the live configuration or saved file")
            manager._CloseSettings()
            manager.ShowSettings()
            this.Assert(manager.settingsDraft["core.keybindings"].bindings[2] = before
                && !manager.settingsApply.Enabled,
                "closing Keybindings discards all uncommitted edits")
            manager._StageConfiguration(candidate)
            this.Assert(manager._ApplyStaged()
                && manager.GetConfiguration()["core.keybindings"].bindings[2] = replacement
                && KB_Manifest.Get(KB_Manifest.Read(manager.path), "bindings", "core.keybindings") != "",
                "Apply saves staged hotkeys and closes the editor without restarting")
            manager.ShowSettings("window-cascade")
            this.Assert(manager.settingsDone.Text = "Back"
                && manager.settingsApply.Text = "Apply"
                && manager.settingsModuleId = "window-cascade",
                "module Keybindings provides Back and live Apply")
            unrelated := manager.settingsDraft["core.keybindings"].bindings[2]
            moduleCandidate := manager._CloneConfiguration(manager.settingsDraft)
            moduleCandidate["window-cascade.help"].bindings[1] := Keybindings.Parse("Caps + F10").signature
            manager._StageConfiguration(moduleCandidate)
            manager._StageDefaults()
            this.Assert(manager.settingsDraft["window-cascade.help"].bindings[1]
                    = manager.actions["window-cascade.help"].defaults[1]
                && manager.settingsDraft["core.keybindings"].bindings[2] = unrelated,
                "module Restore defaults stages only that module's shortcuts")
            manager._CloseSettings()
        }
        finally {
            if IsObject(manager.settings)
                manager._CloseSettings()
            manager.Stop()
        }
    }

    static LiveCascadeSettings() {
        global cascade_auto_placement_paused, cascade_hold_to_skip_key, cascade_hold_to_skip_choice
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        global focus_corner_active_slot_color, focus_corner_inactive_slot_color
        global cascade_history

        app := SuiteApplication(true, SuiteChecks.directory "\live-cascade-settings")
        app.InitializeCatalog()
        manager := app.manager
        previous := {paused: cascade_auto_placement_paused, holdToSkipKey: cascade_hold_to_skip_key,
            holdToSkipChoice: cascade_hold_to_skip_choice, visible: focus_corner_visible,
            activeName: focus_corner_active_slot_color_name,
            inactiveName: focus_corner_inactive_slot_color_name,
            activeColor: focus_corner_active_slot_color,
            inactiveColor: focus_corner_inactive_slot_color}
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowCascadeSettings()
            settings := app.ui.windows["settings:window-cascade"]
            expectedPaused := !previous.paused
            expectedVisible := !previous.visible
            activeName := previous.activeName = "Pink" ? "Green" : "Pink"
            inactiveName := previous.inactiveName = "Blue" ? "Grey" : "Blue"
            settings["paused"].Value := expectedPaused
            selectedSkipKey := previous.holdToSkipChoice = "Pause" ? "CapsLock" : "Pause"
            settings["holdToSkipKey"].Choose(selectedSkipKey)
            settings["holdToSkipEnabled"].Value := false
            app.ui.UpdateSelectorEnabled(settings["holdToSkipKey"], settings["holdToSkipEnabled"])
            this.Assert(!settings["holdToSkipKey"].Enabled,
                "Cascade Kingdom checkbox disables hold-to-skip without forgetting the key")
            settings["tabs"].Value := expectedVisible
            settings["activeColor"].Choose(activeName)
            settings["inactiveColor"].Choose(inactiveName)
            existingHistorySize := cascade_history.Count
            this.Assert(app.ui.pageFooters[settings.Hwnd].buttons[1].button.Text = "Apply",
                "Cascade Kingdom Settings use Apply without restart")
            app.ui.SaveCascade()
            path := app.Settings.directory "\window-cascade\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:window-cascade")
                && cascade_auto_placement_paused = expectedPaused
                && focus_corner_visible = expectedVisible
                && cascade_hold_to_skip_key = "Disabled"
                && cascade_hold_to_skip_choice = selectedSkipKey
                && focus_corner_active_slot_color_name = activeName
                && focus_corner_inactive_slot_color_name = inactiveName
                && focus_corner_active_slot_color = focus_tab_color_presets[activeName]
                && focus_corner_inactive_slot_color = focus_tab_color_presets[inactiveName],
                "Cascade Kingdom applies placement, visibility and colors without reload")
            this.Assert(IniRead(path, "Controls", "AutoPlacementPaused") = (expectedPaused ? "1" : "0")
                && IniRead(path, "Controls", "HoldToSkipKey") = "Disabled"
                && IniRead(path, "Controls", "HoldToSkipChoice") = selectedSkipKey
                && IniRead(path, "FocusTabs", "Visible") = (expectedVisible ? "1" : "0")
                && IniRead(path, "FocusTabs", "ActiveSlotColor") = activeName
                && IniRead(path, "FocusTabs", "InactiveSlotColor") = inactiveName,
                "Cascade Kingdom live settings persist all five choices")
            this.Assert(cascade_history.Count = existingHistorySize,
                "applying Cascade Kingdom preferences preserves in-memory cascade history")
            app.ui.ShowCascadeSettings()
            settings := app.ui.windows["settings:window-cascade"]
            this.Assert(!settings["holdToSkipEnabled"].Value
                && !settings["holdToSkipKey"].Enabled
                && settings["holdToSkipKey"].Text = selectedSkipKey,
                "disabled hold-to-skip remembers the selected key after reopening")
            settings["holdToSkipEnabled"].Value := true
            app.ui.UpdateSelectorEnabled(settings["holdToSkipKey"], settings["holdToSkipEnabled"])
            app.ui.SaveCascade()
            this.Assert(cascade_hold_to_skip_key = selectedSkipKey
                && cascade_hold_to_skip_choice = selectedSkipKey
                && IniRead(path, "Controls", "HoldToSkipKey") = selectedSkipKey,
                "re-enabling hold-to-skip restores the saved key")
        }
        finally {
            cascade_auto_placement_paused := previous.paused
            cascade_hold_to_skip_key := previous.holdToSkipKey
            cascade_hold_to_skip_choice := previous.holdToSkipChoice
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

    static ApplicationSuspension() {
        global pending_windows, cascade_compaction_pending
        app := SuiteApplication(true, SuiteChecks.directory "\hotkey-suspension")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.BuildTray()
            app.suspended := true
            app.dryRun := false
            app.RefreshInputGate()
            this.Assert(manager.paused && manager.gated,
                "suspending the input manager does not require stopping the application")
            this.Assert(!IsCascadeEnabled(),
                "application suspension disables automatic Cascade Kingdom work")
            pending_windows[123456789] := {pid: 0}
            cascade_compaction_pending[1] := 0
            WindowCascadeModule.Suspend()
            this.Assert(!pending_windows.Count && !cascade_compaction_pending.Count,
                "suspension clears queued placements and compactions")
            QueueCascadeCompaction(1)
            this.Assert(!cascade_compaction_pending.Count,
                "suspended Cascade Kingdom discards new compaction requests")
            if IsObject(manager.client)
                this.Assert(!manager.client.session,
                    "suspension releases the native CapsLock and Pause hooks")
            this.Assert(!manager._Eligible(Keybindings.Parse("Ctrl + Alt + K").signature),
                "ordinary configured hotkeys are unavailable while suspended")

            app.systemSuspended := true
            app.ui.ToggleSuspension()
            this.Assert(!app.suspended && manager.gated,
                "resuming the app cannot override a pending Windows suspend")
            app.systemSuspended := false
            app.RefreshInputGate()
            this.Assert(!manager.paused && !manager.gated,
                "hotkeys resume after every independent pause reason clears")
            this.Assert(IsCascadeEnabled(),
                "resuming application suspension restores Cascade Kingdom eligibility")
            if IsObject(manager.client)
                this.Assert(manager.client.session,
                    "CapsLock and Pause layer hooks return when hotkeys resume")

            app.ui.ShowModules()
            this.Assert(!manager.gated && !manager.paused,
                "module settings keep configured hotkeys active")
            app.ui.CloseModules()
            manager.ShowSettings()
            this.Assert(!manager.gated && !manager.paused,
                "Keybindings keeps normal hotkeys active when not recording")
            if IsObject(manager.client)
                this.Assert(manager.client.session,
                    "Keybindings does not reset the running Caps/Pause layer session")
            this.Assert(SuiteFullscreen.Active(),
                "F11 fullscreen remains available while Keybindings is open")
            app.ToggleKeybindings()
            this.Assert(!IsObject(manager.settings) && !manager.gated,
                "opening shortcut closes the focused Keybindings window")
            app.ToggleKeybindings()
            this.Assert(IsObject(manager.settings) && !manager.gated,
                "the same shortcut reopens Keybindings without gating input")
            recordIndex := 0
            for index, row in manager.visibleRows {
                if row.actionId != "" {
                    recordIndex := index
                    break
                }
            }
            this.Assert(recordIndex > 0, "Keybindings has a recordable assignment")
            manager._BeginRecording(recordIndex, 1)
            this.Assert(IsObject(manager.recording) && manager.gated,
                "recording alone temporarily gates normal hotkeys")
            this.Assert(!SuiteFullscreen.Active(),
                "F11 fullscreen is disabled during keybinding recording")
            manager._EndRecording()
            this.Assert(!manager.gated && SuiteFullscreen.Active(),
                "ending recording restores normal hotkeys and F11")
            app.ui.ToggleSuspension()
            this.Assert(manager.gated && app.suspended,
                "suspending while Keybindings is open keeps inputs gated")
            manager._CloseSettings()
            this.Assert(!IsObject(manager.settings),
                "closing Keybindings destroys the editor")
            this.Assert(manager.gated && manager.paused,
                "closing Keybindings does not bypass suspended hotkeys")
            app.ui.ToggleSuspension()
            this.Assert(!manager.paused && !manager.gated,
                "resuming from the tray restores normal hotkey handling")
        }
        finally {
            app.dryRun := true
            app.RefreshInputGate()
            app.ui.CloseAll()
            manager.Stop()
        }
    }

    static DisabledModuleWarning() {
        app := SuiteApplication(true, SuiteChecks.directory "\disabled-secret-keys")
        app.activeModules["keyboard-layers"] := false
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            manager.ShowSettings()
            this.Assert(manager.settings.Title = "Keybindings — Secret Keys disabled",
                "module-disabled Keybindings title describes the unavailable layers")
            manager.settings["search"].Value := "open Keybindings"
            manager._RenderSettings()
            core := manager.visibleRows[2]
            this.Assert(InStr(core.primary.Text, "⚠ Caps + Alt + K") = 1
                && core.secondary.Text = "Ctrl + Alt + K"
                && core.primary.Enabled,
                "disabled Secret Keys marks only the Caps binding and leaves it editable")
            this.Assert(manager.warningButtons.Has(core.primary.Hwnd)
                && !manager.warningButtons.Has(core.secondary.Hwnd),
                "warning background applies only to unavailable assignment buttons")
            this.Assert(manager.settingsDrawButtons[core.primary.Hwnd] = "binding"
                && manager.settingsDrawButtons[core.secondary.Hwnd] = "binding"
                && manager.settingsDrawButtons[core.reset.Hwnd] = "reset"
                && manager.settingsDrawButtons[manager.settingsResetAll.Hwnd] = "reset"
                && manager.settingsDrawButtons[manager.settingsDone.Hwnd] = "done",
                "binding, reset and Done controls share the square-corner drawing system")
            beforePaint := manager.warningPaintCount
            DllCall("RedrawWindow", "ptr", core.primary.Hwnd, "ptr", 0,
                "ptr", 0, "uint", 0x185, "int")
            this.Assert(manager.warningPaintCount > beforePaint,
                "inactive assignment buttons receive custom amber painting")
            beforeNormal := manager.normalPaintCount
            DllCall("RedrawWindow", "ptr", core.secondary.Hwnd, "ptr", 0,
                "ptr", 0, "uint", 0x185, "int")
            this.Assert(manager.normalPaintCount > beforeNormal,
                "normal white assignment boxes use square-corner custom painting")
            beforeDone := manager.normalPaintCount
            DllCall("RedrawWindow", "ptr", manager.settingsDone.Hwnd,
                "ptr", 0, "ptr", 0, "uint", 0x185, "int")
            this.Assert(manager.normalPaintCount > beforeDone,
                "Done receives the same square-corner white painting")
            beforeReset := manager.resetPaintCount
            DllCall("RedrawWindow", "ptr", core.reset.Hwnd, "ptr", 0,
                "ptr", 0, "uint", 0x185, "int")
            DllCall("RedrawWindow", "ptr", manager.settingsResetAll.Hwnd,
                "ptr", 0, "ptr", 0, "uint", 0x185, "int")
            this.Assert(manager.resetPaintCount > beforeReset,
                "row and footer reset controls use matching square-corner painting")
            manager.settings["search"].Value := "show Paper Pad help"
            manager._RenderSettings()
            paper := manager.visibleRows[2].primary
            this.Assert(InStr(paper.Text, "⚠ Pause + F12") = 1 && paper.Enabled,
                "disabled Secret Keys marks the saved Pause Help binding as reassignable")
            this.Assert(manager.warningButtons.Has(paper.Hwnd),
                "disabled Pause bindings also receive the amber warning background")
            before := manager.GetConfiguration()["scratchpad.help"].bindings[1]
            this.Assert(before = Keybindings.Parse("Pause + F12").signature,
                "warning presentation never modifies the saved shortcut")
            manager._CloseSettings()
        }
        finally manager.Stop()
    }

    static ScopesAndObservers() {
        for layered in [false, true] {
            suffix := layered ? "layer" : "ordinary"
            options := {directory: SuiteChecks.directory "\scopes-" suffix}
            if layered
                options.layerFactory := (name, status) => LocalKeyboardLayers(name, status, Map("caps", true, "pause", false))
            manager := Keybindings("scope-check-" suffix, "Scope check", options)
            try {
                manager.RegisterScope("editor", (*) => this.scopeActive)
                manager.RegisterScope("terminal", (*) => this.terminalScopeActive)
                manager.RegisterDisjointScopes("editor", "terminal")
                binding := layered ? "Caps + F8" : "Ctrl + Alt + F8"
                manager.AddAction("inside", "inside editor", (*) => 0, [binding], {scope: "editor"})
                manager.AddAction("outside", "outside editor", (*) => 0, [binding], {scope: "!editor"})
                manager.AddAction("global", "global action", (*) => 0, [])
                alternate := layered ? "Caps + F9" : "Ctrl + Alt + F9"
                manager.AddAction("editor-alt", "editor action", (*) => 0, [alternate],
                    {scope: "editor"})
                manager.AddAction("terminal-alt", "terminal action", (*) => 0, [alternate],
                    {scope: "terminal"})
                SuiteChecks.Rejects((*) => manager.AddAction("unknown", "unknown scope", (*) => 0, [],
                    {scope: "missing"}), "unknown scope names cannot bypass conflicts: " suffix)
                manager.SetPaused(true)
                manager.Start()
                signature := Keybindings.Parse(binding).signature
                this.Assert(manager.routeMap[signature].Length = 2,
                    "explicit complementary scopes may share one physical binding: " suffix)
                alternateSignature := Keybindings.Parse(alternate).signature
                this.Assert(manager.routeMap[alternateSignature].Length = 2,
                    "explicitly disjoint editor and Terminal scopes may share a key: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "terminal-alt",
                    "Terminal-only route selected in Terminal: " suffix)
                this.terminalScopeActive := false
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "editor-alt",
                    "editor-only route selected in the editor: " suffix)
                this.scopeActive := false
                this.Assert(manager._SelectedRoute(signature).action.id = "outside", "outside scope routing: " suffix)
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(signature).action.id = "inside", "inside scope routing: " suffix)
                configuration := manager.GetConfiguration()
                configuration["global"].bindings[1] := binding
                before := FileRead(manager.path)
                SuiteChecks.Rejects((*) => manager.Apply(configuration), "a global collision is still rejected: " suffix)
                this.Assert(FileRead(manager.path) = before, "scope conflict does not overwrite saved bindings: " suffix)
                configuration["global"].bindings[1] := alternate
                manager.Apply(configuration)
                this.Assert(manager.routeMap[alternateSignature].Length = 3,
                    "global fallback shares an explicit scoped shortcut: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := false
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "global",
                    "global fallback works outside scoped windows: " suffix)
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "editor-alt",
                    "editor scope overrides the global fallback: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "terminal-alt",
                    "Terminal scope overrides the global fallback: " suffix)
                this.terminalScopeActive := false
                overlapping := manager.GetConfiguration()
                overlapping["inside"].bindings[1] := alternate
                before := FileRead(manager.path)
                SuiteChecks.Rejects((*) => manager.Apply(overlapping),
                    "two overlapping editor shortcuts still conflict: " suffix)
                this.Assert(FileRead(manager.path) = before,
                    "overlapping scoped conflict preserves saved assignments: " suffix)
                if layered {
                    global CPL
                    CPL.enabled := true
                    CPL.selected := "caps"
                    CPL.layers["caps"].down := true
                    routeKey := CPL_RouteKey("caps", 0, Keybindings.Parse(binding).key)
                    this.scopeActive := false
                    this.Assert(CPL_SelectRoute(routeKey) = this.Route(manager, "outside").specification,
                        "layer dispatcher chooses the outside scope")
                    this.scopeActive := true
                    this.Assert(CPL_SelectRoute(routeKey) = this.Route(manager, "inside").specification,
                        "layer dispatcher chooses the inside scope")
                    alternateRouteKey := CPL_RouteKey("caps", 0, Keybindings.Parse(alternate).key)
                    this.scopeActive := false
                    this.terminalScopeActive := false
                    this.Assert(CPL_SelectRoute(alternateRouteKey) = this.Route(manager, "global").specification,
                        "layer dispatcher chooses global fallback outside scoped windows")
                    this.terminalScopeActive := true
                    this.Assert(CPL_SelectRoute(alternateRouteKey) = this.Route(manager, "terminal-alt").specification,
                        "layer dispatcher prioritizes Terminal over the global fallback")
                    this.terminalScopeActive := false
                    this.scopeActive := true
                    this.Assert(CPL_SelectRoute(alternateRouteKey) = this.Route(manager, "editor-alt").specification,
                        "layer dispatcher prioritizes editor over the global fallback")
                }
                this.observerCalls := 0
                for unused in [1, 2]
                    manager.Observe("~*F24", (*) => true, (*) => this.observerCalls += 1, true)
                this.Assert(manager.observers.Length = 1, "identical passive observers share one native variant: " suffix)
                manager._DispatchObserver("~*F24")
                this.Assert(this.observerCalls = 2, "both modules receive the passive observation: " suffix)
            }
            finally {
                manager.Stop()
                this.scopeActive := false
                this.terminalScopeActive := false
            }
        }
    }

    static GeometryAndOwnership() {
        app := SuiteApplication(true, SuiteChecks.directory "\geometry")
        app.InitializeCatalog()
        try {
            ratios := WW_GetSideCycleRatios("left")
            this.Assert(ratios.Length = 4 && ratios[1][2] = 2 && ratios[2][2] = 4,
                "Wonder Windows retains the four quarter/half-width layout steps")
            top := WW_BuildRatioLayout([-1001, -501, 0, 500], [0, 4, 4], "top")
            bottom := WW_BuildRatioLayout([-1001, -501, 0, 500], [0, 4, 4], "bottom")
            this.Assert(top[1] = -1001 && top[2] + top[4] = bottom[2]
                && bottom[2] + bottom[4] = 500, "odd negative-coordinate layouts retain exact shared boundaries")
            this.Assert(WW_GetNextCycleIndex(4, 4) = 1 && WW_GetNextCycleIndex(1, 4, true) = 4,
                "layout cycling wraps in both directions")
            vertical := WW_GetCollisionLimitedVerticalBounds([100, 200, 300, 200],
                [[100, 0, 300, 150], [100, 550, 300, 100], [600, 300, 200, 100]], 0, 900)
            this.Assert(vertical[1] = 150 && vertical[2] = 550,
                "vertical extension stops at upper and lower obstacles")
            this.Assert(WW_RectanglesMatch(
                WW_FullStretchRectangle([100, 200, 300, 200], [0, 0, 900, 1100], "height"),
                [100, 0, 300, 1100], 0)
                && WW_RectanglesMatch(
                    WW_FullStretchRectangle([100, 200, 300, 200], [0, 0, 900, 1100], "width"),
                    [0, 200, 900, 200], 0),
                "full stretch modes retain the untouched dimension")
            this.Assert(WW_RectanglesMatch(
                WW_FitSwapRectangle([100, 150, 800, 500], [100, 150, 800, 500], [0, 0, 1600, 900]),
                [100, 150, 800, 500], 0),
                "best-effort swap does not alter a fitting destination")
            this.Assert(WW_RectanglesMatch(
                WW_FitSwapRectangle([900, 600, 400, 300], [900, 600, 820, 520], [0, 0, 1600, 900]),
                [780, 380, 820, 520], 0),
                "size-constrained swaps keep accepted dimensions on-screen")
            this.Assert(WW_RectanglesMatch(
                WW_FitSwapRectangle([-100, -80, 400, 300], [-100, -80, 820, 520], [-1600, -900, 0, 0]),
                [-820, -520, 820, 520], 0),
                "best-effort swap handles negative desktop coordinates")
            this.Assert(!IsObject(WW_FitSwapRectangle([100, 100, 400, 300],
                [100, 100, 1800, 300], [0, 0, 1600, 900])),
                "unfittable window dimensions require swapping rollback")
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[100, 0, 200, 300]], 0) = 300,
                "horizontal stretch stops at the nearest facing edge")
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[450, 0, 200, 300]], 0) = 0,
                "pre-existing overlap does not collapse a stretched window")
            window := SuiteGui("+ToolWindow", "Owned migration test window")
            try {
                this.Assert(!SuiteSizeGrip.handles.Has(window.Hwnd),
                    "non-resizable suite windows have no sizing grip")
                this.Assert(SuiteWindowOwnership.IsSuiteSurface(window.Hwnd),
                    "private suite tool windows are recognized")
                this.Assert(!SuiteWindowOwnership.AllowsWonderWindows(window.Hwnd),
                    "private suite tool windows are excluded from Wonder Windows")
                this.Assert(IsIgnoredByWindowCascade(window.Hwnd), "suite GUI is marked before it can be cascaded")
                SuiteWindowOwnership.Claim(window.Hwnd)
                this.Assert(SuiteWindowOwnership.IsManual(window.Hwnd), "manual geometry ownership is recorded per HWND and process")
                global WW_horizontal_stretch_windows, WW_vertical_stretch_windows, WW_normal_window_placements
                WW_horizontal_stretch_windows[window.Hwnd] := Map("pid", SuiteWindowOwnership.ProcessId(window.Hwnd))
                WW_vertical_stretch_windows[window.Hwnd] := Map("pid", SuiteWindowOwnership.ProcessId(window.Hwnd))
                WW_normal_window_placements[window.Hwnd] := Map("pid", SuiteWindowOwnership.ProcessId(window.Hwnd))
                this.Assert(SuiteWindowOwnership.Release(window.Hwnd) && !SuiteWindowOwnership.IsManual(window.Hwnd),
                    "explicit adoption releases manual ownership")
                this.Assert(!WW_horizontal_stretch_windows.Has(window.Hwnd) && !WW_vertical_stretch_windows.Has(window.Hwnd),
                    "adoption discards stretch cleanup that would otherwise undo the new cascade")
                this.Assert(!WW_normal_window_placements.Has(window.Hwnd),
                    "adoption starts a fresh manual-restore history")
                SuiteWindowOwnership.Claim(window.Hwnd)
                DllCall("RemovePropW", "ptr", window.Hwnd, "str", SuiteWindowOwnership.marker, "ptr")
                this.Assert(!SuiteWindowOwnership.IsManual(window.Hwnd), "a lost per-window marker invalidates cached manual ownership")
            }
            finally window.Destroy()
            guiProbe := SuiteGui("+Resize", "Wonder Windows GUI eligibility test")
            try {
                SuiteFullscreen.Enable(guiProbe)
                guiProbe.Show("NA w600 h400")
                this.Assert(SuiteWindowOwnership.AllowsWonderWindows(guiProbe.Hwnd)
                    && WW_IsWindowToggleCandidate(guiProbe.Hwnd),
                    "normal suite GUIs are Wonder Windows candidates")
                this.Assert(!WW_IsNativeFullscreen(guiProbe.Hwnd),
                    "ordinary suite GUI is not mistaken for native fullscreen")
                ; A large window may occupy a smaller logical swap zone.
                guiActual := WW_GetWindowLayoutRectangle(guiProbe.Hwnd)
                guiZone := [guiActual[1], guiActual[2],
                    Max(50, guiActual[3] - 130), Max(50, guiActual[4] - 90)]
                WW_SaveSwapZone(guiProbe.Hwnd, guiZone)
                this.Assert(WW_RectanglesMatch(WW_GetSwapZone(guiProbe.Hwnd), guiZone, 0),
                    "oversized GUI retains its logical swap zone")
                global WW_swap_zones
                this.Assert(WW_swap_zones.Has(guiProbe.Hwnd)
                    && WW_RectanglesMatch(WW_swap_zones[guiProbe.Hwnd]["applied"], guiActual, 2),
                    "logical zone and actual GUI rectangle stay separate")
                ; A recycled HWND must not inherit the previous window's zone.
                DllCall("RemovePropW", "ptr", guiProbe.Hwnd,
                    "str", "nroj.SuperHotkey.SwapZone", "ptr")
                this.Assert(WW_RectanglesMatch(WW_GetSwapZone(guiProbe.Hwnd), guiActual, 2)
                    && !WW_swap_zones.Has(guiProbe.Hwnd),
                    "reopened GUI without the zone marker inherits no stale swap zone")
                WW_SaveSwapZone(guiProbe.Hwnd, guiZone)
                WW_swap_zones[0] := Map("pid", 0)
                WW_PruneSwapZones()
                this.Assert(!WW_swap_zones.Has(0),
                    "dead swap windows do not retain logical zone records")
                ; Manual resizing must forget stale zones rather than spreading them.
                WinGetPos(&gX, &gY, &gW, &gH, guiProbe.Hwnd)
                WinMove(gX, gY, gW + 70, gH, guiProbe.Hwnd)
                Sleep 40
                this.Assert(WW_RectanglesMatch(WW_GetSwapZone(guiProbe.Hwnd),
                    WW_GetWindowLayoutRectangle(guiProbe.Hwnd), 2)
                    && !WW_swap_zones.Has(guiProbe.Hwnd),
                    "manual GUI resize invalidates its remembered swap zone")
                this.Assert(IsIgnoredByWindowCascade(guiProbe.Hwnd),
                    "Cascade Kingdom continues to ignore normal suite GUIs")
                DllCall("SetPropW", "ptr", guiProbe.Hwnd, "str", "nroj.Scratchpad.Notepad3Window", "ptr", 1, "int")
                this.Assert(SuiteWindowOwnership.AllowsWonderWindows(guiProbe.Hwnd),
                    "marked Paper Pad editor windows remain eligible")
            }
            finally {
                SuiteSizeGrip.Detach(guiProbe)
                guiProbe.Destroy()
            }
            focusTabProbe := CreatePhysicalGui("-Caption -DPIScale +ToolWindow +E0x08000000",
                "Cascade Kingdom focus tab grip test")
            try this.Assert(!SuiteSizeGrip.handles.Has(focusTabProbe.Hwnd),
                "Cascade Kingdom focus tabs have no sizing grip")
            finally focusTabProbe.Destroy()
            event := {phase: "down", actionId: "win-key-overhaul.maximize", slot: 1,
                foregroundHwnd: 0, key: "sc148", layer: "normal", modifiers: 8, oneShot: false}
            app.wonder.Event(event)
            this.Assert(InStr(SuiteState.Log.Read(), "dry run: win-key-overhaul.maximize"),
                "Wonder Windows dry-run callbacks do not move real windows")
        }
        finally app.manager.Stop()
    }


    static ActiveShortcutVisibility() {
        app := SuiteApplication(true, SuiteChecks.directory "\visibility")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            groups := Map("Power-Up Utilities", 0,
                "Power-Up Utilities / Windows Terminal", 0,
                "Power-Up Utilities / Extra function keys", 0,
                "Power-Up Utilities / Virtual number pad", 0,
                "Power-Up Utilities / Text and symbols", 0)
            for actionId, action in manager.actions {
                if InStr(actionId, "power-hotkey.") != 1
                    || actionId = "power-hotkey.keyboard.toggle-caps"
                    continue
                this.Assert(groups.Has(action.category),
                    "Power-Up Utilities keeps only useful subcategories: " actionId)
                groups[action.category] += 1
            }
            this.Assert(groups["Power-Up Utilities / Windows Terminal"] = 2,
                "Windows Terminal macros have their own category")
            this.Assert(groups["Power-Up Utilities / Extra function keys"] = 12
                && groups["Power-Up Utilities / Virtual number pad"] = 10
                && groups["Power-Up Utilities / Text and symbols"] = 5,
                "large coherent Power-Up Utilities feature sets have their own headings")
            this.Assert(groups["Power-Up Utilities"] > 0,
                "individual utilities remain directly under Power-Up Utilities")
            this.Assert(manager.actions["core.keybindings"].category = "Global"
                && manager.actions["window-cascade.copy-log"].category = "Global"
                && manager.actions["window-cascade.reset-log"].category = "Global",
                "core and debug actions share one Global display heading")
            this.Assert(manager.actions["core.keybindings"].id = "core.keybindings"
                && manager.actions["window-cascade.copy-log"].id = "window-cascade.copy-log",
                "Global rename leaves saved action IDs unchanged")
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
            this.CheckDisplayOrder(rows)
            actionScopes := Map()
            cleanHeadings := true
            for row in rows {
                if row.id = "" {
                    if HasProp(row, "scope")
                        cleanHeadings := false
                } else
                    actionScopes[row.id] := row.scope
            }
            this.Assert(cleanHeadings && actionScopes["scratchpad.save"] = "paper-pad"
                && actionScopes["power-hotkey.terminal.copy"] = "windows-terminal",
                "scopes belong to action descriptions rather than category headings")
            this.Assert(actionScopes["core.keybindings"] = ""
                && Keybindings.ContextTagText("!paper-pad") = ""
                && Keybindings.ContextTagText("paper-pad") = "editor only"
                && Keybindings.ContextTagText("windows-terminal") = "terminal only",
                "only application-specific shortcuts receive readable context tags")
            this.Assert(manager.actions["win-key-overhaul.layout-left"].scope = ""
                && manager.actions["scratchpad.previous"].scope = "paper-pad",
                "Wonder Windows is a global fallback for Paper Pad editor shortcuts")
            this.Assert(manager.actions["power-hotkey.terminal.clear"].scope = "windows-terminal"
                && manager.actions["power-hotkey.terminal.copy"].scope = "windows-terminal",
                "Terminal shortcuts are gated by the actual foreground application")
            mainHeadings := []
            activeParent := ""
            subcategoriesFollowParent := true
            for row in rows {
                if row.id != ""
                    continue
                separator := InStr(row.label, " / ")
                if separator {
                    if SubStr(row.label, 1, separator - 1) != activeParent
                        subcategoriesFollowParent := false
                } else {
                    activeParent := row.label
                    mainHeadings.Push(row.label)
                }
            }
            expectedOrder := ["Global", "Paper Pad", "Cascade Kingdom",
                "Wonder Windows", "Power-Up Utilities", "Secret Keys"]
            this.Assert(mainHeadings.Length = expectedOrder.Length,
                "Keybindings includes exactly the five assignable sections")
            for index, expectedName in expectedOrder
                this.Assert(mainHeadings[index] = expectedName,
                    "Keybindings section order: " expectedName)
            this.Assert(subcategoriesFollowParent,
                "all Keybindings subcategories stay immediately after their main section")
            paperSection := 0
            for index, row in rows
                if row.id = "" && row.label = "Paper Pad" {
                    paperSection := index
                    break
                }
            this.Assert(paperSection > 0 && rows[paperSection + 1].id = "scratchpad.help"
                && rows[paperSection + 2].id = "scratchpad.toggle"
                && rows[paperSection + 3].label = "Paper Pad / Inside the editor",
                "Paper Pad puts Help first, followed by its toggle and editor subcategory")
            expectedHelp := Map("Paper Pad", "scratchpad.help",
                "Cascade Kingdom", "window-cascade.help",
                "Wonder Windows", "win-key-overhaul.help",
                "Power-Up Utilities", "power-hotkey.interface.open",
                "Secret Keys", "keyboard-layers.help")
            for index, row in rows {
                if row.id != "" || !expectedHelp.Has(row.label)
                    continue
                this.Assert(index < rows.Length && rows[index + 1].id = expectedHelp[row.label],
                    row.label " displays its Help shortcut first")
            }
            saved := manager.GetConfiguration()
            this.Assert(saved["scratchpad.help"].bindings[1]
                = Keybindings.Parse("Pause + F12").signature
                && saved["scratchpad.help"].bindings[2] = "",
                "Paper Pad Help defaults to Pause + F12")
            this.Assert(saved["keyboard-layers.help"].bindings[1] = ""
                && saved["keyboard-layers.help"].bindings[2] = "",
                "Secret Keys Help remains unassigned by default")
            this.Assert(manager.actions["power-hotkey.keyboard.toggle-caps"].category = "Secret Keys"
                && saved["power-hotkey.keyboard.toggle-caps"].bindings[1] = "",
                "Caps Lock toggle belongs to Secret Keys and defaults unassigned")
            this.Assert(saved["window-cascade.help"].bindings[1]
                = Keybindings.Parse("Caps + H").signature
                && saved["win-key-overhaul.help"].bindings[1]
                    = Keybindings.Parse("Caps + Win + H").signature
                && saved["power-hotkey.interface.open"].bindings[1]
                    = Keybindings.Parse("Pause + H").signature,
                "existing module Help shortcuts retain their original defaults")
            this.Assert(this.RouteExists(manager, "scratchpad.help"),
                "Paper Pad Help registers its default Pause + F12 shortcut")
            this.Assert(!this.RouteExists(manager, "keyboard-layers.help"),
                "unassigned Secret Keys Help installs no shortcut")
            this.Assert(InStr(ModuleHelp.Text("keyboard-layers", manager),
                "WHY I MADE THIS") = 1
                && !InStr(ModuleHelp.Text("keyboard-layers", manager), "CURRENT SAVED SHORTCUTS"),
                "Secret Keys help provides a practical guide without a shortcut inventory")
            filtered := Keybindings.DisplayRows(manager.DiscoverParticipants(), "Inside the editor")
            this.Assert(filtered.Length > 2 && filtered[1].label = "Paper Pad"
                && filtered[2].label = "Paper Pad / Inside the editor",
                "filtered editor-only actions retain the Paper Pad parent section")
            generalHeading := 0
            functionHeading := 0
            for index, row in rows {
                if row.id = "" && row.label = "Power-Up Utilities"
                    generalHeading := index
                if row.id = "" && row.label = "Power-Up Utilities / Extra function keys"
                    functionHeading := index
            }
            this.Assert(generalHeading > 0 && functionHeading > generalHeading,
                "general Power-Up Utilities shortcuts precede specialized subcategories")
            sampleActions := [
                {id: "alpha.first", category: "Alpha / Shortcuts", label: "first",
                    enabled: true, bindings: ["", ""]},
                {id: "beta.one", category: "Beta", label: "other module",
                    enabled: true, bindings: ["", ""]},
                {id: "alpha.second", category: "Alpha / Extensions", label: "second",
                    enabled: true, bindings: ["", ""]},
                {id: "alpha.general", category: "Alpha", label: "general",
                    enabled: true, bindings: ["", ""]}
            ]
            sample := [{id: "sample", name: "Sample", actions: sampleActions}]
            sampleRows := Keybindings.DisplayRows(sample)
            headings := []
            for row in sampleRows
                if row.id = ""
                    headings.Push(row.label)
            this.Assert(headings.Length = 4 && headings[1] = "Alpha"
                && headings[2] = "Alpha / Shortcuts"
                && headings[3] = "Alpha / Extensions" && headings[4] = "Beta",
                "subcategories follow their module immediately without interleaving")
            sampleRows := Keybindings.DisplayRows(sample, "Extensions")
            this.Assert(sampleRows.Length = 3 && sampleRows[1].label = "Alpha"
                && sampleRows[2].label = "Alpha / Extensions",
                "search keeps extension headings directly after their parent")
            this.Assert(sampleRows[2].kind = "owner",
                "subcategories retain the same heading style as main categories")
            seenFancy := false
            for row in rows
                if InStr(row.id, "win-key-overhaul.zone-") = 1
                    seenFancy := true
            this.Assert(!seenFancy, "FancyZones actions are hidden while integration is inactive")
            this.Assert(!this.RouteExists(manager, "win-key-overhaul.zone-left"),
                "inactive FancyZones actions reserve no shortcuts")
            app.activeModules["scratchpad"] := false
            manager.Apply(manager.GetConfiguration())
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
            paperFound := false
            for row in rows
                if InStr(row.id, "scratchpad.") = 1
                    paperFound := true
            this.Assert(!paperFound, "disabled Paper Pad entries disappear completely")
            configuration := manager.GetConfiguration()
            this.Assert(configuration["scratchpad.toggle"].bindings[1] != "",
                "hidden module assignments remain safely stored")

            changed := manager.GetConfiguration()
            changed["power-hotkey.keyboard.f13"].bindings[1] := "Ctrl + Alt + Left"
            manager.Apply(changed)
            this.Assert(this.RouteExists(manager, "power-hotkey.keyboard.f13"),
                "an unused FancyZones shortcut can be reassigned without conflict")

            global WW_fancyzones_process_id, WW_fancyzones_integration_state
            WW_fancyzones_process_id := 123456
            WW_fancyzones_integration_state := {override_snap_enabled: true,
                relative_position_enabled: false}
            this.Assert(app.wonder.FancyZonesAvailable("left") && !app.wonder.FancyZonesAvailable("up"),
                "FancyZones availability respects the active navigation mode")
            app.wonder.RefreshOptionalActions()
            this.Assert(!this.RouteExists(manager, "win-key-overhaul.zone-left"),
                "a newly enabled conflicting integration does not steal an active shortcut")
            this.Assert(manager.GetConfiguration()["power-hotkey.keyboard.f13"].bindings[1]
                = Keybindings.Parse("Ctrl + Alt + Left").signature,
                "optional activation conflicts leave saved bindings untouched")

            changed := manager.GetConfiguration()
            changed["power-hotkey.keyboard.f13"].bindings[1] := "Caps + Q"
            manager.Apply(changed)
            this.Assert(this.RouteExists(manager, "win-key-overhaul.zone-left"),
                "FancyZones shortcuts activate after their conflict is cleared")
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
            fancyLeft := false
            fancyUp := false
            fancyHeading := false
            for row in rows {
                if row.id = "" && row.label = "Wonder Windows / FancyZones"
                    fancyHeading := true
                if row.id = "win-key-overhaul.zone-left"
                    fancyLeft := true
                if row.id = "win-key-overhaul.zone-up"
                    fancyUp := true
            }
            this.Assert(fancyLeft && !fancyUp && fancyHeading,
                "only currently usable FancyZones directions appear in their extension subgroup")
            WW_fancyzones_process_id := 0
            WW_fancyzones_integration_state := false
            app.wonder.RefreshOptionalActions()
            this.Assert(!this.RouteExists(manager, "win-key-overhaul.zone-left"),
                "stopping FancyZones releases its registered shortcuts")
            this.Assert(manager.GetConfiguration()["win-key-overhaul.zone-left"].bindings[1] != "",
                "disappearing optional shortcuts preserve their assignments")
            this.Assert(!InStr(Keybindings.DisplayRows(manager.DiscoverParticipants())[1].label, "disabled"),
                "Keybindings headings do not acquire disabled suffixes")
        }
        finally {
            global WW_fancyzones_process_id, WW_fancyzones_integration_state
            WW_fancyzones_process_id := 0
            WW_fancyzones_integration_state := false
            manager.Stop()
        }
    }

    static AssertDisplaySequence(rows, actionIds, label) {
        ; Each visible action must follow its predecessor. Missing actions fail
        ; too, so an accidental rename or deletion cannot pass unnoticed.
        positions := Map()
        for index, row in rows
            if row.id != ""
                positions[row.id] := index
        previous := 0
        ordered := true
        for actionId in actionIds {
            if !positions.Has(actionId) || positions[actionId] <= previous {
                ordered := false
                break
            }
            previous := positions[actionId]
        }
        this.Assert(ordered, label)
    }

    static CheckDisplayOrder(rows) {
        this.AssertDisplaySequence(rows, [
            "core.keybindings", "window-cascade.copy-log", "window-cascade.reset-log"],
            "Global shortcuts group application first and logs together")
        this.AssertDisplaySequence(rows, [
            "scratchpad.help", "scratchpad.toggle", "scratchpad.new",
            "scratchpad.save", "scratchpad.delete", "scratchpad.previous",
            "scratchpad.next", "scratchpad.hide"],
            "Paper Pad groups document operations and page navigation")
        this.AssertDisplaySequence(rows, [
            "window-cascade.help", "window-cascade.focus-previous", "window-cascade.focus-next",
            "window-cascade.slot-previous", "window-cascade.slot-next",
            "window-cascade.swap-up", "window-cascade.swap-down",
            "window-cascade.rotate-next", "window-cascade.rotate-previous",
            "window-cascade.adopt", "window-cascade.bring-forward", "window-cascade.minimize",
            "window-cascade.auto-placement", "window-cascade.gather",
            "window-cascade.move-left", "window-cascade.move-right",
            "window-cascade.close-active", "window-cascade.close-monitor"],
            "Cascade Kingdom groups navigation, rotation and management")
        this.AssertDisplaySequence(rows, [
            "win-key-overhaul.help", "win-key-overhaul.focus-up",
            "win-key-overhaul.focus-down", "win-key-overhaul.focus-left",
            "win-key-overhaul.focus-right", "win-key-overhaul.cycle-expanded",
            "win-key-overhaul.maximize", "win-key-overhaul.restore", "win-key-overhaul.minimize",
            "win-key-overhaul.layout-left", "win-key-overhaul.layout-right",
            "win-key-overhaul.tile-top-left", "win-key-overhaul.tile-top",
            "win-key-overhaul.tile-top-right", "win-key-overhaul.tile-bottom-left",
            "win-key-overhaul.tile-bottom", "win-key-overhaul.tile-bottom-right",
            "win-key-overhaul.stretch-left", "win-key-overhaul.stretch-right",
            "win-key-overhaul.stretch-height", "win-key-overhaul.stretch-full-cycle",
            "win-key-overhaul.reset-stretch",
            "win-key-overhaul.swap-next", "win-key-overhaul.swap-previous",
            "win-key-overhaul.isolate", "win-key-overhaul.minimize-all"],
            "Wonder Windows groups focus, positioning, stretching and grouping")
        this.AssertDisplaySequence(rows, [
            "power-hotkey.interface.open", "power-hotkey.system.wake-speakers",
            "power-hotkey.system.sleep"],
            "Power-Up Utilities groups general system controls")
        this.AssertDisplaySequence(rows, [
            "power-hotkey.keyboard.f13", "power-hotkey.keyboard.f18",
            "power-hotkey.keyboard.f24"],
            "extra function keys follow numeric order")
        this.AssertDisplaySequence(rows, [
            "power-hotkey.keyboard.numpad0", "power-hotkey.keyboard.numpad5",
            "power-hotkey.keyboard.numpad9"],
            "virtual number pad follows numeric order")
        this.AssertDisplaySequence(rows, [
            "power-hotkey.text.apostrophe", "power-hotkey.text.en-dash",
            "power-hotkey.text.nbsp", "power-hotkey.text.sharp-s",
            "power-hotkey.text.timestamp"],
            "text utilities keep characters together before timestamp")
        this.AssertDisplaySequence(rows, [
            "power-hotkey.terminal.copy", "power-hotkey.terminal.clear"],
            "Terminal copy precedes destructive clear")
        this.AssertDisplaySequence(rows, [
            "keyboard-layers.help", "power-hotkey.keyboard.toggle-caps"],
            "Secret Keys keeps Help first")
        powerHeadings := []
        for row in rows
            if row.id = "" && InStr(row.label, "Power-Up Utilities") = 1
                powerHeadings.Push(row.label)
        this.Assert(powerHeadings.Length = 5
            && powerHeadings[1] = "Power-Up Utilities"
            && powerHeadings[2] = "Power-Up Utilities / Extra function keys"
            && powerHeadings[3] = "Power-Up Utilities / Virtual number pad"
            && powerHeadings[4] = "Power-Up Utilities / Text and symbols"
            && powerHeadings[5] = "Power-Up Utilities / Windows Terminal",
            "existing Power-Up Utilities headings have a purposeful order")
        ; Search/filtering must retain the declared order, not the source order.
        subset := [{id: "win-key-overhaul.minimize"}, {id: "win-key-overhaul.focus-up"},
            {id: "win-key-overhaul.unknown"}]
        reordered := Keybindings.OrderDisplayEntries("Wonder Windows", subset)
        this.Assert(reordered.Length = 3
            && reordered[1].id = "win-key-overhaul.focus-up"
            && reordered[2].id = "win-key-overhaul.minimize"
            && reordered[3].id = "win-key-overhaul.unknown",
            "filtered actions keep their order and unknown future actions follow")
        original := Keybindings.OrderDisplayEntries("Unregistered category", subset)
        this.Assert(original.Length = 3 && original[1].id = subset[1].id
            && original[2].id = subset[2].id && original[3].id = subset[3].id,
            "unrecognized categories retain their original order")
    }

    static RouteExists(manager, actionId) {
        for route in manager.routes
            if route.action.id = actionId && route.enabled
                return true
        return false
    }

    static Interfaces() {
        app := SuiteApplication(true, SuiteChecks.directory "\new-interfaces")
        try {
            app.Start()
            this.Assert(SuiteApplication.Name = "Super Hotkey"
                && SuiteApplication.Version = "1.0.0",
                "application identity is Super Hotkey v1.0.0")
            this.Assert(A_IconTip = "Super Hotkey v1.0.0 - dry run",
                "tray hover text includes its assigned version and dry-run suffix")
            count := DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle, "int")
            this.Assert(count = 19,
                "tray includes application suspension and an explicit app restart")
            loop count
                this.Assert(!DllCall("GetSubMenu", "ptr", A_TrayMenu.Handle, "int", A_Index - 1, "ptr"),
                    "tray entry has no submenu: " A_Index)
            for item in [[10, "Verbose logging"], [11, "Open settings folder"],
                [13, "Run at startup"], [14, "Suspend"],
                [15, "Restart Super Hotkey"], [16, "Reset to defaults..."]] {
                name := Buffer(256, 0)
                DllCall("GetMenuStringW", "ptr", A_TrayMenu.Handle,
                    "uint", item[1], "ptr", name, "int", 128, "uint", 0x400, "int")
                this.Assert(StrGet(name, "UTF-16") = item[2],
                    "tray exposes " item[2] " directly")
            }
            verboseStatus := (*) => DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 10, "uint", 0x400, "uint")
            this.Assert(!(verboseStatus.Call() & 8),
                "verbose logging starts unchecked in the tray")
            startupState := DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 13, "uint", 0x400, "uint")
            this.Assert(startupState & 3,
                "Run at startup is disabled during safe dry-run testing")
            this.Assert(!HasMethod(app.ui, "ShowAppSettings"),
                "the redundant App settings window is removed")
            hotkeyState := (*) => DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 14, "uint", 0x400, "uint")
            this.Assert(!(hotkeyState.Call() & 8) && !app.suspended,
                "Suspend starts unchecked")
            app.ui.ToggleSuspension()
            this.Assert(app.suspended && app.manager.paused
                && (hotkeyState.Call() & 8),
                "Suspend checks its menu item and gates the keybinding manager")
            app.ui.ToggleSuspension()
            this.Assert(!app.suspended && !(hotkeyState.Call() & 8)
                && app.manager.paused,
                "Resume hotkeys preserves another pause reason, including dry run")
            app.ui.ToggleVerboseTray()
            this.Assert(SuiteState.Log.verbose && app.Settings.verbose
                && (verboseStatus.Call() & 8),
                "tray enables and checks persistent verbose logging")
            app.ui.ToggleVerboseTray()
            this.Assert(!SuiteState.Log.verbose && !app.Settings.verbose
                && !(verboseStatus.Call() & 8),
                "tray disables and unchecks verbose logging")
            firstEditor := app.manager.settings.Hwnd
            app.ShowKeybindings()
            this.Assert(app.manager.settings.Hwnd = firstEditor, "every Keybindings entry reuses the global editor")
            editor := app.manager.settings
            this.Assert(app.manager.settingsResetAll.Text = "Restore defaults"
                && app.manager.settingsApply.Text = "Apply"
                && app.manager.settingsDone.Text = "Cancel",
                "global Keybindings has Restore defaults, live Apply, and Cancel")
            editor.GetClientPos(, , &firstWidth, &firstHeight)
            this.AssertCentered(editor, "Keybindings")
            this.AssertResizeGrip(editor, "Keybindings")
            expectedKeybindingsHeight := Min(860, Max(560, A_ScreenHeight - 125))
            monitor := GetMonitorForWindow(editor.Hwnd)
            MonitorGetWorkArea(monitor, &workLeft, &workTop, &workRight, &workBottom)
            expectedSize := SuiteFitClientSize(editor, 1060, expectedKeybindingsHeight,
                workRight - workLeft, workBottom - workTop)
            this.Assert(Abs(firstWidth - expectedSize.width) <= 1
                && Abs(firstHeight - expectedSize.height) <= 1,
                "Keybindings opening size fits the current monitor: " firstWidth "x" firstHeight)
            this.Assert(!HasProp(app.manager, "settingsRefresh"),
                "Keybindings no longer has a Refresh button")
            this.Assert(app.manager.rows[1].label = "Global"
                && app.manager.visibleRows[1].categoryTitle.Text = "★ Global ★",
                "Global heading has decorative stars without changing its category identity")
            editorStyle := WinGetStyle("ahk_id " editor.Hwnd)
            this.Assert(!!(editorStyle & 0x00040000) && !!(editorStyle & 0x00010000),
                "Keybindings supports native edge resizing and maximizing")
            controls := [app.manager.visibleRows[1].title,
                app.manager.visibleRows[1].categoryTitle,
                app.manager.visibleRows[1].primary,
                app.manager.visibleRows[1].secondary,
                app.manager.visibleRows[1].reset,
                app.manager.settingsSearch,
                app.manager.settingsResetAll, app.manager.settingsApply, app.manager.settingsDone]
            weights := []
            sizes := []
            faces := []
            for control in controls {
                fontHandle := SendMessage(0x0031, 0, 0, , control.Hwnd) ; WM_GETFONT
                fontData := Buffer(92, 0) ; LOGFONTW
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size,
                    "Keybindings control exposes its font")
                weights.Push(NumGet(fontData, 16, "int"))
                sizes.Push(NumGet(fontData, 0, "int"))
                faces.Push(StrGet(fontData.Ptr + 28, 32, "UTF-16"))
            }
            sameFont := true
            for index, weight in weights
                if weight != 400 || sizes[index] != sizes[1]
                    sameFont := false
            this.Assert(sameFont,
                "all Keybindings text uses the same regular font weight and size")
            consistentFamily := true
            for fontFace in faces
                if fontFace != "Cascadia Mono" && fontFace != "Consolas"
                    consistentFamily := false
            this.Assert(consistentFamily,
                "Keybindings uses the Help-page font family")
            this.Assert(!!(WinGetExStyle("ahk_id " editor.Hwnd) & 0x02000000),
                "Keybindings composites child-control painting")
            initialRows := app.manager.visibleRows.Length
            editor.Show("w1120 h1100")
            editor.GetClientPos(, , &expandedWidth, &expandedHeight)
            app.manager._ResizeSettings(editor, 0, expandedWidth, expandedHeight)
            expandedRows := app.manager.visibleRows.Length
            this.Assert(expandedRows > initialRows,
                "live resizing reveals more rows (old " initialRows
                ", new " expandedRows ", height " expandedHeight
                ", layout " app.manager.settingsRenderedHeight ")")
            markerRow := app.manager.visibleRows[1]
            markerRow.title.Text := "layout-only marker"
            editor.Show("w1080 h" expandedHeight)
            editor.GetClientPos(, , &adjustedWidth, &adjustedHeight)
            app.manager._ResizeSettings(editor, 0, adjustedWidth, adjustedHeight)
            this.Assert(markerRow.title.Text = "layout-only marker",
                "width-only resize does not re-render shortcut labels")
            extraWidth := adjustedWidth - 820
            originalPrimaryX := 323 + Floor(extraWidth * 0.48)
            originalPrimaryWidth := 185 + Floor(extraWidth * 0.28)
            originalSecondaryWidth := 170 + extraWidth
                - (originalPrimaryX - 323) - (originalPrimaryWidth - 185)
            expectedPrimaryWidth := Round(originalPrimaryWidth * 0.9)
            expectedSecondaryWidth := Round(originalSecondaryWidth * 0.9)
            expectedPrimaryX := adjustedWidth - 142
                - expectedPrimaryWidth - expectedSecondaryWidth
            markerRow.primary.GetPos(&actualPrimaryX, , &actualPrimaryWidth)
            markerRow.secondary.GetPos(&actualSecondaryX, , &actualSecondaryWidth)
            markerRow.reset.GetPos(&actualResetX)
            this.Assert(Abs(actualPrimaryX - expectedPrimaryX) <= 2
                && Abs(actualPrimaryWidth - expectedPrimaryWidth) <= 2
                && Abs(actualSecondaryWidth - expectedSecondaryWidth) <= 2,
                "both binding boxes are 10 percent narrower across resized window widths")
            this.Assert(Abs(actualSecondaryX - (actualPrimaryX + actualPrimaryWidth + 10)) <= 2
                && Abs(actualResetX - (actualSecondaryX + actualSecondaryWidth + 10)) <= 2,
                "narrower binding boxes preserve the gaps and reset button alignment")
            app.manager.settingsResetAll.GetPos(, &oldFooterY)
            editor.Show("w1080 h700")
            editor.GetClientPos(, , &shorterWidth, &shorterHeight)
            app.manager._ResizeSettings(editor, 0, shorterWidth, shorterHeight)
            app.manager.settingsResetAll.GetPos(, &newFooterY)
            this.Assert(newFooterY < oldFooterY,
                "live vertical resize moves the footer as one coherent layout")
            editor.Show("w1080 h850")
            editor.GetClientPos(, , &adjustedWidth, &adjustedHeight)
            app.manager._ResizeSettings(editor, 0, adjustedWidth, adjustedHeight)
            app.manager._RenderSettings()
            this.Assert(expandedRows > initialRows, "resizing taller reveals more shortcut rows")
            app.manager.settingsScroll.GetPos(&scrollX)
            this.Assert(scrollX > 950, "scrollbar stays anchored to the right edge")
            app.manager.settingsDone.GetPos(, &doneY)
            editor.GetClientPos(, , , &clientHeight)
            this.Assert(Abs(doneY - (clientHeight - 49)) <= 2,
                "done button stays pinned to the bottom")
            app.manager.settingsResetAll.GetPos(&restoreX, , &restoreW)
            app.manager.settingsApply.GetPos(&applyX, , &applyW)
            app.manager.settingsDone.GetPos(&cancelX, , &cancelW)
            this.Assert(Abs(cancelX + cancelW - (adjustedWidth - 46)) <= 2
                && Abs(applyX - (restoreX + restoreW + 14)) <= 2
                && Abs(cancelX - (applyX + applyW + 14)) <= 2,
                "Keybindings footer buttons are right-aligned with consistent gaps")
            editor.Show("w820 h420")
            editor.GetClientPos(, , &compactWidth, &compactHeight)
            app.manager._ResizeSettings(editor, 0, compactWidth, compactHeight)
            this.Assert(app.manager.visibleRows.Length < expandedRows,
                "resizing smaller reduces the visible row count without losing the catalog")
            app.manager.settingsSearch.Value := "Inside the editor"
            app.manager._SearchChanged()
            headingRow := app.manager.visibleRows[2]
            this.Assert(headingRow.categoryTitle.Visible
                && headingRow.categoryTitle.Text = "Paper Pad / Inside the editor"
                && !headingRow.contextTag.Visible,
                "category headings no longer show the generic scoped marker")
            paperRow := app.manager.visibleRows[3]
            paperRow.title.GetPos(&descriptionX, &descriptionY, &descriptionWidth, &descriptionHeight)
            paperRow.contextTag.GetPos(&tagX, &tagY, &tagWidth, &tagHeight)
            paperRow.primary.GetPos(&bindingX, &bindingY, , &bindingHeight)
            this.Assert(paperRow.contextTag.Visible && paperRow.contextTag.Text = "editor only"
                && descriptionX + descriptionWidth + 8 <= tagX
                && tagX + tagWidth + 12 = bindingX,
                "Paper Pad context tag sits immediately before the first binding")
            this.Assert(tagWidth <= 80 && tagHeight = 16
                && tagY = bindingY + 6
                && Abs((tagY + tagHeight / 2) - (bindingY + bindingHeight / 2)) <= 1
                && tagHeight < descriptionHeight,
                "context tag is compact and vertically centered with the binding")
            nextPaperRow := app.manager.visibleRows[4]
            nextPaperRow.contextTag.GetPos(&nextTagX, , &nextTagWidth)
            nextPaperRow.primary.GetPos(&nextBindingX)
            this.Assert(nextPaperRow.contextTag.Visible
                && nextTagX = tagX && nextTagWidth = tagWidth
                && nextBindingX = bindingX,
                "Paper Pad context tags align across different description lengths")
            app.manager.settingsSearch.Value := "Windows Terminal"
            app.manager._SearchChanged()
            terminalRow := app.manager.visibleRows[3]
            terminalRow.title.GetPos(&terminalDescriptionX, , &terminalDescriptionWidth)
            terminalRow.contextTag.GetPos(&terminalTagX, , &terminalTagWidth)
            terminalRow.primary.GetPos(&terminalBindingX)
            this.Assert(terminalRow.contextTag.Visible
                && terminalRow.contextTag.Text = "terminal only"
                && terminalTagWidth <= 100
                && terminalDescriptionX + terminalDescriptionWidth + 8 <= terminalTagX
                && terminalTagX + terminalTagWidth + 12 = terminalBindingX,
                "Windows Terminal context tag is aligned before its binding")
            editor.Show("w1080 h420")
            editor.GetClientPos(, , &widerWidth, &widerHeight)
            app.manager._ResizeSettings(editor, 0, widerWidth, widerHeight)
            terminalRow.contextTag.GetPos(&wideTagX, , &wideTagWidth)
            terminalRow.primary.GetPos(&wideBindingX)
            this.Assert(wideTagX + wideTagWidth + 12 = wideBindingX,
                "context tag remains anchored beside its binding after resizing")
            app.manager.settingsSearch.Value := ""
            app.manager._SearchChanged()
            this.Assert(!app.manager.visibleRows[1].contextTag.Visible,
                "unscoped heading hides the reused row's context tag")
            app.manager._CloseSettings()
            IniWrite("1300", app.manager.root "\window.ini", "Window", "Width")
            IniWrite("900", app.manager.root "\window.ini", "Window", "Height")
            app.manager.ShowSettings()
            app.manager.settings.GetClientPos(, , &reopenedW, &reopenedH)
            this.Assert(Abs(reopenedW - expectedSize.width) <= 1
                && Abs(reopenedH - expectedSize.height) <= 1,
                "Keybindings ignores size history and reopens at its adaptive default")
            this.AssertCentered(app.manager.settings, "reopened Keybindings")
            app.manager._CloseSettings()
            this.Assert(IniRead(app.manager.root "\window.ini", "Window", "Width") = "1300"
                && IniRead(app.manager.root "\window.ini", "Window", "Height") = "900",
                "Keybindings does not update old saved window sizes")
            IniWrite("1600", app.Settings.directory "\help-window.ini", "Window", "Width")
            IniWrite("950", app.Settings.directory "\help-window.ini", "Window", "Height")
            for id in SuiteSettings.ModuleOrder {
                app.ui.ShowHelp(id)
                key := "help:" id
                window := app.ui.windows[key]
                this.Assert(window.Title = SuiteSettings.ModuleNames[id] " - Getting started",
                    "module Help uses Getting started only in the title bar: " id)
                guide := window["helpText"].Value
                this.Assert(StrLen(guide) > 300 && !InStr(guide, "CURRENT SAVED SHORTCUTS"),
                    "help explains usage without listing every keybinding: " id)
                firstHeading := Map("window-cascade", "AUTOMATIC CASCADES",
                    "win-key-overhaul", "ARRANGE YOUR WINDOWS",
                    "power-hotkey", "MORE KEYS WITHOUT A NEW KEYBOARD",
                    "scratchpad", "YOUR OWN QUICK-NOTES DRAWER",
                    "keyboard-layers", "HOLD A KEY FOR MORE HOTKEYS")
                this.Assert(InStr(guide, "WHY I MADE THIS`r`n") = 1
                    && InStr(guide, "`r`n`r`n" firstHeading[id]) > 0
                    && !InStr(guide, "GETTING STARTED"),
                    "each module starts with a personal introduction: " id)
                this.Assert(StrLen(guide) >= 600,
                    "each Help guide provides substantial practical usage details: " id)
                this.Assert(InStr(guide, "until you") > 0 || id != "window-cascade",
                    "Help sentences aren't split by fixed hard line breaks")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                expectedHelpHeight := Max(480, 145 + app.ui.HelpTextHeight(id, 820) + 12)
                this.Assert(helpWidth = 820 && helpHeight = expectedHelpHeight,
                    "Help opens tall enough for its introduction: " id)
                this.AssertCentered(window, SuiteSettings.ModuleNames[id] " Help")
                this.AssertResizeGrip(window, SuiteSettings.ModuleNames[id] " Help")
                titlePart := app.ui.helpLayouts[id].header
                statusPart := app.ui.helpLayouts[id].status
                titlePart.GetPos(&headingX, , &headingW)
                statusPart.GetPos(&statusX, , &statusW)
                this.Assert(titlePart.Text = SuiteSettings.ModuleNames[id] " - "
                    && statusPart.Text = "dry run; feature effects are inactive"
                    && app.ui.helpLayouts[id].statusColor = "505050"
                    && statusX = headingX + headingW
                    && Abs(headingX + (headingW + statusW) / 2 - helpWidth / 2) <= 2,
                    "Help module name and status are centered as one line: " id)
                guideControl := window["helpText"]
                guideControl.GetPos(, &textY, , &textHeight)
                this.Assert(guideControl.Type = "Text"
                    && app.ui.helpLayouts[id].footer.divider.Visible,
                    "help is plain GUI text with a shared footer divider: " id)
                app.ui.helpLayouts[id].footer.divider.GetPos(, &dividerY)
                this.Assert(dividerY > textY + textHeight,
                    "the Help footer divider stays below the guide: " id)
                fontHandle := SendMessage(0x0031, 0, 0, , guideControl.Hwnd)
                fontData := Buffer(92, 0)
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size
                    && NumGet(fontData, 16, "int") = 400,
                    "help uses the original regular-weight font: " id)
                fontFace := StrGet(fontData.Ptr + 28, 32, "UTF-16")
                this.Assert(fontFace = "Cascadia Mono" || fontFace = "Consolas",
                    "help font is the old Cascadia Mono or the Windows fallback: " id)
                this.Assert(helpWidth >= 560 && helpHeight >= 400
                    && textHeight > 310 && textY + textHeight < helpHeight - 60,
                    "initial help page fits its complete guide: " id)
                this.Assert(app.ui.HelpTextHeight(id, helpWidth) <= textHeight,
                    "all Help guide paragraphs fit above the footer at startup: " id)
                this.Assert(app.ui.helpWindowIds.Has(window.Hwnd),
                    "Help window has its own wrap-aware sizing guard: " id)
                fullWidthHeight := app.ui.HelpTextHeight(id, 820)
                narrowHeight := app.ui.HelpTextHeight(id, 560)
                this.Assert(narrowHeight > fullWidthHeight,
                    "Help paragraphs wrap into more lines when narrower: " id)
                this.Assert(560 > app.ui.helpLayouts[id].footer.total + 20,
                    "minimum width keeps every footer button visible: " id)
                physicalWindow := Buffer(16, 0)
                physicalClient := Buffer(16, 0)
                DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", physicalWindow, "int")
                DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", physicalClient, "int")
                scale := NumGet(physicalClient, 8, "int") / helpWidth
                borderW := NumGet(physicalWindow, 8, "int")
                    - NumGet(physicalWindow, 0, "int") - NumGet(physicalClient, 8, "int")
                borderH := NumGet(physicalWindow, 12, "int")
                    - NumGet(physicalWindow, 4, "int") - NumGet(physicalClient, 12, "int")
                sizing := Buffer(16, 0)
                NumPut("int", 100, sizing, 0)
                NumPut("int", 100, sizing, 4)
                NumPut("int", 100 + Round(560 * scale) + borderW, sizing, 8)
                NumPut("int", 100 + Round(400 * scale) + borderH, sizing, 12)
                app.ui.KeepHelpTextVisible(8, sizing.Ptr, 0, window.Hwnd)
                minimumHeight := Ceil(Max(400, 145 + narrowHeight) * scale) + borderH
                this.Assert(NumGet(sizing, 12, "int") - NumGet(sizing, 4, "int")
                    >= minimumHeight,
                    "narrow window can't hide wrapped text under its footer: " id)
                style := WinGetStyle("ahk_id " window.Hwnd)
                this.Assert(!!(style & 0x00040000) && !!(style & 0x00010000),
                    "help window is resizable and maximizable: " id)
                firstHeight := textHeight
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                window["helpText"].GetPos(, , , &textHeight)
                this.Assert(textHeight > firstHeight, "help body grows vertically: " id)
                this.Assert(app.ui.helpLayouts[id].renderedWidth = helpWidth
                    && app.ui.helpLayouts[id].renderedHeight = helpHeight,
                    "help live resizing processes one coherent control layout: " id)
                this.AssertResizeGrip(window, SuiteSettings.ModuleNames[id] " resized Help")
                app.ui.helpLayouts[id].footer.divider.GetPos(, &dividerY, &dividerWidth)
                this.Assert(dividerY = helpHeight - 64
                    && dividerWidth = helpWidth - 40,
                    "help footer divider stays anchored during resizing: " id)
                for iteration in [1, 2, 3] {
                    window.Show("w" (960 + iteration * 25) " h" (610 + iteration * 20))
                    window.GetClientPos(, , &helpWidth, &helpHeight)
                    app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                    for item in app.ui.helpLayouts[id].footer.buttons {
                        item.button.GetPos(&buttonX, &buttonY, &buttonW)
                        this.Assert(buttonY = helpHeight - 49
                            && buttonX + buttonW <= helpWidth,
                            "buttons remain correctly placed after repeated resizing: " id)
                    }
                }
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                window.Show("w720 h400")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                this.Assert(helpWidth = 720 && helpHeight = 400,
                    "Help can shrink below its starting size: " id)
                window.Show("w560 h650")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                this.Assert(helpWidth = 560
                    && app.ui.helpLayouts[id].footer.divider.Visible,
                    "Help narrows to a footer-safe width and keeps the divider: " id)
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                for control in window {
                    if control.Type != "Button"
                        continue
                    control.GetPos(&buttonX, &buttonY, &buttonWidth)
                    this.Assert(buttonY > textY + textHeight
                        && buttonX >= 0 && buttonX + buttonWidth <= helpWidth,
                        "help navigation stays in the footer: " id "/" control.Text)
                    this.Assert(app.ui.footerButtons.Has(control.Hwnd),
                        "help button uses the shared square-corner styling: " id "/" control.Text)
                }
                beforePaint := app.ui.footerPaintCount
                for item in app.ui.helpLayouts[id].footer.buttons
                    DllCall("RedrawWindow", "ptr", item.button.Hwnd, "ptr", 0, "ptr", 0,
                        "uint", 0x185, "int")
                this.Assert(app.ui.footerPaintCount > beforePaint,
                    "help footer buttons are painted with square corners: " id)
                if SuiteIcons.handles.Length
                    this.Assert(SendMessage(0x007F, 0, 0, , window.Hwnd)
                        = SuiteIcons.handles[1], "module help uses one application icon: " id)

                if id != "power-hotkey" {
                    app.ui.OpenSettingsFromHelp(id)
                    this.Assert(!app.ui.windows.Has(key)
                        && app.ui.configurationWindows.Has("settings:" id),
                        "Settings replaces Help rather than stacking over it: " id)
                    settings := app.ui.windows["settings:" id]
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    if id = "win-key-overhaul" {
                        for pair in [["snapStatus", ["on", "off", "unknown"]],
                            ["screenGridStatus", ["running", "not running"]],
                            ["fancyZonesStatus", ["running", "not running"]]] {
                            statusValue := settings[pair[1]].Text
                            allowed := false
                            for permitted in pair[2]
                                if statusValue = permitted
                                    allowed := true
                            this.Assert(allowed,
                                "Wonder Windows shows an explicit " pair[1] " status")
                        }
                        this.Assert(app.ui.WonderStatusColor("running") = "008000"
                            && app.ui.WonderStatusColor("on") = "008000"
                            && app.ui.WonderStatusColor("off") = "B02020"
                            && app.ui.WonderStatusColor("not running") = "B02020"
                            && app.ui.WonderStatusColor("unknown") = "505050",
                            "Wonder Windows status values use green, red or neutral colors")
                        statusCoords := []
                        for name in ["snapStatus", "screenGridStatus", "fancyZonesStatus"] {
                            settings[name].GetPos(&statusX, &statusY)
                            statusCoords.Push(statusY)
                            this.Assert(statusX = 175,
                                "Wonder Windows " name " value is aligned separately from its label")
                        }
                        this.Assert(statusCoords[1] < statusCoords[2]
                            && statusCoords[2] < statusCoords[3],
                            "Wonder Windows status rows are spaced in reading order")
                    }
                    this.Assert(app.ui.pageLayouts.Has("settings:" id)
                        && !!(WinGetStyle("ahk_id " settings.Hwnd) & 0x00040000),
                        "module Settings are resizable: " id)
                    defaultW := app.ui.pageLayouts["settings:" id].width
                    defaultH := app.ui.pageLayouts["settings:" id].height
                    this.Assert(settingsW = defaultW && settingsH = defaultH,
                        "module Settings open at a sensible size: " id)
                    this.Assert(app.ui.pageLayouts["settings:" id].minWidth < defaultW
                        && app.ui.pageLayouts["settings:" id].minHeight < defaultH,
                        "Settings can shrink below the opening size: " id)
                    this.AssertCentered(settings, SuiteSettings.ModuleNames[id] " Settings")
                    this.AssertResizeGrip(settings, SuiteSettings.ModuleNames[id] " Settings")
                    settings.Show("w" (defaultW + 120) " h" (defaultH + 140))
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    app.ui.ResizePage("settings:" id, settings, 0, settingsW, settingsH)
                    pageFooter := app.ui.pageLayouts["settings:" id].footer
                    pageFooter.divider.GetPos(, &settingsDividerY)
                    pageFooter.buttons[-1].button.GetPos(&lastButtonX, &lastButtonY, &lastButtonW)
                    this.Assert(settingsDividerY = settingsH - 64
                        && lastButtonY = settingsH - 49
                        && lastButtonX + lastButtonW <= settingsW,
                        "module Settings footer follows resizing: " id)
                    settings.Show("w" app.ui.pageLayouts["settings:" id].minWidth
                        " h" app.ui.pageLayouts["settings:" id].minHeight)
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    app.ui.ResizePage("settings:" id, settings, 0, settingsW, settingsH)
                    this.Assert(settingsW = app.ui.pageLayouts["settings:" id].minWidth
                        && settingsH = app.ui.pageLayouts["settings:" id].minHeight,
                        "Settings support smaller manual resizing: " id)
                    backFound := false
                    for control in settings
                        if control.Type = "Button" && control.Text = "Back"
                            backFound := true
                    this.Assert(backFound, "module settings provides Back navigation: " id)
                    settingsDivider := 0
                    settingsPaintTarget := 0
                    for control in settings {
                        if control.Type = "Text"
                            && (WinGetStyle("ahk_id " control.Hwnd) & 0x00000010)
                            settingsDivider := control
                        if control.Type = "Button" && app.ui.footerButtons.Has(control.Hwnd)
                            settingsPaintTarget := control
                    }
                    this.Assert(IsObject(settingsDivider) && settingsDivider.Visible,
                        "module settings retains the same visible footer divider: " id)
                    this.Assert(IsObject(settingsPaintTarget),
                        "module settings footer uses the same square button styling: " id)
                    beforeSettingsPaint := app.ui.footerPaintCount
                    DllCall("RedrawWindow", "ptr", settingsPaintTarget.Hwnd,
                        "ptr", 0, "ptr", 0, "uint", 0x185, "int")
                    this.Assert(app.ui.footerPaintCount > beforeSettingsPaint,
                        "module settings footer uses the shared painter: " id)
                    app.ui.BackToHelp(id)
                    this.Assert(!app.ui.configurationWindows.Has("settings:" id)
                        && app.ui.windows.Has(key),
                        "Back closes Settings and restores Help: " id)
                }

                app.ui.OpenKeybindingsFromHelp(id)
                this.Assert(!app.ui.windows.Has(key)
                    && IsObject(app.manager.settings)
                    && app.manager.settingsModuleId = id
                    && app.manager.settingsDone.Text = "Back",
                    "module Help opens its own filtered Keybindings view: " id)
                moduleName := SuiteSettings.ModuleNames[id]
                onlyModule := true
                for item in app.manager.rows
                    if item.id != "" && !app.manager._ActionInSettingsModule(item.id, id)
                        onlyModule := false
                this.Assert(onlyModule, "module Keybindings excludes unrelated shortcuts: " id)
                app.manager._BackToHelp()
                this.Assert(!IsObject(app.manager.settings) && app.ui.windows.Has(key),
                    "Back from module Keybindings restores the Help page: " id)
                app.ui.CloseWindow(key)
            }
            app.ui.ShowHelp("scratchpad")
            this.Assert(!!WinActive("ahk_id " app.ui.windows["help:scratchpad"].Hwnd),
                "the Help page becomes active for its keyboard shortcut")
            app.ui.ToggleHelp("scratchpad")
            this.Assert(!app.ui.windows.Has("help:scratchpad"),
                "the same Help shortcut closes its active page")
            app.ui.ToggleHelp("scratchpad")
            this.Assert(app.ui.windows.Has("help:scratchpad"),
                "the Help shortcut opens the page again")
            app.ui.windows["help:scratchpad"].GetClientPos(, , &lastHelpW, &lastHelpH)
            this.Assert(lastHelpW = 820 && lastHelpH = 480,
                "Help reopens at the smaller default regardless of prior resizing")
            this.AssertCentered(app.ui.windows["help:scratchpad"], "reopened Paper Pad Help")
            app.ui.CloseWindow("help:scratchpad")
            this.Assert(IniRead(app.Settings.directory "\help-window.ini",
                "Window", "Width") = "1600",
                "Help ignores existing saved window size history")
            app.activeModules["scratchpad"] := false
            app.ui.ShowHelp("scratchpad")
            this.Assert(IsObject(app.ui.windows["help:scratchpad"]),
                "disabled modules still expose their How to use page")
            this.Assert(app.ui.helpLayouts["scratchpad"].header.Text = "Paper Pad - "
                && app.ui.helpLayouts["scratchpad"].status.Text = "disabled"
                && app.ui.helpLayouts["scratchpad"].statusColor = "B02020",
                "disabled Help pages show a centered red status")
            app.ui.CloseWindow("help:scratchpad")
            for page in ["log", "modules"] {
                switch page {
                    case "log": app.ui.OpenLog()
                    case "modules": app.ui.ShowModules()
                }
                window := app.ui.windows[page]
                layout := app.ui.pageLayouts[page]
                window.GetClientPos(, , &pageW, &pageH)
                style := WinGetStyle("ahk_id " window.Hwnd)
                this.Assert(!!(style & 0x00040000) && !!(style & 0x00010000),
                    "all shared utility windows support resize and maximize: " page)
                this.Assert(pageW = layout.width && pageH = layout.height,
                    "utility page opens at its intended size: " page)
                this.Assert(layout.minWidth < layout.width && layout.minHeight < layout.height,
                    "utility page allows smaller manual sizes: " page)
                this.AssertCentered(window, page)
                this.AssertResizeGrip(window, page)
                this.Assert(layout.footer.buttons.Length >= 2
                    && app.ui.footerButtons.Has(layout.footer.buttons[1].button.Hwnd),
                    "utility footer has matching square buttons: " page)
                if page = "log"
                    this.Assert(window["verbose"].Value = 0,
                        "one global logging checkbox is available")
                if page = "modules" {
                    this.Assert(app.ui.moduleControls.Count = 5,
                        "Modules presents all five renamed features")
                    obsoleteLine := false
                    for control in window
                        if control.Type = "Text" && InStr(control.Text, "Disabled modules keep")
                            obsoleteLine := true
                    this.Assert(!obsoleteLine,
                        "Modules no longer has the redundant line under Secret Keys")
                    appSettingsFound := false
                    for control in window
                        if control.Type = "Button" && control.Text = "App settings..."
                            appSettingsFound := true
                    this.Assert(!appSettingsFound,
                        "Modules has no redundant App settings button")
                    descriptionCount := 0
                    for id in SuiteSettings.ModuleOrder {
                        app.ui.moduleControls[id].GetPos(, &checkY, , &checkHeight)
                        this.Assert(checkHeight < 40,
                            "Module checkbox keeps its natural height: " id)
                        checkboxFont := SendMessage(0x0031, 0, 0, ,
                            app.ui.moduleControls[id].Hwnd)
                        checkboxData := Buffer(92, 0)
                        this.Assert(checkboxFont
                            && DllCall("GetObjectW", "ptr", checkboxFont, "int",
                                checkboxData.Size, "ptr", checkboxData, "int") = checkboxData.Size
                            && (StrGet(checkboxData.Ptr + 28, 32, "UTF-16") = "Cascadia Mono"
                                || StrGet(checkboxData.Ptr + 28, 32, "UTF-16") = "Consolas"),
                            "Module controls use the Help-page font: " id)
                        for control in window {
                            if control.Type != "Text"
                                || control.Text != SuiteSettings.ModuleDescriptions[id]
                                continue
                            control.GetPos(, &descriptionY, , &descriptionHeight)
                            this.Assert(descriptionY > checkY
                                && descriptionHeight < 40
                                && descriptionY + descriptionHeight <= checkY + 58,
                                "Module description remains readable without overlap: " id)
                            descriptionCount += 1
                        }
                    }
                    this.Assert(descriptionCount = 5,
                        "all five Module descriptions are actually present and visible")
                }
                window.Show("w" (layout.width + 100) " h" (layout.height + 130))
                window.GetClientPos(, , &pageW, &pageH)
                app.ui.ResizePage(page, window, 0, pageW, pageH)
                layout.footer.divider.GetPos(, &footerDividerY)
                this.Assert(footerDividerY = pageH - 64,
                    "shared utility footer follows resizing: " page)
                window.Show("w" layout.minWidth " h" layout.minHeight)
                window.GetClientPos(, , &pageW, &pageH)
                app.ui.ResizePage(page, window, 0, pageW, pageH)
                this.Assert(pageW = layout.minWidth && pageH = layout.minHeight,
                    "utility page shrinks to its smaller minimum: " page)
                app.ui.CloseWindow(page)
            }
            this.Assert(app.manager.paused && app.wonder.pending.Count = 0,
                "interface navigation keeps dry-run inputs and Wonder Windows effects inactive")
        }
        finally {
            app.Stop("Exit", 0)
            OnExit(app.exitCallback, 0)
            OnError(app.errorCallback, 0)
        }
        this.Assert(!InStr(SuiteState.Log.Read(), "ERROR"), "the five-module GUI smoke test emits no errors")
    }
}
