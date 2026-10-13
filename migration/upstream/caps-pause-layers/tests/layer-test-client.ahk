#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn
#Include "%A_ScriptDir%\..\lib\caps-pause-client.ahk"

; =============================================================================
; layer-test-client.ahk - safe, separate consumer for the layer service
; =============================================================================
; This registers ONLY logging callbacks. It does not move/close windows, send
; keystrokes, alter the clipboard, change volume, or run system commands.
; Launch a second copy to test that occupied bindings are rejected.
; =============================================================================

if A_Args.Length && A_Args[1] = "--check" {
    FileAppend("PASS: test client and included adapter parsed.`n", "*")
    ExitApp 0
}

Persistent true
TestWindow := Gui("+Resize +MinSize700x420", "Caps + Pause Layers - test client")
TestWindow.SetFont("s10", "Consolas")
TestWindow.AddText("w820",
    "Caps + J: once | Caps + K: repeat | Pause + J: once`n"
    . "Caps + Alt + J | Caps + Shift + J | Pause + Ctrl + J`n"
    . "also test tap, then J; unassigned X should type normally and cancel a tap.")
TestWindow.AddButton("xm w130", "Reconnect").OnEvent("Click", TestReconnect)
TestWindow.AddButton("x+8 w130", "Disconnect").OnEvent("Click", TestDisconnect)
TestWindow.AddButton("x+8 w130", "Clear log").OnEvent("Click", TestClear)
TestWindow.AddText("xm w820", "type below to check passthrough / unwanted repeat characters:")
TestWindow.AddEdit("vtyping w820 h70")
TestWindow.AddEdit("vlog ReadOnly -Wrap w820 h260")
TestWindow.OnEvent("Close", (*) => ExitApp())
TestWindow.OnEvent("Size", TestResize)
TestWindow.Show()

TestLines := []
TestClient := CapsPauseClient("layer test client - PID " DllCall("GetCurrentProcessId"), TestLog)
TestClient.Bind("caps", 0, "j", "caps / J / once", TestEvent)
TestClient.Bind("caps", 0, "k", "caps / K / repeat", TestEvent, true)
TestClient.Bind("pause", 0, "j", "pause / J / once", TestEvent)
TestClient.Bind("caps", 2, "j", "caps / Alt + J", TestEvent)
TestClient.Bind("caps", 4, "j", "caps / Shift + J", TestEvent)
TestClient.Bind("pause", 1, "j", "pause / Ctrl + J", TestEvent)
TestClient.Start()

TestEvent(event) {
    TestLog(event.label " -> " event.phase
        . (event.oneShot ? " [one-shot]" : " [held]")
        . " | target " Format("0x{:X}", event.foregroundHwnd))
}

TestLog(text) {
    global TestWindow, TestLines
    TestLines.Push(FormatTime(, "HH:mm:ss") "  " text)
    if TestLines.Length > 150
        TestLines.RemoveAt(1)
    output := ""
    for line in TestLines
        output .= line "`r`n"
    TestWindow["log"].Value := output
}

TestReconnect(*) {
    global TestClient
    TestClient.Reconnect()
}

TestDisconnect(*) {
    global TestClient
    TestClient.Stop()
}

TestClear(*) {
    global TestWindow, TestLines
    TestLines := []
    TestWindow["log"].Value := ""
}

TestResize(guiObject, minMax, width, height) {
    if minMax = -1
        return
    guiObject["typing"].Move(, , Max(200, width - 24))
    guiObject["log"].Move(, , Max(200, width - 24), Max(100, height - 225))
}
