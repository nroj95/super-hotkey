#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn All, StdOut

; One entry point. Included modules define code; none start another script.
#Include "%A_ScriptDir%\core\keybindings.ahk"
#Include "%A_ScriptDir%\core\logging.ahk"
#Include "%A_ScriptDir%\core\settings.ahk"
#Include "%A_ScriptDir%\core\windows.ahk"
#Include "%A_ScriptDir%\core\focus-border.ahk"
#Include "%A_ScriptDir%\core\help.ahk"
#Include "%A_ScriptDir%\core\application.ahk"
#Include "%A_ScriptDir%\core\tray.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\secret-layers.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\state-machine.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\caps-lock-toggle.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\power-up-utilities.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\modules.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\keyboard.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\terminal.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\utilities.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\include.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\adapter.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\paper-pad.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\adapter.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\include.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\adapter.ahk"

if A_LineFile = A_ScriptFullPath
    SuperHotkeyMain()

SuperHotkeyMain() {
    dryRun := false
    openSettings := false
    try {
        for argument in A_Args {
            switch argument {
                case "--check":
                    FileAppend("PASS: Super Hotkey and every module parsed.`n", "*")
                    ExitApp(0)
                case "--dry-run": dryRun := true
                case "--settings": openSettings := true
                default: throw ValueError("Unknown argument: " argument)
            }
        }
        app := SuiteApplication(dryRun)
        app.Start(openSettings)
    }
    catch Error as failure {
        if IsObject(SuiteState.Log)
            SuiteState.Log.Error("Core / startup", failure)
        MsgBox(failure.Message, SuiteApplication.Name " - could not start", "Iconx")
        ExitApp(1)
    }
}
