; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk.

; =============================================================================
; help
; =============================================================================

ToggleWinKeyOverhaulHelp(*)
{
    global fancyzones_integration_state

    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "Win Key Overhaul")

    help_text :=
    (
    "Win + Ctrl + H       Toggle this help`n"
    "`n"
    "WINDOW STATE`n"
    "Win + Up             Maximize / borderless fullscreen`n"
    "Win + Down           Restore to normal window`n"
    "Win + Backspace      Minimize`n"
    "Win + Shift + Home   Isolate active window / restore others`n"
    "Win + M              Minimize all / restore all`n"
    "`n"
    "WINDOW STRETCH`n"
    "Win + Shift + Up     Stretch to full height`n"
    "Win + Shift + Down   Reset all stretch`n"
    "Win + Shift + Left   Toggle stretch left until collision`n"
    "Win + Shift + Right  Toggle stretch right until collision`n"
    "`n"
    "SIDE LAYOUTS`n"
    "Win + Left           Cycle left layouts`n"
    "Win + Right          Cycle right layouts`n"
    "`n"
    "TILES`n"
    "Win + Insert         Top-left 25% <-> 50%`n"
    "Win + Delete         Bottom-left 25% <-> 50%`n"
    "Win + Home           Top-center 50% <-> alternating 25%`n"
    "Win + End            Bottom-center 50% <-> alternating 25%`n"
    "Win + PgUp           Top-right 25% <-> 50%`n"
    "Win + PgDn           Bottom-right 25% <-> 50%`n"
    "`n"
    "WINDOW ARRANGEMENT`n"
    "Win + Enter          Swap clockwise`n"
    "Win + Shift + Enter  Swap counter-clockwise`n"
    "Win + Alt + Arrow    Start / move spatial focus`n"
    "Win + Shift + Tab    Switch between expanded windows"
    )

    if IsFancyZonesRunning() {
        fancyzones_arrow_shortcut :=
            GetFancyZonesArrowShortcutLabel(fancyzones_integration_state)

        help_text .= (
            "`n"
            "`n"
            "FANCYZONES`n"
        )

        help_text .= fancyzones_arrow_shortcut "   Move between zones`n"

        help_text .= (
            "Ctrl + Alt + PgUp    Previous window in current zone`n"
            "Ctrl + Alt + PgDn    Next window in current zone"
        )
    }

    help_gui.SetFont("s10", "Cascadia Mono")
    help_gui.AddText("w650", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*)
    {
        help_gui.Destroy()
        help_gui := 0
    }
}

; =============================================================================
; startup shortcut
; =============================================================================

CreateStartupShortcut()
{
    global startup_shortcut_path

    if A_IsCompiled {
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
}

ToggleStartup(*)
{
    global startup_shortcut_path

    try {
        if FileExist(startup_shortcut_path)
            FileDelete(startup_shortcut_path)
        else
            CreateStartupShortcut()

        UpdateStartupMenu()
    }
    catch Error as err {
        DebugError("Update startup shortcut", err)
        MsgBox(
            "Could not update the startup shortcut.`n`n" err.Message,
            "Win Key Overhaul",
            "Icon!"
        )
    }
}

UpdateStartupMenu()
{
    global startup_shortcut_path

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}
