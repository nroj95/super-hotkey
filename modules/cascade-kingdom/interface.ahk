; One-time startup check for settings in other tools that compete with cascading.

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
