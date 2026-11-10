; =============================================================================
; power.ahk - staying awake, the displays turning on and off, and sleeping
; the computer, shared by every module
; =============================================================================
; Power-Up Utilities' hotkeys turn stay awake on and off, and any module may
; ask whether it is on. SuiteDisplays tells modules when the displays turn
; off and on again, so they can tell when someone comes back, as keeping
; speakers awake does. SuiteSleep puts the computer to sleep for whichever
; module asks, so far the sleep hotkey and stay awake running out, as Start's
; Sleep does. The application starts and stops it; a dry run never starts it.
; =============================================================================

; Asks Windows not to idle-sleep, the request a backup or a video call makes.
; Screens still turn off and lock, and Sleep chosen by hand, the lid and the
; battery stay Windows' to decide; it changes no power setting.
class SuiteStayAwake {
    static active := false

    static Request() {
        DllCall("SetThreadExecutionState", "uint", 0x80000001, "uint") ; ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        this.active := true
    }

    ; Withdraws the request; safe when none is active.
    static Release() {
        if this.active
            DllCall("SetThreadExecutionState", "uint", 0x80000000, "uint") ; ES_CONTINUOUS
        this.active := false
    }
}

; Whether the displays are on, from Windows' own notification
; (GUID_CONSOLE_DISPLAY_STATE): they go off when the screen timeout turns
; them off, and on again at a touch, so coming back to a
; computer left alone is an event, not something to poll for. A dimmed
; display counts as on. Handlers get (on) only when that changes.
class SuiteDisplays {
    static Guid := "{6FE69556-704A-47A0-8F24-C28D936FDA47}"
    static handle := 0
    static on := true
    static handlers := []

    static OnChange(handler) {
        for existing in this.handlers
            if existing = handler
                return
        this.handlers.Push(handler)
    }

    static OffChange(handler) {
        for index, existing in this.handlers
            if existing = handler
                return this.handlers.RemoveAt(index)
    }

    ; Windows answers at once with the current state, which changes nothing.
    static Start() {
        guid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "str", this.Guid, "ptr", guid, "hresult")
        this.handle := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd, "ptr", guid,
            "uint", 0, "ptr") ; DEVICE_NOTIFY_WINDOW_HANDLE
        if !this.handle
            throw OSError(A_LastError, "Register display state notification")
    }

    static Stop(*) {
        if this.handle
            DllCall("UnregisterPowerSettingNotification", "ptr", this.handle)
        this.handle := 0
        this.handlers := []
        this.on := true
    }

    ; WM_POWERBROADCAST's PBT_POWERSETTINGCHANGE: a POWERBROADCAST_SETTING
    ; with the setting's GUID, a data length and the data, 0 off, 1 on and
    ; 2 dimmed.
    static OnPowerSetting(setting) {
        guid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "str", this.Guid, "ptr", guid, "hresult")
        if DllCall("ntdll\RtlCompareMemory", "ptr", setting, "ptr", guid, "uptr", 16, "uptr") != 16
            || NumGet(setting, 16, "uint") < 4
            return
        on := NumGet(setting, 20, "uint") != 0
        if on = this.on
            return
        this.on := on
        for handler in this.handlers.Clone()
            try handler.Call(on)
            catch Error as failure
                SuiteState.Log.Error("Core / displays", failure)
    }
}

; Sleeps the computer as Start's Sleep does. Where the power plan allows
; Away Mode and a program asks for it, Windows keeps running with its screens
; dark instead; turning Allow Away Mode Policy off in Power Options makes sleep
; reliable, a choice the suite leaves to the user. Wake events stay enabled,
; and no elevation is attempted. Only a started suite sleeps, never a dry run.
class SuiteSleep {
    static started := false

    static Start() => this.started := true
    static Stop(*) => this.started := false

    static Now() {
        if !this.started
            throw Error("Sleep is unavailable before the suite starts or in a dry run.")
        ; Expire queued work and release held output first.
        SuiteState.App.CancelInputs()
        token := 0
        previousPrivileges := Buffer(16, 0)
        adjusted := false
        try {
            ; SetSuspendState requires SeShutdownPrivilege. Enable it only in
            ; this process token and restore its prior state when the call returns.
            process := DllCall("GetCurrentProcess", "ptr")
            if !DllCall("Advapi32\OpenProcessToken", "ptr", process,
                "uint", 0x28, "ptr*", &token, "int") ; TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY
                throw OSError(A_LastError, "OpenProcessToken")
            privileges := Buffer(16, 0)
            NumPut("uint", 1, privileges, 0)
            NumPut("uint", 2, privileges, 12) ; SE_PRIVILEGE_ENABLED
            if !DllCall("Advapi32\LookupPrivilegeValueW", "ptr", 0,
                "str", "SeShutdownPrivilege", "ptr", privileges.Ptr + 4, "int")
                throw OSError(A_LastError, "LookupPrivilegeValueW")
            previousLength := 0
            DllCall("SetLastError", "uint", 0)
            success := DllCall("Advapi32\AdjustTokenPrivileges", "ptr", token,
                "int", false, "ptr", privileges, "uint", previousPrivileges.Size,
                "ptr", previousPrivileges, "uint*", &previousLength, "int")
            privilegeError := A_LastError
            if !success || privilegeError
                throw OSError(privilegeError, "AdjustTokenPrivileges",
                    "Windows did not grant sleep permission; no elevation was attempted.")
            adjusted := true
            ; BOOLEAN is one byte. FALSE for the last argument preserves wake events.
            if !DllCall("PowrProf\SetSuspendState", "uchar", 0, "uchar", 0,
                "uchar", 0, "uchar")
                throw OSError(A_LastError, "SetSuspendState", "Windows could not enter sleep.")
        }
        finally {
            if token {
                if adjusted && NumGet(previousPrivileges, 0, "uint") {
                    restored := DllCall("Advapi32\AdjustTokenPrivileges", "ptr", token,
                        "int", false, "ptr", previousPrivileges, "uint", 0,
                        "ptr", 0, "ptr", 0, "int")
                    if !restored
                        SuiteState.Log.Write("Core", "could not restore the previous shutdown-privilege state")
                }
                DllCall("CloseHandle", "ptr", token)
            }
        }
    }
}
