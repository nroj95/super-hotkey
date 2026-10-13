#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn

; =============================================================================
; Scratchpad - a persistent, keyboard-driven Notepad3 drawer
; =============================================================================
; requirements and ownership
; - use 64-bit AutoHotkey v2 and Notepad3 7.26.602.1 (normal privileges).
; - launch one dedicated Notepad3 window; never adopt ordinary editor windows.
; - run independently of CapsLock Layer and other companion scripts.
; - mark the editor with nroj.WindowCascade.Ignore before positioning/showing it.
;
; controls
; - global toggle defaults to Win + F12 and is configurable from the tray menu.
; - inside the editor: Escape hides, Ctrl + N creates, Win + arrows/page keys switch.
; - Ctrl + S uses the same checked save path as autosave.
;
; persistence and safety
; - pages are ordinary files directly inside the configured scratch directory.
; - new pages use scratch-yyyyMMdd-HHmmss.md, UTF-8 without BOM and LF.
; - save before hide/switch/exit; refuse automatic overwrites after disk conflicts.
; - page switching reuses the same window via Notepad3's WM_COPYDATA protocol.
; - undo survives hiding/reload, not loading another page; caret/scroll are cached.
; - native Save As is supported inside the scratch folder. Rename closed pages.
; - Exit saves and normally closes ONLY the owned editor. Reload reattaches.
;
; settings and implementation boundaries
; - controller: %LOCALAPPDATA%\Scratchpad\settings.ini and state.ini.
; - display defaults to Windows main display; tray selection can pin a display.
; - editor: %LOCALAPPDATA%\Scratchpad\Notepad3.ini (separate from normal settings).
; - the old Notepad++ executable setting/profile are ignored, not deleted.
; - no clipboard swaps, injected keystroke saves, process killing or remote memory.
; - Notepad3 native messages/IDs are isolated in Notepad3Bridge below. They are
;   source-level interfaces, not a promised stable plugin API; test editor updates.
; =============================================================================

Persistent
DetectHiddenWindows True
SetTitleMatchMode 2
SetWinDelay -1
SetControlDelay -1
A_IconTip := "Scratchpad"
try TraySetIcon(A_ScriptDir "\icons\scratchpad.ico")

try scratchpad := ScratchpadController()
catch as startup_failure {
    MsgBox startup_failure.Message, "Scratchpad startup", "Iconx"
    ExitApp
}

#HotIf ScratchpadEditorFocused()
~#.::
{
    scratchpad.NoteSystemTextInputInvocation()
}

#HotIf IsSet(scratchpad) && scratchpad.SystemTextInputEscapePending()
~LButton Up::
~RButton Up::
~MButton Up::
~XButton1 Up::
~XButton2 Up::
{
    scratchpad.HandleSystemTextInputClick()
}

#HotIf ScratchpadEditorFocused()
$Esc::
{
    if scratchpad.SystemTextInputEscapePending() {
        scratchpad.ConsumeSystemTextInputEscape()

        ; Let Windows dismiss the system text-input surface first. $Esc keeps
        ; the forwarded key from recursively invoking this hotkey.
        Send "{Esc}"
    } else {
        scratchpad.HandleEscape()
    }

    KeyWait "Escape"
}
$^n::
{
    scratchpad.QueueCommand("new")
    KeyWait "n"
}
$^s::
{
    scratchpad.QueueCommand("save")
    KeyWait "s"
}
$#F4::
{
    scratchpad.QueueCommand("delete")
    KeyWait "F4"
}
$#Left::
{
    scratchpad.QueueCommand("previous")
    KeyWait "Left"
}
$#Right::
{
    scratchpad.QueueCommand("next")
    KeyWait "Right"
}
$#PgUp::
{
    scratchpad.QueueCommand("next")
    KeyWait "PgUp"
}
$#PgDn::
{
    scratchpad.QueueCommand("previous")
    KeyWait "PgDn"
}
#HotIf

ScratchpadEditorFocused()
{
    global scratchpad

    if !IsSet(scratchpad) || !scratchpad.HasWindow()
        return false
    if !WinActive("ahk_id " scratchpad.window_hwnd)
        return false
    if !scratchpad.bridge || scratchpad.bridge.tainted
        return false

    ; Read the actual focused HWND instead of relying on a ClassNN string.
    thread_info := Buffer(72, 0) ; GUITHREADINFO, 64-bit
    NumPut("uint", thread_info.Size, thread_info)

    if !DllCall("GetGUIThreadInfo", "uint", 0, "ptr", thread_info, "int")
        return false

    ; Native menus, popup menus and move/size loops keep their normal shortcuts.
    if NumGet(thread_info, 4, "uint") & 0x1E
        return false

    focused_hwnd := NumGet(thread_info, 16, "ptr")
    return focused_hwnd = scratchpad.bridge.editor_hwnd
}


class ScratchpadController
{
    ; =========================================================================
    ; configuration and serialized commands
    ; =========================================================================

    __New()
    {
        this.window_hwnd := 0
        this.editor_pid := 0
        this.bridge := 0
        this.busy := false
        this.autosave_paused := false
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
        this.system_text_input_escape_pending := false
        this.last_bounds := 0
        this.page_lock_handle := 0
        this.page_lock_path := ""
        this.window_marker := "nroj.Scratchpad.Notepad3Window"
        this.cascade_ignore_marker := "nroj.WindowCascade.Ignore"
        this.controller_title := "nroj.Scratchpad.Controller"
        this.data_directory := EnvGet("LOCALAPPDATA") "\Scratchpad"
        this.settings_path := this.data_directory "\settings.ini"
        this.state_path := this.data_directory "\state.ini"
        this.editor_profile := this.data_directory "\Notepad3.ini"
        this.error_log := this.data_directory "\errors.log"
        this.startup_shortcut := A_Startup "\Scratchpad.lnk"
        this.toggle_hotkey_name := ""
        this.toggle_hotkey_ahk := ""
        this.toggle_hotkey_key := ""
        this.toggle_hotkey_callback := ObjBindMethod(this, "HandleToggleHotkey")
        this.toggle_hotkey_presets := [
            "Win+F12",
            "F12",
            "Ctrl+F12",
            "Ctrl+Shift+F12",
            "Ctrl+Alt+F12",
            "Win+F10",
            "Ctrl+Alt+Space"
        ]
        this.toggle_hotkey_menu := 0
        this.custom_hotkey_gui := 0
        this.monitor_menu := 0
        this.monitor_menu_items := Map()
        this.monitor_menu_items.CaseSense := "Off"
        this.window_width_menu := 0
        this.window_height_menu := 0
        this.window_width_presets := [35, 45, 55, 65, 75]
        this.window_height_presets := [25, 35, 45, 55, 65]
        this.mutex_handle := 0

        this.mutex_handle := DllCall("CreateMutexW", "ptr", 0, "int", false,
            "str", "Local\nroj.Scratchpad.Controller", "ptr")
        mutex_error := A_LastError
        if !this.mutex_handle
            throw OSError(mutex_error, "CreateMutexW")
        if mutex_error = 183 {
            DllCall("CloseHandle", "ptr", this.mutex_handle)
            this.mutex_handle := 0
            throw Error("Scratchpad is already running. Exit the other copy first.")
        }

        DirCreate this.data_directory
        default_scratch_directory := EnvGet("USERPROFILE") "\Scratchpad"
        this.CreateDefaultSettings(default_scratch_directory)
        this.scratch_directory := RTrim(IniRead(this.settings_path, "Paths",
            "ScratchDirectory", default_scratch_directory), "\/")
        if !RegExMatch(this.scratch_directory, "i)^(?:[a-z]:\\|\\\\)")
            throw Error("ScratchDirectory must be an absolute Windows path.")
        DirCreate this.scratch_directory
        ; Resolve . and .. before enforcing the direct-child page boundary.
        this.scratch_directory := RTrim(ScratchpadFullPath(this.scratch_directory), "\/")
        this.monitor_target := this.ReadMonitorTarget()
        this.width_percent := this.ReadNumber("Window", "WidthPercent", 45, 30, 100)
        this.height_percent := this.ReadNumber("Window", "HeightPercent", 35, 20, 100)
        this.animation_ms := this.ReadNumber("Window", "AnimationDurationMs", 180, 0, 1000)
        this.autosave_ms := this.ReadNumber("Saving", "AutosaveIntervalMs", 10000, 500, 60000)
        this.allowed_extensions := "|md|txt|ps1|psm1|psd1|py|pyw|ahk|lua|js|ts|jsx|tsx|"
            . "json|jsonc|yaml|yml|xml|html|htm|css|scss|ini|cfg|conf|toml|log|"
            . "sh|bash|bat|cmd|sql|c|cpp|h|hpp|cs|rs|go|java|rb|php|csv|tsv|"

        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
        this.autosave_callback := ObjBindMethod(this, "Autosave")
        this.page_lock_sync_callback := ObjBindMethod(this, "SyncPageLock")
        OnExit ObjBindMethod(this, "OnScriptExit")

        ; Hidden owner/sender window for WM_COPYDATA page switches.
        this.controller_window := Gui("+ToolWindow", this.controller_title)

        this.BuildTrayMenu()
        configured_hotkey := IniRead(this.settings_path, "Controls", "ToggleHotkey", "Win+F12")
        this.SetToggleHotkey(configured_hotkey, false)

        ; Reacquire the retained editor's page lock immediately after Reload,
        ; even while hidden. A fresh controller must not wait for the next hotkey.
        try this.AttachExistingWindow()
        catch as failure {
            this.autosave_paused := true
            A_IconTip := "Scratchpad - autosave paused"
            this.ReportError(failure, true)
        }
        SetTimer this.autosave_callback, this.autosave_ms
        SetTimer this.page_lock_sync_callback, 250
    }

    CreateDefaultSettings(default_scratch_directory)
    {
        if !FileExist(this.settings_path) {
            settings := "[Paths]`nScratchDirectory=" default_scratch_directory
                . "`nNotepad3Executable=`n"
                . "`n[Window]`nMonitor=Primary`nWidthPercent=45`nHeightPercent=35`nAnimationDurationMs=180`n"
                . "`n[Saving]`nAutosaveIntervalMs=10000`n`n[Controls]`nToggleHotkey=Win+F12`n"
                . "`n[Setup]`nWelcomePending=1`n"
            FileAppend settings, this.settings_path, "UTF-16"
        }
        if IniRead(this.settings_path, "Controls", "ToggleHotkey", "<missing>") = "<missing>" {
            legacy_f12 := this.ReadNumber("Controls", "EnableF12", 0, 0, 1)
            IniWrite legacy_f12 ? "F12" : "Win+F12", this.settings_path, "Controls", "ToggleHotkey"
        }
        if IniRead(this.settings_path, "Controls", "EnableF12", "<missing>") != "<missing>"
            IniDelete this.settings_path, "Controls", "EnableF12"
        ; Do not reuse the old Notepad++ path. Remove that legacy key and ensure
        ; the dedicated Notepad3 setting exists instead.
        if IniRead(this.settings_path, "Paths", "NotepadExecutable", "<missing>") != "<missing>"
            IniDelete this.settings_path, "Paths", "NotepadExecutable"
        if IniRead(this.settings_path, "Paths", "Notepad3Executable", "<missing>") = "<missing>"
            IniWrite "", this.settings_path, "Paths", "Notepad3Executable"
        if IniRead(this.settings_path, "Window", "Monitor", "<missing>") = "<missing>"
            IniWrite "Primary", this.settings_path, "Window", "Monitor"

        ; Remove retired Z-order settings from existing controller files.
        if IniRead(this.settings_path, "Window", "AlwaysOnTop", "<missing>") != "<missing>"
            IniDelete this.settings_path, "Window", "AlwaysOnTop"
        if IniRead(this.settings_path, "Setup", "SettingsVersion", "<missing>") != "<missing>"
            IniDelete this.settings_path, "Setup", "SettingsVersion"

        ; Windows INI writes use CRLF. Normalize the controller settings after
        ; migrations so Notepad3 never sees a mixture of LF and CRLF lines.
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

    HandleToggleHotkey(*)
    {
        ; Keep this hotkey thread alive until release, just like the editor
        ; shortcuts. Holding the key must not queue repeated open/close cycles.
        key := this.toggle_hotkey_key
        this.QueueCommand("toggle")
        if key != ""
            KeyWait key
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

    SetToggleHotkey(name, persist := true)
    {
        parsed := this.ParseToggleHotkey(name)
        old_name := this.toggle_hotkey_name
        old_hotkey := this.toggle_hotkey_ahk
        old_key := this.toggle_hotkey_key

        if old_hotkey != ""
            try Hotkey old_hotkey, "Off"

        try {
            if parsed.ahk != ""
                Hotkey parsed.ahk, this.toggle_hotkey_callback, "On"
            if persist
                IniWrite parsed.name, this.settings_path, "Controls", "ToggleHotkey"
        }
        catch as failure {
            if parsed.ahk != ""
                try Hotkey parsed.ahk, "Off"
            if old_hotkey != ""
                try Hotkey old_hotkey, this.toggle_hotkey_callback, "On"
            this.toggle_hotkey_name := old_name
            this.toggle_hotkey_ahk := old_hotkey
            this.toggle_hotkey_key := old_key
            throw Error("Could not apply the toggle shortcut " parsed.name ".`n`n" failure.Message)
        }

        this.toggle_hotkey_name := parsed.name
        this.toggle_hotkey_ahk := parsed.ahk
        this.toggle_hotkey_key := parsed.key
        this.UpdateToggleHotkeyMenu()
    }

    ParseToggleHotkey(name)
    {
        name := StrReplace(Trim(name), " ", "")
        if name = "" || StrLower(name) = "disabled"
            return {name: "Disabled", ahk: "", key: ""}

        parts := StrSplit(name, "+")
        if parts.Length < 1
            throw Error("Invalid toggle shortcut: " name)

        key := parts.Pop()
        if key = ""
            throw Error("The toggle shortcut needs a non-modifier key.")

        modifiers := Map("win", false, "ctrl", false, "shift", false, "alt", false)
        for modifier in parts {
            normalized := StrLower(modifier)
            if !modifiers.Has(normalized)
                throw Error("Unsupported toggle modifier: " modifier)
            if modifiers[normalized]
                throw Error("Duplicate toggle modifier: " modifier)
            modifiers[normalized] := true
        }

        if parts.Length = 0 && !RegExMatch(key, "i)^F(?:[1-9]|1[0-9]|2[0-4])$")
            throw Error("A custom toggle shortcut needs a modifier unless it is an F-key.")

        canonical_key := RegExMatch(key, "i)^F(?:[1-9]|1[0-9]|2[0-4])$")
            ? StrUpper(key) : this.CanonicalKeyName(key)
        ahk := (modifiers["win"] ? "#" : "")
            . (modifiers["ctrl"] ? "^" : "")
            . (modifiers["shift"] ? "+" : "")
            . (modifiers["alt"] ? "!" : "")
            . canonical_key
        canonical := (modifiers["win"] ? "Win+" : "")
            . (modifiers["ctrl"] ? "Ctrl+" : "")
            . (modifiers["shift"] ? "Shift+" : "")
            . (modifiers["alt"] ? "Alt+" : "")
            . canonical_key
        return {name: canonical, ahk: ahk, key: canonical_key}
    }

    CanonicalKeyName(key)
    {
        switch StrLower(key) {
            case "space": return "Space"
            case "tab": return "Tab"
            case "enter": return "Enter"
            case "escape", "esc": return "Escape"
            case "backspace", "bs": return "Backspace"
            case "delete", "del": return "Delete"
            case "insert", "ins": return "Insert"
            case "home": return "Home"
            case "end": return "End"
            case "pgup": return "PgUp"
            case "pgdn": return "PgDn"
            case "up": return "Up"
            case "down": return "Down"
            case "left": return "Left"
            case "right": return "Right"
        }
        if StrLen(key) = 1
            return StrUpper(key)
        return key
    }

    FriendlyFromHotkeyControl(raw_hotkey, include_win)
    {
        if raw_hotkey = ""
            throw Error("Press a shortcut before choosing Use.")

        ctrl := InStr(raw_hotkey, "^") != 0
        shift := InStr(raw_hotkey, "+") != 0
        alt := InStr(raw_hotkey, "!") != 0
        key := RegExReplace(raw_hotkey, "^[\^+!#<>*$~]+")
        if key = ""
            throw Error("The custom shortcut needs a non-modifier key.")

        friendly := (include_win ? "Win+" : "")
            . (ctrl ? "Ctrl+" : "")
            . (shift ? "Shift+" : "")
            . (alt ? "Alt+" : "")
            . key
        return this.ParseToggleHotkey(friendly).name
    }

    QueueCommand(command, *)
    {
        ; Hiding or toggling the drawer ends any outstanding Windows text-input
        ; session so it cannot affect Escape after Scratchpad is reopened.
        if command = "hide" || command = "toggle"
            this.ConsumeSystemTextInputEscape()

        ; Size settings are already stored; one pending resize applies the latest
        ; width and height without interrupting a show/hide animation.
        if command = "resize" {
            for request in this.command_queue {
                if request.name = "resize"
                    return
            }
        }
        if this.command_queue.Length >= 8
            return
        this.command_queue.Push({name: command, source_window: WinExist("A")})
        SetTimer this.process_commands_callback, -1
    }

    ProcessCommands(*)
    {
        if this.busy
            return
        this.busy := true
        previous_dpi_context := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            while this.command_queue.Length {
                request := this.command_queue.RemoveAt(1)
                try this.ExecuteCommand(request)
                catch as failure {
                    this.command_queue := []
                    this.autosave_paused := true
                    A_IconTip := "Scratchpad - autosave paused"
                    this.RevealAfterError(request.source_window)
                    this.ReportError(failure)
                }
            }
        }
        finally {
            if previous_dpi_context
                DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi_context, "ptr")
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    ExecuteCommand(request)
    {
        if request.name = "exit" {
            this.ExitScratchpad()
            return
        }
        if request.name = "reload" {
            if this.HasWindow() || this.AttachExistingWindow()
                this.SaveCurrentPage()
            Reload
            return
        }
        if request.name = "hide" {
            if this.HasWindow() && this.IsVisible()
                this.HideWindow()
            return
        }
        if request.name = "save" {
            if this.HasWindow()
                this.SaveCurrentPage()
            return
        }
        if request.name = "delete" {
            if this.HasWindow()
                this.DeleteCurrentPage()
            return
        }
        if request.name = "resize" {
            this.ApplyWindowSize()
            return
        }

        was_visible := this.IsVisible()
        page_was_created := this.EnsureWindow(request.source_window)
        ; A freshly launched editor must open, not immediately toggle closed.
        if request.name = "toggle" && was_visible {
            this.HideWindow()
            return
        }
        this.ShowWindow(request.source_window)
        switch request.name {
            case "new":
                if !page_was_created
                    this.SwitchPage("", true)
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
                    throw Error("The current file is no longer in the scratch folder. Resolve its move or rename in Notepad3 first.")
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
        if !this.window_hwnd || !DllCall("IsWindow", "ptr", this.window_hwnd, "int") {
            this.ReleasePageLock()
            return false
        }
        if !DllCall("GetPropW", "ptr", this.window_hwnd, "str", this.window_marker, "ptr") {
            this.ReleasePageLock()
            return false
        }

        try {
            valid := WinGetPID("ahk_id " this.window_hwnd) = this.editor_pid
            if !valid
                this.ReleasePageLock()
            return valid
        }
        catch {
            this.ReleasePageLock()
            return false
        }
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
            throw OSError(A_LastError, "SetPropW", "Could not opt out of Window Cascade.")
        if !DllCall("SetPropW", "ptr", hwnd, "str", this.window_marker, "ptr", 1, "int")
            throw OSError(A_LastError, "SetPropW", "Could not mark the scratch editor.")
    }

    AttachExistingWindow()
    {
        for candidate in WinGetList("ahk_class Notepad3") {
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

            attributes := FileExist(path)
            if this.IsScratchPath(path) && attributes && !InStr(attributes, "D")
                this.ProtectPage(path)

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
        if !this.IsScratchPath(initial_path) || !initial_attributes || InStr(initial_attributes, "D") {
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
        initial_path := ScratchpadFullPath(initial_path)
        before_load_stamp := ScratchpadFileStamp(initial_path)
        ; /n requests a new process/window, /f isolates its INI, /l0 prompts on
        ; external changes. No /i tray mode or copied executable.
        command_line := '"' executable '" /n /f "' this.editor_profile
            . '" /l0 "' initial_path '"'
        Run command_line, this.scratch_directory, "Hide", &editor_pid
        this.editor_pid := editor_pid
        deadline := A_TickCount + 12000
        loop {
            candidate := WinExist("ahk_class Notepad3 ahk_pid " editor_pid)
            if candidate {
                this.window_hwnd := candidate
                this.MarkWindow(candidate)
                WinHide "ahk_id " candidate
                if DllCall("GetDlgItem", "ptr", candidate, "int", 0xFB03, "ptr")
                    && DllCall("GetDlgItem", "ptr", candidate, "int", 0xFB05, "ptr")
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
        this.ProtectPage(initial_path)
        this.bridge.PrepareDrawer()
        this.last_bounds := this.GetBounds()
        this.PersistCurrentState()
        if new_page
            this.ConfigureNewPage()
        ; A newly launched editor starts a new save session. A failure in a
        ; previously closed editor must not leave this one silently paused.
        this.autosave_paused := false
        A_IconTip := "Scratchpad"
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
                    . "`n`nCorrect it in Scratchpad settings, then reload.")
            return configured
        }

        if executable := this.FindInstalledNotepad3()
            return executable

        choice := MsgBox(
            "Notepad3 was not found.`n`n"
                . "Scratchpad requires Notepad3.`n`n"
                . "Yes = install Notepad3`n"
                . "No = locate Notepad3.exe manually`n"
                . "Cancel = stop",
            "Scratchpad setup",
            "YesNoCancel Iconi 4096"
        )

        if choice = "No"
            return this.SelectNotepad3Executable()

        if choice != "Yes"
            throw Error("Notepad3 is required to use Scratchpad.")

        existing_notepad3_windows := this.SnapshotNotepad3Windows()

        MsgBox(
            "Scratchpad will open the Notepad3 installer.`n`n"
                . "Choose any installation options you want. Scratchpad will continue "
                . "automatically when setup finishes.",
            "Scratchpad setup",
            "Iconi 4096"
        )

        if !this.InstallNotepad3WithWinget() {
            choice := MsgBox(
                "Scratchpad could not install Notepad3 automatically.`n`n"
                    . "Would you like to locate an existing Notepad3.exe manually?",
                "Scratchpad setup",
                "YesNo Iconx 4096"
            )

            if choice = "Yes"
                return this.SelectNotepad3Executable()

            throw Error("Notepad3 is required to use Scratchpad.")
        }

        ; The installer can optionally launch an ordinary Notepad3 window.
        ; Consider only new, empty, unmodified main windows for cleanup. Never
        ; close a document just because it appeared during this installation.
        this.CloseInstallerNotepad3Windows(existing_notepad3_windows)
        Sleep 200
        this.CloseInstallerNotepad3Windows(existing_notepad3_windows)

        ; Give App Paths and the installation directory a moment to appear.
        loop 50 {
            if executable := this.FindInstalledNotepad3()
                return executable
            Sleep 100
        }

        MsgBox(
            "Notepad3 appears to be installed, but Scratchpad could not locate it "
                . "automatically.`n`nLocate Notepad3.exe to continue.",
            "Scratchpad setup",
            "Iconi 4096"
        )
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

    InstallNotepad3WithWinget()
    {
        command := "winget.exe install --exact --id Rizonesoft.Notepad3 --source winget"
            . " --accept-package-agreements --accept-source-agreements --interactive"

        try return RunWait(command, , "Hide") = 0
        catch
            return false
    }

    SnapshotNotepad3Windows()
    {
        known_windows := Map()
        for hwnd in WinGetList("ahk_exe Notepad3.exe")
            known_windows[hwnd] := true
        return known_windows
    }

    CloseInstallerNotepad3Windows(known_windows)
    {
        for hwnd in WinGetList("ahk_class Notepad3 ahk_exe Notepad3.exe") {
            if known_windows.Has(hwnd)
                continue

            ; Never touch a Scratchpad-owned editor if this helper is reused later.
            if DllCall(
                "GetPropW",
                "ptr", hwnd,
                "str", this.window_marker,
                "ptr"
            )
                continue

            try {
                candidate := Notepad3Bridge(hwnd)
                candidate.CheckReady()
                if candidate.CurrentPath() != "" || candidate.IsDirty()
                    || candidate.Scintilla(2006) != 0 ; SCI_GETLENGTH
                    continue
                ; WM_CLOSE still lets Notepad3 prompt if typing starts after
                ; the checks. No dialog is confirmed and no process is killed.
                PostMessage 0x0010, 0, 0, , "ahk_id " hwnd ; WM_CLOSE
            }
            catch {
                ; An uncertain or busy ordinary editor is not ours to close.
            }
        }
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
            throw Error("Notepad3 is required to use Scratchpad.")

        SplitPath selected, &file_name
        if StrLower(file_name) != "notepad3.exe"
            throw Error("Select Notepad3.exe, not its installer or a shortcut.")

        IniWrite selected, this.settings_path, "Paths", "Notepad3Executable"
        return selected
    }

    ; =========================================================================
    ; persistent pages, checked saves and in-place switching
    ; =========================================================================

    IsScratchPath(path)
    {
        if path = ""
            return false
        try path := ScratchpadFullPath(path)
        catch
            return false
        SplitPath path, , &directory, &extension
        return RTrim(directory, "\/") = this.scratch_directory
            && InStr(this.allowed_extensions, "|" StrLower(extension) "|")
    }

    ListPages()
    {
        sortable_pages := ""
        Loop Files this.scratch_directory "\*", "F" {
            if this.IsScratchPath(A_LoopFileFullPath)
                sortable_pages .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"
        }
        pages := []
        ; Creation time is stable when a page is renamed; names break time ties.
        Loop Parse Sort(sortable_pages), "`n", "`r" {
            if A_LoopField != ""
                pages.Push(this.scratch_directory "\" SubStr(A_LoopField, 16))
        }
        return pages
    }

    CreatePage()
    {
        base_name := "scratch-" FormatTime(, "yyyyMMdd-HHmmss")
        loop {
            suffix := A_Index = 1 ? "" : "-" Format("{:02}", A_Index)
            path := this.scratch_directory "\" base_name suffix ".md"
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

    ProtectPage(path)
    {
        path := ScratchpadFullPath(path)

        if this.page_lock_handle && path = this.page_lock_path
            return

        attributes := FileExist(path)
        if !attributes || InStr(attributes, "D")
            throw Error("Cannot protect a missing or invalid scratch page:`n" path)

        ; Match the tested PowerShell lock: permit normal reads/writes while
        ; denying delete sharing. This blocks external delete/rename/replace
        ; without interfering with Notepad3's normal Save or Save As.
        new_handle := DllCall(
            "CreateFileW",
            "str", path,
            "uint", 0x80000000, ; GENERIC_READ
            "uint", 0x00000003, ; FILE_SHARE_READ | FILE_SHARE_WRITE
            "ptr", 0,
            "uint", 3,          ; OPEN_EXISTING
            "uint", 0x80,       ; FILE_ATTRIBUTE_NORMAL
            "ptr", 0,
            "ptr"
        )

        if new_handle = -1
            throw OSError(A_LastError, "CreateFileW", path)

        ; Acquire the new lock before releasing the old one so a page switch
        ; never leaves both pages unprotected because opening the new lock failed.
        old_handle := this.page_lock_handle
        this.page_lock_handle := new_handle
        this.page_lock_path := path

        if old_handle
            DllCall("CloseHandle", "ptr", old_handle)
    }

    ReleasePageLock()
    {
        if this.page_lock_handle
            DllCall("CloseHandle", "ptr", this.page_lock_handle)

        this.page_lock_handle := 0
        this.page_lock_path := ""
    }

    SyncPageLock(*)
    {
        if this.busy || !this.IsVisible()
            return

        ; Serialize the whole watcher, including Z-order. A hotkey must not hide
        ; or replace the editor halfway through this timer's window operations.
        this.busy := true
        try {
            ; Reuse this watcher for Z-order without another permanent timer.
            try this.SyncZOrder()

            ; Native Save As happens outside Scratchpad's command path. Watch its
            ; filename so the delete-denying handle follows it before autosave.
            if !this.bridge || this.bridge.tainted
                return
            if !ScratchpadWindowIdle(this.window_hwnd)
                return

            path := this.bridge.CurrentPath()
            if path = this.page_lock_path
                return

            attributes := path != "" ? FileExist(path) : ""
            if this.IsScratchPath(path) && attributes && !InStr(attributes, "D")
                this.ProtectPage(path)
            else
                this.ReleasePageLock()
        }
        catch {
            ; Native dialogs and transient filename changes are retried on the
            ; next tick. Normal Scratchpad commands still report real failures.
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    WelcomeText()
    {
        if this.toggle_hotkey_name = "Disabled"
            toggle_text := "The global toggle shortcut is currently disabled."
        else
            toggle_text := this.DisplayHotkeyName(this.toggle_hotkey_name)
                . " — show or hide Scratchpad"

        return "# Welcome to Scratchpad`n`n"
            . toggle_text "`n"
            . "Escape — hide Scratchpad`n`n"
            . "Right-click the Scratchpad tray icon and choose **How to use** "
            . "for shortcuts and more.`n`n"
            . "You can also change the toggle shortcut from the tray menu.`n`n"
            . "Start typing below.`n`n"
    }

    CheckCurrentPage()
    {
        if !this.HasWindow()
            throw Error("The scratch editor has closed.")
        if !this.bridge || this.bridge.tainted
            this.ConnectBridge()
        this.bridge.CheckReady()
        path := this.bridge.CurrentPath()
        if !this.IsScratchPath(path)
            throw Error("The editor is not showing a supported file directly inside:`n"
                . this.scratch_directory "`n`nReturn to a scratch page or use File > Save As. Unrelated files will not be saved or closed automatically.")
        attributes := FileExist(path)
        if !attributes
            throw Error("The active scratch page unexpectedly disappeared from disk:`n" path)
        if InStr(attributes, "D")
            throw Error("The open page path now refers to a directory:`n" path)

        this.ProtectPage(path)

        if path != this.current_path {
            ; Notepad3's path control follows native Open, Rename and Save As.
            ; Accept the user's explicit document change; subsequent disk changes
            ; are checked against this new baseline.
            this.current_path := path
            this.disk_stamp := ScratchpadFileStamp(path)
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

    SaveCurrentPage(require_clean := true)
    {
        path := this.CheckCurrentPage()
        current_stamp := ScratchpadFileStamp(path)
        if this.disk_stamp = "" || current_stamp != this.disk_stamp {
            ; A native save/reload is harmless only when disk and editor agree.
            ; Never auto-reload here: the user may have kept a different version.
            if !this.bridge.MatchesDisk(path)
                throw Error("The page changed on disk, or its previous save state is unknown.`n`n"
                    . "Use Notepad3 File > Save As to preserve the editor version under a new scratch name,"
                    . " or File > Revert to keep the disk version. No automatic overwrite was attempted.")
            if ScratchpadFileStamp(path) != current_stamp
                throw Error("The file changed again while being checked. Retry after the other writer has finished.")
            this.disk_stamp := current_stamp
        }

        ; Autosave needs one verified disk snapshot. Hide/switch/reload/exit also
        ; require a clean editor after verification, with bounded save retries.
        save_passes := require_clean ? 3 : 1
        loop save_passes {
            before_save_stamp := ScratchpadFileStamp(path)
            if before_save_stamp != this.disk_stamp
                throw Error("The page changed on disk before saving. No automatic overwrite was attempted.")

            try save_snapshot := this.bridge.DocumentText()
            catch ScratchpadTextChangedError as failure {
                ; No Save has been sent on this autosave pass. Ordinary typing
                ; can safely defer it to the next interval without pausing saves.
                ; Never suppress a timeout, embedded NUL or post-save failure.
                if require_clean
                    throw failure
                return false
            }

            ; Recheck after the cross-process text read, and on every retry.
            if this.bridge.CurrentPath() != path
                throw Error("The active page changed before saving. Inspect Notepad3 before retrying.")
            if ScratchpadFileStamp(path) != before_save_stamp
                throw Error("The page changed on disk while preparing to save. No automatic overwrite was attempted.")

            ; Always ask the native editor to save: encoding-only changes may not
            ; set Scintilla's text-dirty flag. Its Save handler is synchronous.
            this.bridge.Save()
            if this.bridge.CurrentPath() != path || !FileExist(path)
                throw Error("The save target changed or disappeared. Inspect the editor before retrying.")

            after_save_stamp := ScratchpadFileStamp(path)
            if !this.bridge.MatchesDiskText(path, save_snapshot) {
                ; Notepad3 may trim trailing blanks during Save, or typing may
                ; reach it between our snapshot and its native Save handler.
                ; Accept that newer result only when the current editor is clean
                ; and independently matches disk. A timestamp alone is not proof.
                if this.bridge.IsDirty() || !this.bridge.MatchesDisk(path)
                    || this.bridge.IsDirty()
                {
                    throw Error("The completed save could not be verified against either the submitted snapshot or the clean editor. No new save baseline was accepted. Stop editing briefly and retry, or preserve the editor text with File > Save As.")
                }
            }
            if ScratchpadFileStamp(path) != after_save_stamp
                throw Error("The file changed again while the completed save was being verified.")

            this.AcceptSave(path, after_save_stamp)
            if !require_clean || !this.bridge.IsDirty()
                return true

            ; The native Save already returned; a dirty editor now has newer
            ; edits. Save those on the next pass instead of polling for up to
            ; two seconds for a dirty flag that typing can keep setting.
        }

        throw Error("The page kept changing while Scratchpad tried to save it. Stop editing briefly and retry.")
    }

    AcceptSave(path, stamp)
    {
        ; File comparisons may take time. Do not record success for a document
        ; that was replaced, or a disk version that changed during verification.
        this.bridge.CheckReady()
        if this.bridge.CurrentPath() != path
            throw Error("The active page changed while the completed save was being verified.")
        if ScratchpadFileStamp(path) != stamp
            throw Error("The file changed again before the verified save could be recorded.")
        this.disk_stamp := stamp
        this.PersistCurrentState()
        this.autosave_paused := false
        A_IconTip := "Scratchpad"
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
        next_path := ScratchpadFullPath(next_path)
        attributes := FileExist(next_path)
        if !this.IsScratchPath(next_path) || !attributes || InStr(attributes, "D")
            throw Error("The next scratch page is no longer available:`n" next_path)
        this.RememberPageView(this.current_path)
        before_load_stamp := ScratchpadFileStamp(next_path)
        this.bridge.OpenPage(next_path, this.controller_window.Hwnd)
        if this.bridge.CurrentPath() != next_path
            throw Error("Notepad3 did not load the requested page. Inspect its dialog and retry.")

        this.ProtectPage(next_path)
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
            throw Error("The current scratch page could not be found in the page list.")

        ; Save and leave the page before recycling it. ProtectPage() acquires the
        ; replacement page's lock before releasing this page's delete-denying lock.
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
                "The scratch page could not be moved to the Recycle Bin:`n"
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

    Autosave(*)
    {
        if this.busy || this.autosave_paused || !this.IsVisible()
            return
        ; Never interact with an open native menu, file dialog or move/size loop.
        if !ScratchpadWindowIdle(this.window_hwnd)
            return
        this.busy := true
        try this.SaveCurrentPage(false)
        catch as failure {
            this.autosave_paused := true
            A_IconTip := "Scratchpad - autosave paused"
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
            MonitorGetWorkArea(
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

            MonitorGetWorkArea(
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
        WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
        ; Some window styles impose a minimum size; animate the actual dimensions.
        WinGetPos , , &actual_width, &actual_height, "ahk_id " this.window_hwnd
        bounds.w := actual_width
        bounds.h := actual_height

        ; Scratchpad is a drawer, so it remains topmost whenever it is visible.
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
        WinGetPos &window_x, &window_y, &window_width, &window_height, "ahk_id " this.window_hwnd
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

    IsWinKeyBorderlessWindow(hwnd)
    {
        static marker := "nroj.WinKeyOverhaul.Borderless"

        return hwnd
            && DllCall("IsWindow", "ptr", hwnd, "int")
            && DllCall("GetPropW", "ptr", hwnd, "str", marker, "ptr")
    }

    RaiseDrawerAboveBorderlessWindow()
    {
        if !this.window_hwnd
            || !DllCall("IsWindow", "ptr", this.window_hwnd, "int")
        {
            return
        }

        ; Move Scratchpad to the front of the topmost band without activating it.
        ; The borderless application keeps focus and remains topmost over the taskbar.
        DllCall(
            "SetWindowPos",
            "ptr", this.window_hwnd,
            "ptr", -1, ; HWND_TOPMOST
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", 0x0013, ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
            "int"
        )
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

        WinSetAlwaysOnTop enabled, "ahk_id " this.window_hwnd
    }

    SyncZOrder()
    {
        if !this.IsVisible()
            return

        foreground := DllCall("GetForegroundWindow", "ptr")

        if foreground && foreground != this.window_hwnd
            && !ScratchpadIsDialogWindow(foreground)
        {
            this.last_external_window := foreground
        }

        ; Important dialogs and prompts are still allowed above the drawer.
        dialog := this.FindYieldDialog(foreground)
        if dialog {
            this.YieldDrawerTo(dialog)
            return
        }

        this.SetDrawerTopmost(true)

        ; A clicked Win Key Overhaul borderless window can move ahead inside the
        ; topmost band. Restore Scratchpad above it without stealing focus.
        if foreground
            && foreground != this.window_hwnd
            && this.IsWinKeyBorderlessWindow(foreground)
        {
            this.RaiseDrawerAboveBorderlessWindow()
        }
    }

    FindYieldDialog(foreground)
    {
        if foreground && foreground != this.window_hwnd
            && ScratchpadIsDialogWindow(foreground)
            return foreground

        context := 0
        if foreground && foreground != this.window_hwnd
            && ScratchpadUsableWindow(foreground)
            && !ScratchpadIsDialogWindow(foreground)
        {
            context := foreground
        } else if ScratchpadUsableWindow(this.last_external_window) {
            context := this.last_external_window
        }

        context_pid := context ? ScratchpadWindowProcessId(context) : 0

        ; Keep hidden-window detection enabled elsewhere for the retained editor,
        ; but exclude hidden/cloaked windows from this frequent dialog scan.
        ; Cloaked dialogs on another virtual desktop must not lower this drawer.
        previous_hidden := DetectHiddenWindows(false)
        try candidates := WinGetList()
        finally DetectHiddenWindows previous_hidden

        ; The list follows top-level Z-order. OperationStatusWindow is specific
        ; enough to yield globally; broader dialogs need the current context.
        for candidate in candidates {
            if candidate = this.window_hwnd || !ScratchpadIsDialogWindow(candidate)
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

            owner := DllCall("GetWindow", "ptr", candidate, "uint", 4, "ptr") ; GW_OWNER
            if owner = this.window_hwnd
                return candidate

            if context {
                if owner = context
                    return candidate

                candidate_pid := ScratchpadWindowProcessId(candidate)
                if context_pid && candidate_pid = context_pid
                    return candidate
            }
        }

        return 0
    }

    YieldDrawerTo(dialog)
    {
        if !ScratchpadUsableWindow(dialog)
            return

        this.SetDrawerTopmost(false)

        ; HWND_NOTOPMOST can leave the drawer at the top of the normal band. Put
        ; it explicitly behind the prompt so the prompt becomes visible without
        ; activating, moving, resizing or otherwise modifying that foreign window.
        DllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", dialog,
            "int", 0, "int", 0, "int", 0, "int", 0,
            "uint", 0x213, "int") ; NOSIZE | NOMOVE | NOACTIVATE | NOOWNERZORDER
    }

    AnimateWindow(showing, bounds, animate := true)
    {
        duration := animate ? this.animation_ms : 0
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
            started := ScratchpadClockMs()
            last_frame_y := start_y
            loop {
                progress := duration ? Min(1, (ScratchpadClockMs() - started) / duration) : 1
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
                frame_wait_started := ScratchpadClockMs()
                if DllCall("dwmapi\DwmFlush", "int") != 0
                    Sleep 8
                else if ScratchpadClockMs() - frame_wait_started < 1
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
                WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
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
        if !DllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", 0,
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
        if !DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", region, "int", true, "int") {
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

    HandleEscape()
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
        if pass_escape
            Send "{Escape}" ; Completion/calltip gets Escape before the drawer.
        else
            this.QueueCommand("hide")
    }

    RevealAfterError(source_window)
    {
        if !this.HasWindow()
            return
        try {
            previous_dpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
            try {
                DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                bounds := this.GetBounds()
                if WinGetMinMax("ahk_id " this.window_hwnd) != 0
                    WinRestore "ahk_id " this.window_hwnd
                WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
                WinShow "ahk_id " this.window_hwnd
            }
            finally {
                if previous_dpi
                    DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi, "ptr")
            }
            this.FocusEditor()
        }
    }

    ReportError(failure, notification := false)
    {
        detail := FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " failure.Message
            . "`n" failure.What " | line " failure.Line "`n" failure.Stack "`n`n"
        try FileAppend detail, this.error_log, "UTF-8-RAW"
        if notification
            TrayTip failure.Message, "Scratchpad - autosave paused", 2
        else {
            ; ProcessCommands keeps the controller busy while reporting failures,
            ; so the timer cannot yield Z-order for our own modal message box.
            ; Lower the drawer explicitly, then restore the requested policy.
            restore_topmost := this.IsVisible()
            if restore_topmost
                try this.SetDrawerTopmost(false)
            try MsgBox failure.Message "`n`nDetails: " this.error_log, "Scratchpad", "Iconx 4096"
            finally {
                if restore_topmost && this.IsVisible()
                    try this.SetDrawerTopmost(true)
            }
        }
    }

    ; =========================================================================
    ; tray, GUI help, explicit exit and reload recovery
    ; =========================================================================

    BuildTrayMenu()
    {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Toggle scratchpad", ObjBindMethod(this, "QueueCommand", "toggle"))
        A_TrayMenu.Default := "Toggle scratchpad"

        this.toggle_hotkey_menu := Menu()
        for preset in this.toggle_hotkey_presets
            this.toggle_hotkey_menu.Add(this.DisplayHotkeyName(preset), ObjBindMethod(this, "ChooseToggleHotkey", preset))
        this.toggle_hotkey_menu.Add()
        this.toggle_hotkey_menu.Add("Custom...", ObjBindMethod(this, "ShowCustomHotkeyDialog"))
        this.toggle_hotkey_menu.Add("Disabled", ObjBindMethod(this, "ChooseToggleHotkey", "Disabled"))
        A_TrayMenu.Add("Toggle shortcut", this.toggle_hotkey_menu)

        this.monitor_menu := Menu()
        this.BuildMonitorMenu()
        A_TrayMenu.Add("Display", this.monitor_menu)

        this.window_width_menu := Menu()
        for percent in this.window_width_presets {
            this.window_width_menu.Add(
                percent "%",
                ObjBindMethod(this, "SetWindowSizePercent", "width", percent)
            )
        }

        this.window_height_menu := Menu()
        for percent in this.window_height_presets {
            this.window_height_menu.Add(
                percent "%",
                ObjBindMethod(this, "SetWindowSizePercent", "height", percent)
            )
        }

        A_TrayMenu.Add("Window width", this.window_width_menu)
        A_TrayMenu.Add("Window height", this.window_height_menu)

        A_TrayMenu.Add()
        A_TrayMenu.Add("Open scratch folder", (*) => Run('explorer.exe "' this.scratch_directory '"'))
        A_TrayMenu.Add("Open settings", (*) => Run('notepad.exe "' this.settings_path '"'))
        A_TrayMenu.Add("How to use", ObjBindMethod(this, "ShowHelp"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Run at startup", ObjBindMethod(this, "ToggleStartup"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Reload", ObjBindMethod(this, "QueueCommand", "reload"))
        A_TrayMenu.Add("Exit", ObjBindMethod(this, "QueueCommand", "exit"))
        this.UpdateTrayChecks()
    }

    BuildMonitorMenu()
    {
        try this.monitor_menu.Delete()
        this.monitor_menu_items := Map()
        this.monitor_menu_items.CaseSense := "Off"

        main_label := "Main display"
        this.monitor_menu.Add(
            main_label,
            ObjBindMethod(this, "SetMonitorTarget", "Primary")
        )
        this.monitor_menu_items["Primary"] := main_label

        monitor_count := MonitorGetCount()
        if monitor_count {
            this.monitor_menu.Add()
            primary_index := MonitorGetPrimary()

            loop monitor_count {
                monitor_index := A_Index
                try {
                    monitor_name := MonitorGetName(monitor_index)
                    ; MonitorGetCount can include displays which are not currently
                    ; part of the desktop. Only offer displays with a usable work area.
                    MonitorGetWorkArea(monitor_index)
                }
                catch
                    continue

                label := this.MonitorMenuLabel(monitor_name, monitor_index)
                if monitor_index = primary_index
                    label .= " (main)"

                this.monitor_menu.Add(
                    label,
                    ObjBindMethod(this, "SetMonitorTarget", monitor_name)
                )
                this.monitor_menu_items[monitor_name] := label
            }
        }

        ; Keep a disconnected pinned display visible in the menu. Scratchpad
        ; falls back to the main display until that Windows display returns.
        if this.monitor_target != "Primary"
            && !this.monitor_menu_items.Has(this.monitor_target)
        {
            this.monitor_menu.Add()
            unavailable_label := this.MonitorMenuLabel(this.monitor_target)
                . " (unavailable)"
            this.monitor_menu.Add(unavailable_label, (*) => 0)
            this.monitor_menu.Disable(unavailable_label)
            this.monitor_menu_items[this.monitor_target] := unavailable_label
        }

        this.UpdateMonitorMenu()
    }

    MonitorMenuLabel(monitor_name, fallback_index := 0)
    {
        if RegExMatch(monitor_name, "i)DISPLAY(\d+)$", &match)
            return "Display " match[1]

        if fallback_index
            return "Display " fallback_index

        return monitor_name
    }

    SetMonitorTarget(target, *)
    {
        try IniWrite target, this.settings_path, "Window", "Monitor"
        catch as failure {
            MsgBox(
                failure.Message,
                "Scratchpad display",
                "Iconx 4096"
            )
            return
        }

        this.monitor_target := target
        this.UpdateMonitorMenu()
        this.QueueCommand("resize")
    }

    UpdateMonitorMenu()
    {
        if !this.monitor_menu
            return

        for target, item in this.monitor_menu_items
            try this.monitor_menu.Uncheck(item)

        if this.monitor_menu_items.Has(this.monitor_target) {
            try this.monitor_menu.Check(this.monitor_menu_items[this.monitor_target])
        }
        else if this.monitor_menu_items.Has("Primary") {
            try this.monitor_menu.Check(this.monitor_menu_items["Primary"])
        }
    }

    SetWindowSizePercent(dimension, percent, *)
    {
        if dimension != "width" && dimension != "height"
            return

        setting_name := dimension = "width"
            ? "WidthPercent"
            : "HeightPercent"

        try {
            IniWrite percent, this.settings_path, "Window", setting_name
        }
        catch as failure {
            MsgBox(
                failure.Message,
                "Scratchpad window size",
                "Iconx 4096"
            )
            return
        }

        if dimension = "width"
            this.width_percent := percent
        else
            this.height_percent := percent

        this.UpdateWindowSizeMenu()
        this.QueueCommand("resize")
    }

    ApplyWindowSize()
    {
        if !this.IsVisible()
            return

        previous_dpi_context := DllCall(
            "SetThreadDpiAwarenessContext",
            "ptr", -4,
            "ptr"
        )

        try {
            bounds := this.GetBounds()

            WinMove(
                bounds.x,
                bounds.y,
                bounds.w,
                bounds.h,
                "ahk_id " this.window_hwnd
            )

            WinGetPos(
                &actual_x,
                &actual_y,
                &actual_width,
                &actual_height,
                "ahk_id " this.window_hwnd
            )

            this.last_bounds := {
                x: actual_x,
                y: actual_y,
                w: actual_width,
                h: actual_height
            }
        }
        catch as failure {
            MsgBox(
                "The size was saved, but the current window could not be resized.`n`n"
                    . failure.Message,
                "Scratchpad window size",
                "Iconx 4096"
            )
        }
        finally {
            if previous_dpi_context {
                DllCall(
                    "SetThreadDpiAwarenessContext",
                    "ptr", previous_dpi_context,
                    "ptr"
                )
            }
        }
    }

    UpdateWindowSizeMenu()
    {
        if !this.window_width_menu || !this.window_height_menu
            return

        for percent in this.window_width_presets {
            item := percent "%"
            this.window_width_menu.Uncheck(item)

            if percent = this.width_percent
                this.window_width_menu.Check(item)
        }

        for percent in this.window_height_presets {
            item := percent "%"
            this.window_height_menu.Uncheck(item)

            if percent = this.height_percent
                this.window_height_menu.Check(item)
        }
    }

    DisplayHotkeyName(name)
    {
        return StrReplace(name, "+", " + ")
    }

    ChooseToggleHotkey(name, *)
    {
        try this.SetToggleHotkey(name)
        catch as failure
            MsgBox failure.Message, "Scratchpad shortcut", "Iconx 4096"
    }

    UpdateToggleHotkeyMenu()
    {
        if !this.toggle_hotkey_menu
            return

        for preset in this.toggle_hotkey_presets
            try this.toggle_hotkey_menu.Uncheck(this.DisplayHotkeyName(preset))
        try this.toggle_hotkey_menu.Uncheck("Custom...")
        try this.toggle_hotkey_menu.Uncheck("Disabled")

        is_preset := false
        for preset in this.toggle_hotkey_presets {
            if preset = this.toggle_hotkey_name {
                this.toggle_hotkey_menu.Check(this.DisplayHotkeyName(preset))
                is_preset := true
                break
            }
        }
        if !is_preset {
            if this.toggle_hotkey_name = "Disabled"
                this.toggle_hotkey_menu.Check("Disabled")
            else
                this.toggle_hotkey_menu.Check("Custom...")
        }
    }

    ShowCustomHotkeyDialog(*)
    {
        if this.custom_hotkey_gui {
            try this.custom_hotkey_gui.Show()
            return
        }

        custom_gui := Gui("+AlwaysOnTop", "Scratchpad shortcut")
        custom_gui.SetFont("s10", "Segoe UI")
        custom_gui.AddText("w330", "Press a key combination. Use the Win checkbox for Windows-key shortcuts.")
        hotkey_control := custom_gui.AddHotkey("xm w250")
        win_control := custom_gui.AddCheckBox("xm y+10", "Include Win")
        custom_gui.AddText("xm y+10 w330", "Plain letters and numbers require a modifier; F1-F24 may be used alone.")
        use_button := custom_gui.AddButton("xm y+14 w90 Default", "Use")
        cancel_button := custom_gui.AddButton("x+8 w90", "Cancel")

        use_button.OnEvent("Click", UseCustomHotkey)
        cancel_button.OnEvent("Click", CloseCustomHotkey)
        custom_gui.OnEvent("Close", CloseCustomHotkey)
        custom_gui.OnEvent("Escape", CloseCustomHotkey)
        this.custom_hotkey_gui := custom_gui
        custom_gui.Show()

        UseCustomHotkey(*) {
            try {
                friendly := this.FriendlyFromHotkeyControl(hotkey_control.Value, !!win_control.Value)
                this.SetToggleHotkey(friendly)
                CloseCustomHotkey()
            }
            catch as failure {
                MsgBox failure.Message, "Scratchpad shortcut", "Iconx 4096"
            }
        }

        CloseCustomHotkey(*) {
            try custom_gui.Destroy()
            this.custom_hotkey_gui := 0
        }
    }

    ToggleStartup(*)
    {
        if FileExist(this.startup_shortcut)
            FileDelete this.startup_shortcut
        else if A_IsCompiled
            FileCreateShortcut A_ScriptFullPath, this.startup_shortcut, A_ScriptDir
        else
            FileCreateShortcut A_AhkPath, this.startup_shortcut, A_ScriptDir, '"' A_ScriptFullPath '"'
        this.UpdateTrayChecks()
    }

    UpdateTrayChecks()
    {
        this.UpdateToggleHotkeyMenu()
        this.UpdateMonitorMenu()
        this.UpdateWindowSizeMenu()

        if FileExist(this.startup_shortcut)
            A_TrayMenu.Check("Run at startup")
        else
            A_TrayMenu.Uncheck("Run at startup")
    }

    ShowHelp(*)
    {
        static help_gui := 0
        static help_icons := []

        if help_gui {
            CloseHelp()
            return
        }

        help_gui := Gui("+AlwaysOnTop", "Scratchpad")
        help_icons := SetScratchpadHelpIcons(help_gui)
        help_gui.SetFont("s10", "Cascadia Mono")

        help_text :=
        (
        "GLOBAL`n"
        this.DisplayHotkeyName(this.toggle_hotkey_name) "   Toggle scratchpad`n"
        "Change the toggle shortcut from the tray menu.`n"
        "`n"
        "INSIDE THE EDITOR`n"
        "Escape                  Hide scratchpad`n"
        "Ctrl + N / Ctrl + S     New page / save page`n"
        "Win + F4                Delete page to Recycle Bin`n"
        "Win + Left / PgDn       Previous page`n"
        "Win + Right / PgUp      Next page`n"
        "`n"
        "PAGES`n"
        "New pages are named automatically.`n"
        "Scratchpad remembers the last used page between launches.`n"
        "Use File > Save As to name a page; rename closed files normally.`n"
        "`n"
        "SAVING`n"
        "Autosave runs while visible (10 seconds by default).`n"
        "Pages are also saved before hiding or switching.`n"
        "Undo history survives hiding, but not switching pages.`n"
        "`n"
        "SETTINGS`n"
        "Display defaults to the Windows main display; choose a pinned display in the tray.`n"
        "Choose common window sizes from Window width / Window height in the tray menu.`n"
        "Use Open settings for exact percentages, display, scratch folder, Notepad3 path,`n"
        "animation, autosave interval, and toggle shortcut.`n"
        "Reload Scratchpad after editing settings.ini directly.`n"
        "`n"
        "SCRATCH FOLDER`n"
        )

        help_text .= this.scratch_directory

        help_gui.AddText("w610", help_text)

        help_gui.OnEvent("Close", CloseHelp)
        help_gui.OnEvent("Escape", CloseHelp)
        help_gui.Show()

        CloseHelp(*) {
            try help_gui.Destroy()
            help_gui := 0

            for icon_handle in help_icons
                DllCall("DestroyIcon", "ptr", icon_handle, "int")

            help_icons := []
        }
    }

    ExitScratchpad()
    {
        ; Also find a retained editor when Exit is used directly after Reload.
        if this.HasWindow() || this.AttachExistingWindow() {
            this.SaveCurrentPage()
            target_hwnd := this.window_hwnd
            ; A normal close permits Notepad3's own final save checks and prompts.
            ; No process-wide kill, no global executable/class matching.
            PostMessage 0x0010, 0, 0, , "ahk_id " target_hwnd ; WM_CLOSE
            if !WinWaitClose("ahk_id " target_hwnd, , 5)
                throw Error("Notepad3 has not closed. Resolve its dialog, then choose Exit again.")
            this.window_hwnd := 0
            this.editor_pid := 0
            this.bridge := 0
        }
        this.exit_prepared := true
        ExitApp
    }

    OnScriptExit(exit_reason, exit_code)
    {
        SetTimer this.autosave_callback, 0
        SetTimer this.page_lock_sync_callback, 0
        SetTimer this.process_commands_callback, 0
        if this.HasWindow() {
            if !this.exit_prepared {
                try this.SaveCurrentPage()
            }
            ; Reload retains the real editor and its undo history. Unexpected
            ; ordinary exits reveal it rather than stranding a hidden document.
            try {
                DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                bounds := this.last_bounds ? this.last_bounds : this.GetBounds()
                WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
                if exit_reason != "Reload" && exit_reason != "Single"
                    && exit_reason != "Shutdown" && exit_reason != "Logoff" {
                    WinSetAlwaysOnTop false, "ahk_id " this.window_hwnd
                    WinShow "ahk_id " this.window_hwnd
                }
            }
        }
        this.ReleasePageLock()
        this.bridge := 0
        if this.mutex_handle {
            DllCall("CloseHandle", "ptr", this.mutex_handle)
            this.mutex_handle := 0
        }
        return 0
    }
}


; =============================================================================
; Notepad3 / Scintilla bridge
; =============================================================================
; Verified against Notepad3 source: src/Notepad3.h (np3params, IDC_*),
; src/Notepad3.c (MsgCopyData, _SetEnumWindowsItems, MsgCommand), and
; language/common_res.h (command IDs). Native message handlers may return zero
; even on success; transport success and the resulting editor state are distinct.
;
; WM_GETTEXT and WM_COPYDATA are marshaled by Windows. Scintilla calls below carry
; integers only. There is no VirtualAllocEx, WriteProcessMemory or pointer injection.
; =============================================================================

; A changing text length is retryable before Save; corrupt/unsupported text and
; failed message transport remain ordinary hard errors.
class ScratchpadTextChangedError extends Error
{
}

class Notepad3Bridge
{

    static encoding_utf8 := 40103
    static line_endings_lf := 40202
    static view_menubar := 41023
    static view_toolbar := 41024
    static minimize_to_tray := 42019
    static no_escape_action := 42027

    __New(hwnd)
    {
        this.hwnd := hwnd
        this.tainted := false
        ; One bounded WM_GETTEXT reads the filename atomically. Keep an extra
        ; character beyond the path limit so truncation is never accepted.
        this.filename_buffer := Buffer((32767 + 2) * 2, 0)
        this.cached_filename := ""
        this.cached_full_path := ""
        this.pid := WinGetPID("ahk_id " hwnd)
        this.editor_hwnd := DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB03, "ptr")
        this.filename_hwnd := DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB05, "ptr")
        if !this.editor_hwnd || !this.filename_hwnd
            throw Error("This window does not expose the expected Notepad3 controls. No document was changed.")
        if WinGetClass("ahk_id " this.editor_hwnd) != "Scintilla"
            throw Error("The Notepad3 editor control is not Scintilla. No document was changed.")
    }

    CheckReady()
    {
        if this.tainted
            throw Error("The previous Notepad3 request timed out. Resolve its dialog, then retry.")
        if !DllCall("IsWindow", "ptr", this.hwnd, "int")
            || WinGetPID("ahk_id " this.hwnd) != this.pid
            throw Error("The owned Notepad3 window is no longer available.")
        if !ScratchpadWindowIdle(this.hwnd)
            throw Error("Finish or cancel the Notepad3 menu/dialog before using a scratch command.")
    }

    Send(message, w_param := 0, l_param := 0, target_hwnd := 0)
    {
        if this.tainted
            throw Error("Notepad3 is still waiting on a previous request. Resolve its dialog and retry.")
        if !target_hwnd
            target_hwnd := this.hwnd
        result := Buffer(A_PtrSize, 0)
        ; SMTO_BLOCK | SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT. A timeout is NOT success.
        if !DllCall("SendMessageTimeoutW", "ptr", target_hwnd, "uint", message,
            "uptr", w_param, "ptr", l_param, "uint", 0x23, "uint", 3000,
            "ptr", result, "ptr") {
            this.tainted := true
            throw Error("Notepad3 did not respond within three seconds (message " Format("0x{:X}", message)
                . "). Resolve any editor dialog, then retry. No save or close was assumed successful.")
        }
        return NumGet(result, 0, "ptr")
    }

    CurrentPath()
    {
        capacity := this.filename_buffer.Size // 2
        copied := this.Send(0x000D, capacity, this.filename_buffer.Ptr, this.filename_hwnd) ; WM_GETTEXT
        if copied < 0 || copied > 32767
            throw Error("Notepad3's current filename exceeds the supported path length.")
        path := copied ? StrGet(this.filename_buffer, copied, "UTF-16") : ""
        if StrLen(path) != copied
            throw Error("Notepad3 returned an invalid current filename.")

        ; The visible watcher reads this four times per second. Avoid two path
        ; normalization calls whenever the actual filename has not changed.
        if !(path == this.cached_filename) {
            full_path := path = "" ? "" : ScratchpadFullPath(path)
            this.cached_filename := path
            this.cached_full_path := full_path
        }
        return this.cached_full_path
    }

    ReadWindowText(hwnd, limit := 16777216)
    {
        ; Standard Unicode WM_GETTEXT is marshaled by Windows. Retry a changing
        ; length briefly; a short read caused by typing is not a disk conflict.
        loop 3 {
            length := this.Send(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH
            if length < 0 || length > limit
                throw Error("The editor text is too large to verify automatically. Save it manually in Notepad3.")
            text_buffer := Buffer((length + 1) * 2, 0)
            copied := this.Send(0x000D, length + 1, text_buffer.Ptr, hwnd) ; WM_GETTEXT
            if copied < 0 || copied > length
                throw Error("Notepad3 returned an invalid editor text length.")
            text := copied ? StrGet(text_buffer, copied, "UTF-16") : ""
            if StrLen(text) != copied
                throw Error("The editor contains embedded NUL characters. Save it manually in Notepad3.")
            if this.Send(0x000E, 0, 0, hwnd) = length && copied = length
                return text
        }
        throw ScratchpadTextChangedError("The editor kept changing while its text was being read. Retry after editing stops.")
    }

    Scintilla(message, w_param := 0, l_param := 0)
    {
        return this.Send(message, w_param, l_param, this.editor_hwnd)
    }

    IsDirty()
    {
        return this.Scintilla(2159) != 0 ; SCI_GETMODIFY
    }

    Command(command_id)
    {
        this.CheckReady()
        this.Send(0x0111, command_id, 0) ; WM_COMMAND, native menu command
        this.CheckReady()
    }

    Save()
    {
        ; File > Save is the third item in Notepad3's File menu.
        ; Resolve its command ID from the running editor instead of hardcoding it.
        command_id := this.MenuCommandId(0, 2)
        this.Command(command_id)
    }

    MenuCommandId(top_level_index, item_index)
    {
        this.CheckReady()

        main_menu := DllCall("GetMenu", "ptr", this.hwnd, "ptr")
        if !main_menu
            throw Error("Notepad3's menu bar is unavailable.")

        submenu := DllCall(
            "GetSubMenu",
            "ptr", main_menu,
            "int", top_level_index,
            "ptr"
        )

        if !submenu
            throw Error("Notepad3's expected menu is unavailable.")

        command_id := DllCall(
            "GetMenuItemID",
            "ptr", submenu,
            "int", item_index,
            "uint"
        )

        if command_id = 0xFFFFFFFF
            throw Error("Notepad3's Save command could not be resolved.")

        return command_id
    }

    MenuState(command_id)
    {
        menu_handle := DllCall("GetMenu", "ptr", this.hwnd, "ptr")
        if !menu_handle
            throw Error("Show Notepad3's menu bar before retrying the scratch command.")
        this.Send(0x0116, menu_handle, 0) ; WM_INITMENU refreshes dynamic check states.
        state := DllCall("GetMenuState", "ptr", menu_handle, "uint", command_id, "uint", 0, "uint")
        if state = 0xFFFFFFFF
            throw Error("Notepad3's expected menu command is missing: " command_id)
        return state
    }

    PrepareDrawer()
    {
        this.CheckReady()
        ; Keep native File/Settings menus available for saving and error recovery.
        if !DllCall("GetMenu", "ptr", this.hwnd, "ptr")
            this.Command(Notepad3Bridge.view_menubar)
        for command_id in [Notepad3Bridge.view_toolbar, Notepad3Bridge.minimize_to_tray] {
            if this.MenuState(command_id) & 8 ; MF_CHECKED
                this.Command(command_id)
        }
        ; Our Escape handler owns hiding, not Notepad3's optional Escape-to-exit.
        this.Command(Notepad3Bridge.no_escape_action)
    }

    OpenPage(path, sender_hwnd)
    {
        this.CheckReady()
        if this.IsDirty()
            throw Error("The current page became dirty during switching. It has not been replaced.")
        ; np3params is twelve 32-bit fields, then UTF-16 text at offset 48.
        ; sizeof(np3params) is 52 (tail padding), regardless of editor bitness.
        payload := Buffer(52 + StrPut(path, "UTF-16") * 2, 0)
        NumPut("int", 1, payload, 0)   ; flagFileSpecified
        NumPut("int", 2, payload, 4)   ; FWM_MSGBOX: prompt, never silently reload
        NumPut("int", -1, payload, 32) ; CPI_NONE: preserve file encoding detection
        StrPut path, payload.Ptr + 48, (payload.Size - 48) // 2, "UTF-16"
        copy_data := Buffer(3 * A_PtrSize, 0)
        NumPut("uptr", 0xFB10, copy_data, 0) ; DATA_NOTEPAD3_PARAMS
        NumPut("uint", payload.Size, copy_data, A_PtrSize)
        NumPut("ptr", payload.Ptr, copy_data, 2 * A_PtrSize)
        this.Send(0x004A, sender_hwnd, copy_data.Ptr) ; WM_COPYDATA (not PostMessage)
        ; MsgCopyData returns FALSE even on a successful load. Check the real path.
        this.CheckReady()
        if this.CurrentPath() != path
            throw Error("Notepad3 did not switch to:`n" path)
    }

    DocumentText()
    {
        this.CheckReady()
        return this.ReadWindowText(this.editor_hwnd)
    }

    MatchesDisk(path)
    {
        return this.MatchesDiskText(path, this.DocumentText())
    }

    MatchesDiskText(path, expected_text)
    {
        limit := 32 * 1024 * 1024
        if FileGetSize(path) > limit
            throw Error("This file is too large for automatic conflict comparison. Preserve both versions before continuing.")
        ; Bound the read itself too: a concurrently growing file must not bypass
        ; the limit checked above. One extra byte detects a truncated read.
        bytes := FileRead(path, "RAW m" (limit + 1))
        size := bytes.Size
        if size > limit
            throw Error("This file grew beyond the automatic comparison limit. Preserve both versions before continuing.")
        if !size
            disk_text := ""
        else if size >= 2 && NumGet(bytes, 0, "ushort") = 0xFEFF {
            if Mod(size - 2, 2)
                return false
            disk_text := StrGet(bytes.Ptr + 2, (size - 2) // 2, "UTF-16")
            if StrLen(disk_text) != (size - 2) // 2
                return false
        }
        else {
            ; Strict UTF-8 for the normal scratch format; BOM is not document text.
            offset := size >= 3 && NumGet(bytes, 0, "uchar") = 0xEF
                && NumGet(bytes, 1, "uchar") = 0xBB && NumGet(bytes, 2, "uchar") = 0xBF ? 3 : 0
            if size = offset
                disk_text := ""
            else {
                count := DllCall("MultiByteToWideChar", "uint", 65001, "uint", 8,
                    "ptr", bytes.Ptr + offset, "int", size - offset, "ptr", 0, "int", 0, "int")
                if !count
                    throw Error("Automatic conflict comparison supports UTF-8 and UTF-16 LE pages. This file uses another encoding. Preserve the editor text with File > Save As to a new UTF-8 scratch page.")
                unicode := Buffer((count + 1) * 2, 0)
                if !DllCall("MultiByteToWideChar", "uint", 65001, "uint", 8,
                    "ptr", bytes.Ptr + offset, "int", size - offset, "ptr", unicode, "int", count, "int")
                    throw OSError(A_LastError, "MultiByteToWideChar")
                disk_text := StrGet(unicode, "UTF-16")
                if StrLen(disk_text) != count
                    return false
            }
        }
        return disk_text == expected_text
    }
}


; =============================================================================
; small native helpers
; =============================================================================

ScratchpadWindowIdle(hwnd)
{
    if !DllCall("IsWindowEnabled", "ptr", hwnd, "int")
        return false
    thread_id := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    info := Buffer(72, 0) ; GUITHREADINFO, 64-bit
    NumPut("uint", info.Size, info)
    if !DllCall("GetGUIThreadInfo", "uint", thread_id, "ptr", info, "int")
        return false
    if NumGet(info, 4, "uint") & 0x1E ; menus, popup menus, move/size loops
        return false
    popup := DllCall("GetLastActivePopup", "ptr", hwnd, "ptr")
    return !popup || popup = hwnd || !DllCall("IsWindowVisible", "ptr", popup, "int")
}

ScratchpadUsableWindow(hwnd)
{
    return hwnd
        && DllCall("IsWindow", "ptr", hwnd, "int")
        && DllCall("IsWindowVisible", "ptr", hwnd, "int")
        && !DllCall("IsIconic", "ptr", hwnd, "int")
}

ScratchpadWindowProcessId(hwnd)
{
    if !hwnd
        return 0
    process_id := Buffer(4, 0)
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", process_id, "uint")
    return NumGet(process_id, 0, "uint")
}

ScratchpadIsDialogWindow(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("IsIconic", "ptr", hwnd, "int")
        return false

    try {
        window_class := WinGetClass("ahk_id " hwnd)
        if window_class = "#32770" || window_class = "OperationStatusWindow"
            return true
    }
    catch {
        return false
    }

    ex_style := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", -20, "ptr")
    if ex_style & 0x1 ; WS_EX_DLGMODALFRAME
        return true

    ; Owned top-level windows are commonly prompts, property sheets and other
    ; transient UI that should not be hidden under an explicitly topmost drawer.
    return DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") != 0 ; GW_OWNER
}

ScratchpadFullPath(path)
{
    required := DllCall("GetFullPathNameW", "str", path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
    if !required
        throw OSError(A_LastError, "GetFullPathNameW", path)
    path_buffer := Buffer(required * 2, 0)
    length := DllCall("GetFullPathNameW", "str", path, "uint", required, "ptr", path_buffer, "ptr", 0, "uint")
    if !length || length >= required
        throw Error("Could not normalize the file path:`n" path)
    return StrGet(path_buffer, "UTF-16")
}

SetScratchpadHelpIcons(help_gui)
{
    icon_handles := []
    icon_path := A_ScriptDir "\icons\scratchpad.ico"

    if !FileExist(icon_path)
        return icon_handles

    try {
        for icon_index, size in [16, 32] {
            image_type := 0
            icon_handle := LoadPicture(
                icon_path,
                "Icon1 w" size " h" size,
                &image_type
            )

            if !icon_handle
                continue

            if image_type != 1 {
                DllCall(
                    image_type = 2 ? "DestroyCursor" : "DeleteObject",
                    "ptr",
                    icon_handle,
                    "int"
                )
                continue
            }

            icon_handles.Push(icon_handle)

            SendMessage(
                0x0080,
                icon_index - 1,
                icon_handle,
                ,
                help_gui.Hwnd
            )
        }
    }
    catch {
    }

    return icon_handles
}


ScratchpadFileStamp(path)
{
    attributes := Buffer(36, 0) ; WIN32_FILE_ATTRIBUTE_DATA
    if !DllCall("GetFileAttributesExW", "str", path, "int", 0, "ptr", attributes, "int")
        throw OSError(A_LastError, "GetFileAttributesExW", path)
    ; Preserve FILETIME precision, including same-size edits within one second.
    return Format("{:016X}:{:08X}{:08X}", NumGet(attributes, 20, "int64"),
        NumGet(attributes, 28, "uint"), NumGet(attributes, 32, "uint"))
}

ScratchpadClockMs()
{
    static frequency := 0
    if !frequency
        DllCall("QueryPerformanceFrequency", "int64*", &frequency)
    counter := 0
    DllCall("QueryPerformanceCounter", "int64*", &counter)
    return counter * 1000 / frequency
}
