; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk.

; =============================================================================
; safe transition from the old script name
; =============================================================================

EnsurePreviousLaunchersAreStopped()
{
    previous_setting := DetectHiddenWindows(true)

    try {
        for hwnd in WinGetList("ahk_class AutoHotkey") {
            if hwnd = A_ScriptHwnd
                continue

            title := StrLower(WinGetTitle(hwnd))

            if !InStr(title, "\windows-key-overhaul.ahk - autohotkey v")
                && !InStr(title, "\window-hotkeys.ahk - autohotkey v")
            {
                continue
            }

            MsgBox(
                "A previous Win-key window manager is still running.`n`n"
                . "Exit it from its tray menu, then launch win-key-overhaul.ahk "
                . "again. Running both would register conflicting shortcuts.",
                "Win Key Overhaul",
                "Icon!"
            )
            ExitApp()
        }
    }
    finally {
        DetectHiddenWindows(previous_setting)
    }
}

InitializeDesktopIntegration(*)
{
    try MigratePreviousStartupShortcuts()
    try MigratePreviousPreferences()
    try PromptToDisableNativeWindowsSnap()
    try RecommendScreenGrid()
    CheckFancyZonesStartup()
    SetTimer(CheckFancyZonesStartup, 5000)
}

MigratePreviousStartupShortcuts()
{
    global previous_startup_shortcut_paths

    shortcuts_to_replace := []

    for shortcut_path in previous_startup_shortcut_paths {
        if !FileExist(shortcut_path)
            continue

        try FileGetShortcut(shortcut_path, &target, , &arguments)
        catch
            continue

        if IsPreviousWinKeyOverhaulShortcut(target, arguments)
            shortcuts_to_replace.Push(shortcut_path)
    }

    if !shortcuts_to_replace.Length
        return

    response := MsgBox(
        "Replace this installation's previous startup shortcut with "
        . "Win Key Overhaul?`n`n"
        . "The new shortcut is created before the previous one is removed.",
        "Win Key Overhaul",
        "YesNo Default2 Icon?"
    )

    if response != "Yes"
        return

    CreateStartupShortcut()

    for shortcut_path in shortcuts_to_replace
        try FileDelete(shortcut_path)

    UpdateStartupMenu()
}

IsPreviousWinKeyOverhaulShortcut(target, arguments)
{
    target := StrLower(target)
    arguments := StrLower(Trim(arguments, ' "`t'))

    previous_launchers := [
        StrLower(A_ScriptDir "\windows-key-overhaul.ahk"),
        StrLower(A_ScriptDir "\windows-key-overhaul.exe"),
        StrLower(A_ScriptDir "\window-hotkeys.ahk"),
        StrLower(A_ScriptDir "\window-hotkeys.exe")
    ]

    for launcher_path in previous_launchers {
        if target = launcher_path || arguments = launcher_path
            return true
    }

    return false
}

MigratePreviousPreferences()
{
    global user_preferences_directory, user_preferences_path
    global previous_user_preferences_path

    if FileExist(user_preferences_path)
        return

    if !FileExist(previous_user_preferences_path)
        return

    DirCreate(user_preferences_directory)
    FileCopy(previous_user_preferences_path, user_preferences_path, false)
}

; =============================================================================
; native Windows Snap
; =============================================================================

GetNativeWindowsSnapState()
{
    enabled := 0
    if !DllCall(
        "SystemParametersInfoW", "uint", 0x0082, "uint", 0,
        "int*", &enabled, "uint", 0, "int" ; SPI_GETWINARRANGING
    ) {
        return -1
    }
    return !!enabled
}

PromptToDisableNativeWindowsSnap()
{
    state := GetNativeWindowsSnapState()
    if state != 1 {
        if state = -1
            DebugLog("Could not query native Windows Snap state.")
        return
    }

    response := MsgBox(
        "Native Windows Snap is currently enabled.`n`n"
        . "Disabling it is recommended so Windows' built-in snapping does not "
        . "compete with Win Key Overhaul or other window-layout tools.`n`n"
        . "Disable Windows Snap for your account now?`n`n"
        . "Choosing No leaves Windows Snap enabled. You can change this later in "
        . "Settings > System > Multitasking.",
        "Win Key Overhaul",
        "YesNo Default2 Icon?"
    )
    if response != "Yes"
        return

    ; Use the documented API, not a collection of guessed registry switches.
    ; SPI_SETWINARRANGING; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE.
    succeeded := DllCall(
        "SystemParametersInfoW", "uint", 0x0083, "uint", 0,
        "ptr", 0, "uint", 0x0003, "int"
    )
    if !succeeded || GetNativeWindowsSnapState() != 0 {
        MsgBox(
            "Windows Snap could not be disabled automatically.`n`n"
            . "Open Recommended setup from the tray, choose Windows Snap settings, and turn off Snap windows.",
            "Win Key Overhaul", "Icon!"
        )
    }
}

OpenWindowsSnapSettings(*)
{
    Run("ms-settings:multitasking")
}

ShowRecommendedSetup(*)
{
    static setup_gui := 0

    if setup_gui {
        try setup_gui.Destroy()
        setup_gui := 0
        return
    }

    snap_state := GetNativeWindowsSnapState()
    if snap_state = 0
        snap_status := "Off"
    else if snap_state = 1
        snap_status := "On"
    else
        snap_status := "Unknown"

    screengrid_running := IsScreenGridRunning()
    fancyzones_running := IsFancyZonesRunning()

    screengrid_status := screengrid_running ? "Running" : "Not running"
    fancyzones_status := fancyzones_running ? "Running" : "Not running"

    setup_gui := Gui("+AlwaysOnTop", "Recommended setup")
    setup_gui.MarginX := 20
    setup_gui.MarginY := 18

    setup_gui.SetFont("s11 Bold")
    setup_gui.AddText("xm", "Recommended setup")

    setup_gui.SetFont("s9 Norm")
    setup_gui.AddText(
        "xm y+8 w380",
        "Use one drag-snapping tool at a time."
    )

    setup_gui.SetFont("s9 Bold")
    setup_gui.AddText("xm y+18 w120", "Tool")
    setup_gui.AddText("x+10 yp w120", "Recommended")
    setup_gui.AddText("x+10 yp w120", "Current")

    setup_gui.SetFont("s9 Norm")

    setup_gui.AddText("xm y+8 w120", "Windows Snap")
    setup_gui.AddText("x+10 yp w120", "Off")
    snap_current := setup_gui.AddText("x+10 yp w120", snap_status)
    snap_current.SetFont(snap_state = 0 ? "c008000" : "cC00000")

    setup_gui.AddText("xm y+8 w120", "ScreenGrid")
    setup_gui.AddText("x+10 yp w120", "On")
    screengrid_current := setup_gui.AddText("x+10 yp w120", screengrid_status)
    screengrid_current.SetFont(screengrid_running ? "c008000" : "cC00000")

    setup_gui.AddText("xm y+8 w120", "FancyZones")
    setup_gui.AddText("x+10 yp w120", "Off")
    fancyzones_current := setup_gui.AddText("x+10 yp w120", fancyzones_status)
    fancyzones_current.SetFont(fancyzones_running ? "cC00000" : "c008000")

    snap_button := setup_gui.AddButton(
        "xm y+20 w185",
        "Windows Snap settings"
    )
    snap_button.OnEvent("Click", OpenWindowsSnapSettings)

    screengrid_button := setup_gui.AddButton(
        "x+10 yp w185",
        "ScreenGrid on GitHub"
    )
    screengrid_button.OnEvent("Click", OpenScreenGridReleases)

    fancyzones_button := setup_gui.AddButton(
        "xm y+10 w380",
        "Check FancyZones compatibility"
    )
    fancyzones_button.OnEvent("Click", CheckFancyZonesFromSetup)

    close_button := setup_gui.AddButton(
        "xm y+18 w380",
        "Close"
    )
    close_button.OnEvent("Click", CloseSetup)

    setup_gui.OnEvent("Close", CloseSetup)
    setup_gui.OnEvent("Escape", CloseSetup)
    setup_gui.Show()

    CheckFancyZonesFromSetup(*)
    {
        ; Keep compatibility prompts modal to and above this AlwaysOnTop GUI.
        setup_gui.Opt("+OwnDialogs")

        result := CheckFancyZonesIntegration()
        if result = "ready" {
            MsgBox(
                "FancyZones is already compatible. No settings need to be changed.",
                "Win Key Overhaul",
                "Iconi"
            )
        }
    }

    CloseSetup(*)
    {
        setup_gui.Destroy()
        setup_gui := 0
    }
}

; =============================================================================
; optional ScreenGrid recommendation
; =============================================================================

RecommendScreenGrid()
{
    global user_preferences_directory, user_preferences_path
    if IniRead(user_preferences_path, "Startup", "ScreenGridRecommendationSeen", "0") = "1"
        return

    if !IsScreenGridRunning() {
        response := MsgBox(
            "ScreenGrid is recommended as a companion to these keyboard shortcuts.`n`n"
            . "It adds customizable Shift + drag window layouts. It is optional; "
            . "Win Key Overhaul runs without it.`n`n"
            . "Open ScreenGrid's official GitHub releases page? Nothing will be "
            . "downloaded or installed automatically.`n`n"
            . "This recommendation is shown once. The GitHub link remains in the tray menu.",
            "Win Key Overhaul", "YesNo Default2 Icon?"
        )
        if response = "Yes"
            OpenScreenGridReleases()
    }

    DirCreate(user_preferences_directory)
    IniWrite(1, user_preferences_path, "Startup", "ScreenGridRecommendationSeen")
}

IsScreenGridRunning()
{
    for executable in ["ScreenGrid.exe", "ScreenGrid-standalone.exe", "ScreenGrid-small.exe"] {
        if ProcessExist(executable)
            return true
    }
    return false
}

OpenScreenGridReleases(*)
{
    global screengrid_releases_url
    Run(screengrid_releases_url)
}
