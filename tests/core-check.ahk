; Settings, the lifecycle, input gating, logging, notices, the working display and the focus border.
; Disposable preferences, dry-run inputs and test-owned windows only.
class CoreChecks {
    static Run() {
        this.CheckSettings()
        this.CheckCatalog()
        this.CheckNoLayers()
        this.CheckLogging()
        this.CheckRecovery()
        this.CheckExitVeto()
        this.CheckDryRunLifecycle()
        this.CheckModuleStartFailure()
        this.Preferences()
        this.ApplicationSuspension()
        this.DisabledModuleWarning()
        this.PowerCancellation()
        this.LogClearing()
        this.WorkingMonitor()
        this.PassingOverlay()
        this.CenteredNotices()
        this.FocusReturn()
        this.DeferredInputsAndSessions()
        this.InputQueueCancellation()
        this.FocusBorderLifecycle()
        this.CloseAndBorderRules()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static calls := 0

    static CheckSettings() {
        settings := SuiteSettings(SuiteChecks.directory "\preferences")
        enabled := 0
        for id, value in settings.modules
            enabled += value
        this.Assert(enabled = 5, "all five modules default to enabled")
        choices := settings.modules.Clone()
        choices["secret-layers"] := false
        settings.Save(choices)
        loaded := SuiteSettings(settings.directory)
        this.Assert(!loaded.modules["secret-layers"], "disabled module choice survives reload")
        document := KB_Manifest.Read(settings.path)
        document["modules"]["paper-pad"] := "invalid"
        KB_Manifest.WriteAtomic(settings.path, document)
        before := FileRead(settings.path, "UTF-8")
        recovered := SuiteSettings(settings.directory)
        this.Assert(recovered.loadWarning != "" && recovered.modules["paper-pad"]
            && recovered.modules["secret-layers"],
            "invalid module configuration falls back to defaults with a warning")
        this.Assert(before = FileRead(settings.path, "UTF-8"), "loading never rewrites an invalid configuration")
        damagedCopy := false
        loop files settings.path ".damaged-*"
            damagedCopy := FileRead(A_LoopFileFullPath, "UTF-8") = before
        this.Assert(damagedCopy, "an unreadable settings file is kept as a timestamped copy")
        settings.Save(choices)
        folder := settings.directory "\paper-pad"
        DirCreate folder
        path := folder "\settings.ini"
        IniWrite("sentinel-notes-folder", path, "Paths", "NotesDirectory")
        IniWrite("sentinel-editor.exe", path, "Paths", "Notepad3Executable")
        IniWrite("55", path, "Window", "WidthPercent")
        FileAppend("personal note", folder "\note.md", "UTF-8-RAW")
        FileAppend("editor preference", folder "\Notepad3.ini", "UTF-8-RAW")
        FileAppend("page state", folder "\state.ini", "UTF-8-RAW")
        backup := settings.Backup([path])
        settings.ResetModulePreferences(Map("paper-pad", ["Window"]))
        this.Assert(IniRead(path, "Window", "WidthPercent", "missing") = "missing", "factory reset removes only whitelisted preferences")
        this.Assert(IniRead(path, "Paths", "NotesDirectory") = "sentinel-notes-folder", "factory reset retains the notes folder")
        this.Assert(IniRead(path, "Paths", "Notepad3Executable") = "sentinel-editor.exe", "factory reset retains the editor path")
        this.Assert(FileRead(folder "\note.md") = "personal note", "factory reset preserves notes")
        this.Assert(FileRead(folder "\Notepad3.ini") = "editor preference" && FileRead(folder "\state.ini") = "page state", "factory reset preserves editor preferences and page state")
        this.Assert(FileExist(backup "\paper-pad-settings.ini"), "resettable settings have a backup")
    }

    static CheckCatalog() {
        app := SuiteApplication(true, SuiteChecks.directory "\catalog")
        app.InitializeCatalog()
        manager := app.manager
        power := app.modules["power-up-utilities"]
        try {
            manager.SetPaused(true)
            manager.Start()
            this.Assert(manager.actions.Count > 50 && manager.actions.Count < 128, "all modules share one action catalog")
            SuiteChecks.Rejects((*) => Keybindings("second", "Second", {directory: SuiteChecks.directory}), "a second manager is rejected")
            this.Assert(!manager.client.hooksInstalled, "paused startup does not capture native CapsLock or Pause")
            for route in manager.routes
                this.Assert(!InStr(route.state, "error:"), "registration: " route.action.id " / " route.slot)
            configuration := manager.GetConfiguration()
            this.Assert(configuration["core.keybindings"].bindings[1] = Keybindings.Parse("Caps + Alt + K").signature, "Caps + Alt + K opens the shared editor")
            this.Assert(configuration["power-up-utilities.terminal.copy"].bindings[1] = Keybindings.Parse("Caps + C").signature, "Terminal copy defaults to Caps + C")
            this.Assert(configuration["power-up-utilities.terminal.clear"].bindings[1] = Keybindings.Parse("Caps + K").signature, "Terminal clear defaults to Caps + K")
            this.Assert(configuration["core.restart"].bindings[1] = Keybindings.Parse("Pause + F3").signature
                && manager.actions["core.restart"].category = "Global",
                "a Global action restarts Super Hotkey with Pause + F3")
            this.Assert(configuration["power-up-utilities.system.wake-speakers"].bindings[1] = Keybindings.Parse("Pause + Pause").signature, "speaker wake defaults to Pause double-tap")
            this.Assert(configuration["wonder-windows.focus-up"].bindings[1] = Keybindings.Parse("Win + PgUp").signature
                && configuration["wonder-windows.focus-down"].bindings[1] = Keybindings.Parse("Win + PgDn").signature
                && !manager.actions.Has("wonder-windows.focus-left")
                && !manager.actions.Has("wonder-windows.focus-right"),
                "focus moves up and down with Win + PgUp/PgDn")
            this.Assert(configuration["paper-pad.previous"].bindings[2] = Keybindings.Parse("Win + PgUp").signature
                && configuration["paper-pad.next"].bindings[2] = Keybindings.Parse("Win + PgDn").signature,
                "Paper Pad pages follow the suite's PgUp = previous, PgDn = next")
            this.Assert(!manager.actions.Has("wonder-windows.isolate")
                && configuration["core.close-active"].bindings[1]
                    = Keybindings.Parse("Caps + Delete").signature
                && configuration["core.close-active"].bindings[2]
                    = Keybindings.Parse("Win + Delete").signature
                && !manager.actions.Has("cascade-kingdom.close-active")
                && !manager.actions.Has("wonder-windows.close-active")
                && manager.actions["core.close-active"].category = "Global",
                "Win + Home is left to Windows; a Global action closes with Caps + Delete or Win + Delete")
            this.Assert(configuration["wonder-windows.help"].bindings[1] = Keybindings.Parse("Ctrl + Alt + H").signature
                && configuration["wonder-windows.help"].bindings[2] = Keybindings.Parse("Caps + Win + H").signature,
                "Wonder Windows help opens with Ctrl + Alt + H, or Caps + Win + H")
            for name in ["layout-left", "layout-right", "tile-top-left", "tile-top", "tile-top-right",
                "tile-bottom-left", "tile-bottom", "tile-bottom-right"]
                this.Assert(!manager.actions.Has("wonder-windows." name),
                    "zone cycling replaces " name)
            for direction in ["left", "right", "up", "down"] {
                this.Assert(configuration["wonder-windows.move-onto-" direction].bindings[1]
                    = Keybindings.Parse("Win + Alt + " direction).signature
                    && configuration["wonder-windows.move-onto-" direction].bindings[2]
                    = Keybindings.Parse("Caps + Win + " direction).signature,
                    "moving onto a window defaults to Win + Alt + " direction " and Caps + Win + " direction)
                this.Assert(!manager.actions.Has("wonder-windows.swap-" direction),
                    "stacking on the nearest window replaces swapping: " direction)
            }
            this.Assert(configuration["wonder-windows.stretch"].bindings[1]
                = Keybindings.Parse("Win + Shift + Enter").signature
                && !manager.actions.Has("wonder-windows.stretch-left")
                && !manager.actions.Has("wonder-windows.reset-stretch"),
                "one Win + Shift + Enter cycle replaces the stretch actions")
            this.Assert(configuration["wonder-windows.cycle-stacked"].bindings[1]
                    = Keybindings.Parse("Win + Enter").signature
                && configuration["wonder-windows.cycle-expanded-next"].bindings[1]
                    = Keybindings.Parse("Win + Alt + Enter").signature
                && configuration["wonder-windows.cycle-expanded-next"].bindings[2]
                    = Keybindings.Parse("Caps + Win + Enter").signature
                && configuration["wonder-windows.cycle-expanded-previous"].bindings[1]
                    = Keybindings.Parse("Win + Alt + Shift + Enter").signature
                && configuration["wonder-windows.cycle-expanded-previous"].bindings[2]
                    = Keybindings.Parse("Caps + Win + Shift + Enter").signature,
                "Win + Enter cycles the stack; Win + Alt + Enter and its Shift twin cycle big windows")
            this.Assert(!manager.actions.Has("wonder-windows.swap-next")
                && !manager.actions.Has("wonder-windows.swap-previous"),
                "old clockwise swap actions are removed")
            this.Assert(configuration["wonder-windows.zones-from-left"].bindings[1]
                    = Keybindings.Parse("Win + WheelDown").signature
                && configuration["wonder-windows.zones-from-left"].bindings[2]
                    = Keybindings.Parse("Win + Left").signature
                && configuration["wonder-windows.zones-from-right"].bindings[1]
                    = Keybindings.Parse("Win + WheelUp").signature
                && configuration["wonder-windows.zones-from-right"].bindings[2]
                    = Keybindings.Parse("Win + Right").signature,
                "zone cycling defaults to Win + wheel and Win + Left/Right")
            for direction in ["up", "down", "left", "right"]
                this.Assert(!manager.actions.Has("wonder-windows.zone-" direction),
                    "FancyZones forwarding is removed: " direction)
            this.Assert(!manager.actions.Has("wonder-windows.move-monitor-left"),
                "moving between displays is left to Windows' own Win + Shift + Left/Right")
            ; Wonder Windows works without the Caps layer: Caps only appears in second slots.
            capsPrimaries := ""
            for actionId, action in manager.actions
                if InStr(actionId, "wonder-windows.") = 1 && action.defaults[1] != ""
                    && StrSplit(action.defaults[1], "|")[1] != "normal"
                    capsPrimaries .= actionId " "
            this.Assert(capsPrimaries = "", "no Wonder Windows primary default needs a layer: " capsPrimaries)
            this.Assert(!manager.actions.Has("cascade-kingdom.auto-placement"),
                "old pause-cascading keybinding is removed")
            this.Assert(!manager.actions.Has("cascade-kingdom.rotate-previous")
                    && !manager.actions.Has("cascade-kingdom.move-left")
                    && !manager.actions.Has("cascade-kingdom.move-right"),
                "backward all-slot rotation and old Cascade monitor hotkeys are removed")
            this.Assert(!manager.actions.Has("paper-pad.new") && !manager.actions.Has("paper-pad.save"),
                "native New and Save are not duplicated in Keybindings")
            this.Assert(HasMethod(manager.actions["paper-pad.delete"].context, "Call"),
                "Paper Pad delete has an explicit editor context")
            this.Assert(!manager.ContextActive(manager.actions["paper-pad.delete"]),
                "Paper Pad commands are inactive outside its editor")
            manager.ShowSettings()
            this.Assert(IsObject(manager.editor.window) && manager.editor.rows.Length > 50, "shared editor renders the complete catalog")
            manager.editor.Close()

            app.activeModules["power-up-utilities"] := false
            manager.Apply(configuration)
            this.Assert(!SuiteChecks.HasRoute(manager, "power-up-utilities.keyboard.f13"), "disabled module releases its routes")
            capsConfiguration := manager.GetConfiguration()
            capsConfiguration["secret-layers.toggle-caps"].bindings[1] := "Ctrl + Alt + F10"
            manager.Apply(capsConfiguration)
            this.Assert(SuiteChecks.HasRoute(manager, "secret-layers.toggle-caps"),
                "Caps Lock shortcut works with Power-Up Utilities disabled")
            manager.Apply(configuration)
            rows := Keybindings.DisplayRows(manager.Catalog())
            found := false
            for row in rows
                if row.id = "power-up-utilities.keyboard.f13"
                    found := true
            this.Assert(!found, "disabled modules are hidden from the active Keybindings view")
            this.Assert(manager.GetConfiguration()["power-up-utilities.keyboard.f13"].bindings[1] = configuration["power-up-utilities.keyboard.f13"].bindings[1], "disabling a module preserves its assignments")
            changed := manager.GetConfiguration()
            changed["paper-pad.toggle"].bindings[1] := "Caps + Q"
            manager.Apply(changed)
            this.Assert(manager.GetConfiguration()["paper-pad.toggle"].bindings[1] = Keybindings.Parse("Caps + Q").signature, "a disabled module's key can be reused")
            before := FileRead(manager.path, "UTF-8")
            app.activeModules["power-up-utilities"] := true
            SuiteChecks.Rejects((*) => manager.Apply(manager.GetConfiguration()), "re-enabling a conflicting module is rejected")
            this.Assert(FileRead(manager.path, "UTF-8") = before, "conflict rejection preserves the saved configuration")
            this.Assert(!SuiteChecks.HasRoute(manager, "power-up-utilities.keyboard.f13"), "conflict rejection retains the prior runtime")
            manager.Apply(configuration)
            this.Assert(SuiteChecks.HasRoute(manager, "power-up-utilities.keyboard.f13"), "restoring a valid configuration restores the module routes")
            manager.actions["paper-pad.toggle"].available := false
            defaults := manager._DefaultConfiguration()
            this.Assert(defaults["paper-pad.toggle"].bindings[1] = Keybindings.Parse("Win + F12").signature, "shortcut defaults include disabled actions")
            manager.actions["paper-pad.toggle"].available := true

            ; Direct callbacks exercise dry-run guards without emitting any input.
            event := {phase: "down", actionId: "cascade-kingdom.minimize", slot: 1,
                key: "sc032", modifiers: 0, layer: "caps", foregroundHwnd: 0, oneShot: false}
            manager.actions[event.actionId].callback.Call(event)
            event.actionId := "paper-pad.toggle"
            manager.actions[event.actionId].callback.Call(event)
            power.keyboard.SendOutput("F13", " down")
            power.keyboard.SendOutput("F13", " up")
            diagnosticLog := FileRead(SuiteState.Log.path, "UTF-8")
            this.Assert(InStr(diagnosticLog, "dry run: cascade-kingdom.minimize") && InStr(diagnosticLog, "dry run: toggle") && InStr(diagnosticLog, "dry run: send F13"), "feature callbacks use dry-run guards")

            layers := manager.client
            layers.showIndicator := false
            layers.armed := "caps"
            layers.armedUntil := KeyboardLayers.Now() + 1000
            layers.running := true
            this.Assert(layers.Busy() && layers.Active("caps") && !layers.Active("pause"),
                "an armed one-shot layer excludes ordinary bindings")
            layers.armedUntil := KeyboardLayers.Now() - 1
            this.Assert(!layers.Busy(), "an expired one-shot arm releases ordinary bindings")
            layers.armed := ""
            layers.running := false
            manager.Observe("~*F24", (*) => false, (*) => 0)
            this.Assert(manager.observers.Length = 1, "native observers are owned by the shared manager")
        }
        finally {
            manager.Stop()
            power.Stop()
        }
        this.Assert(!IsObject(Keybindings.Current) && !manager.running, "manager shutdown releases singleton ownership")
    }

    static CheckNoLayers() {
        app := SuiteApplication(true, SuiteChecks.directory "\without-layers")
        app.activeModules["secret-layers"] := false
        app.InitializeCatalog()
        manager := app.manager
        flag := {active: false}
        manager.AddAction("test.context", "context check", (*) => 0, ["F24"], {context: (*) => flag.active})
        try {
            manager.SetPaused(true)
            manager.Start()
            this.Assert(!IsObject(manager.client), "disabled keyboard layers create no layer client or prefix hooks")
            configuration := manager.GetConfiguration()
            this.Assert(configuration["core.keybindings"].bindings[1] != "", "inactive layer assignments remain saved")
            unavailable := 0
            for route in manager.routes
                if InStr(route.state, "unavailable:")
                    unavailable += 1
            this.Assert(unavailable > 20, "layer bindings are explicitly unavailable without the module")
            configuration["paper-pad.toggle"].bindings[1] := "CapsLock"
            manager.Apply(configuration)
            this.Assert(SuiteChecks.HasRoute(manager, "paper-pad.toggle"), "CapsLock can be explicitly rebound without layers")
            configuration["paper-pad.toggle"].bindings[1] := "Pause"
            manager.Apply(configuration)
            this.Assert(manager.GetConfiguration()["paper-pad.toggle"].bindings[1] = Keybindings.Parse("Pause").signature, "Pause can be explicitly rebound without layers")
            configuration["paper-pad.toggle"].bindings[1] := "Ctrl + Alt + J"
            manager.Apply(configuration)
            this.Assert(manager.GetConfiguration()["paper-pad.toggle"].bindings[1] = Keybindings.Parse("Ctrl + Alt + J").signature, "ordinary replacements work without layers")
            this.Assert(!manager.ContextActive(manager.actions["test.context"]), "false context disables the action")
            flag.active := true
            this.Assert(manager.ContextActive(manager.actions["test.context"]), "true context enables the action")
            for invalid in ["LButton", "Ctrl + RButton", "Ctrl + Alt + Delete", "Win + L", "Ctrl", "Caps + Pause"]
                SuiteChecks.Rejects((*) => Keybindings.Parse(invalid), "unsafe or reserved binding rejected: " invalid)
            this.Assert(Keybindings.Parse("Escape").signature = Keybindings.Parse("Esc").signature, "key aliases normalize consistently")
            this.Assert(Keybindings.Parse("Pause + Escape").layer = "pause", "layer Escape remains a valid assignment")
        }
        finally manager.Stop()
    }

    static CheckLogging() {
        diagnosticLog := SuiteLog(SuiteChecks.directory "\logging", 100)
        diagnosticLog.Write("Core", "first " StrReplace(Format("{:120}", "x"), " ", "x"))
        diagnosticLog.Write("Paper Pad", "second")
        this.Assert(FileExist(diagnosticLog.path ".old"), "central log rotates at the size limit")
        diagnosticLog.Error("Power-Up Utilities", Error("diagnostic marker", "native checks"))
        this.Assert(InStr(FileRead(diagnosticLog.path, "UTF-8"), "diagnostic marker"), "errors retain their details and module attribution")
        viewer := FileOpen(diagnosticLog.path, "r -d") ; viewers usually share read and write, not delete
        diagnosticLog.Write("Core", "written while viewed")
        viewer.Close()
        this.Assert(InStr(FileRead(diagnosticLog.path, "UTF-8"), "written while viewed"), "an open log viewer cannot block log writes")
        diagnosticLog.Clear()
        this.Assert(InStr(FileRead(diagnosticLog.path, "UTF-8"), "previous log retained"), "clearing the log retains one previous segment")
    }

    ; Damaged files fall back to defaults with a kept copy; unchanged
    ; configurations are never rewritten; backups are bounded.
    static CheckRecovery() {
        directory := SuiteChecks.directory "\recovery"
        DirCreate directory
        loop 3 {
            stage := A_Index
            manager := Keybindings("recovery", "Recovery", {directory: directory})
            try {
                manager.AddAction("fixture.one", "first", (*) => 0, ["Ctrl + Alt + F21"])
                manager.AddAction("fixture.two", "second", (*) => 0, ["Ctrl + Alt + F22"])
                manager.SetPaused(true)
                if stage = 1 {
                    FileAppend("not a manifest", manager.path, "UTF-8-RAW")
                    manager.Start()
                    this.Assert(manager.loadWarnings.Length = 1
                        && manager.GetConfiguration()["fixture.one"].bindings[1]
                            = Keybindings.Parse("Ctrl + Alt + F21").signature,
                        "an unreadable keybindings file starts with defaults and a warning")
                    copies := 0
                    loop files manager.path ".damaged-*"
                        copies += FileRead(A_LoopFileFullPath) = "not a manifest"
                    this.Assert(copies = 1, "the unreadable keybindings file is kept as a timestamped copy")
                    configuration := manager.GetConfiguration()
                    configuration["fixture.two"].bindings[1] := Keybindings.Parse("Ctrl + Alt + F23").signature
                    manager.Apply(configuration)
                } else if stage = 2 {
                    document := KB_Manifest.Read(manager.path)
                    document["bindings"]["fixture.one"] := "1`tnot|a|binding`t"
                    KB_Manifest.WriteAtomic(manager.path, document)
                    manager.Start()
                    this.Assert(manager.loadWarnings.Length = 1
                        && InStr(manager.loadWarnings[1], "first")
                        && manager.GetConfiguration()["fixture.two"].bindings[1]
                            = Keybindings.Parse("Ctrl + Alt + F23").signature,
                        "one unreadable assignment falls back alone; the others survive")
                } else {
                    FileAppend("; marker`n", manager.path, "UTF-8-RAW")
                    manager.Start()
                    manager.Apply(manager.GetConfiguration())
                    this.Assert(!manager.loadWarnings.Length && InStr(FileRead(manager.path, "UTF-8"), "; marker"),
                        "applying an unchanged configuration does not rewrite the file")
                }
            }
            finally manager.Stop()
        }

        ; An exclusive handle prevents copying: recovery must fail without
        ; changing the source. Both settings loaders must enforce this boundary.
        lockedDirectory := directory "\locked"
        DirCreate lockedDirectory
        lockedSettings := lockedDirectory "\settings.ini"
        FileAppend("damaged preferences", lockedSettings, "UTF-8-RAW")
        lockedManager := Keybindings("locked", "Locked", {directory: lockedDirectory})
        FileAppend("damaged hotkeys", lockedManager.path, "UTF-8-RAW")
        for path in [lockedSettings, lockedManager.path] {
            handle := DllCall("CreateFileW", "str", path, "uint", 0x80000000,
                "uint", 0, "ptr", 0, "uint", 3, "uint", 0, "ptr", 0, "ptr")
            this.Assert(handle != -1, "fixture exclusively locks the damaged file")
            try {
                if path = lockedSettings
                    SuiteChecks.Rejects(() => SuiteSettings(lockedDirectory),
                        "suite settings cannot recover when preservation fails")
                else
                    SuiteChecks.Rejects(() => lockedManager.Start(),
                        "keybindings cannot recover when preservation fails")
            }
            finally DllCall("CloseHandle", "ptr", handle)
        }
        lockedManager.Stop()
        this.Assert(FileRead(lockedSettings) = "damaged preferences"
            && FileRead(lockedManager.path) = "damaged hotkeys",
            "failed recovery retains both original files")
        firstCopy := KB_Manifest.KeepDamagedFile(lockedSettings)
        secondCopy := KB_Manifest.KeepDamagedFile(lockedSettings)
        this.Assert(firstCopy != secondCopy && FileRead(firstCopy) = "damaged preferences"
            && FileRead(secondCopy) = "damaged preferences",
            "repeated recovery preserves separate copies without overwriting")

        settings := SuiteSettings(SuiteChecks.directory "\backups")
        DirCreate settings.directory "\backups\keep-me"
        loop SuiteSettings.BackupsKept + 5 {
            FileAppend("x", settings.directory "\backup-source-" A_Index ".ini")
            settings.Backup([settings.directory "\backup-source-" A_Index ".ini"])
        }
        folders := 0
        loop files settings.directory "\backups\*", "D"
            folders += 1
        this.Assert(folders = SuiteSettings.BackupsKept + 1 && DirExist(settings.directory "\backups\keep-me"),
            "backups keep only the newest folders and never touch other folders")
        this.Assert(settings.Backup([settings.directory "\missing.ini"]) = "",
            "a backup of missing files creates no empty folder")
    }

    static CheckExitVeto() {
        busyController := {busy: true, command_queue: []}
        SuiteChecks.Rejects((*) => PaperPadController.Prototype.PrepareSuiteExit.Call(busyController, "Reload"),
            "Paper Pad can refuse a restart while a command is active")
    }

    static CheckDryRunLifecycle() {
        app := SuiteApplication(true, SuiteChecks.directory "\startup")
        try {
            app.Start()
            this.Assert(app.manager.running && app.manager.paused, "dry-run startup keeps every shortcut inactive")
            this.Assert(!app.modules["cascade-kingdom"].started && !app.modules["paper-pad"].started,
                "dry-run startup does not start native feature modules")
            this.Assert(IsObject(app.ui) && IsObject(app.manager.editor.window), "dry-run startup creates the shared tray and editor")
            app.ui.ShowModules()
            this.Assert(app.ui.windows.Has("modules"), "module settings window opens")
            app.ui.CloseModules()
            this.Assert(app.manager.paused, "closing module settings keeps dry-run inputs inactive")
        }
        finally {
            app.Stop()
            OnExit(app.exitCallback, 0)
            OnError(app.errorCallback, 0)
        }
        this.Assert(!app.manager.running && !app.mutex, "suite shutdown releases manager and process ownership")
        this.Assert(!InStr(FileRead(SuiteState.Log.path, "UTF-8"), "ERROR:"), "dry-run startup and shutdown emit no errors")
    }

    static CheckModuleStartFailure() {
        app := SuiteApplication(true, SuiteChecks.directory "\module-failure")
        module := SuiteFailingModule(app, "paper-pad")
        manager := Keybindings("failure", "Failure", {directory: app.Settings.directory})
        try {
            manager.AddAction("fixture.action", "fixture", (*) => 0, ["Ctrl + Alt + F24"],
                {available: (*) => app.ModuleActive("paper-pad")})
            manager.SetPaused(true)
            manager.Start()
            signature := Keybindings.Parse("Ctrl + Alt + F24").signature
            this.Assert(IsObject(manager._SelectedRoute(signature)),
                "fixture action is routed before its module fails")
            app.StartModule(module)
            this.Assert(!module.started && module.cleaned && !app.ModuleActive("paper-pad")
                && !IsObject(manager._SelectedRoute(signature)),
                "failed module startup releases resources and stops claiming its hotkeys")
            this.Assert(app.Settings.modules["paper-pad"] && app.ModuleActive("cascade-kingdom")
                && app.startupWarnings.Length = 1,
                "startup failure keeps saved choices and other modules enabled with a warning")
        }
        finally manager.Stop()
    }

    static Preferences() {
        settings := SuiteSettings(SuiteChecks.directory "\upgrade-preferences")
        this.Assert(settings.layers["caps"] && settings.layers["pause"] && !settings.verbose,
            "both keyboard layers default on; verbose debugging defaults off")
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
        recovered := SuiteSettings(settings.directory)
        this.Assert(recovered.loadWarning != "" && recovered.layers["caps"] && recovered.layers["pause"],
            "an invalid layer preference falls back to defaults with a warning")
        this.Assert(FileRead(settings.path) = before, "bad layer preferences are not silently rewritten")
        settings.Save(settings.modules)
        settings.WritePreferences("paper-pad", Map("Paths", Map("NotesDirectory", "sentinel-folder"),
            "Window", Map("WidthPercent", 45)))
        settings.WritePreferences("paper-pad", Map("Window", Map("WidthPercent", 55)))
        path := settings.directory "\paper-pad\settings.ini"
        this.Assert(IniRead(path, "Window", "WidthPercent") = "55", "module preferences save through an atomic replacement")
        this.Assert(IniRead(path, "Paths", "NotesDirectory") = "sentinel-folder", "preference edits preserve unrelated note paths")
        logger := SuiteLog(settings.directory "\log")
        logger.Debug("Paper Pad", "hidden diagnostic")
        logger.Error("Paper Pad", Error("always recorded"))
        this.Assert(!InStr(logger.Read(), "hidden diagnostic") && InStr(logger.Read(), "always recorded"),
            "errors remain automatic when global verbose debugging is off")
        logger.verbose := true
        logger.Debug("Wonder Windows", "visible diagnostic")
        this.Assert(InStr(logger.Read(), "visible diagnostic"), "global verbose mode enables module diagnostics")
    }

    static ApplicationSuspension() {
        global cascade_compaction_pending
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
            cascade_compaction_pending[1] := 0
            app.modules["cascade-kingdom"].Suspend()
            this.Assert(!cascade_compaction_pending.Count,
                "suspension clears queued compactions")
            QueueCascadeCompaction(1)
            this.Assert(!cascade_compaction_pending.Count,
                "suspended Cascade Kingdom discards new compaction requests")
            if IsObject(manager.client)
                this.Assert(manager.client.running = manager.client.LayerEnabled("pause"),
                    "suspension keeps only the Pause layer the suspend toggle needs")
            this.Assert(!manager._Eligible(Keybindings.Parse("Ctrl + Alt + K").signature),
                "ordinary configured hotkeys are unavailable while suspended")
            this.Assert(manager._Passes(KeybindingsChecks.Route(manager, "core.suspend"))
                && !manager._Passes(KeybindingsChecks.Route(manager, "core.keybindings")),
                "only the suspend toggle passes the gate while suspended")

            app.systemSuspended := true
            app.RefreshInputGate()
            this.Assert(!manager._Passes(KeybindingsChecks.Route(manager, "core.suspend"))
                && (!IsObject(manager.client) || !manager.client.running),
                "a Windows suspend silences the suspend toggle and every layer")
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
                this.Assert(manager.client.running,
                    "CapsLock and Pause layer hooks return when hotkeys resume")

            app.ui.ShowModules()
            this.Assert(!manager.gated && !manager.paused,
                "module settings keep configured hotkeys active")
            app.ui.CloseModules()
            manager.ShowSettings()
            this.Assert(!manager.gated && !manager.paused,
                "Keybindings keeps normal hotkeys active when not recording")
            if IsObject(manager.client)
                this.Assert(manager.client.running,
                    "Keybindings does not reset the running Caps/Pause layer session")
            app.ToggleKeybindings()
            this.Assert(!IsObject(manager.editor.window) && !manager.gated,
                "opening shortcut closes the focused Keybindings window")
            app.ToggleKeybindings()
            this.Assert(IsObject(manager.editor.window) && !manager.gated,
                "the same shortcut reopens Keybindings without gating input")
            recordIndex := 0
            for index, row in manager.editor.visibleRows {
                if row.actionId != "" {
                    recordIndex := index
                    break
                }
            }
            this.Assert(recordIndex > 0, "Keybindings has a recordable assignment")
            manager.editor.BeginRecording(recordIndex, 1)
            this.Assert(IsObject(manager.editor.recording) && manager.gated,
                "recording alone temporarily gates normal hotkeys")
            manager.editor.EndRecording()
            this.Assert(!manager.gated, "ending recording restores normal hotkeys")
            app.ui.ToggleSuspension()
            this.Assert(manager.gated && app.suspended,
                "suspending while Keybindings is open keeps inputs gated")
            manager.editor.Close()
            this.Assert(!IsObject(manager.editor.window),
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
        app := SuiteApplication(true, SuiteChecks.directory "\disabled-secret-layers")
        app.activeModules["secret-layers"] := false
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            manager.ShowSettings()
            this.Assert(manager.editor.window.Title = "Keybindings — Secret Layers disabled",
                "module-disabled Keybindings title describes the unavailable layers")
            manager.editor.window["search"].Value := "open Keybindings"
            manager.editor.Render()
            core := manager.editor.visibleRows[2]
            this.Assert(InStr(core.primary.Text, "⚠ Caps + Alt + K") = 1
                && core.secondary.Text = "Ctrl + Alt + K"
                && core.primary.Enabled,
                "disabled Secret Layers marks only the Caps binding and leaves it editable")
            manager.editor.window["search"].Value := "show Paper Pad help"
            manager.editor.Render()
            paper := manager.editor.visibleRows[2].primary
            this.Assert(InStr(paper.Text, "⚠ Pause + F12") = 1 && paper.Enabled,
                "disabled Secret Layers marks the saved Pause Help binding as reassignable")
            before := manager.GetConfiguration()["paper-pad.help"].bindings[1]
            this.Assert(before = Keybindings.Parse("Pause + F12").signature,
                "warning presentation never modifies the saved shortcut")
            manager.editor.Close()
        }
        finally manager.Stop()
    }

    static PowerCancellation() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-power")
        app.InitializeCatalog()
        manager := app.manager
        previousCritical := Critical("On")
        try {
            manager.SetPaused(true)
            manager.Start()
            power := app.modules["power-up-utilities"]
            ; Exercise dispatch without registering active input or emitting effects.
            power.DefineProp("CanDispatch", {Call: (self, actionId) => !self.stopping})
            power.DefineProp("InputsReleased", {Call: (self, event) => true})
            event := {actionId: "power-up-utilities.system.sleep", slot: 1,
                phase: "down", foregroundHwnd: 0, layer: "normal",
                key: "F24", binding: "F24", modifiers: 0, oneShot: false}
            token := event.actionId "|1"
            power.Dispatch(event)
            this.Assert(power.pending.Count = 1, "Power-Up Utilities queues a test press")
            event.phase := "cancel"
            power.Dispatch(event)
            power.CheckPending()
            this.Assert(!power.pending.Count && !IsObject(power.activeJob),
                "cancelling a power command discards it rather than completing it")

            event.phase := "down"
            power.Dispatch(event)
            event.phase := "up"
            power.Dispatch(event)
            job := power.pending[token]
            this.Assert(job.completed, "a genuine release still completes a utility press")
            generation := app.inputGeneration
            manager.Apply(manager.GetConfiguration())
            this.Assert(!power.pending.Count && app.inputGeneration > generation
                && !power.JobValid(job), "reconfiguration invalidates released but unexecuted utilities")

            event.phase := "down"
            power.Dispatch(event)
            event.phase := "up"
            power.Dispatch(event)
            job := power.pending[token]
            power.CheckPending()
            this.Assert(power.activeJob = job, "an eligible test utility can reach its deferred worker")
            power.CancelWork()
            power.RunJob(job)
            SetTimer(job.worker, 0)
            this.Assert(!IsObject(power.activeJob)
                && !InStr(SuiteState.Log.Read(), "dry run: " event.actionId),
                "cancellation also expires a worker already scheduled for execution")

            manager.gated := false
            event.phase := "down"
            power.Dispatch(event)
            manager.SetPaused(true)
            this.Assert(!power.pending.Count, "closing the input gate cancels module-owned work")
        }
        finally {
            app.Stop("test")
            Critical(previousCritical)
        }
    }

    static LogClearing() {
        app := SuiteApplication(true, SuiteChecks.directory "\log-clearing")
        app.ui := SuiteInterface(app)
        try {
            SuiteState.Log.Write("Core", "before-clear-marker")
            this.Assert(app.ui.ClearLog() && InStr(FileRead(SuiteState.Log.path ".old"), "before-clear-marker")
                && InStr(SuiteState.Log.Read(), "log cleared; previous log retained"),
                "clearing the log keeps the previous log as debug.log.old without asking")
        }
        finally app.ui.CloseAll()
    }

    ; Keyboard-only users never see a parked pointer choose a display.
    static WorkingMonitor() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-working-monitor")
        work := SuiteGui(, "Working monitor app")
        older := SuiteGui(, "Working monitor older app")
        passage := SuiteGui("+ToolWindow", "Working monitor shell surface")
        try {
            SuiteShowCentered(older, 320, 240)
            SuiteShowCentered(work, 320, 240)
            passage.Show("NoActivate w200 h100")
            workMonitor := WindowMonitorIndex(work.Hwnd)
            olderMonitor := WindowMonitorIndex(older.Hwnd)
            last := MonitorGetCount()
            MonitorGetPixels(last, &left, &top, &right, &bottom)
            press := {tick: A_TickCount, x: left + (right - left) // 2, y: top + (bottom - top) // 2}
            this.Assert(SuiteWorkingMonitor.IsWorkWindow(work.Hwnd)
                && !SuiteWorkingMonitor.IsWorkWindow(passage.Hwnd),
                "app windows are work windows; tool surfaces are passed through")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: work.Hwnd, click: 0}]) = workMonitor,
                "the active app window chooses its display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: passage.Hwnd, click: 0},
                {hwnd: older.Hwnd, click: 0}]) = olderMonitor,
                "a surface opened from the keyboard defers to the previous app window")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: passage.Hwnd, click: press},
                {hwnd: older.Hwnd, click: 0}]) = last,
                "a surface opened by a click chooses the clicked display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: work.Hwnd, click: 0},
                {hwnd: older.Hwnd, click: 0}], work.Hwnd) = olderMonitor,
                "a window being placed never chooses its own display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: 987654321, click: press}]) = MonitorGetPrimary()
                && SuiteWorkingMonitor.Choose([]) = MonitorGetPrimary(),
                "closed windows are skipped and the primary display is the last resort")
            ; The desktop spans every display: clicking it elsewhere keeps it in
            ; front, so the newer click must replace the one that opened it.
            savedRecent := SuiteWorkingMonitor.recent, savedClick := SuiteWorkingMonitor.click
            MonitorGetPixels(1, &firstLeft, &firstTop, &firstRight, &firstBottom)
            SuiteWorkingMonitor.recent := [{hwnd: passage.Hwnd,
                click: {tick: A_TickCount, x: firstLeft + 10, y: firstTop + 10}}]
            SuiteWorkingMonitor.NoteClick(press, passage.Hwnd)
            refreshed := SuiteWorkingMonitor.Choose(SuiteWorkingMonitor.recent)
            SuiteWorkingMonitor.NoteClick({tick: A_TickCount, x: firstLeft + 10, y: firstTop + 10}, work.Hwnd)
            this.Assert(refreshed = last && SuiteWorkingMonitor.Choose(SuiteWorkingMonitor.recent) = last,
                "a click that keeps the same window in front updates where it was clicked")
            ; Closing a suite page hands focus back to the clicked desktop; the
            ; later foreground event must not erase where it was clicked.
            SuiteWorkingMonitor.recent := [{hwnd: work.Hwnd, click: 0}, {hwnd: passage.Hwnd, click: press}]
            SuiteWorkingMonitor.Return(passage.Hwnd)
            SuiteWorkingMonitor._RecordForeground(0, 3, passage.Hwnd)
            this.Assert(SuiteWorkingMonitor.recent[1].hwnd = passage.Hwnd
                && SuiteWorkingMonitor.recent[1].click = press
                && SuiteWorkingMonitor.Choose(SuiteWorkingMonitor.recent, work.Hwnd) = last,
                "focus handed back by the suite keeps the click that chose the display")
            SuiteWorkingMonitor.recent := savedRecent, SuiteWorkingMonitor.click := savedClick
        }
        finally {
            for window in [work, older, passage]
                window.Destroy()
        }
    }

    ; A shortcut guide that pops up while Win is held must not redirect a hotkey.
    static PassingOverlay() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-passing-overlay")
        manager := Keybindings("passing-overlay", "Passing overlay",
            {directory: app.Settings.directory "\keybindings"})
        app.manager := manager
        work := SuiteGui(, "Passing overlay app")
        overlay := SuiteGui("+AlwaysOnTop +ToolWindow", "Passing overlay guide")
        savedRecent := SuiteWorkingMonitor.recent
        presses := []
        try {
            SuiteShowCentered(work, 320, 240)
            overlay.Show("w200 h100")
            WinWaitActive("ahk_id " overlay.Hwnd, , 1)
            SuiteWorkingMonitor.recent := [{hwnd: overlay.Hwnd, click: 0}, {hwnd: work.Hwnd, click: 0}]
            this.Assert(IsPassingOverlay(overlay.Hwnd) && !IsPassingOverlay(work.Hwnd),
                "a topmost tool window is a passing overlay; an app window is not")
            this.Assert(SuiteWorkingMonitor.UserWindow() = work.Hwnd,
                "the user is still in the window a passing overlay covers")

            ; The action exists only in the covered window, like Paper Pad's pages.
            manager.AddAction("fixture.covered", "covered window input",
                (event) => event.phase = "down" && presses.Push({target: event.foregroundHwnd,
                    active: DllCall("GetForegroundWindow", "ptr")}),
                ["F24"], {context: (*) => SuiteWorkingMonitor.UserWindow() = work.Hwnd})
            candidate := manager._CandidateRoutes(manager._DefaultConfiguration())
            manager.configuration := candidate.configuration
            manager.routes := candidate.routes
            route := manager.routes[1]
            route.enabled := true
            manager.routeMap := Map(route.binding.signature, [route])
            manager.running := true
            manager._KeyDown(route.binding.signature)
            manager._KeyUp(route.binding.key)
            manager._Drain()
            this.Assert(presses.Length = 1 && presses[1].target = work.Hwnd
                && presses[1].active = work.Hwnd,
                "a hotkey pressed through an overlay runs in the covered window, brought back to front")
        }
        finally {
            SuiteWorkingMonitor.recent := savedRecent
            for window in [overlay, work]
                window.Destroy()
            app.Stop("test")
        }
    }

    ; Keyboard users read notices in the middle of the working display.
    static CenteredNotices() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-notices")
        try {
            SuiteNotice.Show("layer", "Caps held")
            SuiteNotice.Show("status", "Debug log copied", 150)
            layer := SuiteNotice.notices["layer"].window
            status := SuiteNotice.notices["status"].window
            layer.GetPos(&x, &y, &width, &height)
            status.GetPos(, &statusY)
            MonitorGetWorkArea(SuiteWorkingMonitor.Get(), &left, &top, &right, &bottom)
            this.Assert(Abs(x + width // 2 - (left + right) // 2) <= 2
                && Abs(y + height // 2 - (top + bottom) // 2) <= 2,
                "a notice is centered on the working display")
            this.Assert(statusY >= y + height,
                "a status notice stacks below the layer indicator")
            exStyle := WinGetExStyle(layer.Hwnd)
            this.Assert(DllCall("IsWindowVisible", "ptr", layer.Hwnd, "int")
                && (exStyle & 0x08080028) = 0x08080028 && !WinActive(layer.Hwnd),
                "notices are topmost, click-through and never take focus")
            SuiteNotice.Show("layer", "Pause - next key")
            this.Assert(SuiteNotice.notices["layer"].window != layer,
                "new notice text rebuilds the notice at its own size")
            ; Timers cannot interrupt a critical thread; let the expiry run.
            previousCritical := Critical("Off")
            Sleep 300
            Critical(previousCritical)
            this.Assert(!DllCall("IsWindowVisible", "ptr", status.Hwnd, "int"),
                "a timed notice hides itself")
            SuiteNotice.Hide("layer")
            this.Assert(!DllCall("IsWindowVisible", "ptr", SuiteNotice.notices["layer"].window.Hwnd, "int"),
                "hiding a notice removes it from the screen")
            ; Tap Pause, then F2: the one-shot indicator hides before the status shows.
            SuiteNotice.Show("status", "Debug log copied")
            SuiteNotice.notices["status"].window.GetPos(, &statusY, , &statusHeight)
            this.Assert(Abs(statusY + statusHeight // 2 - (top + bottom) // 2) <= 2,
                "a status notice takes the center when no indicator shows")
        }
        finally SuiteNotice.Destroy()
        this.Assert(!SuiteNotice.notices.Count, "notices release every window")
    }

    ; Closing a suite window gives focus back to where the user was, instead of
    ; letting Windows pick an app that may sit on another display. Windows may
    ; refuse focus changes to a background test run, so each step checks first.
    static FocusReturn() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-focus-return")
        desktop := WinExist("ahk_class Progman")
        if !desktop
            return
        page := SuiteGui(, "Focus return page")
        try {
            WinActivate(desktop)
            Sleep 100
            if DllCall("GetForegroundWindow", "ptr") != desktop
                return
            SuiteShowCentered(page, 300, 200)
            this.Assert(SuiteFocusReturn.target = desktop,
                "opening a suite window remembers the window that had focus")
            WinActivate(page.Hwnd)
            Sleep 100
            if DllCall("GetForegroundWindow", "ptr") != page.Hwnd
                return
            SuiteFocusReturn.Destroy(page)
            page := 0
            Sleep 100
            this.Assert(DllCall("GetForegroundWindow", "ptr") = desktop,
                "closing a suite window returns focus to that window")
        }
        finally {
            if IsObject(page)
                page.Destroy()
        }
    }

    static DeferredInputsAndSessions() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-sessions")
        ; No module startup and no bound keys: only the lifecycle state is exercised.
        app.manager := CheckInputGate()
        app.dryRun := false
        pad := CheckPad()
        previousCritical := Critical("On")
        try {
            this.calls := 0
            callback := (*) => this.calls += 1
            generation := app.inputGeneration
            app.RunInput(generation, callback)
            this.Assert(this.calls = 1, "a current deferred input can execute")
            app.CancelInputs()
            app.RunInput(generation, callback)
            this.Assert(this.calls = 1, "an expired callback cannot replay after inputs resume")
            app.manager.gated := true
            app.RunInput(app.inputGeneration, callback)
            this.Assert(this.calls = 1, "deferred callbacks respect a closed input gate")
            app.manager.gated := false

            pad.QueueCommand("new", app.inputGeneration)
            app.CancelInputs()
            pad.ProcessCommands()
            this.Assert(!pad.executed.Length, "Paper Pad expires queued hotkey commands before execution")
            app.manager.gated := true
            pad.QueueCommand("save")
            pad.ProcessCommands()
            this.Assert(pad.executed.Length = 1 && pad.executed[1] = "save",
                "Paper Pad direct save requests survive the hotkey gate")
            app.manager.gated := false
            pad.QueueCommand("new", app.inputGeneration)
            pad.ProcessCommands()
            this.Assert(pad.executed.Length = 2 && pad.executed[2] = "new",
                "current Paper Pad hotkey requests remain usable")

            app.SessionEvent(7)
            this.Assert(app.sessionLocked && app.manager.gated && !IsCascadeEnabled(),
                "locking the session pauses hotkeys and automatic window management")
            app.PowerEvent(0x12)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(app.sessionLocked && !app.systemSuspended && app.manager.gated
                && !IsCascadeEnabled(), "automatic power resume cannot unlock the input gate")
            app.SessionEvent(8)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(!app.sessionLocked && !app.manager.gated && IsCascadeEnabled(),
                "unlocking restores input after all system pause reasons clear")
            app.SetSuspended(true)
            app.SessionEvent(7)
            app.SessionEvent(8)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(app.suspended && app.manager.gated && !IsCascadeEnabled(),
                "unlock never overrides explicit tray suspension")
            app.SetSuspended(false)
            app.PowerEvent(4)
            this.Assert(app.systemSuspended && app.manager.gated && !IsCascadeEnabled(),
                "a fresh power suspend closes the gate again")
        }
        finally {
            SetTimer(app.resumeCallback, 0)
            SetTimer(pad.process_commands_callback, 0)
            app.manager := 0
            app.dryRun := true
            Critical(previousCritical)
        }
    }

    static InputQueueCancellation() {
        app := SuiteApplication(true, SuiteChecks.directory "\hardening-input")
        manager := Keybindings("hardening-input", "Hardening input",
            {directory: app.Settings.directory "\keybindings"})
        app.manager := manager
        events := []
        previousCritical := Critical("On")
        try {
            manager.AddAction("fixture.input", "inert input", (event) => events.Push(event.phase),
                ["Ctrl + Alt + F24"], {repeat: true})
            ; Build real routes without registering hotkeys or enabling feature modules.
            candidate := manager._CandidateRoutes(manager._DefaultConfiguration())
            manager.configuration := candidate.configuration
            manager.routes := candidate.routes
            route := manager.routes[1]
            route.enabled := true
            manager.running := true

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.SetPaused(true)
            manager.SetPaused(false)
            manager._Drain()
            this.Assert(!events.Length && !manager.delivered.Count,
                "a complete queued shortcut cannot replay after pause/resume")

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager._Drain()
            this.Assert(events.Length = 2 && events[1] = "down" && events[2] = "up",
                "fresh shortcuts remain usable after cancellation")
            events.Length := 0

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.externalCapture := true
            manager._RefreshGate()
            manager.externalCapture := false
            manager._RefreshGate()
            manager._Drain()
            this.Assert(!events.Length, "entering and leaving recording expires queued input")

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager._Deactivate()
            route.enabled := true ; model restoring old routes after a failed configuration write
            manager._Drain()
            this.Assert(!events.Length, "configuration rollback cannot revive old queued input")

            manager._QueueEvent(route, "down", 0, false)
            manager._Drain()
            manager._QueueEvent(route, "repeat", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.SetPaused(true)
            manager.SetPaused(false)
            manager._Drain()
            this.Assert(events.Length = 2 && events[1] = "down" && events[2] = "cancel"
                && !manager.delivered.Count,
                "delivered output receives one cancel, not a stale repeat or release action")
        }
        finally {
            app.Stop("test")
            Critical(previousCritical)
        }
    }

    static FocusBorderLifecycle() {
        app := SuiteApplication(true, SuiteChecks.directory "\hardening-border")
        window := SuiteGui("+Resize", "Hardening border target")
        probes := []
        previousCritical := Critical("Off")
        try {
            window.Show("NA w320 h220")
            SuiteFocusBorder.Hide("", true)
            Loop 4
                probes.Push(CheckBorderProbe())
            SuiteFocusBorder.guis := probes
            this.Assert(SuiteFocusBorder.Show(window.Hwnd, "wonder-windows") && !A_IsCritical,
                "showing the border restores the caller's interruptibility")
            for probe in probes
                this.Assert(probe.visible && probe.showCritical > 0,
                    "each reused border segment is shown inside the critical section")

            ; The outline goes as soon as its window is dragged, moved by a
            ; hotkey, resized or minimized, not when it expires.
            SuiteFocusBorder.Watch()
            this.Assert(probes[1].visible && SuiteFocusBorder.target = window.Hwnd,
                "the border stays while its window stays put")
            WinGetPos(&borderX, &borderY, , , window.Hwnd)
            WinMove(borderX + 40, borderY, , , window.Hwnd)
            SuiteFocusBorder.Watch()
            this.Assert(!probes[1].visible && !SuiteFocusBorder.target && SuiteFocusBorder.owner = "",
                "moving the window hides its border at once")
            SuiteFocusBorder.Show(window.Hwnd, "wonder-windows")
            WinMove(, , 360, , window.Hwnd)
            SuiteFocusBorder.Watch()
            this.Assert(!probes[1].visible, "resizing the window hides its border at once")
            SuiteFocusBorder.Show(window.Hwnd, "wonder-windows")
            WinMinimize(window.Hwnd)
            SuiteFocusBorder.Watch()
            this.Assert(!probes[1].visible, "minimizing the window hides its border at once")
            WinRestore(window.Hwnd)
            this.Assert(SuiteFocusBorder.Moved([1, 2, 3, 4], [1, 2, 3, 5])
                && !SuiteFocusBorder.Moved([1, 2, 3, 4], [1, 2, 3, 4]),
                "only a changed position or size counts as a move")

            SuiteFocusBorder.Show(window.Hwnd, "close-window")
            this.Assert(!SuiteFocusBorder.Hide("wonder-windows")
                && SuiteFocusBorder.owner = "close-window",
                "old module cleanup cannot hide another module's outline")
            SuiteFocusBorder.Expire()
            for probe in probes
                this.Assert(!probe.visible && probe.hideCritical > 0,
                    "timer expiry hides border segments inside the critical section")

            SuiteFocusBorder.Show(window.Hwnd, "close-window")
            app.CancelInputs()
            this.Assert(SuiteFocusBorder.owner = "", "input cancellation clears the shared border owner")
            for probe in probes
                this.Assert(!probe.visible, "input cancellation hides a close-owned border")

            Critical(50)
            SuiteFocusBorder.Show(window.Hwnd, "wonder-windows")
            this.Assert(A_IsCritical = 50, "show preserves an existing critical interval")
            SuiteFocusBorder.Hide("", true)
            this.Assert(A_IsCritical = 50 && !SuiteFocusBorder.guis.Length,
                "destroy preserves an existing critical interval and releases border references")
            for probe in probes
                this.Assert(probe.destroyCritical > 0, "border destruction stays serialized")
        }
        finally {
            SuiteFocusBorder.Hide("", true)
            window.Destroy()
            Critical(previousCritical)
        }
    }

    static CloseAndBorderRules() {
        this.Assert(SuiteCloseWindow.Decision(true, false) = "preserve"
            && SuiteCloseWindow.Decision(true, true) = "preserve"
            && SuiteCloseWindow.Decision(false, true) = "wait"
            && SuiteCloseWindow.Decision(false, false) = "recover",
            "closing preserves genuine focus and recovers only after closing")
        this.Assert(SuiteCloseWindow.ShouldHighlight("preserve", false)
            && !SuiteCloseWindow.ShouldHighlight("preserve", true)
            && !SuiteCloseWindow.ShouldHighlight("wait", true)
            && !SuiteCloseWindow.ShouldHighlight("recover", false),
            "closing highlights native focus only after the close completes")
        clip := (rect) => (clipped := SuiteFocusBorder.Clip(rect, [0, 0, 1920, 1080]))
            ? clipped[1] "," clipped[2] "," clipped[3] "," clipped[4] : "hidden"
        this.Assert(clip([-10, 100, 12, 300]) = "0,100,2,300"
            && clip([1918, 100, 12, 300]) = "1918,100,2,300"
            && clip([1920, 100, 12, 300]) = "hidden"
            && clip([90, -10, 500, 12]) = "90,0,500,2"
            && clip([90, 90, 500, 12]) = "90,90,500,12",
            "the focus border keeps only the part on its window's display")
        this.Assert(SuiteFocusBorder.durationMs = 1500
            && SuiteFocusBorder.thickness = 12
            && SuiteFocusBorder.overlap = 2
            && SuiteFocusBorder.CanHide("wonder-windows", "wonder-windows")
            && !SuiteFocusBorder.CanHide("wonder-windows", "close-window")
            && SuiteFocusBorder.CanHide("", "close-window"),
            "shared core border preserves appearance and respects module ownership")
    }
}

class SuiteFailingModule extends SuiteModule {
    cleaned := false

    Start() {
        throw Error("Expected module startup failure")
    }

    Stop(*) {
        this.cleaned := true
    }
}

class CheckInputGate {
    running := true
    gated := false
    applying := false
    disposed := false

    SetPaused(paused, *) => this.gated := paused
}

class CheckBorderProbe {
    BackColor := ""
    visible := false
    showCritical := 0
    hideCritical := 0
    destroyCritical := 0

    Show(*) {
        this.showCritical := A_IsCritical
        this.visible := true
    }

    Hide() {
        this.hideCritical := A_IsCritical
        this.visible := false
    }

    Destroy() {
        this.destroyCritical := A_IsCritical
        this.visible := false
    }
}
