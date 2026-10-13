#Requires AutoHotkey v2.0
#SingleInstance Off
#Include "%A_ScriptDir%\..\power-hotkey.ahk"
#Warn All, StdOut

; =============================================================================
; pure catalog / configuration tests; never start Power Hotkey or send input
; =============================================================================
; No settings are written, no layer session is opened, and no real clipboard,
; volume, capitalization or power state is changed by these tests.
; =============================================================================

try {
    PH_Check.Run()
    ExitApp 0
}
catch Error as powerHotkeysTestError {
    FileAppend("FAIL: " powerHotkeysTestError.Message "`n", "**")
    ExitApp 1
}

class PH_Check {
    static count := 0

    static Assert(condition, label) {
        this.count += 1
        if !condition
            throw Error(label)
    }

    static Run() {
        app := PowerHotkeys({dryRun: true,
            directory: A_Temp "\PowerHotkeys-check-" DllCall("GetCurrentProcessId", "uint")})
        manager := app.manager
        this.Assert(app.modules.Length = 9, "nine optional feature modules")
        this.Assert(app.catalog.Count = 33, "33 original feature/control actions")
        this.Assert(manager.actions.Count = 33, "every catalog action is registered")
        this.Assert(!manager.running, "construction must not start hooks or persistence")
        this.Assert(!IsObject(manager.client), "construction must not connect to the layer service")
        configuration := manager._DefaultConfiguration()
        for actionId, setting in configuration {
            this.Assert(setting.enabled, actionId " is available without enabling a module")
            this.Assert(setting.bindings.Length = 2, actionId " has two configurable slots")
            this.Assert(setting.bindings[1] = "" && setting.bindings[2] = "",
                actionId " has no implicit shortcut")
        }
        for index, suffix in ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"] {
            output := "F" (index + 12)
            actionId := "keyboard." StrLower(output)
            this.Assert(app.catalog[actionId].value = output, "independent F-key output " output)
        }
        loop 10 {
            numpadDigit := A_Index - 1
            actionId := "keyboard.numpad" numpadDigit
            this.Assert(app.catalog[actionId].value = "Numpad" numpadDigit,
                "independent number-pad output " numpadDigit)
        }
        this.Assert(app.catalog["text.sharp-s"].value = "ß", "sharp s preserved")
        this.Assert(app.catalog["text.en-dash"].value = "–", "en dash preserved")
        this.Assert(app.catalog["text.apostrophe"].value = "’", "curly apostrophe preserved")
        this.Assert(app.catalog["text.nbsp"].value = "&nbsp;", "literal entity preserved")
        this.Assert(app.catalog["text.timestamp"].kind = "timestamp", "timestamp is dynamic")
        this.Assert(app.catalog["terminal.copy"].needsFocus, "terminal copy needs focus")
        this.Assert(app.catalog["terminal.clear"].needsFocus, "terminal clear needs focus")
        this.Assert(manager._CandidateRoutes(configuration).routes.Length = 0,
            "fresh Power Hotkey installs no hotkeys")
        draft := manager._CloneConfiguration(configuration)
        draft["keyboard.f13"].bindings[1] := Keybindings.Parse("Ctrl + Alt + F9").signature
        this.Assert(manager._CandidateRoutes(draft).routes.Length = 1,
            "one configured F-key installs exactly one route")
        this.Assert(configuration["keyboard.f13"].bindings[1] = "",
            "configuration snapshots remain independent")
        draft["keyboard.f14"].bindings[1] := Keybindings.Parse("Ctrl + Shift + F9").signature
        this.Assert(manager._CandidateRoutes(draft).routes.Length = 2,
            "F-keys are not locked to the original QWER layout")
        fence := Chr(96) Chr(96) Chr(96)
        this.Assert(PH_Terminal.FormatBuffer("hello`r`n`r`n") = fence "`nhello`n" fence,
            "Markdown copy trims trailing empty lines")
        this.Assert(PH_Terminal.FormatBuffer("a`n`nb`n") = fence "`na`n`nb`n" fence,
            "Markdown copy preserves internal blank lines")
        this.Assert(PH_Terminal.FormatBuffer("x`n `t`n") = fence "`nx`n" fence,
            "Markdown copy trims whitespace-only trailing lines")
        this.Assert(PH_Utilities.ShouldRestoreVolume(0.16, 0.16), "restore unchanged temporary volume")
        this.Assert(!PH_Utilities.ShouldRestoreVolume(0.25, 0.16), "preserve user-selected volume")
        this.Assert(PH_Utilities.ShouldRestoreVolume(0.160001, 0.16), "tolerate endpoint rounding")
        manager.SetPaused(true)
        this.Assert(manager.paused && !manager.running, "pause works before Start without starting the manager")
        manager.SetPaused(false)
        this.Assert(!manager.paused, "pause can be cleared")
        this.Assert(!FileExist(manager.path), "pure checks did not create a settings file")
        FileAppend("PASS: " this.count " Power Hotkey catalog and safety-helper assertions.`n", "*")
    }
}
