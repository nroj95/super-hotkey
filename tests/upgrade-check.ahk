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
        this.DisabledModuleWarning()
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
            this.Assert(InStr(core.primary.Text, "⚠ Caps + K") = 1
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
            this.Assert(manager.actions["core.keybindings"].category = "Global"
                && manager.actions["window-cascade.copy-log"].category = "Global"
                && manager.actions["window-cascade.reset-log"].category = "Global",
                "core and debug actions share one Global display heading")
            this.Assert(manager.actions["core.keybindings"].id = "core.keybindings"
                && manager.actions["window-cascade.copy-log"].id = "window-cascade.copy-log",
                "Global rename leaves saved action IDs unchanged")
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
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
            this.Assert(saved["window-cascade.help"].bindings[1]
                = Keybindings.Parse("Caps + H").signature
                && saved["win-key-overhaul.help"].bindings[1]
                    = Keybindings.Parse("Win + Ctrl + H").signature
                && saved["power-hotkey.interface.open"].bindings[1]
                    = Keybindings.Parse("Pause + H").signature,
                "existing module Help shortcuts retain their original defaults")
            this.Assert(this.RouteExists(manager, "scratchpad.help"),
                "Paper Pad Help registers its default Pause + F12 shortcut")
            this.Assert(!this.RouteExists(manager, "keyboard-layers.help"),
                "unassigned Secret Keys Help installs no shortcut")
            this.Assert(InStr(ModuleHelp.Text("keyboard-layers", manager),
                "GETTING STARTED") > 0
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
            this.Assert(count = 12, "tray has exactly the agreed flat entries and separators")
            loop count
                this.Assert(!DllCall("GetSubMenu", "ptr", A_TrayMenu.Handle, "int", A_Index - 1, "ptr"),
                    "tray entry has no submenu: " A_Index)
            firstEditor := app.manager.settings.Hwnd
            app.ShowKeybindings()
            this.Assert(app.manager.settings.Hwnd = firstEditor, "every Keybindings entry reuses the global editor")
            editor := app.manager.settings
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
                app.manager.settingsSearch, app.manager.settingsRefresh,
                app.manager.settingsResetAll, app.manager.settingsDone]
            weights := []
            sizes := []
            for control in controls {
                fontHandle := SendMessage(0x0031, 0, 0, , control.Hwnd) ; WM_GETFONT
                fontData := Buffer(92, 0) ; LOGFONTW
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size,
                    "Keybindings control exposes its font")
                weights.Push(NumGet(fontData, 16, "int"))
                sizes.Push(NumGet(fontData, 0, "int"))
            }
            sameFont := true
            for index, weight in weights
                if weight != 600 || sizes[index] != sizes[1]
                    sameFont := false
            this.Assert(sameFont,
                "all Keybindings text uses the same stronger font weight and size")
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
                this.Assert(window.Title = SuiteSettings.ModuleNames[id] " - How to use",
                    "module opens its How to use guide: " id)
                guide := window["helpText"].Value
                this.Assert(StrLen(guide) > 300 && !InStr(guide, "CURRENT SAVED SHORTCUTS"),
                    "help explains usage without listing every keybinding: " id)
                this.Assert(InStr(guide, "GETTING STARTED") > 0,
                    "help starts with practical instructions: " id)
                window.GetClientPos(, , &helpWidth, &helpHeight)
                guideControl := window["helpText"]
                guideControl.GetPos(, &textY, , &textHeight)
                this.Assert(guideControl.Type = "Text"
                    && !app.ui.helpLayouts[id].footer.divider.Visible,
                    "help is one plain GUI surface with no inner box or footer separator: " id)
                fontHandle := SendMessage(0x0031, 0, 0, , guideControl.Hwnd)
                fontData := Buffer(92, 0)
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size
                    && NumGet(fontData, 16, "int") = 400,
                    "help uses the original regular-weight font: " id)
                fontFace := StrGet(fontData.Ptr + 28, 32, "UTF-16")
                this.Assert(fontFace = "Cascadia Mono" || fontFace = "Consolas",
                    "help font is the old Cascadia Mono or the Windows fallback: " id)
                lineCount := StrSplit(guide, "`n").Length
                this.Assert(helpWidth >= 720 && helpHeight >= 450
                    && textHeight > 350 && textY + textHeight < helpHeight - 60
                    && lineCount * 20 <= textHeight,
                    "initial help page fits its complete guide: " id)
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
                for control in window {
                    if control.Type != "Button"
                        continue
                    control.GetPos(&buttonX, &buttonY, &buttonWidth)
                    this.Assert(buttonY > textY + textHeight
                        && buttonX >= 0 && buttonX + buttonWidth <= helpWidth,
                        "help navigation stays in the footer: " id "/" control.Text)
                }
                if SuiteIcons.handles.Length
                    this.Assert(SendMessage(0x007F, 0, 0, , window.Hwnd)
                        = SuiteIcons.handles[1], "module help uses one application icon: " id)

                if id != "power-hotkey" {
                    app.ui.OpenSettingsFromHelp(id)
                    this.Assert(!app.ui.windows.Has(key)
                        && app.ui.configurationWindows.Has("settings:" id),
                        "Settings replaces Help rather than stacking over it: " id)
                    settings := app.ui.windows["settings:" id]
                    backFound := false
                    for control in settings
                        if control.Type = "Button" && control.Text = "Back"
                            backFound := true
                    this.Assert(backFound, "module settings provides Back navigation: " id)
                    app.ui.BackToHelp(id)
                    this.Assert(!app.ui.configurationWindows.Has("settings:" id)
                        && app.ui.windows.Has(key),
                        "Back closes Settings and restores Help: " id)
                }

                app.ui.OpenKeybindingsFromHelp(id)
                this.Assert(!app.ui.windows.Has(key)
                    && IsObject(app.manager.settings),
                    "Keybindings closes Help without a Back button: " id)
            }
            app.ui.ShowHelp("scratchpad")
            app.ui.CloseWindow("help:scratchpad")
            this.Assert(IniRead(app.ui.helpSizePath, "Window", "Width") > 900,
                "user-chosen Help window width is remembered")
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
