; Preserved Notepad3 controller; shared shortcuts, logging and save-aware suite lifecycle.

class PaperPadController
{
    static AutosaveIdleMs := 1000
    static AutosaveMaxMs := 10000
    static AutosavePollMs := 500
    ; [Window] size preferences: default, minimum and maximum.
    static WindowDefaults := Map("WidthPercent", [45, 30, 100], "HeightPercent", [35, 20, 100])
    ; The drawer slides this long unless Windows' Animation effects are off.
    static AnimationMs := 180
    static DefaultNotesDirectory => EnvGet("USERPROFILE") "\Paper Pad"

    ; =========================================================================
    ; configuration and serialized commands
    ; =========================================================================

    __New(dataDirectory)
    {
        this.window_hwnd := 0
        this.editor_pid := 0
        this.bridge := 0
        this.busy := false
        this.autosave_paused := false
        this.untitled_notice_shown := false
        this.last_verified_save_tick := A_TickCount
        this.last_autosave_attempt_tick := A_TickCount - PaperPadController.AutosaveIdleMs
        this.autosave_tracking := {sampled: false, text: "", last_change: 0}
        this.exit_prepared := false
        this.command_queue := []
        this.page_views := Map()
        this.page_views.CaseSense := "Off"
        this.current_path := ""
        this.disk_stamp := ""
        this.persisted_path := ""
        this.persisted_stamp := ""
        this.previous_window := 0
        this.last_external_window := 0
        this.z_order_snapshot := ""
        this.system_text_input_escape_pending := false
        this.last_bounds := 0
        this.window_marker := "nroj.PaperPad.Notepad3Window"
        this.cascade_ignore_marker := "nroj.SuperHotkey.CascadeIgnore"
        this.data_directory := dataDirectory
        this.settings_path := this.data_directory "\settings.ini"
        this.state_path := this.data_directory "\state.ini"
        this.editor_profile := this.data_directory "\Notepad3.ini"
        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
        this.autosave_callback := ObjBindMethod(this, "Autosave")
        this.watch_callback := ObjBindMethod(this, "WatchEditor")

        DirCreate this.data_directory
        default_notes_directory := PaperPadController.DefaultNotesDirectory
        this.CreateDefaultSettings(default_notes_directory)
        this.notes_directory := RTrim(IniRead(this.settings_path, "Paths",
            "NotesDirectory", default_notes_directory), "\/")
        if !RegExMatch(this.notes_directory, "i)^(?:[a-z]:\\|\\\\)")
            throw Error("NotesDirectory must be an absolute Windows path.")
        DirCreate this.notes_directory
        ; Resolve . and .. before enforcing the direct-child page boundary.
        this.notes_directory := RTrim(PaperPadFullPath(this.notes_directory), "\/")
        this.monitor_target := this.ReadMonitorTarget()
        sizes := PaperPadController.WindowDefaults
        this.width_percent := this.ReadNumber("Window", "WidthPercent", sizes["WidthPercent"]*)
        this.height_percent := this.ReadNumber("Window", "HeightPercent", sizes["HeightPercent"]*)
        this.allowed_extensions := "|md|txt|ps1|psm1|psd1|py|pyw|ahk|lua|js|ts|jsx|tsx|"
            . "json|jsonc|yaml|yml|xml|html|htm|css|scss|ini|cfg|conf|toml|log|"
            . "sh|bash|bat|cmd|sql|c|cpp|h|hpp|cs|rs|go|java|rb|php|csv|tsv|"

        ; Hidden owner/sender window for WM_COPYDATA page switches.
        this.controller_window := SuiteGui("+ToolWindow", "nroj.PaperPad.Controller")

        ; Reattach the retained editor immediately after Reload, even while
        ; hidden. A fresh controller must not wait for the next hotkey.
        try this.AttachExistingWindow()
        catch as failure {
            this.autosave_paused := true
            this.ReportError(failure, true)
        }
        SetTimer this.autosave_callback, PaperPadController.AutosavePollMs
        SetTimer this.watch_callback, 250
    }

    CreateDefaultSettings(default_notes_directory)
    {
        if !FileExist(this.settings_path) {
            sizes := PaperPadController.WindowDefaults
            settings := "[Paths]`nNotesDirectory=" default_notes_directory
                . "`nNotepad3Executable=`n"
                . "`n[Window]`nMonitor=Primary"
                . "`nWidthPercent=" sizes["WidthPercent"][1]
                . "`nHeightPercent=" sizes["HeightPercent"][1] "`n"
                . "`n[Setup]`nWelcomePending=1`n"
            FileAppend settings, this.settings_path, "UTF-16"
        }
        if IniRead(this.settings_path, "Paths", "Notepad3Executable", "<missing>") = "<missing>"
            IniWrite "", this.settings_path, "Paths", "Notepad3Executable"
        if IniRead(this.settings_path, "Window", "Monitor", "<missing>") = "<missing>"
            IniWrite "Primary", this.settings_path, "Window", "Monitor"

        ; Normalize line endings to CRLF for Notepad3 compatibility.
        original_settings := FileRead(this.settings_path, "UTF-16")
        settings := StrReplace(original_settings, "`r`n", "`n")
        settings := StrReplace(settings, "`r", "`n")
        settings := StrReplace(settings, "`n", "`r`n")
        if settings != original_settings {
            settings_file := FileOpen(this.settings_path, "w", "UTF-16")
            if !settings_file
                throw Error("Could not normalize settings.ini.")
            try settings_file.Write(settings)
            finally settings_file.Close()
        }

        ; Notepad3 owns this UTF-8 INI. Never rewrite its existing preferences.
        if !FileExist(this.editor_profile)
            FileAppend "[Notepad3]`n`n[Settings]`nSettingsVersion=5`n", this.editor_profile, "UTF-8-RAW"
    }

    ReadMonitorTarget()
    {
        target := Trim(IniRead(this.settings_path, "Window", "Monitor", "Primary"))
        if target = "" || StrLower(target) = "primary"
            return "Primary"

        ; Explicit display choices are stored by Windows device name so the
        ; selection remains pinned instead of following whichever display is main.
        if RegExMatch(target, "i)^\\\\\.\\DISPLAY\d+$")
            return target

        return "Primary"
    }

    ReadNumber(section, key, fallback, minimum, maximum)
    {
        value := IniRead(this.settings_path, section, key, fallback)
        if !IsNumber(value)
            return fallback
        return Min(maximum, Max(minimum, Round(value)))
    }

    NoteSystemTextInputInvocation()
    {
        this.system_text_input_escape_pending := true
    }

    SystemTextInputEscapePending()
    {
        return this.system_text_input_escape_pending
    }

    ConsumeSystemTextInputEscape()
    {
        this.system_text_input_escape_pending := false
    }

    HandleSystemTextInputClick()
    {
        if !this.system_text_input_escape_pending
            return

        point := Buffer(8, 0)
        if !DllCall("GetCursorPos", "ptr", point, "int") {
            this.ConsumeSystemTextInputEscape()
            return
        }

        point_value := NumGet(point, 0, "int64")
        clicked_hwnd := DllCall(
            "WindowFromPoint",
            "int64", point_value,
            "ptr"
        )

        if !clicked_hwnd {
            this.ConsumeSystemTextInputEscape()
            return
        }

        ; The Windows emoji picker exposes its interactive surface under the
        ; pointer as TextInputHost / Windows.UI.Core.CoreWindow. Clicks there
        ; keep the picker session alive; any click elsewhere dismisses it.
        try {
            process_name := WinGetProcessName("ahk_id " clicked_hwnd)
            window_class := WinGetClass("ahk_id " clicked_hwnd)
        }
        catch {
            process_name := ""
            window_class := ""
        }

        if StrLower(process_name) != "textinputhost.exe"
            || window_class != "Windows.UI.Core.CoreWindow"
        {
            this.ConsumeSystemTextInputEscape()
        }
    }

    QueueCommand(command, inputGeneration := -1, *)
    {
        ; Hiding or toggling the drawer ends any outstanding Windows text-input
        ; session so it cannot affect Escape after PaperPad is reopened.
        if command = "hide" || command = "toggle"
            this.ConsumeSystemTextInputEscape()
        if this.command_queue.Length >= 8
            return
        this.command_queue.Push({name: command, source_window: WinExist("A"),
            inputGeneration: IsInteger(inputGeneration) ? inputGeneration : -1})
        SetTimer this.process_commands_callback, -1
    }

    ProcessCommands(*)
    {
        if this.busy
            return
        this.busy := true
        try {
            while this.command_queue.Length {
                request := this.command_queue.RemoveAt(1)
                ; Only hotkey requests expire. Autosave and direct UI operations stay available.
                if request.inputGeneration >= 0 && !SuiteState.App.InputIsCurrent(request.inputGeneration)
                    continue
                try this.ExecuteCommand(request)
                catch as failure {
                    this.command_queue := []
                    this.autosave_paused := true
                    this.RevealAfterError(request.source_window)
                    this.ReportError(failure)
                }
            }
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    ExecuteCommand(request)
    {
        if request.name = "hide" {
            if this.HasWindow() && this.IsVisible()
                this.HideWindow()
            return
        }
        if request.name = "delete" {
            if this.HasWindow()
                this.DeleteCurrentPage()
            return
        }
        was_visible := this.IsVisible()
        this.EnsureWindow(request.source_window)
        if request.name = "toggle" && was_visible {
            this.HideWindow()
            return
        }
        this.ShowWindow(request.source_window)
        switch request.name {
            case "previous", "next":
                ; Resolve native Save As/Open before finding our place in the
                ; list. SwitchPage owns the one checked save before loading.
                this.CheckCurrentPage()
                pages := this.ListPages()
                current_index := 0
                for index, path in pages {
                    if path = this.current_path {
                        current_index := index
                        break
                    }
                }
                if !current_index
                    throw Error("The current file is no longer in the notes folder. Resolve its move or rename in Notepad3 first.")
                direction := request.name = "next" ? 1 : -1
                next_index := Mod(current_index - 1 + direction + pages.Length, pages.Length) + 1
                this.SwitchPage(pages[next_index])
        }
    }

    ; =========================================================================
    ; editor ownership, startup and reattachment
    ; =========================================================================

    HasWindow()
    {
        if !this.window_hwnd || !DllCall("IsWindow", "ptr", this.window_hwnd, "int")
            || !DllCall("GetPropW", "ptr", this.window_hwnd, "str", this.window_marker, "ptr")
            return false
        try return WinGetPID("ahk_id " this.window_hwnd) = this.editor_pid
        catch
            return false
    }

    IsVisible()
    {
        return this.HasWindow()
            && DllCall("IsWindowVisible", "ptr", this.window_hwnd, "int")
            && !DllCall("IsIconic", "ptr", this.window_hwnd, "int")
    }

    MarkWindow(hwnd)
    {
        ; Opt out before making it visible or performing slow editor queries.
        if !DllCall("SetPropW", "ptr", hwnd, "str", this.cascade_ignore_marker, "ptr", 1, "int")
            throw OSError(A_LastError, "SetPropW", "Could not opt out of Cascade Kingdom.")
        if !DllCall("SetPropW", "ptr", hwnd, "str", this.window_marker, "ptr", 1, "int")
            throw OSError(A_LastError, "SetPropW", "Could not mark the Paper Pad editor.")
    }

    AttachExistingWindow()
    {
        for candidate in WinGetList("ahk_exe Notepad3.exe") {
            if !DllCall("GetPropW", "ptr", candidate, "str", this.window_marker, "ptr")
                continue
            this.window_hwnd := candidate
            this.editor_pid := WinGetPID("ahk_id " candidate)
            this.MarkWindow(candidate)
            this.ConnectBridge()
            path := this.bridge.CurrentPath()
            saved_path := IniRead(this.state_path, "CurrentPage", "Path", "")
            this.current_path := path
            ; Keep the old disk stamp on reattach: reload must not bless a conflict.
            this.disk_stamp := path = saved_path
                ? IniRead(this.state_path, "CurrentPage", "DiskStamp", "") : ""

            this.bridge.PrepareDrawer()
            ; A visible drawer is always topmost; a retained hidden editor is not.
            this.SetDrawerTopmost(this.IsVisible())
            return true
        }
        return false
    }

    EnsureWindow(source_window)
    {
        if this.HasWindow() {
            if !this.bridge || this.bridge.tainted
                this.ConnectBridge()
            return false
        }
        this.window_hwnd := 0
        this.editor_pid := 0
        this.bridge := 0
        if this.AttachExistingWindow()
            return false

        executable := this.FindNotepad3Executable()
        initial_path := IniRead(this.state_path, "CurrentPage", "Path", "")
        new_page := false
        welcome_pending := IniRead(
            this.settings_path,
            "Setup",
            "WelcomePending",
            "0"
        ) = "1"

        initial_attributes := initial_path != "" ? FileExist(initial_path) : ""
        if !this.IsNotePath(initial_path) || !initial_attributes || InStr(initial_attributes, "D") {
            pages := this.ListPages()

            if pages.Length
                initial_path := pages[pages.Length]
            else {
                initial_path := this.CreatePage()

                if welcome_pending
                    FileAppend this.WelcomeText(), initial_path, "UTF-8-RAW"

                new_page := true
            }
        }

        ; Welcome is a first-install opportunity, not a recurring empty-folder state.
        if welcome_pending
            IniWrite 0, this.settings_path, "Setup", "WelcomePending"
        initial_path := PaperPadFullPath(initial_path)
        before_load_stamp := PaperPadFileStamp(initial_path)
        ; /n isolates the editor process; /f isolates settings.
        ; /l enables read-only log monitoring, so use normal file watching.
        command_line := '"' executable '" /n /f "' this.editor_profile
            . '" "' initial_path '"'
        Run command_line, this.notes_directory, "Hide", &editor_pid
        this.editor_pid := editor_pid
        deadline := A_TickCount + 12000
        loop {
            candidate := 0
            for hwnd in WinGetList("ahk_pid " editor_pid) {
                if DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB03, "ptr")
                    && DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB05, "ptr") {
                    candidate := hwnd
                    break
                }
            }
            if candidate {
                this.window_hwnd := candidate
                this.MarkWindow(candidate)
                WinHide "ahk_id " candidate
                break
            }
            if A_TickCount >= deadline || !ProcessExist(editor_pid)
                throw Error("Notepad3 did not create a ready editor. Check for a startup dialog, then retry.")
            Sleep 10
        }
        this.ConnectBridge()
        ; A window/control can exist before its initial document has finished loading.
        loop {
            if this.bridge.CurrentPath() = initial_path
                break
            if A_TickCount >= deadline
                throw Error("Notepad3 did not open the requested page. No editor was closed.")
            Sleep 30
        }
        WinHide "ahk_id " this.window_hwnd
        this.current_path := initial_path
        this.disk_stamp := before_load_stamp
        this.bridge.PrepareDrawer()
        this.last_bounds := this.GetBounds()
        this.PersistCurrentState()
        if new_page
            this.ConfigureNewPage()
        ; A newly launched editor starts a new save session. A failure in a
        ; previously closed editor must not leave this one silently paused.
        this.autosave_paused := false
        return new_page
    }

    ConnectBridge()
    {
        if !this.HasWindow()
            throw Error("The dedicated Notepad3 window has closed. Try the command again.")
        this.bridge := Notepad3Bridge(this.window_hwnd)
    }

    FindNotepad3Executable()
    {
        configured := IniRead(this.settings_path, "Paths", "Notepad3Executable", "")
        if configured != "" {
            SplitPath configured, &file_name
            if !FileExist(configured) || StrLower(file_name) != "notepad3.exe"
                throw Error("Notepad3Executable must point to Notepad3.exe:`n" configured
                    . "`n`nCorrect it in Paper Pad settings, then reload.")
            return configured
        }

        if executable := this.FindInstalledNotepad3()
            return executable

        ; Installing software is the user's step, never Paper Pad's.
        choice := MsgBox(
            "Paper Pad needs Notepad3, and it was not found.`n`n"
                . "Install it, for example with:`n"
                . "winget install Rizonesoft.Notepad3`n`n"
                . "Then choose OK to continue or locate Notepad3.exe.",
            "Paper Pad setup",
            "OKCancel Iconi 4096"
        )
        if choice != "OK"
            throw Error("Notepad3 is required to use Paper Pad.")

        if executable := this.FindInstalledNotepad3()
            return executable
        return this.SelectNotepad3Executable()
    }

    FindInstalledNotepad3()
    {
        candidates := []

        for root in ["HKCU", "HKLM"] {
            try candidates.Push(
                RegRead(root "\Software\Microsoft\Windows\CurrentVersion\App Paths\Notepad3.exe")
            )
        }

        for variable in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
            directory := EnvGet(variable)
            if directory != ""
                candidates.Push(directory "\Notepad3\Notepad3.exe")
        }

        for hwnd in WinGetList("ahk_exe Notepad3.exe") {
            try candidates.Push(WinGetProcessPath("ahk_id " hwnd))
        }

        for candidate in candidates {
            if !FileExist(candidate)
                continue
            SplitPath candidate, &file_name
            if StrLower(file_name) = "notepad3.exe"
                return candidate
        }

        return ""
    }

    SelectNotepad3Executable()
    {
        selected := FileSelect(
            1,
            ,
            "Locate Notepad3.exe (installed or portable)",
            "Notepad3 (Notepad3.exe)"
        )

        if selected = ""
            throw Error("Notepad3 is required to use Paper Pad.")

        SplitPath selected, &file_name
        if StrLower(file_name) != "notepad3.exe"
            throw Error("Select Notepad3.exe, not its installer or a shortcut.")

        IniWrite selected, this.settings_path, "Paths", "Notepad3Executable"
        return selected
    }

    ; =========================================================================
    ; persistent pages, checked saves and in-place switching
    ; =========================================================================

    IsNotePath(path)
    {
        if path = ""
            return false
        try path := PaperPadFullPath(path)
        catch
            return false
        SplitPath path, , &directory, &extension
        return RTrim(directory, "\/") = this.notes_directory
            && InStr(this.allowed_extensions, "|" StrLower(extension) "|")
    }

    ListPages()
    {
        sortable_pages := ""
        Loop Files this.notes_directory "\*", "F" {
            if this.IsNotePath(A_LoopFileFullPath)
                sortable_pages .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"
        }
        pages := []
        ; Creation time is stable when a page is renamed; names break time ties.
        Loop Parse Sort(sortable_pages), "`n", "`r" {
            if A_LoopField != ""
                pages.Push(this.notes_directory "\" SubStr(A_LoopField, 16))
        }
        return pages
    }

    CreatePage()
    {
        base_name := "paper-pad-" FormatTime(, "yyyyMMdd-HHmmss")
        loop {
            suffix := A_Index = 1 ? "" : "-" Format("{:02}", A_Index)
            path := this.notes_directory "\" base_name suffix ".md"
            ; CREATE_NEW is atomic: even rapid presses cannot overwrite a page.
            file_handle := DllCall("CreateFileW", "str", path, "uint", 0x40000000,
                "uint", 7, "ptr", 0, "uint", 1, "uint", 0x80, "ptr", 0, "ptr")
            if file_handle != -1 {
                DllCall("CloseHandle", "ptr", file_handle)
                return path
            }
            file_error := A_LastError
            if file_error != 80 && file_error != 183
                throw OSError(file_error, "CreateFileW", path)
        }
    }

    WatchEditor(*)
    {
        if this.busy || !this.IsVisible()
            return

        ; Serialize the whole watcher, including Z-order. A hotkey must not hide
        ; or replace the editor halfway through this timer's window operations.
        this.busy := true
        try {
            ; Reuse this watcher for Z-order without another permanent timer.
            try this.SyncZOrder()

            ; Reconcile native File > New and File > Save As without another timer.
            if !this.bridge || this.bridge.tainted
                return
            if !PaperPadWindowIdle(this.window_hwnd)
                return

            path := this.bridge.CurrentPath()
            if path = "" {
                this.AdoptNativeNew()
                return
            }
            this.untitled_notice_shown := false
            ; Native Save As can recover under a different supported page path.
            if this.autosave_paused && this.IsNotePath(path)
                path := this.CheckCurrentPage()
            ; A clean native Save or reload can resume a previously paused autosave.
            this.ResumeAutosaveAfterCleanNativeSave(path)
        }
        catch {
            ; Native dialogs and transient filename changes are retried on the
            ; next tick. Normal PaperPad commands still report real failures.
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    static UntitledHasEdits(dirty, text) => !!dirty || text != ""

    AdoptNativeNew()
    {
        if this.bridge.CurrentPath() != ""
            return false

        ; Never replace a native untitled buffer that already contains user text.
        if PaperPadController.UntitledHasEdits(this.bridge.IsDirty(), this.bridge.DocumentText()) {
            if !this.untitled_notice_shown {
                this.untitled_notice_shown := true
                TrayTip "Save this untitled document using File > Save As inside:`n"
                    . this.notes_directory, "Paper Pad - unsaved page", 2
            }
            return false
        }

        path := this.CreatePage()
        try this.bridge.OpenPage(path, this.controller_window.Hwnd)
        catch as failure {
            ; A failed native open must not create another orphan on every tick.
            try {
                if this.bridge.CurrentPath() != path && FileGetSize(path) = 0
                    FileDelete path
            }
            throw failure
        }
        this.current_path := path
        this.disk_stamp := PaperPadFileStamp(path)
        this.PersistCurrentState()
        this.ConfigureNewPage()
        this.untitled_notice_shown := false
        SuiteState.Log.Debug("Paper Pad", "adopted native New as " path)
        return true
    }

    WelcomeText() {
        return "# Welcome to Paper Pad`n`n"
            . "Open Paper Pad from the Super Hotkey tray for instructions.`n"
            . "Use Keybindings to see and change the current shortcuts.`n`n"
            . "Your pages are ordinary files. Start typing below.`n`n"
    }

    CheckCurrentPage()
    {
        if !this.HasWindow()
            throw Error("The Paper Pad editor has closed.")
        if !this.bridge || this.bridge.tainted
            this.ConnectBridge()
        this.bridge.CheckReady()
        path := this.bridge.CurrentPath()
        if path = ""
            throw Error("An untitled document is not yet a saved Paper Pad page. "
                . "Use File > Save As inside:`n" this.notes_directory
                . "`n`nUnsaved text has been preserved.")
        if !this.IsNotePath(path)
            throw Error("The editor is not showing a supported file directly inside:`n"
                . this.notes_directory "`n`nReturn to a Paper Pad page or use File > Save As. Unrelated files will not be saved or closed automatically.")
        attributes := FileExist(path)
        if !attributes
            throw Error("The active page unexpectedly disappeared from disk:`n" path)
        if InStr(attributes, "D")
            throw Error("The open page path now refers to a directory:`n" path)

        if path != this.current_path {
            ; Notepad3's path control follows native Open, Rename and Save As.
            ; Accept the user's explicit document change; subsequent disk changes
            ; are checked against this new baseline.
            this.current_path := path
            this.disk_stamp := PaperPadFileStamp(path)
        }
        return path
    }

    PersistCurrentState()
    {
        if this.current_path = this.persisted_path && this.disk_stamp = this.persisted_stamp
            return
        IniWrite "Path=" this.current_path "`nDiskStamp=" this.disk_stamp,
            this.state_path, "CurrentPage"
        this.persisted_path := this.current_path
        this.persisted_stamp := this.disk_stamp
    }

    ResumeAutosaveAfterCleanNativeSave(path)
    {
        if !this.autosave_paused || path != this.current_path || !FileExist(path)
            return false
        ; Check the editor before and after the comparison, and the file around it.
        stamp := PaperPadFileStamp(path)
        if this.bridge.IsDirty() || !this.bridge.MatchesDisk(path)
            || this.bridge.IsDirty() || PaperPadFileStamp(path) != stamp
            return false

        this.disk_stamp := stamp
        this.PersistCurrentState()
        this.last_verified_save_tick := A_TickCount
        this.autosave_tracking.sampled := false
        this.autosave_tracking.text := ""
        this.autosave_tracking.last_change := 0
        this.autosave_paused := false
        SuiteState.Log.Debug("Paper Pad", "Resumed autosave after native Save or reload.")
        return true
    }

    SaveCurrentPage(require_clean := true)
    {
        ; Handle an immediate toggle before the normal 250 ms watcher fires.
        if this.bridge && !this.bridge.tainted && this.bridge.CurrentPath() = ""
            this.AdoptNativeNew()
        path := this.CheckCurrentPage()
        ; Notepad3 owns external-file monitoring, saving, and reloading.

        ; Autosave needs one verified disk snapshot. Hide/switch/reload/exit also
        ; require a clean editor after verification, with bounded save retries.
        save_passes := require_clean ? 3 : 1
        loop save_passes {
            try save_snapshot := this.bridge.DocumentText()
            catch PaperPadTextChangedError as failure {
                ; No Save has been sent on this autosave pass. Ordinary typing
                ; can safely defer it to the next interval without pausing saves.
                ; Never suppress a timeout, embedded NUL or post-save failure.
                if require_clean
                    throw failure
                return false
            }

            ; Verify that Notepad3 is still editing the expected file.
            if this.bridge.CurrentPath() != path
                throw Error("The active page changed before saving. Inspect Notepad3 before retrying.")

            ; Always ask the native editor to save: encoding-only changes may not
            ; set Scintilla's text-dirty flag. Its Save handler is synchronous.
            this.bridge.Save()
            if this.bridge.CurrentPath() != path || !FileExist(path)
                throw Error("The save target changed or disappeared. Inspect the editor before retrying.")

            after_save_stamp := PaperPadFileStamp(path)
            if !this.bridge.MatchesDiskText(path, save_snapshot) {
                ; Notepad3 may trim trailing blanks during Save, or typing may
                ; reach it between our snapshot and its native Save handler.
                ; Accept that newer result only when the current editor is clean
                ; and independently matches disk. A timestamp alone is not proof.
                if this.bridge.IsDirty() || !this.bridge.MatchesDisk(path)
                    || this.bridge.IsDirty()
                {
                    throw Error("Notepad3 did not save the expected document version. Resolve any native dialog or save error and retry; no successful save was recorded.")
                }
            }
            if PaperPadFileStamp(path) != after_save_stamp
                throw Error("The file changed again while the completed save was being verified.")

            this.AcceptSave(path, after_save_stamp)
            if !require_clean || !this.bridge.IsDirty()
                return true

            ; The native Save already returned; a dirty editor now has newer
            ; edits. Save those on the next pass instead of polling for up to
            ; two seconds for a dirty flag that typing can keep setting.
        }

        throw Error("The page kept changing while Paper Pad tried to save it. Stop editing briefly and retry.")
    }

    AcceptSave(path, stamp)
    {
        ; File comparisons may take time. Do not record success for a document
        ; that was replaced, or a disk version that changed during verification.
        this.bridge.CheckReady()
        if this.bridge.CurrentPath() != path
            throw Error("The active page changed while the completed save was being verified.")
        if PaperPadFileStamp(path) != stamp
            throw Error("The file changed again before the verified save could be recorded.")
        this.disk_stamp := stamp
        this.PersistCurrentState()
        this.last_verified_save_tick := A_TickCount
        this.autosave_tracking.sampled := false
        this.autosave_tracking.text := ""
        this.autosave_tracking.last_change := 0
        this.autosave_paused := false
    }

    ConfigureNewPage()
    {
        ; Existing files retain their encoding and line endings.
        this.bridge.Command(Notepad3Bridge.encoding_utf8)
        this.bridge.Command(Notepad3Bridge.line_endings_lf)
        this.SaveCurrentPage()

        ; New pages open ready for immediate typing; welcome pages start below the guide.
        length := this.bridge.Scintilla(2006) ; SCI_GETLENGTH
        this.bridge.Scintilla(2160, length, length) ; SCI_SETSEL
    }

    SwitchPage(next_path, new_page := false)
    {
        this.SaveCurrentPage()
        if new_page
            next_path := this.CreatePage()
        else if next_path = this.current_path
            return
        next_path := PaperPadFullPath(next_path)
        attributes := FileExist(next_path)
        if !this.IsNotePath(next_path) || !attributes || InStr(attributes, "D")
            throw Error("The next page is no longer available:`n" next_path)
        this.RememberPageView(this.current_path)
        before_load_stamp := PaperPadFileStamp(next_path)
        this.bridge.OpenPage(next_path, this.controller_window.Hwnd)
        if this.bridge.CurrentPath() != next_path
            throw Error("Notepad3 did not load the requested page. Inspect its dialog and retry.")

        this.current_path := next_path
        this.disk_stamp := before_load_stamp
        this.PersistCurrentState()
        if new_page
            this.ConfigureNewPage()
        else
            this.RestorePageView(next_path)
        this.FocusEditor()
    }

    DeleteCurrentPage()
    {
        path := this.CheckCurrentPage()
        pages := this.ListPages()
        current_index := 0

        for index, candidate in pages {
            if candidate = path {
                current_index := index
                break
            }
        }

        if !current_index
            throw Error("The current page could not be found in the page list.")

        ; Save and leave the page before recycling it.
        if pages.Length = 1 {
            this.SwitchPage("", true)
        } else {
            next_index := current_index < pages.Length
                ? current_index + 1
                : current_index - 1

            this.SwitchPage(pages[next_index])
        }

        try {
            FileRecycle path
        }
        catch as failure {
            ; The page is still intact if recycling failed. Return to it so the
            ; delete command can be retried instead of leaving it behind unnoticed.
            try this.SwitchPage(path)

            throw Error(
                "The page could not be moved to the Recycle Bin:`n"
                    . path "`n`n"
                    . failure.Message
            )
        }

        if this.page_views.Has(path)
            this.page_views.Delete(path)
    }

    RememberPageView(path)
    {
        this.page_views[path] := {
            caret: this.bridge.Scintilla(2008),
            anchor: this.bridge.Scintilla(2009),
            first_line: this.bridge.Scintilla(2152),
            horizontal_scroll: this.bridge.Scintilla(2398)
        }
    }

    RestorePageView(path)
    {
        if !this.page_views.Has(path)
            return
        view := this.page_views[path]
        length := this.bridge.Scintilla(2006)
        this.bridge.Scintilla(2160, Min(length, view.anchor), Min(length, view.caret))
        this.bridge.Scintilla(2613, view.first_line)
        this.bridge.Scintilla(2397, view.horizontal_scroll)
    }

    static TrackAutosaveChanges(tracking, dirty, document_text, now)
    {
        if !dirty {
            tracking.sampled := false
            tracking.text := ""
            tracking.last_change := 0
        } else if !tracking.sampled || StrCompare(document_text, tracking.text, true) != 0 {
            tracking.sampled := true
            tracking.text := document_text
            tracking.last_change := now
        }
    }

    static ShouldAutosave(dirty, idle_ms, save_age_ms, attempt_age_ms)
    {
        if attempt_age_ms < this.AutosaveIdleMs
            return false
        return save_age_ms >= this.AutosaveMaxMs
            || (dirty && idle_ms >= this.AutosaveIdleMs)
    }

    Autosave(*)
    {
        if this.busy || this.autosave_paused || !this.IsVisible()
            return
        ; Never interact with an open native menu, file dialog or move/size loop.
        if !PaperPadWindowIdle(this.window_hwnd)
            return
        this.busy := true
        try {
            if !this.bridge || this.bridge.tainted
                this.ConnectBridge()
            ; Clean untitled pages are adopted by the watcher; never autosave
            ; an untitled buffer with user text to an invented path.
            if this.bridge.CurrentPath() = ""
                return
            dirty := this.bridge.IsDirty()
            ; Compare actual text so paste, undo and mouse edits reset the idle delay.
            document_text := dirty ? this.bridge.DocumentText() : ""
            now := A_TickCount
            PaperPadController.TrackAutosaveChanges(this.autosave_tracking, dirty, document_text, now)
            idle_ms := dirty ? now - this.autosave_tracking.last_change : 0
            if PaperPadController.ShouldAutosave(dirty, idle_ms,
                now - this.last_verified_save_tick,
                now - this.last_autosave_attempt_tick) {
                ; A changing snapshot can fail safely; do not retry every poll.
                this.last_autosave_attempt_tick := now
                this.SaveCurrentPage(false)
            }
        }
        catch PaperPadTextChangedError {
            ; Ordinary edits can interrupt a snapshot. Wait for another sample.
            this.autosave_tracking.last_change := A_TickCount
        }
        catch as failure {
            this.autosave_paused := true
            this.ReportError(failure, true)
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    ; =========================================================================
    ; monitor placement, focus and animation
    ; =========================================================================

    GetBounds()
    {
        monitor_index := this.ResolveMonitorIndex()

        try {
            MonitorGetWorkAreaPixels(
                monitor_index,
                &left,
                &top,
                &right,
                &bottom
            )
        }
        catch as failure {
            primary_index := MonitorGetPrimary()
            if monitor_index = primary_index
                throw failure

            MonitorGetWorkAreaPixels(
                primary_index,
                &left,
                &top,
                &right,
                &bottom
            )
        }

        work_width := right - left
        work_height := bottom - top
        width := Min(work_width, Max(320, Round(work_width * this.width_percent / 100)))
        height := Min(work_height, Max(180, Round(work_height * this.height_percent / 100)))

        return {
            x: left + Round((work_width - width) / 2),
            y: top,
            w: width,
            h: height
        }
    }

    ResolveMonitorIndex()
    {
        monitor_count := MonitorGetCount()

        if this.monitor_target != "Primary" {
            loop monitor_count {
                try monitor_name := MonitorGetName(A_Index)
                catch
                    continue

                if StrLower(monitor_name) = StrLower(this.monitor_target)
                    return A_Index
            }
        }

        ; A disconnected pinned display temporarily falls back to the Windows
        ; main display without overwriting the saved preference.
        try return MonitorGetPrimary()
        catch
            return 1
    }

    ShowWindow(source_window, animate := true)
    {
        if this.IsVisible() {
            this.FocusEditor()
            return
        }
        if source_window && source_window != this.window_hwnd {
            this.previous_window := source_window
            this.last_external_window := source_window
        }
        this.last_bounds := this.GetBounds()
        bounds := this.last_bounds

        ; Start with an empty region so restoring a minimized window cannot flash.
        this.SetClip(1, 1, 1)
        if WinGetMinMax("ahk_id " this.window_hwnd) != 0
            WinRestore "ahk_id " this.window_hwnd
        WinHide "ahk_id " this.window_hwnd
        WinMovePixels(bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd)
        ; Some window styles impose a minimum size; animate the actual dimensions.
        WinGetPosPixels(, , &actual_width, &actual_height, "ahk_id " this.window_hwnd)
        bounds.w := actual_width
        bounds.h := actual_height

        ; PaperPad is a drawer, so it remains topmost whenever it is visible.
        this.z_order_snapshot := ""
        this.SetDrawerTopmost(true)
        this.AnimateWindow(true, bounds, animate)
        this.FocusEditor()
    }

    HideWindow()
    {
        if !this.bridge || this.bridge.tainted
            this.ConnectBridge()
        this.SaveCurrentPage()
        was_active := !!WinActive("ahk_id " this.window_hwnd)
        bounds := this.GetBounds()
        WinGetPosPixels(&window_x, &window_y, &window_width, &window_height, "ahk_id " this.window_hwnd)
        bounds.x := window_x
        bounds.w := window_width
        bounds.h := window_height
        bounds.start_y := window_y
        this.last_bounds := bounds
        this.AnimateWindow(false, bounds)
        this.SetDrawerTopmost(false)
        if was_active && this.previous_window
            && DllCall("IsWindowVisible", "ptr", this.previous_window, "int")
            && !DllCall("IsIconic", "ptr", this.previous_window, "int")
        {
            try WinActivate "ahk_id " this.previous_window
        }
    }

    SetDrawerTopmost(enabled)
    {
        if !this.window_hwnd || !DllCall("IsWindow", "ptr", this.window_hwnd, "int")
            return

        enabled := !!enabled
        ex_style := DllCall("GetWindowLongPtrW", "ptr", this.window_hwnd, "int", -20, "ptr")
        is_topmost := !!(ex_style & 0x8) ; WS_EX_TOPMOST
        if is_topmost = enabled
            return

        ; Use explicit HWND_TOPMOST/HWND_NOTOPMOST placement; report failed restoration.
        if !DllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", enabled ? -1 : -2,
            "int", 0, "int", 0, "int", 0, "int", 0,
            "uint", 0x213, "int") ; NOSIZE | NOMOVE | NOACTIVATE | NOOWNERZORDER
            throw OSError(A_LastError, "SetWindowPos", "Paper Pad topmost")
        updated_style := DllCall("GetWindowLongPtrW", "ptr", this.window_hwnd, "int", -20, "ptr")
        if !!(updated_style & 0x8) != enabled
            throw Error("Paper Pad could not " (enabled ? "restore" : "lower") " its topmost status.")
    }

    SyncZOrder()
    {
        if !this.IsVisible()
            return

        foreground := DllCall("GetForegroundWindow", "ptr")
        if foreground && foreground != this.window_hwnd
            && !PaperPadIsDialogWindow(foreground)
            this.last_external_window := foreground

        verbose := SuiteState.Log.verbose
        try {
            if verbose
                before_topmost := !!(WinGetExStyle("ahk_id " this.window_hwnd) & 0x8)

            dialog := this.FindYieldDialog(foreground)
            if dialog
                this.YieldDrawerTo(dialog)
            else
                this.SetDrawerTopmost(true)
        }
        catch Error as failure {
            SuiteState.Log.Error("Paper Pad / Z-order", failure)
            throw
        }

        if !verbose {
            this.z_order_snapshot := ""
            return
        }

        ; Diagnostics must never interfere with the drawer's normal behavior.
        try this.TraceZOrder(foreground, dialog, before_topmost)
        catch Error as failure
            SuiteState.Log.Error("Paper Pad / Z-order diagnostics", failure)
    }

    TraceZOrder(foreground, dialog, before_topmost)
    {
        after_topmost := !!(WinGetExStyle("ahk_id " this.window_hwnd) & 0x8)
        above := DllCall("GetWindow", "ptr", this.window_hwnd, "uint", 3, "ptr")
        snapshot := foreground "|" dialog "|" before_topmost "|" after_topmost "|" above
        if snapshot = this.z_order_snapshot
            return
        this.z_order_snapshot := snapshot

        action := dialog ? "yield" : (before_topmost ? "maintain" : "restore")
        details := "Z-order | action=" action
            . " | topmost=" before_topmost "->" after_topmost
        for item in [["foreground", foreground], ["yield", dialog], ["above", above]] {
            hwnd := item[2]
            process_name := ""
            if hwnd {
                try process_name := WinGetProcessName("ahk_id " hwnd)
            }
            details .= " | " item[1] "=" hwnd ":" process_name
        }
        if dialog {
            try {
                owner := DllCall("GetWindow", "ptr", dialog, "uint", 4, "ptr") ; GW_OWNER
                details .= " | dialog-class=" WinGetClass("ahk_id " dialog)
                    . " | dialog-owner=" owner
                    . " | owner-enabled=" (owner ? DllCall("IsWindowEnabled", "ptr", owner, "int") : -1)
                    . " | dialog-exstyle=" Format("0x{:X}", WinGetExStyle("ahk_id " dialog))
            }
        }
        SuiteState.Log.Debug("Paper Pad", details)
    }

    FindYieldDialog(foreground, candidates := unset)
    {
        if foreground && foreground != this.window_hwnd
            && PaperPadIsDialogWindow(foreground)
            return foreground

        context := 0
        if foreground && foreground != this.window_hwnd
            && PaperPadUsableWindow(foreground)
            && !PaperPadIsDialogWindow(foreground)
        {
            context := foreground
        } else if PaperPadUsableWindow(this.last_external_window) {
            context := this.last_external_window
        }

        ; Tests supply only their own windows; production scans visible top-level windows.
        if !IsSet(candidates) {
            previous_hidden := DetectHiddenWindows(false)
            try candidates := WinGetList()
            finally DetectHiddenWindows previous_hidden
        }

        ; The list follows top-level Z-order. OperationStatusWindow is specific
        ; enough to yield globally; broader dialogs need the current context.
        for candidate in candidates {
            if candidate = this.window_hwnd || !PaperPadIsDialogWindow(candidate)
                continue

            try candidate_class := WinGetClass("ahk_id " candidate)
            catch
                continue

            if candidate_class = "OperationStatusWindow"
                return candidate

            ; Explorer's File In Use/delete/error prompts commonly use the classic
            ; dialog class. Recognize those directly so a fast prompt cannot slip
            ; between foreground samples and lose its Explorer context.
            if candidate_class = "#32770" {
                try candidate_process := WinGetProcessName("ahk_id " candidate)
                catch
                    candidate_process := ""
                if StrLower(candidate_process) = "explorer.exe"
                    return candidate
            }

            ; A process can own many unrelated windows. Require the actual owner chain.
            if PaperPadIsOwnedBy(candidate, this.window_hwnd)
                || (context && PaperPadIsOwnedBy(candidate, context))
                return candidate
        }

        return 0
    }

    YieldDrawerTo(dialog)
    {
        if !PaperPadUsableWindow(dialog)
            return

        this.SetDrawerTopmost(false)

        ; Placing the drawer after a topmost popup promotes it to topmost again.
        ; A topmost menu/dialog already stays above a normal window.
        if WinGetExStyle("ahk_id " dialog) & 0x8 ; WS_EX_TOPMOST
            return

        ; Non-topmost dialogs still need explicit ordering within the normal band.
        if !DllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", dialog,
            "int", 0, "int", 0, "int", 0, "int", 0,
            "uint", 0x213, "int") ; NOSIZE | NOMOVE | NOACTIVATE | NOOWNERZORDER
            SuiteState.Log.Error("Paper Pad / dialog Z-order", OSError(A_LastError, "SetWindowPos"))
    }

    AnimateWindow(showing, bounds, animate := true)
    {
        duration := animate ? PaperPadController.AnimationMs : 0
        animation_setting := Buffer(4, 0)
        if DllCall("SystemParametersInfoW", "uint", 0x1042, "uint", 0,
            "ptr", animation_setting, "uint", 0, "int") && !NumGet(animation_setting, 0, "int")
            duration := 0

        start_y := showing ? bounds.y - bounds.h : bounds.start_y
        end_y := showing ? bounds.y : bounds.y - bounds.h
        try {
            if showing {
                this.PlaceAnimationFrame(bounds, start_y)
                DllCall("ShowWindow", "ptr", this.window_hwnd, "int", 4) ; SW_SHOWNOACTIVATE
            }
            started := PaperPadClockMs()
            last_frame_y := start_y
            loop {
                progress := duration ? Min(1, (PaperPadClockMs() - started) / duration) : 1
                eased := 1 - (1 - progress) ** 3
                current_y := Round(start_y + (end_y - start_y) * eased)
                ; Easing often rounds several final frames to the same pixel.
                ; Do not allocate another region and repaint an identical frame.
                if current_y != last_frame_y {
                    this.PlaceAnimationFrame(bounds, current_y)
                    last_frame_y := current_y
                }
                if progress >= 1
                    break
                ; Frame pacing follows desktop composition, without a permanent
                ; high-resolution timer request or a CPU-spinning wait loop.
                frame_wait_started := PaperPadClockMs()
                if DllCall("dwmapi\DwmFlush", "int") != 0
                    Sleep 8
                else if PaperPadClockMs() - frame_wait_started < 1
                    Sleep 1
                Sleep -1
            }
            if !showing
                WinHide "ahk_id " this.window_hwnd
        }
        finally {
            if showing {
                ; Finish a successful show at the normal visible bounds.
                DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                WinMovePixels(bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd)
            } else {
                ; Keep the fully retracted editor hidden until the next show.
                try WinHide "ahk_id " this.window_hwnd
            }
        }
    }

    PlaceAnimationFrame(bounds, current_y)
    {
        ; Clip at the chosen work-area top: no spill onto a monitor above it.
        clip_top := Min(bounds.h, Max(0, bounds.y - current_y))
        this.SetClip(bounds.w, bounds.h, clip_top)
        if !PhysicalDllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", 0,
            "int", bounds.x, "int", current_y, "int", 0, "int", 0,
            "uint", 0x215, "int") ; NOSIZE | NOZORDER | NOACTIVATE | NOOWNERZORDER
            throw OSError(A_LastError, "SetWindowPos")
    }

    SetClip(width, height, top)
    {
        region := DllCall("gdi32\CreateRectRgn", "int", 0, "int", top,
            "int", width, "int", height, "ptr")
        if !region
            throw OSError(A_LastError, "CreateRectRgn")
        if !PhysicalDllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", region, "int", true, "int") {
            DllCall("gdi32\DeleteObject", "ptr", region)
            throw OSError(A_LastError, "SetWindowRgn")
        }
        ; Windows owns the region after success; deleting it here would be wrong.
    }

    FocusEditor()
    {
        popup := DllCall("GetLastActivePopup", "ptr", this.window_hwnd, "ptr")
        if popup && popup != this.window_hwnd
            && DllCall("IsWindowVisible", "ptr", popup, "int")
        {
            WinActivate "ahk_id " popup
            return
        }
        WinActivate "ahk_id " this.window_hwnd
        if this.bridge && !this.bridge.tainted {
            try ControlFocus this.bridge.editor_hwnd, "ahk_id " this.window_hwnd
        }
    }

    HandleEscape(inputGeneration := -1)
    {
        if this.busy
            return
        this.busy := true
        pass_escape := true
        try pass_escape := this.bridge.Scintilla(2102) || this.bridge.Scintilla(2202)
        catch {
            ; Preserve native Escape if the editor state cannot be inspected.
            pass_escape := true
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
        if inputGeneration >= 0 && (!SuiteState.App.InputIsCurrent(inputGeneration)
            || !PaperPadEditorFocused())
            return
        if pass_escape
            Send "{Escape}" ; Completion/calltip gets Escape before the drawer.
        else
            this.QueueCommand("hide", inputGeneration)
    }

    RevealAfterError(source_window)
    {
        if !this.HasWindow()
            return
        try {
            DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
            bounds := this.GetBounds()
            if WinGetMinMax("ahk_id " this.window_hwnd) != 0
                WinRestore "ahk_id " this.window_hwnd
            WinMovePixels(bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd)
            WinShow "ahk_id " this.window_hwnd
            this.FocusEditor()
        }
    }

    ReportError(failure, notification := false)
    {
        SuiteState.Log.Error("Paper Pad", failure)
        if notification
            TrayTip failure.Message, "Paper Pad - autosave paused", 2
        else {
            ; ProcessCommands keeps the controller busy while reporting failures,
            ; so the timer cannot yield Z-order for our own modal message box.
            ; Lower the drawer explicitly, then restore the requested policy.
            restore_topmost := this.IsVisible()
            if restore_topmost
                try this.SetDrawerTopmost(false)
            try MsgBox failure.Message "`n`nDetails: " SuiteState.Log.path, "Paper Pad", "Iconx 4096"
            finally {
                if restore_topmost && this.IsVisible()
                    try this.SetDrawerTopmost(true)
            }
        }
    }

    ; =========================================================================
    ; suite exit
    ; =========================================================================

    OnScriptExit(exit_reason, exit_code)
    {
        SetTimer this.autosave_callback, 0
        SetTimer this.watch_callback, 0
        SetTimer this.process_commands_callback, 0
        ; Leave the native editor to Windows during shutdown or logoff.
        if exit_reason != "Shutdown" && exit_reason != "Logoff" && this.HasWindow() {
            if !this.exit_prepared {
                try this.SaveCurrentPage()
            }
            ; Reload retains the real editor and its undo history. Unexpected
            ; ordinary exits reveal it rather than stranding a hidden document.
            try {
                DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                bounds := this.last_bounds ? this.last_bounds : this.GetBounds()
                WinMovePixels(bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd)
                if exit_reason != "Reload" && exit_reason != "Single" {
                    WinSetAlwaysOnTop false, "ahk_id " this.window_hwnd
                    WinShow "ahk_id " this.window_hwnd
                }
            }
        }
        this.bridge := 0
        return 0
    }

    PrepareSuiteExit(reason) {
        if this.busy || this.command_queue.Length
            throw Error("Paper Pad is finishing a command. Retry the suite exit or restart afterwards.")
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
