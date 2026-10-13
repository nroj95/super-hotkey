; Loaded from a temporary harness at the repository root. No real feature effects.
class SuiteChecks {
    static count := 0
    static directory := A_Temp "\SHW-check-" FormatTime(, "yyyyMMdd-HHmmss") "-" DllCall("GetCurrentProcessId", "uint")

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
        this.CheckExitVeto()
        this.CheckDryRunLifecycle()
    }

    static CheckSettings() {
        settings := SuiteSettings(this.directory "\preferences")
        enabled := 0
        for id, value in settings.modules
            enabled += value
        this.Assert(enabled = 4, "all four modules default to enabled")
        choices := settings.modules.Clone()
        choices["keyboard-layers"] := false
        settings.Save(choices)
        loaded := SuiteSettings(settings.directory)
        this.Assert(!loaded.modules["keyboard-layers"], "disabled module choice survives reload")
        document := KB_Manifest.Read(settings.path)
        document["modules"]["scratchpad"] := "invalid"
        KB_Manifest.WriteAtomic(settings.path, document)
        before := FileRead(settings.path, "UTF-8")
        this.Rejects((*) => SuiteSettings(settings.directory), "invalid module configuration is rejected")
        this.Assert(before = FileRead(settings.path, "UTF-8"), "invalid configuration is not rewritten")
        settings.Save(choices)
        folder := settings.directory "\scratchpad"
        DirCreate folder
        path := folder "\settings.ini"
        IniWrite("sentinel-notes-folder", path, "Paths", "ScratchDirectory")
        IniWrite("sentinel-editor.exe", path, "Paths", "Notepad3Executable")
        IniWrite("55", path, "Window", "WidthPercent")
        FileAppend("personal note", folder "\note.md", "UTF-8-RAW")
        FileAppend("editor preference", folder "\Notepad3.ini", "UTF-8-RAW")
        FileAppend("page state", folder "\state.ini", "UTF-8-RAW")
        backup := settings.Backup([path])
        settings.ResetModulePreferences()
        this.Assert(IniRead(path, "Window", "WidthPercent", "missing") = "missing", "factory reset removes only whitelisted preferences")
        this.Assert(IniRead(path, "Paths", "ScratchDirectory") = "sentinel-notes-folder", "factory reset retains the notes folder")
        this.Assert(IniRead(path, "Paths", "Notepad3Executable") = "sentinel-editor.exe", "factory reset retains the editor path")
        this.Assert(FileRead(folder "\note.md") = "personal note", "factory reset preserves notes")
        this.Assert(FileRead(folder "\Notepad3.ini") = "editor preference" && FileRead(folder "\state.ini") = "page state", "factory reset preserves editor preferences and page state")
        this.Assert(FileExist(backup "\scratchpad-settings.ini"), "resettable settings have a backup")
    }

    static CheckCatalog() {
        app := SuiteApplication(true, this.directory "\catalog")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.power.Start()
            this.Assert(manager.actions.Count > 50 && manager.actions.Count < 128, "all modules share one action catalog")
            this.Rejects((*) => Keybindings("second", "Second", {directory: this.directory}), "a second manager is rejected")
            this.Assert(!manager.client.hooksInstalled, "paused startup does not capture native CapsLock or Pause")
            for status in manager.GetStatus()
                this.Assert(!InStr(status.state, "error:"), "registration: " status.actionId " / " status.slot)
            configuration := manager.GetConfiguration()
            this.Assert(configuration["core.keybindings"].bindings[1] = Keybindings.Parse("Caps + K").signature, "Caps + K opens the shared editor")
            this.Assert(configuration["power-hotkey.terminal.clear"].bindings[1] = Keybindings.Parse("Caps + Ctrl + K").signature, "terminal clear has a nonconflicting default")
            this.Assert(HasMethod(manager.actions["scratchpad.save"].context, "Call"), "Scratchpad save has an explicit editor context")
            this.Assert(!manager.ContextActive(manager.actions["scratchpad.save"]), "Scratchpad commands are inactive outside its editor")
            manager.ShowSettings()
            this.Assert(IsObject(manager.settings) && manager.rows.Length > 50, "shared editor renders the complete catalog")
            manager._CloseSettings()

            app.activeModules["power-hotkey"] := false
            manager.Apply(configuration)
            this.Assert(!this.HasRoute(manager, "power-hotkey.keyboard.f13"), "disabled module releases its routes")
            rows := Keybindings.DisplayRows(manager.DiscoverParticipants())
            found := false
            for row in rows
                if row.id = "power-hotkey.keyboard.f13"
                    found := true
            this.Assert(found, "disabled module assignments remain visible and editable")
            this.Assert(manager.GetConfiguration()["power-hotkey.keyboard.f13"].bindings[1] = configuration["power-hotkey.keyboard.f13"].bindings[1], "disabling a module preserves its assignments")
            changed := manager.GetConfiguration()
            changed["scratchpad.toggle"].bindings[1] := "Caps + Q"
            manager.Apply(changed)
            this.Assert(manager.GetConfiguration()["scratchpad.toggle"].bindings[1] = Keybindings.Parse("Caps + Q").signature, "a disabled module's key can be reused")
            before := FileRead(manager.path, "UTF-8")
            app.activeModules["power-hotkey"] := true
            this.Rejects((*) => manager.Apply(manager.GetConfiguration()), "re-enabling a conflicting module is rejected")
            this.Assert(FileRead(manager.path, "UTF-8") = before, "conflict rejection preserves the saved configuration")
            this.Assert(!this.HasRoute(manager, "power-hotkey.keyboard.f13"), "conflict rejection retains the prior runtime")
            manager.Apply(configuration)
            this.Assert(this.HasRoute(manager, "power-hotkey.keyboard.f13"), "restoring a valid configuration restores the module routes")
            manager.actions["scratchpad.toggle"].available := false
            defaults := manager._DefaultConfiguration()
            this.Assert(defaults["scratchpad.toggle"].bindings[1] = Keybindings.Parse("Win + F12").signature, "shortcut defaults include disabled actions")
            manager.actions["scratchpad.toggle"].available := true

            ; Direct callbacks exercise dry-run guards without emitting any input.
            event := {phase: "down", actionId: "window-cascade.minimize", slot: 1,
                key: "sc032", modifiers: 0, layer: "caps", foregroundHwnd: 0, oneShot: false}
            manager.actions[event.actionId].callback.Call(event)
            event.actionId := "scratchpad.toggle"
            manager.actions[event.actionId].callback.Call(event)
            app.power.keyboard.SendOutput("F13", " down")
            app.power.keyboard.SendOutput("F13", " up")
            diagnosticLog := FileRead(SuiteState.Log.path, "UTF-8")
            this.Assert(InStr(diagnosticLog, "dry run: window-cascade.minimize") && InStr(diagnosticLog, "dry run: toggle") && InStr(diagnosticLog, "dry run: send F13"), "feature callbacks use dry-run guards")

            global CPL
            CPL.showIndicator := false
            CPL.armed := "caps"
            CPL.armedUntil := CPL_Now() + 1000
            CPL.enabled := true
            this.Assert(manager.client.OwnsInput("sc024"), "one-shot layer input excludes ordinary bindings")
            CPL.armedUntil := CPL_Now() - 1
            this.Assert(!manager.client.OwnsInput("sc024"), "expired one-shot input releases ordinary bindings")
            CPL.armed := ""
            CPL.enabled := false
            manager.Observe("~*F24", (*) => false, (*) => 0)
            this.Assert(manager.observers.Length = 1, "native observers are owned by the shared manager")
        }
        finally {
            manager.Stop()
            app.power.Stop()
        }
        this.Assert(!IsObject(Keybindings.Current) && !manager.running, "manager shutdown releases singleton ownership")
    }

    static CheckNoLayers() {
        app := SuiteApplication(true, this.directory "\without-layers")
        app.activeModules["keyboard-layers"] := false
        app.InitializeCatalog()
        manager := app.manager
        flag := {active: false}
        manager.AddAction("test.context", "context check", (*) => 0, ["F24"], {context: (*) => flag.active})
        try {
            manager.SetPaused(true)
            manager.Start()
            this.Assert(!IsObject(manager.client), "disabled keyboard layers create no adapter or prefix hooks")
            configuration := manager.GetConfiguration()
            this.Assert(configuration["core.keybindings"].bindings[1] != "", "inactive layer assignments remain saved")
            unavailable := 0
            for status in manager.GetStatus()
                if InStr(status.state, "unavailable:")
                    unavailable += 1
            this.Assert(unavailable > 20, "layer bindings are explicitly unavailable without the module")
            configuration["scratchpad.toggle"].bindings[1] := "CapsLock"
            manager.Apply(configuration)
            this.Assert(this.HasRoute(manager, "scratchpad.toggle"), "CapsLock can be explicitly rebound without layers")
            configuration["scratchpad.toggle"].bindings[1] := "Pause"
            manager.Apply(configuration)
            this.Assert(manager.GetConfiguration()["scratchpad.toggle"].bindings[1] = Keybindings.Parse("Pause").signature, "Pause can be explicitly rebound without layers")
            configuration["scratchpad.toggle"].bindings[1] := "Ctrl + Alt + J"
            manager.Apply(configuration)
            this.Assert(manager.GetConfiguration()["scratchpad.toggle"].bindings[1] = Keybindings.Parse("Ctrl + Alt + J").signature, "ordinary replacements work without layers")
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
        diagnosticLog.Write("Scratchpad", "second")
        this.Assert(FileExist(diagnosticLog.path ".old"), "central log rotates at the size limit")
        diagnosticLog.Error("Power Hotkey", Error("diagnostic marker", "native checks"))
        this.Assert(InStr(FileRead(diagnosticLog.path, "UTF-8"), "diagnostic marker"), "errors retain their details and module attribution")
        diagnosticLog.Clear()
        this.Assert(InStr(FileRead(diagnosticLog.path, "UTF-8"), "previous log retained"), "clearing the log retains one previous segment")
    }

    static CheckDryRunLifecycle() {
        app := SuiteApplication(true, this.directory "\startup")
        try {
            app.Start()
            this.Assert(app.manager.running && app.manager.paused, "dry-run startup keeps every shortcut inactive")
            this.Assert(!app.cascadeStarted && !app.scratchpadStarted, "dry-run startup does not start native feature modules")
            this.Assert(IsObject(app.ui) && IsObject(app.manager.settings), "dry-run startup creates the shared tray and editor")
            app.ui.ShowModules()
            this.Assert(IsObject(app.ui.modulesWindow), "module settings window opens")
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

    static CheckExitVeto() {
        busyController := {busy: true, command_queue: []}
        this.Rejects((*) => ScratchpadController.Prototype.PrepareSuiteExit.Call(busyController, "Reload"),
            "Scratchpad can refuse a restart while a command is active")
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
