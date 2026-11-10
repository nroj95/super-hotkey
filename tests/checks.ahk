; The native check runner, loaded from a temporary harness at the repository root.
; No real feature effects.
#Include "%A_ScriptDir%\tests\core-check.ahk"
#Include "%A_ScriptDir%\tests\keybindings-check.ahk"
#Include "%A_ScriptDir%\tests\interface-check.ahk"
#Include "%A_ScriptDir%\tests\paper-pad-check.ahk"
#Include "%A_ScriptDir%\tests\power-up-check.ahk"
#Include "%A_ScriptDir%\tests\wonder-windows-check.ahk"
#Include "%A_ScriptDir%\tests\cascade-kingdom-check.ahk"
class SuiteChecks {
    static count := 0
    static directory := A_Temp "\SuperHotkey-check-" FormatTime(, "yyyyMMdd-HHmmss") "-" DllCall("GetCurrentProcessId", "uint")

    static Assert(condition, label) {
        if !condition
            throw Error(label)
        this.count += 1
        FileAppend("PASS: " label "`n", "*")
    }

    static Rejects(callback, label) {
        rejected := false
        try callback.Call()
        catch Error
            rejected := true
        this.Assert(rejected, label)
    }

    static HasRoute(manager, actionId) {
        for route in manager.routes
            if route.action.id = actionId
                return true
        return false
    }

    ; The checks open windows and test focus, so a key press or click while
    ; they run can fail one. A countdown on every display asks for hands off;
    ; it is gone before the first check.
    static WarnHandsOff(seconds := 3) {
        Loop seconds {
            text := "Super Hotkey checks start in " (seconds - A_Index + 1)
                . " s`nHands off the keyboard and mouse until they finish"
            SuiteNotice.ShowEverywhere("checks", text)
            Sleep 1000
        }
        SuiteNotice.Destroy()
    }

    ; Every run starts from the primary display, wherever the terminal that
    ; started it is: a small window there takes focus first, so the working
    ; display, notices and pages begin there, as unpositioned test windows do.
    static anchor := 0

    static FocusPrimary() {
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top)
        this.anchor := SuiteGui("-MinimizeBox", "Super Hotkey checks")
        this.anchor.AddText("w260", "Super Hotkey checks are running.")
        this.anchor.Show("NA x" (left + 40) " y" (top + 40))
        ; The suite's log does not exist yet, so not ActivateWindow, which logs.
        WinActivate("ahk_id " this.anchor.Hwnd)
    }

    static Run() {
        this.WarnHandsOff()
        this.FocusPrimary()
        DirCreate this.directory
        CoreChecks.Run()
        KeybindingsChecks.Run()
        InterfaceChecks.Run()
        PaperPadChecks.Run()
        PowerUpChecks.Run()
        WonderWindowsChecks.Run()
        CascadeChecks.Run()
    }
}

SHW_RunSuiteChecks() {
    result := 0
    try {
        SuiteChecks.Run()
        FileAppend("PASS: native suite checks completed: " SuiteChecks.count " assertions.`n", "*")
    }
    catch Error as failure {
        FileAppend("FAIL: " failure.Message "`n" failure.File ":" failure.Line "`n" failure.Stack "`n", "**")
        result := 1
    }
    finally {
        if IsObject(Keybindings.Current)
            try Keybindings.Current.Stop()
        if SuiteChecks.anchor
            try SuiteChecks.anchor.Destroy()
        try DirDelete(SuiteChecks.directory, true)
    }
    ExitApp(result)
}

SHW_RunSuiteChecks()
