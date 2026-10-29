; Paper Pad: hotkeys, lifecycle, settings page and guide. The Notepad3
; controller is the global paperPad while the module runs.
class PaperPadModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Window"]

    __New(app) {
        super.__New(app, "paper-pad")
        this.manager := 0
        this.displayChoices := []
        this.settingsPath := app.Settings.directory "\paper-pad\settings.ini"
    }

    ; Registration order is the Keybindings display order. Page commands use
    ; the editor scope, so they never take Win + arrows from other windows.
    Register(manager) {
        this.manager := manager
        manager.AddAction("paper-pad.help", "show Paper Pad help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Pause + F12"],
            {category: "Paper Pad", available: ObjBindMethod(this, "Available")})
        manager.AddAction("paper-pad.toggle", "show / hide Paper Pad", ObjBindMethod(this, "Event", "toggle"),
            ["Win + F12"], {category: "Paper Pad", available: ObjBindMethod(this, "Available")})
        ; Showing and hiding, then page navigation, then the destructive delete.
        for item in [
            ["hide", "hide Paper Pad / dismiss completion", ["Escape"]],
            ["previous", "previous page", ["Win + Left", "Win + PgDn"]],
            ["next", "next page", ["Win + Right", "Win + PgUp"]],
            ["delete", "move page to Recycle Bin", ["Win + F4"]]
        ]
            manager.AddAction("paper-pad." item[1], item[2], ObjBindMethod(this, "Event", item[1]), item[3],
                {category: "Paper Pad", available: ObjBindMethod(this, "Available"),
                    scope: "paper-pad", context: PaperPadEditorFocused})
    }

    Available(*) => this.app.ModuleActive(this.id)

    Start() {
        global paperPad
        paperPad := PaperPadController(this.app.Settings.directory "\paper-pad")
        this.manager.Observe("~#.", PaperPadEditorFocused,
            (*) => paperPad.NoteSystemTextInputInvocation())
        pending := (*) => IsSet(paperPad) && paperPad.SystemTextInputEscapePending()
        for key in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
            this.manager.Observe("~" key " Up", pending, (*) => paperPad.HandleSystemTextInputClick())
    }

    PrepareExit(reason) {
        global paperPad
        if IsSet(paperPad) && IsObject(paperPad)
            paperPad.PrepareSuiteExit(reason)
    }

    Stop(reason := "Exit", code := 0) {
        global paperPad
        if IsSet(paperPad) && IsObject(paperPad)
            paperPad.OnScriptExit(reason, code)
    }

    Event(command, event) {
        if event.phase != "down"
            return
        if this.app.dryRun {
            SuiteState.Log.Write("Paper Pad", "dry run: " command)
            return
        }
        this.app.QueueInput(ObjBindMethod(this, "Execute", command, event.foregroundHwnd))
    }

    Execute(command, foreground, *) {
        global paperPad
        if !this.Available() || !IsSet(paperPad) || this.app.stopping
            return
        if command != "toggle" && (!PaperPadEditorFocused() || foreground != paperPad.window_hwnd)
            return
        if command = "hide" {
            if paperPad.SystemTextInputEscapePending() {
                paperPad.ConsumeSystemTextInputEscape()
                Send "{Escape}"
            } else
                paperPad.HandleEscape(this.app.inputGeneration)
        } else
            paperPad.QueueCommand(command, this.app.inputGeneration)
    }

    HelpButtons() => [["Open pad", ObjBindMethod(this, "OpenPad"), 110]]

    OpenPad(*) {
        global paperPad
        if this.app.dryRun || !this.started || !IsSet(paperPad) {
            MsgBox("Enable Paper Pad and use a normal launch to open the editor.", SuiteApplication.Name, "Iconi")
            return
        }
        this.app.ui.CloseWindow("help:paper-pad")
        paperPad.QueueCommand("show")
    }

    ; Path changes never move or delete notes; they take effect after a restart.
    ShowSettings(ui) {
        key := "settings:paper-pad"
        if ui.Existing(key)
            return
        path := this.settingsPath
        window := ui.NewWindow(key, "Paper Pad - Settings", true)
        window.AddText("x20 y18 w740", "Changing the notes folder does not move or delete existing notes.")
        window.AddText("x20 y60 w150", "Notes folder")
        window.AddEdit("x180 y55 w590 vfolder", IniRead(path, "Paths", "NotesDirectory",
            PaperPadController.DefaultNotesDirectory))
        window.AddText("x20 y105 w150", "Notepad3 executable")
        window.AddEdit("x180 y100 w590 veditor", IniRead(path, "Paths", "Notepad3Executable", ""))
        window.AddText("x180 y132 w590", "Leave the executable blank for automatic detection.")
        choices := ui.DisplayChoices(IniRead(path, "Window", "Monitor", "Primary"))
        this.displayChoices := choices.values
        window.AddText("x20 y180 w150", "Display")
        window.AddDropDownList("x180 y175 w380 vdisplay", choices.names).Choose(choices.selected)
        y := 225
        for item in [["width", "Width (%)", "WidthPercent"], ["height", "Height (%)", "HeightPercent"]] {
            window.AddText("x20 y" (y + 5) " w150", item[2])
            window.AddEdit("x180 y" y " w140 v" item[1],
                IniRead(path, "Window", item[3], PaperPadController.WindowDefaults[item[3]][1]))
            y += 43
        }
        ui.Footer(window, [["Open notes folder", ObjBindMethod(this, "OpenNotesFolder"), 165],
            ["Apply and restart", ObjBindMethod(this, "SaveSettings", ui), 160],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]], 349)
        ui.ShowPage(key, 800, 399, 760, 374)
    }

    SaveSettings(ui, *) {
        global paperPad
        key := "settings:paper-pad"
        window := ui.windows[key]
        path := this.settingsPath
        try {
            folder := Trim(window["folder"].Value)
            editor := Trim(window["editor"].Value)
            if !RegExMatch(folder, "i)^(?:[a-z]:\\|\\\\)") || RegExMatch(folder, "[\r\n]")
                throw ValueError("Use an absolute Windows path for the notes folder.")
            if editor != "" && (!RegExMatch(editor, "i)^(?:[a-z]:\\|\\\\)") || !FileExist(editor))
                throw ValueError("Select an existing Notepad3 executable, or leave the field blank.")
            sizes := PaperPadController.WindowDefaults
            changes := Map("Paths", Map("NotesDirectory", folder, "Notepad3Executable", editor),
                "Window", Map("Monitor", this.displayChoices[window["display"].Value],
                    "WidthPercent", ui.NumberField(window, "width",
                        sizes["WidthPercent"][2], sizes["WidthPercent"][3]),
                    "HeightPercent", ui.NumberField(window, "height",
                        sizes["HeightPercent"][2], sizes["HeightPercent"][3])))
            pathsChanged := folder != IniRead(path, "Paths", "NotesDirectory", PaperPadController.DefaultNotesDirectory)
                || editor != IniRead(path, "Paths", "Notepad3Executable", "")
            if pathsChanged && this.started && IsSet(paperPad) {
                editorOpen := paperPad.HasWindow() || paperPad.AttachExistingWindow()
                if editorOpen && MsgBox("Changing these paths requires saving and closing the Paper Pad editor."
                    . "`n`nExisting notes will not be moved or deleted.",
                    "Paper Pad", "OKCancel Default2 Icon?") != "OK"
                    return
                paperPad.PrepareSuiteExit("Exit")
            }
            this.app.Settings.WritePreferences(this.id, changes)
            ui.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            ui.Report(failure, "Paper Pad / settings")
    }

    OpenNotesFolder(*) {
        folder := IniRead(this.settingsPath, "Paths", "NotesDirectory", PaperPadController.DefaultNotesDirectory)
        if DirExist(folder)
            Run('"' A_WinDir '\explorer.exe" "' folder '"')
        else
            MsgBox("The notes folder does not exist yet: " folder, "Paper Pad", "Iconi")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nI wanted a place to quickly jot down anything, anytime, without "
            . "worrying about saving files or finding notes buried in windows and tabs. "
            . "Something I could open and hide instantly, easily switch between notes, "
            . "and keep my ideas organized and separate from the clutter of everyday project work."
            . "`r`n`r`nYOUR OWN QUICK-NOTES DRAWER"
            . "`r`nPaper Pad opens a dedicated Notepad3 window without taking over your "
            . "ordinary editor sessions. Use Open pad below or the configurable toggle "
            . "hotkey. Notepad3's Ctrl + N creates a timestamped page automatically. "
            . "Page navigation shortcuts work only inside the editor."
            . "`r`n`r`nPAGES ARE REAL FILES"
            . "`r`nNew pages receive timestamped filenames. They remain ordinary files "
            . "in your notes folder, and Save As can rename a page within that folder. "
            . "If you type before a native New is attached, use Save As to preserve it. "
            . "Hiding Paper Pad preserves undo history, but switching pages clears it. "
            . "You can still inspect and back up these files in an ordinary file manager."
            . "`r`n`r`nSAVING AND RELOADING"
            . "`r`nPaper Pad automatically saves changes when switching pages, hiding or exiting. "
            . "Settings lets you choose your Notepad3 executable, notes folder, display "
            . "and drawer size. Changing paths never moves existing notes. "
            . "Notepad3 controls external-file reloads, which may replace unsaved text."
    }
}
