WW_GetNativeWindowsSnapState()
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

WW_PromptToDisableNativeWindowsSnap()
{
    state := WW_GetNativeWindowsSnapState()
    if state != 1 {
        if state = -1
            WW_DebugLog("Could not query native Windows Snap state.")
        return
    }

    response := MsgBox(
        "Native Windows Snap is currently enabled.`n`n"
        . "Disabling it is recommended so Windows' built-in snapping does not "
        . "compete with Wonder Windows or other window-layout tools.`n`n"
        . "Disable Windows Snap for your account now?`n`n"
        . "Choosing No leaves Windows Snap enabled. You can change this later in "
        . "Settings > System > Multitasking.",
        "Wonder Windows",
        "YesNo Default2 Icon?"
    )
    if response != "Yes"
        return

    ; Use the documented API, not a collection of guessed registry switches.
    ; SPI_SETWINARRANGING; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE.
    succeeded := DllCall("SystemParametersInfoW", "uint", 0x0083, "uint", 0,
        "ptr", 0, "uint", 0x0003, "int")
    if !succeeded || WW_GetNativeWindowsSnapState() != 0 {
        MsgBox(
            "Windows Snap could not be disabled automatically.`n`n"
            . "Open Wonder Windows Settings, choose Windows Snap settings, and turn off Snap windows.",
            "Wonder Windows", "Icon!"
        )
    }
}

WW_OpenWindowsSnapSettings(*)
{
    Run("ms-settings:multitasking")
}

WW_IsScreenGridRunning()
{
    for executable in ["ScreenGrid.exe", "ScreenGrid-standalone.exe", "ScreenGrid-small.exe"] {
        if ProcessExist(executable)
            return true
    }
    return false
}

WW_OpenScreenGridReleases(*)
{
    global WW_screengrid_releases_url
    Run(WW_screengrid_releases_url)
}
