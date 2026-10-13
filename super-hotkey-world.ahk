#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn

; One entry point. Included modules define code; none start another script.
#Include "%A_ScriptDir%\core\keybindings.ahk"
#Include "%A_ScriptDir%\core\logging.ahk"
#Include "%A_ScriptDir%\core\settings.ahk"
#Include "%A_ScriptDir%\core\application.ahk"
#Include "%A_ScriptDir%\core\tray.ahk"
#Include "%A_ScriptDir%\modules\keyboard-layers\keyboard-layers.ahk"
#Include "%A_ScriptDir%\modules\keyboard-layers\state-machine.ahk"
#Include "%A_ScriptDir%\modules\power-hotkey\power-hotkey.ahk"
#Include "%A_ScriptDir%\modules\power-hotkey\modules.ahk"
#Include "%A_ScriptDir%\modules\power-hotkey\keyboard.ahk"
#Include "%A_ScriptDir%\modules\power-hotkey\terminal.ahk"
#Include "%A_ScriptDir%\modules\power-hotkey\utilities.ahk"
#Include "%A_ScriptDir%\modules\window-cascade\include.ahk"
#Include "%A_ScriptDir%\modules\window-cascade\adapter.ahk"
#Include "%A_ScriptDir%\modules\scratchpad\scratchpad.ahk"
#Include "%A_ScriptDir%\modules\scratchpad\adapter.ahk"

if A_LineFile = A_ScriptFullPath
    SHW_Main()

SHW_Main() {
    dryRun := false
    openSettings := false
    try {
        for argument in A_Args {
            switch argument {
                case "--check":
                    FileAppend("PASS: Super Hotkey World and every module parsed.`n", "*")
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
