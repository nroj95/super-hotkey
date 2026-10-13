class SuiteInterface {
    __New(app) {
        this.app := app
        this.modulesWindow := 0
        this.moduleControls := Map()
        this.startupPath := A_Startup "\Super Hotkey World.lnk"
    }

    BuildTray() {
        A_IconTip := SuiteApplication.Name (this.app.dryRun ? " - dry run" : "")
        try TraySetIcon(A_ScriptDir "\assets\keybindings.ico", , true)
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Keybindings", ObjBindMethod(this.app, "ShowKeybindings"))
        A_TrayMenu.Add("Modules", ObjBindMethod(this, "ShowModules"))
        A_TrayMenu.Add()
        if this.app.cascadeStarted
            A_TrayMenu.Add("Window Cascade", SuiteState.CascadeMenu)
        if this.app.ModuleActive("power-hotkey")
            A_TrayMenu.Add("Power Hotkey status", (*) => PH_Modules.ShowStatus(this.app.power))
        if this.app.scratchpadStarted
            A_TrayMenu.Add("Scratchpad", SuiteState.ScratchpadMenu)
        A_TrayMenu.Add("Open debug log", ObjBindMethod(this, "OpenLog"))
        A_TrayMenu.Add("Open settings folder", (*) => Run('explorer.exe "' this.app.Settings.directory '"'))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Restore factory defaults...", ObjBindMethod(this, "FactoryDefaults"))
        A_TrayMenu.Add("Run at startup", ObjBindMethod(this, "ToggleStartup"))
        if this.app.dryRun
            A_TrayMenu.Disable("Run at startup")
        else if FileExist(this.startupPath)
            A_TrayMenu.Check("Run at startup")
        A_TrayMenu.Add("Reload", (*) => Reload())
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Keybindings"
    }

    OpenLog(*) {
        if !FileExist(SuiteState.Log.path)
            SuiteState.Log.Write("Core", "log opened")
        Run('notepad.exe "' SuiteState.Log.path '"')
    }

    ShowModules(*) {
        if IsObject(this.modulesWindow) {
            this.modulesWindow.Show()
            return
        }
        this.app.CancelInputs()
        window := Gui("-Resize", SuiteApplication.Name " - Modules")
        this.modulesWindow := window
        window.SetFont("s10", "Segoe UI")
        window.AddText("xm w430", "Module changes take effect after restarting the application.")
        this.moduleControls := Map()
        for id, label in SuiteSettings.ModuleNames {
            control := window.AddCheckbox("xm y+14 w400", label)
            control.Value := this.app.Settings.modules[id]
            this.moduleControls[id] := control
        }
        window.AddText("xm y+18 w430", "Keybindings is always available. Disabled modules keep their saved assignments.")
        window.AddButton("xm y+18 w200 Default", "Apply and restart").OnEvent("Click", ObjBindMethod(this, "SaveModules"))
        window.AddButton("x+12 w100", "Cancel").OnEvent("Click", ObjBindMethod(this, "CloseModules"))
        window.OnEvent("Close", ObjBindMethod(this, "CloseModules"))
        window.OnEvent("Escape", ObjBindMethod(this, "CloseModules"))
        this.app.RefreshInputGate()
        window.Show()
    }

    SaveModules(*) {
        modules := Map()
        for id, control in this.moduleControls
            modules[id] := control.Value != 0
        try this.app.Settings.Save(modules)
        catch Error as failure {
            SuiteState.Log.Error("Core / module settings", failure)
            MsgBox(failure.Message, SuiteApplication.Name, "Icon!")
            return
        }
        this.CloseModules()
        SuiteState.Log.Write("Core", "module choices saved; restart requested")
        Reload()
    }

    CloseModules(*) {
        if IsObject(this.modulesWindow)
            this.modulesWindow.Destroy()
        this.modulesWindow := 0
        this.app.RefreshInputGate()
    }

    ToggleStartup(*) {
        if this.app.dryRun
            return
        if FileExist(this.startupPath) {
            FileDelete(this.startupPath)
            A_TrayMenu.Uncheck("Run at startup")
        } else {
            if A_IsCompiled
                FileCreateShortcut(A_ScriptFullPath, this.startupPath, A_ScriptDir)
            else
                FileCreateShortcut(A_AhkPath, this.startupPath, A_ScriptDir, '"' A_ScriptFullPath '"')
            A_TrayMenu.Check("Run at startup")
        }
    }

    FactoryDefaults(*) {
        if MsgBox("Re-enable every module and restore default shortcuts and module preferences?"
            . "`n`nScratchpad notes, their folder, the editor path and Notepad3 preferences will be kept."
            . "`nA settings backup will be created before changes. The suite will restart.",
            SuiteApplication.Name, "YesNo Default2 Icon?") != "Yes"
            return
        app := this.app
        root := app.Settings.directory
        paths := [app.Settings.path, app.manager.path,
            root "\window-cascade\settings.ini", root "\scratchpad\settings.ini"]
        backup := ""
        try {
            backup := app.Settings.Backup(paths)
            app.manager.Apply(app.manager._DefaultConfiguration())
            choices := Map()
            for id in SuiteSettings.ModuleNames
                choices[id] := true
            app.Settings.Save(choices)
            app.Settings.ResetModulePreferences()
            SuiteState.Log.Write("Core", "factory preferences restored; backup: " backup)
            Reload()
        }
        catch Error as failure {
            SuiteState.Log.Error("Core / factory reset", failure)
            MsgBox("The reset stopped. Some preferences may have changed; notes were not deleted."
                . "`n`n" failure.Message "`n`nBackup: " backup, SuiteApplication.Name, "Icon!")
        }
    }
}
