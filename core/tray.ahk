; =============================================================================
; One flat tray. Module entries open help; settings and diagnostics live in GUIs.
; Every Keybindings button returns to the same manager-owned editor.
; =============================================================================
class SuiteInterface {
    __New(app) {
        this.app := app
        this.windows := Map()
        this.configurationWindows := Map()
        this.modulesWindow := 0
        this.moduleControls := Map()
        this.startupPath := A_Startup "\Super Hotkey World.lnk"
    }

    BuildTray() {
        A_IconTip := SuiteApplication.Name (this.app.dryRun ? " - dry run" : "")
        try TraySetIcon(SuiteIcons.path, , true)
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Modules...", ObjBindMethod(this, "ShowModules"))
        A_TrayMenu.Add("Keybindings...", ObjBindMethod(this.app, "ShowKeybindings"))
        A_TrayMenu.Add()
        for id in SuiteSettings.ModuleOrder
            A_TrayMenu.Add(SuiteSettings.ModuleNames[id] "...", ObjBindMethod(this, "ShowHelp", id))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Debug log...", ObjBindMethod(this, "OpenLog"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Keybindings..."
    }

    Existing(key) {
        if !this.windows.Has(key)
            return false
        this.windows[key].Show()
        return true
    }

    NewWindow(key, title, configuration := false) {
        window := SuiteGui("-Resize", title)
        window.SetFont("s10", "Segoe UI")
        window.OnEvent("Close", ObjBindMethod(this, "CloseWindow", key))
        window.OnEvent("Escape", ObjBindMethod(this, "CloseWindow", key))
        this.windows[key] := window
        if configuration {
            this.configurationWindows[key] := true
            this.app.CancelInputs()
            this.app.RefreshInputGate()
        }
        return window
    }

    Footer(window, buttons, y, width := 800) {
        total := 0
        for item in buttons
            total += (item.Length >= 3 ? item[3] : 130) + 10
        x := width - 10 - total
        window.AddText("x20 y" (y - 15) " w" (width - 40) " h2 +0x10", "")
        for item in buttons {
            buttonWidth := item.Length >= 3 ? item[3] : 130
            window.AddButton("x" x " y" y " w" buttonWidth " h30", item[1]).OnEvent("Click", item[2])
            x += buttonWidth + 10
        }
    }

    CloseWindow(key, *) {
        if this.windows.Has(key) {
            this.windows[key].Destroy()
            this.windows.Delete(key)
        }
        if this.configurationWindows.Has(key)
            this.configurationWindows.Delete(key)
        if key = "modules"
            this.modulesWindow := 0
        this.app.RefreshInputGate()
    }

    CloseAll() {
        for key in this.windows.Clone()
            this.CloseWindow(key)
    }

    HasSettingsOpen() => this.configurationWindows.Count != 0
    CloseModules(*) => this.CloseWindow("modules")

    Report(failure, area) {
        SuiteState.Log.Error(area, failure)
        MsgBox(failure.Message, SuiteApplication.Name, "Icon!")
    }

    ; =========================================================================
    ; Help and suite-wide module selection
    ; =========================================================================

    ShowHelp(id, *) {
        key := "help:" id
        if this.Existing(key) {
            this.RefreshHelp()
            return
        }
        name := SuiteSettings.ModuleNames[id]
        window := this.NewWindow(key, name " - How to use")
        state := this.app.ModuleActive(id) ? "enabled" : "disabled; assignments and settings are retained"
        if this.app.dryRun
            state := "dry run; feature effects are inactive"
        window.AddText("x20 y18 w760", name " - " state)
        window.AddEdit("x20 y50 w760 h390 ReadOnly +VScroll vhelpText", ModuleHelp.Text(id, this.app.manager))
        buttons := []
        if id = "scratchpad"
            buttons.Push(["Open Pad", ObjBindMethod(this, "OpenPad"), 110])
        if id != "power-hotkey"
            buttons.Push(["Settings...", ObjBindMethod(this, "ShowModuleSettings", id), 120])
        buttons.Push(["Keybindings...", ObjBindMethod(this.app, "ShowKeybindings"), 135])
        buttons.Push(["Close", ObjBindMethod(this, "CloseWindow", key), 100])
        this.Footer(window, buttons, 475)
        window.Show("w800 h525")
    }

    RefreshHelp(*) {
        for id in SuiteSettings.ModuleOrder {
            key := "help:" id
            if this.windows.Has(key)
                this.windows[key]["helpText"].Value := ModuleHelp.Text(id, this.app.manager)
        }
    }

    ShowModules(*) {
        if this.Existing("modules")
            return
        window := this.NewWindow("modules", SuiteApplication.Name " - Modules", true)
        this.modulesWindow := window
        window.AddText("x20 y18 w560", "Module changes take effect after restarting. Keybindings is always available.")
        this.moduleControls := Map()
        y := 60
        for id in SuiteSettings.ModuleOrder {
            control := window.AddCheckbox("x20 y" y " w540", SuiteSettings.ModuleNames[id])
            control.Value := this.app.Settings.modules[id]
            this.moduleControls[id] := control
            window.AddText("x42 y" (y + 25) " w518", SuiteSettings.ModuleDescriptions[id])
            y += 58
        }
        window.AddText("x20 y358 w560", "Disabled modules keep their assignments. Their help remains available in the tray.")
        this.Footer(window, [["App settings...", ObjBindMethod(this, "ShowAppSettings"), 130],
            ["Apply and restart", ObjBindMethod(this, "SaveModules"), 160],
            ["Cancel", ObjBindMethod(this, "CloseModules"), 100]], 410, 600)
        window.Show("w600 h460")
    }

    SaveModules(*) {
        choices := Map()
        for id, control in this.moduleControls
            choices[id] := control.Value != 0
        try {
            this.app.Settings.Save(choices)
            this.CloseModules()
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Core / module settings")
    }

    ShowModuleSettings(id, *) {
        switch id {
            case "keyboard-layers": this.ShowLayerSettings()
            case "window-cascade": this.ShowCascadeSettings()
            case "scratchpad": this.ShowPaperSettings()
            case "win-key-overhaul": this.ShowWonderSettings()
        }
    }

    ; =========================================================================
    ; Secret Keys: persistent, independent layer choices; restart-based hooks
    ; =========================================================================

    ShowLayerSettings(*) {
        key := "settings:keyboard-layers"
        if this.Existing(key)
            return
        window := this.NewWindow(key, "Secret Keys - Settings", true)
        window.AddText("x20 y20 w560", "Modules is the master switch. These choices control each layer independently.")
        window.AddCheckbox("x20 y70 w540 vcaps", "Enable CapsLock Layer").Value := this.app.Settings.layers["caps"]
        window.AddCheckbox("x20 y115 w540 vpause", "Enable Pause Layer").Value := this.app.Settings.layers["pause"]
        window.AddText("x20 y165 w560", "A disabled layer releases its native key unless you explicitly reassign it."
            . "`nSaved layer shortcuts stay visible and editable in Keybindings.")
        this.Footer(window, [["Apply and restart", ObjBindMethod(this, "SaveLayers"), 160],
            ["Cancel", ObjBindMethod(this, "CloseWindow", key), 100]], 260, 600)
        window.Show("w600 h310")
    }

    SaveLayers(*) {
        key := "settings:keyboard-layers"
        window := this.windows[key]
        try {
            this.app.Settings.Save(this.app.Settings.modules,
                Map("caps", window["caps"].Value != 0, "pause", window["pause"].Value != 0))
            this.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Secret Keys / settings")
    }

    ; =========================================================================
    ; Cascade Kingdom settings replace the old tray submenus
    ; =========================================================================

    ShowCascadeSettings(*) {
        key := "settings:window-cascade"
        if this.Existing(key)
            return
        global cascade_auto_placement_paused, focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        window := this.NewWindow(key, "Cascade Kingdom - Settings", true)
        window.AddCheckbox("x20 y25 w550 vpaused", "Pause automatic placement of new windows").Value := cascade_auto_placement_paused
        window.AddCheckbox("x20 y65 w550 vtabs", "Show focus tabs").Value := focus_corner_visible
        colors := []
        for name in focus_tab_color_presets
            colors.Push(name)
        window.AddText("x20 y115 w200", "Active-slot tab color")
        active := window.AddDropDownList("x240 y110 w210 vactiveColor", colors)
        active.Choose(focus_corner_active_slot_color_name)
        window.AddText("x20 y160 w200", "Inactive-slot tab color")
        inactive := window.AddDropDownList("x240 y155 w210 vinactiveColor", colors)
        inactive.Choose(focus_corner_inactive_slot_color_name)
        window.AddText("x20 y215 w550", "Changes apply after restarting. Shortcuts remain in the shared Keybindings editor.")
        this.Footer(window, [["Compatibility...", ObjBindMethod(this, "CascadeCompatibility"), 140],
            ["Apply and restart", ObjBindMethod(this, "SaveCascade"), 160],
            ["Cancel", ObjBindMethod(this, "CloseWindow", key), 100]], 290, 600)
        window.Show("w600 h340")
    }

    CascadeCompatibility(*) {
        if this.app.dryRun {
            MsgBox("Compatibility actions are inactive in the dry run.", SuiteApplication.Name, "Iconi")
            return
        }
        CheckCompatibilitySettings()
    }

    SaveCascade(*) {
        key := "settings:window-cascade"
        window := this.windows[key]
        try {
            this.app.Settings.WritePreferences("window-cascade", Map(
                "Controls", Map("AutoPlacementPaused", window["paused"].Value),
                "FocusTabs", Map("Visible", window["tabs"].Value,
                    "ActiveSlotColor", window["activeColor"].Text, "InactiveSlotColor", window["inactiveColor"].Text)))
            this.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Cascade Kingdom / settings")
    }

    ; =========================================================================
    ; Paper Pad: checked preference changes, never moving or deleting note files
    ; =========================================================================

    ShowPaperSettings(*) {
        key := "settings:scratchpad"
        if this.Existing(key)
            return
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        window := this.NewWindow(key, "Paper Pad - Settings", true)
        window.AddText("x20 y18 w740", "Changing the notes folder does not move or delete existing notes.")
        window.AddText("x20 y60 w150", "Notes folder")
        window.AddEdit("x180 y55 w590 vfolder", IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad"))
        window.AddText("x20 y105 w150", "Notepad3 executable")
        window.AddEdit("x180 y100 w590 veditor", IniRead(path, "Paths", "Notepad3Executable", ""))
        window.AddText("x180 y132 w590", "Leave the executable blank for automatic detection.")
        this.padMonitors := ["Primary"]
        names := ["Main display"]
        loop MonitorGetCount() {
            try {
                name := MonitorGetName(A_Index)
                MonitorGetWorkArea(A_Index)
                this.padMonitors.Push(name)
                names.Push("Display " A_Index " (" name ")")
            }
        }
        selected := IniRead(path, "Window", "Monitor", "Primary")
        selectedIndex := 0
        for index, name in this.padMonitors
            if name = selected
                selectedIndex := index
        if !selectedIndex {
            this.padMonitors.Push(selected)
            names.Push(selected " (unavailable)")
            selectedIndex := names.Length
        }
        window.AddText("x20 y180 w150", "Display")
        window.AddDropDownList("x180 y175 w380 vdisplay", names).Choose(selectedIndex)
        fields := [["width", "Width (%)", "Window", "WidthPercent", 45],
            ["height", "Height (%)", "Window", "HeightPercent", 35],
            ["animation", "Animation (ms)", "Window", "AnimationDurationMs", 180],
            ["autosave", "Autosave (ms)", "Saving", "AutosaveIntervalMs", 10000]]
        y := 225
        for item in fields {
            window.AddText("x20 y" (y + 5) " w150", item[2])
            window.AddEdit("x180 y" y " w140 v" item[1], IniRead(path, item[3], item[4], item[5]))
            y += 43
        }
        this.Footer(window, [["Open notes folder", ObjBindMethod(this, "OpenNotesFolder"), 165],
            ["Apply and restart", ObjBindMethod(this, "SavePaper"), 160],
            ["Cancel", ObjBindMethod(this, "CloseWindow", key), 100]], 435)
        window.Show("w800 h485")
    }

    NumberField(window, name, minimum, maximum) {
        text := Trim(window[name].Value)
        if !IsInteger(text) || Integer(text) < minimum || Integer(text) > maximum
            throw ValueError(name " must be an integer from " minimum " to " maximum ".")
        return Integer(text)
    }

    SavePaper(*) {
        global scratchpad
        key := "settings:scratchpad"
        window := this.windows[key]
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        try {
            folder := Trim(window["folder"].Value)
            editor := Trim(window["editor"].Value)
            if !RegExMatch(folder, "i)^(?:[a-z]:\\|\\\\)") || RegExMatch(folder, "[\r\n]")
                throw ValueError("Use an absolute Windows path for the notes folder.")
            if editor != "" && (!RegExMatch(editor, "i)^(?:[a-z]:\\|\\\\)") || !FileExist(editor))
                throw ValueError("Select an existing Notepad3 executable, or leave the field blank.")
            changes := Map("Paths", Map("ScratchDirectory", folder, "Notepad3Executable", editor),
                "Window", Map("Monitor", this.padMonitors[window["display"].Value],
                    "WidthPercent", this.NumberField(window, "width", 30, 100),
                    "HeightPercent", this.NumberField(window, "height", 20, 100),
                    "AnimationDurationMs", this.NumberField(window, "animation", 0, 1000)),
                "Saving", Map("AutosaveIntervalMs", this.NumberField(window, "autosave", 500, 60000)))
            pathsChanged := folder != IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad")
                || editor != IniRead(path, "Paths", "Notepad3Executable", "")
            if pathsChanged && this.app.scratchpadStarted && IsSet(scratchpad) {
                if MsgBox("Save and close the owned Notepad3 window before changing these paths?"
                    . "`nExisting notes remain where they are; no files will be moved or deleted.",
                    "Paper Pad", "YesNo Default2 Icon?") != "Yes"
                    return
                scratchpad.PrepareSuiteExit("Exit")
            }
            this.app.Settings.WritePreferences("scratchpad", changes)
            this.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Paper Pad / settings")
    }

    OpenNotesFolder(*) {
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        folder := IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad")
        if DirExist(folder)
            Run('explorer.exe "' folder '"')
        else
            MsgBox("The notes folder does not exist yet: " folder, "Paper Pad", "Iconi")
    }

    OpenPad(*) {
        global scratchpad
        if this.app.dryRun || !this.app.scratchpadStarted || !IsSet(scratchpad) {
            MsgBox("Enable Paper Pad and use a normal launch to open the editor.", SuiteApplication.Name, "Iconi")
            return
        }
        this.CloseWindow("help:scratchpad")
        scratchpad.QueueCommand("show")
    }

    ; =========================================================================
    ; Wonder Windows: explicit external compatibility actions, never startup writes
    ; =========================================================================

    ShowWonderSettings(*) {
        key := "settings:win-key-overhaul"
        if this.Existing(key)
            return
        window := this.NewWindow(key, "Wonder Windows - Settings", true)
        snap := WW_GetNativeWindowsSnapState()
        status := "Windows Snap: " (snap < 0 ? "unknown" : snap ? "on" : "off")
            . "`r`nScreenGrid: " (WW_IsScreenGridRunning() ? "running" : "not running")
            . "`r`nFancyZones: " (WW_IsFancyZonesRunning() ? "running" : "not running")
        window.AddText("x20 y20 w760", "Use one drag-snapping tool at a time. ScreenGrid is optional; FancyZones remains supported.")
        window.AddText("x20 y80 w760", status)
        window.AddText("x20 y180 w760", "Windows and PowerToys preferences are not changed at startup."
            . "`nThe actions below either open settings or ask for confirmation before applying changes."
            . "`nFancyZones owns its zone-window switching shortcuts; they are not registered twice here.")
        this.Footer(window, [["Windows Snap...", ObjBindMethod(this, "WonderAction", "snap"), 145],
            ["Disable Snap...", ObjBindMethod(this, "WonderAction", "disable"), 140],
            ["ScreenGrid...", ObjBindMethod(this, "WonderAction", "screengrid"), 125],
            ["FancyZones...", ObjBindMethod(this, "WonderAction", "fancyzones"), 135],
            ["Close", ObjBindMethod(this, "CloseWindow", key), 90]], 290)
        window.Show("w800 h340")
    }

    WonderAction(action, *) {
        if this.app.dryRun {
            MsgBox("Compatibility actions are inactive in the dry run.", SuiteApplication.Name, "Iconi")
            return
        }
        try {
            switch action {
                case "snap": WW_OpenWindowsSnapSettings()
                case "disable": WW_PromptToDisableNativeWindowsSnap()
                case "screengrid": WW_OpenScreenGridReleases()
                case "fancyzones": WW_CheckFancyZonesIntegration()
            }
        }
        catch Error as failure
            this.Report(failure, "Wonder Windows / compatibility")
    }

    ; =========================================================================
    ; Global logging and application preferences
    ; =========================================================================

    OpenLog(*) {
        if this.Existing("log") {
            this.RefreshLog()
            return
        }
        window := this.NewWindow("log", SuiteApplication.Name " - Debug log")
        verbose := window.AddCheckbox("x20 y18 w750 vverbose", "Verbose debugging for the whole application")
        verbose.Value := SuiteState.Log.verbose
        verbose.OnEvent("Click", ObjBindMethod(this, "SetVerbose"))
        window.AddText("x20 y50 w760", "Errors are always logged. Verbose diagnostics may include window titles and paths, not note or clipboard contents.")
        window.AddEdit("x20 y85 w760 h335 ReadOnly +VScroll vlog", SuiteState.Log.Read())
        this.Footer(window, [["Refresh", ObjBindMethod(this, "RefreshLog"), 100],
            ["Copy", ObjBindMethod(this, "CopyLog"), 100], ["Clear...", ObjBindMethod(this, "ClearLog"), 100],
            ["Open file", ObjBindMethod(this, "OpenLogFile"), 115],
            ["Close", ObjBindMethod(this, "CloseWindow", "log"), 100]], 455)
        window.Show("w800 h505")
    }

    SetVerbose(control, *) {
        try {
            this.app.Settings.Save(this.app.Settings.modules, this.app.Settings.layers, control.Value != 0)
            SuiteState.Log.verbose := control.Value != 0
            SuiteState.Log.Write("Core", "verbose debugging " (control.Value ? "enabled" : "disabled"))
            this.RefreshLog()
        }
        catch Error as failure {
            control.Value := SuiteState.Log.verbose
            this.Report(failure, "Core / logging preference")
        }
    }

    RefreshLog(*) {
        if this.windows.Has("log")
            this.windows["log"]["log"].Value := SuiteState.Log.Read()
    }

    CopyLog(*) {
        try A_Clipboard := SuiteState.Log.Read()
        catch Error as failure
            this.Report(failure, "Core / copy log")
    }

    ClearLog(*) {
        if MsgBox("Clear the current log? Its previous contents will be retained in debug.log.old.",
            SuiteApplication.Name, "YesNo Default2 Icon?") = "Yes" {
            SuiteState.Log.Clear()
            this.RefreshLog()
        }
    }

    OpenLogFile(*) {
        if !FileExist(SuiteState.Log.path)
            SuiteState.Log.Write("Core", "log opened")
        Run('notepad.exe "' SuiteState.Log.path '"')
    }

    ShowAppSettings(*) {
        key := "application-settings"
        if this.Existing(key)
            return
        window := this.NewWindow(key, SuiteApplication.Name " - App settings", true)
        window.AddText("x20 y20 w760", SuiteApplication.Name " " SuiteApplication.Version)
        startup := window.AddCheckbox("x20 y65 w760 vstartup", "Run Super Hotkey World at sign-in")
        startup.Value := !!FileExist(this.startupPath)
        startup.Enabled := !this.app.dryRun
        startup.OnEvent("Click", ObjBindMethod(this, "ToggleStartup"))
        window.AddText("x20 y115 w760", "One startup entry for the suite. Existing standalone startup entries are never changed automatically.")
        window.AddText("x20 y170 w760", "Settings: " this.app.Settings.directory)
        this.Footer(window, [["Open folder", (*) => Run('explorer.exe "' this.app.Settings.directory '"'), 120],
            ["Factory defaults...", ObjBindMethod(this, "FactoryDefaults"), 170],
            ["Reload", (*) => Reload(), 100],
            ["Close", ObjBindMethod(this, "CloseWindow", key), 100]], 260)
        window.Show("w800 h310")
    }

    ToggleStartup(control, *) {
        if this.app.dryRun
            return
        try {
            if control.Value {
                if A_IsCompiled
                    FileCreateShortcut(A_ScriptFullPath, this.startupPath, A_ScriptDir)
                else
                    FileCreateShortcut(A_AhkPath, this.startupPath, A_ScriptDir, '"' A_ScriptFullPath '"')
            } else if FileExist(this.startupPath)
                FileDelete(this.startupPath)
        }
        catch Error as failure {
            control.Value := !!FileExist(this.startupPath)
            this.Report(failure, "Core / startup preference")
        }
    }

    FactoryDefaults(*) {
        if MsgBox("Re-enable all five modules and both layers, and restore default shortcuts and preferences?"
            . "`n`nNotes, their folder, editor path, Notepad3 preferences and page state will be kept."
            . "`nA settings backup will be created. The suite will restart.",
            SuiteApplication.Name, "YesNo Default2 Icon?") != "Yes"
            return
        app := this.app
        root := app.Settings.directory
        backup := ""
        try {
            backup := app.Settings.Backup([app.Settings.path, app.manager.path,
                root "\window-cascade\settings.ini", root "\scratchpad\settings.ini"])
            app.manager.Apply(app.manager._DefaultConfiguration())
            choices := Map()
            for id in SuiteSettings.ModuleOrder
                choices[id] := true
            app.Settings.Save(choices, Map("caps", true, "pause", true), false)
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
