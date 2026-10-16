; Cascade Kingdom navigation is owned by the suite interface.

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
            "This setting may compete with Cascade Kingdom:`n`n"

        for warning in warnings
            message .= "• " warning "`n`n"

        message .= "Cascade Kingdom will not change PowerToys settings automatically."

        MsgBox(message, "Cascade Kingdom", "Icon!")
    }
    catch {
        return
    }
}

UpdateTrayMenu() {
    global cascade_auto_placement_paused
    SuiteState.CascadeStatus := cascade_auto_placement_paused ? "Cascade Kingdom (placement paused)" : "Cascade Kingdom"
}

ToggleWindowCascadeHelp(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.ToggleHelp("window-cascade")
}

CloseWindowCascadeHelp(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.CloseWindow("help:window-cascade")
}

RefreshCascadeHelpBindings(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.RefreshHelp()
}
