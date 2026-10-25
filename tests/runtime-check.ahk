; Loaded from a temporary harness at the repository root. No real feature effects.
class SuiteChecks {
    static count := 0
    static directory := A_Temp "\SuperHotkey-check-" FormatTime(, "yyyyMMdd-HHmmss") "-" DllCall("GetCurrentProcessId", "uint")

    static Assert(condition, label) {
        if !condition
            throw Error(label)
        this.count += 1
        FileAppend("PASS: " label "`n", "*")
    }

    static Rejects(callback, label) {
        rejected := false
        try callback.Call()
        catch Error
            rejected := true
        this.Assert(rejected, label)
    }

    static HasRoute(manager, actionId) {
        for route in manager.routes
            if route.action.id = actionId
                return true
        return false
    }

    static Run() {
        DirCreate this.directory
        this.CheckSettings()
        this.CheckCatalog()
        this.CheckNoLayers()
        this.CheckLogging()
        this.CheckRecovery()
        this.CheckExitVeto()
        this.CheckAutosavePolicy()
        this.CheckDryRunLifecycle()
        this.CheckModuleStartFailure()
        SuiteUpgradeChecks.Run()
        SuiteReleaseChecks.Run()
    }

    static CheckSettings() {
        settings := SuiteSettings(this.directory "\preferences")
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
        app := SuiteApplication(true, this.directory "\catalog")
        app.InitializeCatalog()
        manager := app.manager
        power := app.modules["power-up-utilities"]
        try {
            manager.SetPaused(true)
            manager.Start()
            this.Assert(manager.actions.Count > 50 && manager.actions.Count < 128, "all modules share one action catalog")
            this.Rejects((*) => Keybindings("second", "Second", {directory: this.directory}), "a second manager is rejected")
            this.Assert(!manager.client.hooksInstalled, "paused startup does not capture native CapsLock or Pause")
            for route in manager.routes
                this.Assert(!InStr(route.state, "error:"), "registration: " route.action.id " / " route.slot)
            configuration := manager.GetConfiguration()
            this.Assert(configuration["core.keybindings"].bindings[1] = Keybindings.Parse("Caps + Alt + K").signature, "Caps + Alt + K opens the shared editor")
            this.Assert(configuration["power-up-utilities.terminal.copy"].bindings[1] = Keybindings.Parse("Caps + C").signature, "Terminal copy defaults to Caps + C")
            this.Assert(configuration["power-up-utilities.terminal.clear"].bindings[1] = Keybindings.Parse("Caps + K").signature, "Terminal clear defaults to Caps + K")
            this.Assert(configuration["power-up-utilities.system.wake-speakers"].bindings[1] = Keybindings.Parse("Pause + Pause").signature, "speaker wake defaults to Pause double-tap")
            for direction in ["left", "right", "up", "down"] {
                this.Assert(configuration["wonder-windows.focus-" direction].bindings[1]
                    = Keybindings.Parse("Win + Alt + " direction).signature,
                    "directional focus defaults to Win + Alt + " direction)
                this.Assert(configuration["wonder-windows.swap-" direction].bindings[1]
                    = Keybindings.Parse("Caps + Win + " direction).signature,
                    "directional swap defaults to Caps + Win + " direction)
            }
            this.Assert(configuration["wonder-windows.stretch-full-cycle"].bindings[1]
                = Keybindings.Parse("Shift + Win + Enter").signature
                && configuration["wonder-windows.reset-stretch"].bindings[2] = "",
                "full stretch cycling and undo have revised defaults")
            this.Assert(configuration["wonder-windows.cycle-expanded"].bindings[1]
                = Keybindings.Parse("Caps + Win + Enter").signature
                && configuration["wonder-windows.cycle-stacked"].bindings[1]
                    = Keybindings.Parse("Win + Enter").signature,
                "expanded and stacked window cycling use separate default shortcuts")
            this.Assert(!manager.actions.Has("wonder-windows.swap-next")
                && !manager.actions.Has("wonder-windows.swap-previous"),
                "old clockwise swap actions are removed")
            this.Assert(configuration["wonder-windows.zones-from-left"].bindings[1]
                    = Keybindings.Parse("Win + WheelDown").signature
                && configuration["wonder-windows.zones-from-left"].bindings[2]
                    = Keybindings.Parse("Caps + Win + PgDn").signature
                && configuration["wonder-windows.zones-from-right"].bindings[1]
                    = Keybindings.Parse("Win + WheelUp").signature
                && configuration["wonder-windows.zones-from-right"].bindings[2]
                    = Keybindings.Parse("Caps + Win + PgUp").signature,
                "zone cycling defaults to Win + wheel and Caps + Win + PgDn/PgUp")
            for direction in ["up", "down", "left", "right"]
                this.Assert(!manager.actions.Has("wonder-windows.zone-" direction),
                    "FancyZones forwarding is removed: " direction)
            this.Assert(configuration["wonder-windows.move-monitor"].bindings[1]
                    = Keybindings.Parse("Caps + Win + Backspace").signature,
                "Wonder Windows defaults to one monitor-cycle shortcut")
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
            this.Assert(!this.HasRoute(manager, "power-up-utilities.keyboard.f13"), "disabled module releases its routes")
            capsConfiguration := manager.GetConfiguration()
            capsConfiguration["power-up-utilities.keyboard.toggle-caps"].bindings[1] := "Ctrl + Alt + F10"
            manager.Apply(capsConfiguration)
            this.Assert(this.HasRoute(manager, "power-up-utilities.keyboard.toggle-caps"),
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
            this.Rejects((*) => manager.Apply(manager.GetConfiguration()), "re-enabling a conflicting module is rejected")
            this.Assert(FileRead(manager.path, "UTF-8") = before, "conflict rejection preserves the saved configuration")
            this.Assert(!this.HasRoute(manager, "power-up-utilities.keyboard.f13"), "conflict rejection retains the prior runtime")
            manager.Apply(configuration)
            this.Assert(this.HasRoute(manager, "power-up-utilities.keyboard.f13"), "restoring a valid configuration restores the module routes")
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
        app := SuiteApplication(true, this.directory "\without-layers")
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
            this.Assert(this.HasRoute(manager, "paper-pad.toggle"), "CapsLock can be explicitly rebound without layers")
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
                this.Rejects((*) => Keybindings.Parse(invalid), "unsafe or reserved binding rejected: " invalid)
            this.Assert(Keybindings.Parse("Escape").signature = Keybindings.Parse("Esc").signature, "key aliases normalize consistently")
            this.Assert(Keybindings.Parse("Pause + Escape").layer = "pause", "layer Escape remains a valid assignment")
        }
        finally manager.Stop()
    }

    static CheckLogging() {
        diagnosticLog := SuiteLog(this.directory "\logging", 100)
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
        directory := this.directory "\recovery"
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
                    this.Rejects(() => SuiteSettings(lockedDirectory),
                        "suite settings cannot recover when preservation fails")
                else
                    this.Rejects(() => lockedManager.Start(),
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

        settings := SuiteSettings(this.directory "\backups")
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

    static CheckDryRunLifecycle() {
        app := SuiteApplication(true, this.directory "\startup")
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
        app := SuiteApplication(true, this.directory "\module-failure")
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

    static CheckExitVeto() {
        busyController := {busy: true, command_queue: []}
        this.Rejects((*) => PaperPadController.Prototype.PrepareSuiteExit.Call(busyController, "Reload"),
            "Paper Pad can refuse a restart while a command is active")
    }

    static CheckAutosavePolicy() {
        tracking := {sampled: false, text: "", last_change: 0}
        PaperPadController.TrackAutosaveChanges(tracking, true, "abc", 1000)
        this.Assert(tracking.sampled && tracking.last_change = 1000,
            "first dirty snapshot starts Paper Pad's idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "abc", 1500)
        this.Assert(tracking.last_change = 1000,
            "unchanged document text preserves the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "aBc", 1600)
        this.Assert(tracking.last_change = 1600,
            "case-only edits reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "xyz", 1700)
        this.Assert(tracking.last_change = 1700,
            "equal-length replacements reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "", 1800)
        this.Assert(tracking.last_change = 1800,
            "deletions reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, false, "", 1900)
        this.Assert(!tracking.sampled && tracking.text = "" && tracking.last_change = 0,
            "clean documents release their retained snapshot")
        this.Assert(!PaperPadController.ShouldAutosave(false, 2000, 9999, 9999),
            "clean Paper Pad skips idle autosave")
        this.Assert(!PaperPadController.ShouldAutosave(true, 999, 5000, 2000),
            "recent document edits defer autosave")
        this.Assert(!PaperPadController.ShouldAutosave(true, 1000, 5000, 999),
            "failed saves cannot trigger a rapid retry loop")
        this.Assert(PaperPadController.ShouldAutosave(true, 1000, 5000, 2000),
            "dirty Paper Pad saves one second after the last document change")
        this.Assert(PaperPadController.ShouldAutosave(true, 0, 10000, 1000),
            "continuous edits receive a ten-second fallback")
        this.Assert(PaperPadController.ShouldAutosave(false, 0, 10000, 1000),
            "encoding-only changes retain periodic save attempts")
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

SHW_RunSuiteChecks() {
    result := 0
    try {
        SuiteChecks.Run()
        FileAppend("PASS: native suite checks completed: " SuiteChecks.count " assertions.`n", "*")
    }
    catch Error as failure {
        FileAppend("FAIL: " failure.Message "`n" failure.File ":" failure.Line "`n" failure.Stack "`n", "**")
        result := 1
    }
    finally {
        if IsObject(Keybindings.Current)
            try Keybindings.Current.Stop()
        try DirDelete(SuiteChecks.directory, true)
    }
    ExitApp(result)
}

SHW_RunSuiteChecks()
