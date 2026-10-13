#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn
#Include "%A_ScriptDir%\..\power-hotkey.ahk"

; Safe isolated preview: dry-run effects, no inherited real user settings.
try {
    root := A_Temp "\nroj-power-hotkey-assignments-preview-"
        . DllCall("GetCurrentProcessId", "uint")
    app := PowerHotkeys({dryRun: true, directory: root})
    app.Start(true)
} catch Error as assignmentPreviewError {
    MsgBox(assignmentPreviewError.Message, "Power Hotkey preview failed", "Iconx")
    ExitApp 1
}