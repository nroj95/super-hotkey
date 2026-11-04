; =============================================================================
; power.ahk - staying awake and sleeping the computer, shared by every module
; =============================================================================
; Power-Up Utilities' hotkeys turn stay awake on and off, and any module may
; ask whether it is on. SuiteSleep puts the computer to sleep for whichever
; module asks: the sleep hotkey and bedtime's sleep. Where the power plan lets
; Away Mode replace sleep, keeping the computer running with its screens dark,
; it sleeps for real unless the caller allows Away Mode, as the sleep hotkey
; may; bedtime's sleep and the faint never do, since their night needs it.
; The application starts and stops it, so an interrupted sleep transaction is
; restored at the next start or on exit; a dry run never starts it.
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

; Sleep keeps wake events enabled and does not attempt automatic elevation.
class SuiteSleep {
    static policy := 0

    static Start(directory) {
        this.policy := SuiteSleepPolicy(directory)
        try this.policy.Recover()
        catch Error as failure {
            SuiteState.Log.Error("Core / sleep recovery", failure)
            TrayTip("Could not restore the previous Away Mode settings: " failure.Message,
                SuiteApplication.Name, 2)
        }
    }

    static Stop(*) {
        if IsObject(this.policy)
            this.policy.Restore()
    }

    static OnPowerEvent(event) {
        if IsObject(this.policy)
            this.policy.OnPowerEvent(event)
    }

    static Now(allowAwayMode := false) {
        if !IsObject(this.policy)
            throw Error("Sleep is unavailable before the suite starts or in a dry run.")
        ; Expire queued work and release held output first.
        SuiteState.App.CancelInputs()
        token := 0
        previousPrivileges := Buffer(16, 0)
        adjusted := false
        sleepAccepted := false
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
            ; An active Away Mode request can turn off displays without sleeping.
            ; Restore on resume or a bounded timeout, not immediately on API return.
            if !allowAwayMode {
                this.policy.Begin()
                this.policy.Arm()
            }
            ; BOOLEAN is one byte. FALSE for the last argument preserves wake events.
            if !DllCall("PowrProf\SetSuspendState", "uchar", 0, "uchar", 0,
                "uchar", 0, "uchar")
                throw OSError(A_LastError, "SetSuspendState", "Windows could not enter sleep.")
            sleepAccepted := true
        }
        finally {
            if !sleepAccepted {
                try this.policy.Restore()
                catch Error as failure
                    SuiteState.Log.Error("Core / sleep restoration", failure)
            }
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

; An explicit sleep request may otherwise become Away Mode. Journal the original
; plan's AC/DC values before changing either, and restore without switching plans.
class SuiteSleepPolicy {
    static sleepSubgroup := "{238C9FA8-0AAD-41ED-83F4-97BE242C8F20}"
    static awaySetting := "{25DFA149-5DD1-4736-B5AB-E8A37B5B8187}"

    __New(directory) {
        this.path := directory "\sleep-policy.ini"
        this.pending := false
        this.restoreCallback := ObjBindMethod(this, "RestoreSafely")
    }

    static Guid(value) {
        guidBuffer := Buffer(16, 0)
        if DllCall("Ole32\CLSIDFromString", "wstr", value, "ptr", guidBuffer.Ptr, "int")
            throw ValueError("Invalid power scheme GUID: " value)
        return guidBuffer
    }

    GetActiveGuid() {
        pointer := 0
        errorCode := DllCall("PowrProf\PowerGetActiveScheme", "ptr", 0,
            "ptr*", &pointer, "uint")
        if errorCode
            throw OSError(errorCode, "PowerGetActiveScheme")
        try {
            text := Buffer(78, 0)
            if !DllCall("Ole32\StringFromGUID2", "ptr", pointer,
                "ptr", text.Ptr, "int", 39, "int")
                throw Error("Could not format active power scheme GUID.")
            return StrGet(text.Ptr, "UTF-16")
        }
        finally DllCall("LocalFree", "ptr", pointer, "ptr")
    }

    ReadValue(scheme, source) {
        value := 0
        subgroup := SuiteSleepPolicy.Guid(SuiteSleepPolicy.sleepSubgroup)
        setting := SuiteSleepPolicy.Guid(SuiteSleepPolicy.awaySetting)
        api := source = "AC" ? "PowerReadACValueIndex" : "PowerReadDCValueIndex"
        errorCode := DllCall("PowrProf\" api, "ptr", 0, "ptr", scheme.Ptr,
            "ptr", subgroup.Ptr, "ptr", setting.Ptr,
            "uint*", &value, "uint")
        if errorCode
            throw OSError(errorCode, api)
        if value != 0 && value != 1
            throw ValueError("Unsupported Away Mode setting: " value)
        return value
    }

    WriteValue(scheme, source, value) {
        subgroup := SuiteSleepPolicy.Guid(SuiteSleepPolicy.sleepSubgroup)
        setting := SuiteSleepPolicy.Guid(SuiteSleepPolicy.awaySetting)
        api := source = "AC" ? "PowerWriteACValueIndex" : "PowerWriteDCValueIndex"
        errorCode := DllCall("PowrProf\" api, "ptr", 0, "ptr", scheme.Ptr,
            "ptr", subgroup.Ptr, "ptr", setting.Ptr,
            "uint", value, "uint")
        if errorCode
            throw OSError(errorCode, api)
    }

    Apply(scheme) {
        errorCode := DllCall("PowrProf\PowerSetActiveScheme", "ptr", 0,
            "ptr", scheme.Ptr, "uint")
        if errorCode
            throw OSError(errorCode, "PowerSetActiveScheme")
    }

    ReadJournal() {
        document := KB_Manifest.Read(this.path)
        scheme := KB_Manifest.Get(document, "sleep", "scheme")
        ac := KB_Manifest.Get(document, "sleep", "ac")
        dc := KB_Manifest.Get(document, "sleep", "dc")
        if !RegExMatch(scheme, "i)^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$")
            || !RegExMatch(ac, "^[01]$") || !RegExMatch(dc, "^[01]$")
            throw Error("Sleep recovery record is damaged; no power settings were overwritten.")
        return {scheme: scheme, ac: Integer(ac), dc: Integer(dc)}
    }

    Begin() {
        ; Never discard an older unresolved recovery record.
        this.Restore()
        schemeId := this.GetActiveGuid()
        scheme := SuiteSleepPolicy.Guid(schemeId)
        ac := this.ReadValue(scheme, "AC")
        dc := this.ReadValue(scheme, "DC")
        if !ac && !dc
            return
        SplitPath(this.path, , &directory)
        DirCreate(directory)
        KB_Manifest.WriteAtomic(this.path, Map("sleep",
            Map("scheme", schemeId, "ac", String(ac), "dc", String(dc))))
        this.pending := true
        try {
            if ac
                this.WriteValue(scheme, "AC", 0)
            if dc
                this.WriteValue(scheme, "DC", 0)
            ; A concurrent plan switch invalidates the transaction; fail closed.
            if this.GetActiveGuid() != schemeId
                throw Error("The active power plan changed during sleep preparation.")
            this.Apply(scheme)
        }
        catch Error as failure {
            try this.Restore()
            catch Error as restoreFailure
                SuiteState.Log.Error("Core / sleep rollback", restoreFailure)
            throw failure
        }
    }

    Arm() {
        if this.pending
            SetTimer(this.restoreCallback, -30000)
    }

    OnPowerEvent(event) {
        ; Automatic wake is sent even when nobody is at the keyboard.
        if this.pending && (event = 7 || event = 0x12)
            SetTimer(this.restoreCallback, -1000)
    }

    Recover() {
        if FileExist(this.path)
            this.Restore()
    }

    RestoreSafely(*) {
        try this.Restore()
        catch Error as failure {
            SuiteState.Log.Error("Core / sleep restoration", failure)
            TrayTip("Could not restore the previous Away Mode settings: " failure.Message,
                SuiteApplication.Name, 2)
        }
    }

    Restore(*) {
        SetTimer(this.restoreCallback, 0)
        if !FileExist(this.path) {
            this.pending := false
            return
        }
        record := this.ReadJournal()
        scheme := SuiteSleepPolicy.Guid(record.scheme)
        ; Respect changes made by another process after our own 0 writes.
        if record.ac && this.ReadValue(scheme, "AC") = 0
            this.WriteValue(scheme, "AC", record.ac)
        if record.dc && this.ReadValue(scheme, "DC") = 0
            this.WriteValue(scheme, "DC", record.dc)
        ; Reapply even if an earlier recovery restored the values but failed here.
        if this.GetActiveGuid() = record.scheme
            this.Apply(scheme)
        FileDelete(this.path)
        this.pending := false
    }
}
