#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn All, StdOut

; One entry point. Included modules define code; none start another script.
#Include "%A_ScriptDir%\core\keybindings.ahk"
#Include "%A_ScriptDir%\core\keybindings-editor.ahk"
#Include "%A_ScriptDir%\core\logging.ahk"
#Include "%A_ScriptDir%\core\settings.ahk"
#Include "%A_ScriptDir%\core\ui.ahk"
#Include "%A_ScriptDir%\core\windows.ahk"
#Include "%A_ScriptDir%\core\focus-border.ahk"
#Include "%A_ScriptDir%\core\application.ahk"
#Include "%A_ScriptDir%\core\tray.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\layers.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\caps-lock-toggle.ahk"
#Include "%A_ScriptDir%\modules\secret-layers\module.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\power-up-utilities.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\keyboard.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\terminal.ahk"
#Include "%A_ScriptDir%\modules\power-up-utilities\utilities.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\commands.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\controls.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\debug.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\discovery.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\display.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\dpi.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\drop-guides.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\policy.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\focus-corners.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\focus-tab-clicks.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\keybindings.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\layout.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\navigation.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\opt-in.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\placement.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\settings.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\suspension.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\window-drag.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\windows.ahk"
#Include "%A_ScriptDir%\modules\cascade-kingdom\module.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\native.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\notepad3-bridge.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\paper-pad.ahk"
#Include "%A_ScriptDir%\modules\paper-pad\module.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\settings.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\window-state.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\layout-geometry.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\layouts.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\nearest-window.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\focus.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\window-switcher.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\monitor-move.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\native-fullscreen.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\zones.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\windows.ahk"
#Include "%A_ScriptDir%\modules\wonder-windows\module.ahk"

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
