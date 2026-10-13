class ScratchpadMigration {
    BuildTrayMenu() {
        moduleMenu := SuiteState.ScratchpadMenu
        moduleMenu.Delete()
        moduleMenu.Add("Toggle Scratchpad", ObjBindMethod(this, "QueueCommand", "toggle"))
        moduleMenu.Add("Keybindings", (*) => SuiteState.App.ShowKeybindings())
        moduleMenu.Add()
        this.monitor_menu := Menu()
        this.BuildMonitorMenu()
        moduleMenu.Add("Display", this.monitor_menu)
        this.window_width_menu := Menu()
        for percent in this.window_width_presets
            this.window_width_menu.Add(percent "%", ObjBindMethod(this, "SetWindowSizePercent", "width", percent))
        this.window_height_menu := Menu()
        for percent in this.window_height_presets
            this.window_height_menu.Add(percent "%", ObjBindMethod(this, "SetWindowSizePercent", "height", percent))
        moduleMenu.Add("Window width", this.window_width_menu)
        moduleMenu.Add("Window height", this.window_height_menu)
        moduleMenu.Add()
        moduleMenu.Add("Open scratch folder", (*) => Run('explorer.exe "' this.scratch_directory '"'))
        moduleMenu.Add("Open settings", (*) => Run('notepad.exe "' this.settings_path '"'))
        moduleMenu.Add("How to use", ObjBindMethod(this, "ShowHelp"))
        this.UpdateTrayChecks()
    }

    UpdateTrayChecks() {
        this.UpdateMonitorMenu()
        this.UpdateWindowSizeMenu()
    }

    ShowHelp(*) {
        MsgBox("Open Keybindings for the current global toggle and editor-only shortcuts."
            . "`nRight-click a shortcut to enter a key name, including Escape."
            . "`n`nPages are ordinary files. New pages use timestamped names."
            . "`nSave As can rename a page inside the scratch folder."
            . "`nUndo survives hiding and suite reloads, but not switching pages."
            . "`n`nSaves are checked before hiding, switching, reloading or exiting."
            . "`nA disk conflict stops automatic overwriting."
            . "`n`nScratch folder: " this.scratch_directory,
            "Scratchpad", "Iconi")
    }

    PrepareSuiteExit(reason) {
        if this.busy || this.command_queue.Length
            throw Error("Scratchpad is finishing a command. Retry the suite exit or restart afterwards.")
        if this.HasWindow() || this.AttachExistingWindow() {
            this.SaveCurrentPage()
            if reason != "Reload" && reason != "Single" && reason != "Shutdown" && reason != "Logoff" {
                target := this.window_hwnd
                PostMessage(0x0010, 0, 0, , "ahk_id " target)
                if !WinWaitClose("ahk_id " target, , 5)
                    throw Error("Notepad3 has not closed. Resolve its dialog, then retry.")
                this.window_hwnd := 0
                this.editor_pid := 0
                this.bridge := 0
            }
        }
        this.exit_prepared := true
    }
}
