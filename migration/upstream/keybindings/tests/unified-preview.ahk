#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn
#Include "%A_ScriptDir%\..\lib\keybindings.ahk"

; Launch this file with "host" and "peer" in separate processes. Both use
; a dedicated temporary registry, never the real user keybindings directory.
try {
    role := A_Args.Length ? StrLower(A_Args[1]) : "host"
    if role != "host" && role != "peer"
        throw ValueError("Use host or peer.")
    ; Optional second argument isolates integration tests from normal previews.
    root := A_Args.Length >= 2 ? A_Args[2] : A_Temp "\nroj-keybindings-unified-preview"
    displayName := role = "host" ? "Preview Host" : "Preview Peer"
    if A_Args.Length >= 2
        displayName .= " [Restart Test]"
    manager := Keybindings("unified-preview-" role, displayName, {directory: root})
    manager.AddAction("preview.one", "sample action", (*) => 0, [""],
        {category: "test"})
    manager.AddAction("preview.two", "another action", (*) => 0, [""],
        {category: role = "host" ? "Utilities" : "test"})
    manager.Start()
    Persistent true
    if role = "host"
        manager.ShowSettings()
} catch Error as failure {
    MsgBox(failure.Message, "Unified preview error", "Iconx")
    ExitApp 1
}