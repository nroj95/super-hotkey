; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; tray menu and settings
; =============================================================================

BuildTrayMenu()
{
    ; Editable bindings replace the fixed rotation submenu.
    global focus_tab_color_presets
    global focus_tab_color_menu
    global focus_tab_active_slot_color_menu
    global focus_tab_inactive_slot_color_menu

    A_TrayMenu.Delete()

    A_TrayMenu.Add("How to use", ToggleWindowCascadeHelp)
    A_TrayMenu.Add("Keybindings", ShowCascadeKeybindings)
    A_TrayMenu.Add("How to debug", ShowWindowCascadeDebugHelp)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Pause auto cascading", ToggleCascadeAutoPlacement)
    A_TrayMenu.Add("Show focus tabs", ToggleFocusCornerVisibility)

    focus_tab_active_slot_color_menu := Menu()
    focus_tab_inactive_slot_color_menu := Menu()

    for color_name, color_value in focus_tab_color_presets {
        focus_tab_active_slot_color_menu.Add(
            color_name,
            SetFocusTabColor.Bind("active", color_name)
        )
        focus_tab_inactive_slot_color_menu.Add(
            color_name,
            SetFocusTabColor.Bind("inactive", color_name)
        )
    }

    focus_tab_color_menu := Menu()
    focus_tab_color_menu.Add(
        "Active slot",
        focus_tab_active_slot_color_menu
    )
    focus_tab_color_menu.Add(
        "Inactive slots",
        focus_tab_inactive_slot_color_menu
    )
    A_TrayMenu.Add("Focus tab colors", focus_tab_color_menu)
    A_TrayMenu.Add("Check compatibility", CheckCompatibilitySettings)



    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", ToggleStartup)
    A_TrayMenu.Add("Verbose debug logging", ToggleVerboseDebugLogging)
    A_TrayMenu.Add()
    A_TrayMenu.AddStandard()
    ; Native Pause/Suspend would bypass Window Cascade's own runtime state.
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")

    UpdateTrayMenu()
}


SetFocusTabColor(target_group, color_name, *)
{
    global settings_directory, settings_path
    global focus_tab_color_presets
    global focus_corner_active_slot_color_name
    global focus_corner_inactive_slot_color_name
    global focus_corner_active_slot_color
    global focus_corner_inactive_slot_color

    if !focus_tab_color_presets.Has(color_name)
        return

    switch target_group {
        case "active":
            setting_name := "ActiveSlotColor"
        case "inactive":
            setting_name := "InactiveSlotColor"
        default:
            return
    }

    try {
        DirCreate(settings_directory)
        IniWrite(
            color_name,
            settings_path,
            "FocusTabs",
            setting_name
        )
    }
    catch Error as err {
        MsgBox(
            "Could not save the focus-tab color.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
        return
    }

    if target_group = "active" {
        focus_corner_active_slot_color_name := color_name
        focus_corner_active_slot_color := focus_tab_color_presets[color_name]
    } else {
        focus_corner_inactive_slot_color_name := color_name
        focus_corner_inactive_slot_color := focus_tab_color_presets[color_name]
    }

    UpdateFocusCornerOverlays()
    UpdateTrayMenu()
}

ShowCascadeStatusTip(text)
{
    CoordMode "Mouse", "Screen"
    CoordMode "ToolTip", "Screen"
    MouseGetPos &mouse_x, &mouse_y

    ; Every new status replaces the previous one and owns a fresh timeout.
    SetTimer HideCascadeStatusTip, 0
    ToolTip text, mouse_x + 14, mouse_y + 18, 3
    SetTimer HideCascadeStatusTip, -1400
}

HideCascadeStatusTip()
{
    ToolTip , , , 3
}


ToggleStartup(*)
{
    global startup_shortcut_path

    try {
        if FileExist(startup_shortcut_path) {
            FileDelete(startup_shortcut_path)
        } else if A_IsCompiled {
            FileCreateShortcut(
                A_ScriptFullPath,
                startup_shortcut_path,
                A_ScriptDir
            )
        } else {
            FileCreateShortcut(
                A_AhkPath,
                startup_shortcut_path,
                A_ScriptDir,
                '"' A_ScriptFullPath '"'
            )
        }

        UpdateTrayMenu()
    }
    catch Error as err {
        MsgBox(
            "Could not update the startup shortcut.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
    }
}

UpdateTrayMenu()
{
    global cascade_auto_placement_paused, startup_shortcut_path
    global focus_corner_visible, debug_verbose_enabled
    ; Rotate bindings now live in the shared Keybindings settings.
    global focus_tab_color_presets
    global focus_corner_active_slot_color_name
    global focus_corner_inactive_slot_color_name
    global focus_tab_active_slot_color_menu
    global focus_tab_inactive_slot_color_menu

    if cascade_auto_placement_paused
        A_TrayMenu.Check("Pause auto cascading")
    else
        A_TrayMenu.Uncheck("Pause auto cascading")

    A_IconTip := cascade_auto_placement_paused ? "Window Cascade (auto cascading paused)" : "Window Cascade"

    if focus_corner_visible
        A_TrayMenu.Check("Show focus tabs")
    else
        A_TrayMenu.Uncheck("Show focus tabs")

    if debug_verbose_enabled
        A_TrayMenu.Check("Verbose debug logging")
    else
        A_TrayMenu.Uncheck("Verbose debug logging")

    if (
        IsObject(focus_tab_active_slot_color_menu)
        && IsObject(focus_tab_inactive_slot_color_menu)
    ) {
        for color_name, color_value in focus_tab_color_presets {
            focus_tab_active_slot_color_menu.Uncheck(color_name)
            focus_tab_inactive_slot_color_menu.Uncheck(color_name)
        }

        focus_tab_active_slot_color_menu.Check(
            focus_corner_active_slot_color_name
        )
        focus_tab_inactive_slot_color_menu.Check(
            focus_corner_inactive_slot_color_name
        )
    }

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}


; =============================================================================
; help
; =============================================================================

GetWindowCascadeHelpState()
{
    static state := {
        help_gui: 0,
        help_icons: [],
        help_text: 0,
        more_help_gui: 0,
        more_help_icons: []
    }
    return state
}


CascadeHelpActionBinding(actionId, configuration := 0)
{
    global cascade_keybindings

    if !IsObject(cascade_keybindings)
        return "(unavailable)"
    if !IsObject(configuration)
        configuration := cascade_keybindings.GetConfiguration()
    if !configuration.Has(actionId)
        return "(unavailable)"

    setting := configuration[actionId]
    bindings := []
    for encoded in setting.bindings {
        parsed := Keybindings.Parse(encoded)
        if IsObject(parsed)
            bindings.Push(parsed.label)
    }

    label := bindings.Length ? Keybindings.Join(bindings, " / ") : "(unassigned)"
    return setting.enabled ? label : label " (disabled)"
}

BuildCascadeHelpText()
{
    global cascade_keybindings

    if !IsObject(cascade_keybindings) || !cascade_keybindings.running
        return "Keybindings are unavailable. Window management and the tray menu still work."

    configuration := cascade_keybindings.GetConfiguration()
    text := ""
    spaces := "                                                            "

    ; Show all actions using their current saved bindings.
    text .= "Hold Caps or Pause for a layer shortcut.`n"
    text .= "Tap a layer key for one-shot input (1.4 seconds).`n`n"

    for actionId, action in cascade_keybindings.actions {
        binding := CascadeHelpActionBinding(actionId, configuration)
        if StrLen(binding) > 32
            text .= binding "`n    " action.label "`n"
        else
            text .= binding SubStr(spaces, 1, 34 - StrLen(binding)) action.label "`n"
    }

    text .= "`nClick a focus tab to change its exposed window.`n"
    text .= "Drag near a slot to adopt or re-slot a window.`n"
    text .= "Caps/Pause shortcuts require the separate Caps + Pause Layers service.`n"
    text .= "Bindings shown are saved assignments; conflicts can prevent activation."
    return text
}

RefreshCascadeHelpBindings(*)
{
    state := GetWindowCascadeHelpState()
    if IsObject(state.help_text)
        state.help_text.Text := BuildCascadeHelpText()
}

ToggleWindowCascadeHelp(*)
{
    state := GetWindowCascadeHelpState()

    if state.help_gui || state.more_help_gui {
        CloseWindowCascadeHelp()
        return
    }

    state.help_gui := CallWithDpiContext(-2, Gui, "+AlwaysOnTop", "Window Cascade")
    state.help_icons := SetWindowCascadeHelpIcons(state.help_gui)
    state.help_gui.SetFont("s10", "Cascadia Mono")

    state.help_text := state.help_gui.AddText(
        "w780", BuildCascadeHelpText())

    more_help_button := state.help_gui.AddButton("xm+660 w120", "More help")
    more_help_button.OnEvent("Click", ShowWindowCascadeMoreHelp)

    state.help_gui.OnEvent("Close", CloseWindowCascadeHelp)
    state.help_gui.OnEvent("Escape", CloseWindowCascadeHelp)
    state.help_gui.Show()
}


ShowWindowCascadeMoreHelp(*)
{
    state := GetWindowCascadeHelpState()
    if !state.help_gui
        return

    if state.more_help_gui {
        state.help_gui.Hide()
        state.more_help_gui.Show()
        return
    }

    state.more_help_gui := CallWithDpiContext(-2, Gui, "+AlwaysOnTop", "Window Cascade - More help")
    state.more_help_icons := SetWindowCascadeHelpIcons(state.more_help_gui)
    state.more_help_gui.SetFont("s10", "Cascadia Mono")

    more_help_text :=
    (
    "NOTES`n"
    "Caps/Pause shortcuts require the separate Caps + Pause Layers service.`n"
    "All keyboard shortcuts can be changed in Keybindings.`n"
    "When auto cascading is paused, new windows stay unmanaged; existing cascade controls remain active.`n"
    "Other window commands are blocked during native drags/resizes or while maximized/fullscreen.`n"
    "Window Cascade continues running if Caps + Pause Layers stops.`n"
    "`n"
    "FOCUS TABS`n"
    "Each slot shows at most one tab: its exposed window, or the next layer below the active window.`n"
    "Press an inactive slot's tab to focus its exposed window immediately.`n"
    "Press the active slot's tab to cycle to the next layer in the same Z-order band.`n"
    "Always-on-top windows keep that setting; normal layers remain behind the topmost band.`n"
    "Single-layer slot: the tab disappears on press. Holding, dragging, and release add no action.`n"
    "Tabs in the active slot and inactive slots can use different tray-selected colors.`n"
    "Use Show focus tabs in the tray to show or hide them.`n"
    "`n"
    "WINDOW DRAGS`n"
    "Slot matching uses the window's visible top-left corner, not the mouse pointer or focus tab.`n"
    "The decision is made on release; the adopt shortcut is configurable in Keybindings.`n"
    "Dropped windows keep their slot; a cascade smaller than one full layer may compact inward.`n"
    "`n"
    "TRAY`n"
    "How to debug               Isolate a bug and prepare a GitHub report`n"
    "Pause auto cascading       Toggles automatic placement; its shortcut is configurable`n"
    "Show focus tabs            Show / hide the faint focus tabs`n"
    "Focus tab colors           Choose colors for the active and inactive slots`n"
    "Check compatibility        Check conflicting settings`n"
    "Verbose debug logging      Toggle detailed diagnostics for this run"
    )

    state.more_help_gui.AddText("w780", more_help_text)
    back_button := state.more_help_gui.AddButton("xm+680 w100", "Back")
    back_button.OnEvent("Click", ReturnToWindowCascadeHelp)

    state.more_help_gui.OnEvent("Close", ReturnToWindowCascadeHelp)
    state.more_help_gui.OnEvent("Escape", ReturnToWindowCascadeHelp)

    state.help_gui.Hide()
    state.more_help_gui.Show()
}


ReturnToWindowCascadeHelp(*)
{
    state := GetWindowCascadeHelpState()

    if state.more_help_gui {
        try state.more_help_gui.Destroy()
        state.more_help_gui := 0
        for icon_handle in state.more_help_icons
            DllCall("DestroyIcon", "ptr", icon_handle, "int")
        state.more_help_icons := []
    }

    if state.help_gui
        state.help_gui.Show()
}


CloseWindowCascadeHelp(*)
{
    state := GetWindowCascadeHelpState()

    if state.more_help_gui {
        try state.more_help_gui.Destroy()
        state.more_help_gui := 0
        for icon_handle in state.more_help_icons
            DllCall("DestroyIcon", "ptr", icon_handle, "int")
        state.more_help_icons := []
    }

    if state.help_gui {
        try state.help_gui.Destroy()
        state.help_gui := 0
        state.help_text := 0
        ; Destroy the GUI before releasing the HICONs it was displaying.
        for icon_handle in state.help_icons
            DllCall("DestroyIcon", "ptr", icon_handle, "int")
        state.help_icons := []
    }
}

ShowWindowCascadeDebugHelp(*)
{
    static debug_gui := 0
    static debug_icons := []

    if debug_gui {
        debug_gui.Show()
        return
    }

    debug_gui := CallWithDpiContext(-2, Gui, "+AlwaysOnTop", "Window Cascade - How to debug")
    debug_icons := SetWindowCascadeHelpIcons(debug_gui)
    debug_gui.SetFont("s10", "Cascadia Mono")

    debug_text :=
    (
    "HOW TO DEBUG`n"
    "`n"
    "Use a clean log so a bug report contains only the actions that matter.`n"
    "`n"
    "1. Close the help windows.`n"
    "2. Clear the log (binding: " CascadeHelpActionBinding("reset-log") ").`n"
    "3. Reproduce the problem with as few unrelated actions as possible.`n"
    "4. Copy the log (binding: " CascadeHelpActionBinding("copy-log") ").`n"
    "5. Open GitHub Issues and paste the log with a short description.`n"
    "`n"
    "Please include what you expected, what actually happened, and which`n"
    "application/window was involved. Include monitor/scaling details when relevant.`n"
    "`n"
    "If the normal log is not detailed enough, enable Verbose debug logging`n"
    "from the tray menu, clear the log again, and repeat the reproduction.`n"
    "`n"
    "Copying the log does not clear it or focus another window, so the`n"
    "captured history remains isolated."
    )

    debug_gui.AddText("w720", debug_text)
    issues_button := debug_gui.AddButton("xm w170", "Open GitHub Issues")
    issues_button.OnEvent("Click", OpenWindowCascadeIssues)

    debug_gui.OnEvent("Close", CloseDebugHelp)
    debug_gui.OnEvent("Escape", CloseDebugHelp)
    debug_gui.Show()

    CloseDebugHelp(*) {
        try debug_gui.Destroy()
        debug_gui := 0
        for icon_handle in debug_icons
            DllCall("DestroyIcon", "ptr", icon_handle, "int")
        debug_icons := []
    }
}


OpenWindowCascadeIssues(*)
{
    Run "https://github.com/nroj95/window-cascade/issues"
}


SetWindowCascadeHelpIcons(help_gui)
{
    icon_handles := []
    icon_path := A_ScriptDir "\icons\window-cascade.ico"

    if !FileExist(icon_path)
        return icon_handles

    try {
        for icon_index, size in [16, 32] {
            image_type := 0
            icon_handle := LoadPicture(icon_path, "Icon1 w" size " h" size, &image_type)
            if !icon_handle
                continue
            if image_type != 1 {
                DllCall(image_type = 2 ? "DestroyCursor" : "DeleteObject", "ptr", icon_handle, "int")
                continue
            }
            icon_handles.Push(icon_handle)
            ; WM_SETICON: ICON_SMALL = 0 (caption), ICON_BIG = 1 (Alt+Tab/taskbar).
            SendMessage(0x0080, icon_index - 1, icon_handle, , help_gui.Hwnd)
        }
    }
    catch Error as err {
        DebugError("Set help window icon", err)
    }
    return icon_handles
}

; =============================================================================
; compatibility checks
; =============================================================================

CheckCompatibilitySettings(*)
{
    if !IsCascadeEnabled()
        return

    try {
        warnings := []

        fancyzones_settings_path :=
            EnvGet("LOCALAPPDATA") "\Microsoft\PowerToys\FancyZones\settings.json"


        if FileExist(fancyzones_settings_path) {
            fancyzones_settings := FileRead(
                fancyzones_settings_path,
                "UTF-8"
            )

            if RegExMatch(
                fancyzones_settings,
                '"fancyzones_appLastZone_moveWindows"\s*:\s*\{\s*"value"\s*:\s*true'
            ) {
                warnings.Push(
                    'FancyZones: "Move newly created windows to the last known zone" '
                    . "is enabled."
                )
            }
        }

        if warnings.Length = 0 {
            return
        }

        message :=
            "This setting may compete with Window Cascade:`n`n"

        for warning in warnings
            message .= "• " warning "`n`n"

        message .= "Window Cascade will not change PowerToys settings automatically."

        MsgBox(message, "Window Cascade", "Icon!")
    }
    catch {
        return
    }
}
