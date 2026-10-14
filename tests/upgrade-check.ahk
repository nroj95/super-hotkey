; Isolated regression checks. No physical keystrokes, personal windows or editor saves.
class SuiteUpgradeChecks {
    static scopeActive := false
    static observerCalls := 0

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static Route(manager, actionId, slot := 1) {
        for route in manager.routes
            if route.action.id = actionId && route.slot = slot
                return route
        throw Error("Missing test route: " actionId)
    }

    static Run() {
        this.Preferences()
        this.IndependentLayers()
        this.ScopesAndObservers()
        this.GeometryAndOwnership()
        this.ActiveShortcutVisibility()
        this.Interfaces()
    }

    static Preferences() {
        settings := SuiteSettings(SuiteChecks.directory "\upgrade-preferences")
        this.Assert(settings.layers["caps"] && settings.layers["pause"] && !settings.verbose,
            "both Secret Keys layers default on; verbose debugging defaults off")
        settings.Save(settings.modules, Map("caps", false, "pause", true), true)
        loaded := SuiteSettings(settings.directory)
        this.Assert(!loaded.layers["caps"] && loaded.layers["pause"] && loaded.verbose,
            "independent layers and the one global debug preference survive restart")
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
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Caps + K")) = "") = flags[1],
                    "Caps assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause + T")) = "") = flags[2],
                    "Pause assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("CapsLock")) = "") = !flags[1],
                    "native CapsLock ownership: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause")) = "") = !flags[2],
                    "native Pause ownership: " label)
                this.Assert(this.Route(manager, "core.keybindings", 2).enabled,
                    "ordinary Keybindings shortcut remains available: " label)
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

    static ScopesAndObservers() {
        for layered in [false, true] {
            suffix := layered ? "layer" : "ordinary"
            options := {directory: SuiteChecks.directory "\scopes-" suffix}
            if layered
                options.layerFactory := (name, status) => LocalKeyboardLayers(name, status, Map("caps", true, "pause", false))
            manager := Keybindings("scope-check-" suffix, "Scope check", options)
            try {
                manager.RegisterScope("editor", (*) => this.scopeActive)
                binding := layered ? "Caps + F8" : "Ctrl + Alt + F8"
                manager.AddAction("inside", "inside editor", (*) => 0, [binding], {scope: "editor"})
                manager.AddAction("outside", "outside editor", (*) => 0, [binding], {scope: "!editor"})
                manager.AddAction("global", "global action", (*) => 0, [])
                SuiteChecks.Rejects((*) => manager.AddAction("unknown", "unknown scope", (*) => 0, [],
                    {scope: "missing"}), "unknown scope names cannot bypass conflicts: " suffix)
                manager.SetPaused(true)
                manager.Start()
                signature := Keybindings.Parse(binding).signature
                this.Assert(manager.routeMap[signature].Length = 2,
                    "explicit complementary scopes may share one physical binding: " suffix)
                this.scopeActive := false
                this.Assert(manager._SelectedRoute(signature).action.id = "outside", "outside scope routing: " suffix)
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(signature).action.id = "inside", "inside scope routing: " suffix)
                configuration := manager.GetConfiguration()
                configuration["global"].bindings[1] := binding
                before := FileRead(manager.path)
                SuiteChecks.Rejects((*) => manager.Apply(configuration), "a global collision is still rejected: " suffix)
                this.Assert(FileRead(manager.path) = before, "scope conflict does not overwrite saved bindings: " suffix)
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
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[100, 0, 200, 300]], 0) = 300,
                "horizontal stretch stops at the nearest facing edge")
            this.Assert(WW_GetCollisionLimitedEdge("left", [400, 0, 200, 300], [[450, 0, 200, 300]], 0) = 0,
                "pre-existing overlap does not collapse a stretched window")
            window := SuiteGui("+ToolWindow", "Owned migration test window")
            try {
                this.Assert(SuiteWindowOwnership.IsSuiteSurface(window.Hwnd), "Wonder Windows excludes the suite's own windows")
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
                "Power-Up Utilities / Extra function keys", 0,
                "Power-Up Utilities / Virtual number pad", 0,
                "Power-Up Utilities / Text and symbols", 0)
            for actionId, action in manager.actions {
                if InStr(actionId, "power-hotkey.") != 1
                    continue
                this.Assert(groups.Has(action.category),
                    "Power-Up Utilities keeps only useful subcategories: " actionId)
                groups[action.category] += 1
            }
            this.Assert(groups["Power-Up Utilities / Extra function keys"] = 12
                && groups["Power-Up Utilities / Virtual number pad"] = 10
                && groups["Power-Up Utilities / Text and symbols"] = 5,
                "large coherent Power-Up Utilities feature sets have their own headings")
            this.Assert(groups["Power-Up Utilities"] > 0,
                "individual utilities remain directly under Power-Up Utilities")
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
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
            count := DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle, "int")
            this.Assert(count = 12, "tray has exactly the agreed flat entries and separators")
            loop count
                this.Assert(!DllCall("GetSubMenu", "ptr", A_TrayMenu.Handle, "int", A_Index - 1, "ptr"),
                    "tray entry has no submenu: " A_Index)
            firstEditor := app.manager.settings.Hwnd
            app.ShowKeybindings()
            this.Assert(app.manager.settings.Hwnd = firstEditor, "every Keybindings entry reuses the global editor")
            editor := app.manager.settings
            editorStyle := WinGetStyle("ahk_id " editor.Hwnd)
            this.Assert(!!(editorStyle & 0x00040000) && !!(editorStyle & 0x00010000),
                "Keybindings supports native edge resizing and maximizing")
            initialRows := app.manager.visibleRows.Length
            editor.Show("w1120 h850")
            editor.GetClientPos(, , &expandedWidth, &expandedHeight)
            app.manager._ResizeSettings(editor, 0, expandedWidth, expandedHeight)
            expandedRows := app.manager.visibleRows.Length
            this.Assert(expandedRows > initialRows,
                "live resizing immediately reveals more shortcut rows")
            markerRow := app.manager.visibleRows[1]
            markerRow.title.Text := "layout-only marker"
            editor.Show("w1080 h850")
            editor.GetClientPos(, , &adjustedWidth, &adjustedHeight)
            app.manager._ResizeSettings(editor, 0, adjustedWidth, adjustedHeight)
            this.Assert(markerRow.title.Text = "layout-only marker",
                "width-only resize does not re-render shortcut labels")
            expectedPrimaryX := 323 + Floor((adjustedWidth - 820) * 0.48)
            markerRow.primary.GetPos(&actualPrimaryX)
            this.Assert(Abs(actualPrimaryX - expectedPrimaryX) <= 2,
                "batched native movement matches logical control positions")
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
            editor.Show("w820 h420")
            editor.GetClientPos(, , &compactWidth, &compactHeight)
            app.manager._ResizeSettings(editor, 0, compactWidth, compactHeight)
            this.Assert(app.manager.visibleRows.Length < expandedRows,
                "resizing smaller reduces the visible row count without losing the catalog")
            app.manager._CloseSettings()
            this.Assert(IniRead(app.manager.root "\window.ini", "Window", "Width") = compactWidth
                && IniRead(app.manager.root "\window.ini", "Window", "Height") = compactHeight,
                "the chosen editor size is saved between openings")
            app.manager.ShowSettings()
            this.Assert(app.manager.settingsWindowWidth = compactWidth
                && app.manager.settingsWindowHeight = compactHeight,
                "the editor restores its previous size")
            app.manager._CloseSettings()
            for id in SuiteSettings.ModuleOrder {
                app.ui.ShowHelp(id)
                key := "help:" id
                window := app.ui.windows[key]
                this.Assert(window.Title = SuiteSettings.ModuleNames[id] " - How to use", "module opens help first: " id)
                this.Assert(StrLen(window["helpText"].Value) > 100, "help content is populated: " id)
                window["helpText"].GetPos(, &textY, , &textHeight)
                buttons := 0
                for control in window {
                    if control.Type != "Button"
                        continue
                    buttons += 1
                    control.GetPos(&buttonX, &buttonY, &buttonWidth)
                    this.Assert(buttonY > textY + textHeight && buttonX >= 0 && buttonX + buttonWidth <= 800,
                        "help button stays on the lower-right footer: " id "/" control.Text)
                }
                this.Assert(buttons >= 2, "module help has useful navigation: " id)
                if SuiteIcons.handles.Length
                    this.Assert(SendMessage(0x007F, 0, 0, , window.Hwnd) = SuiteIcons.handles[1],
                        "module help uses the single application icon: " id)
                app.ui.CloseWindow(key)
                if id != "power-hotkey" {
                    app.ui.ShowModuleSettings(id)
                    this.Assert(app.ui.configurationWindows.Has("settings:" id), "module settings opens without a submenu: " id)
                    app.ui.CloseWindow("settings:" id)
                }
            }
            app.activeModules["scratchpad"] := false
            app.ui.ShowHelp("scratchpad")
            this.Assert(IsObject(app.ui.windows["help:scratchpad"]), "disabled modules still expose their How to use page")
            app.ui.CloseWindow("help:scratchpad")
            app.ui.OpenLog()
            this.Assert(app.ui.windows["log"]["verbose"].Value = 0, "one global logging checkbox is available")
            app.ui.CloseWindow("log")
            app.ui.ShowAppSettings()
            this.Assert(IsObject(app.ui.windows["application-settings"]), "startup and factory reset live in application settings")
            app.ui.CloseWindow("application-settings")
            app.ui.ShowModules()
            this.Assert(app.ui.moduleControls.Count = 5, "Modules presents all five renamed features")
            app.ui.CloseModules()
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
