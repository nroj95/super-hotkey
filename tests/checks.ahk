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

    static Run() {
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
        try DirDelete(SuiteChecks.directory, true)
    }
    ExitApp(result)
}

SHW_RunSuiteChecks()
