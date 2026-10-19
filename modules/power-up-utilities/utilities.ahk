; =============================================================================
; utilities.ahk - speaker wake and sleep; simple text actions live in dispatch
; =============================================================================
; Preserve the original sound and 16% temporary volume floor. Retain the exact
; endpoint object and restore only a level that still matches our own change.
; Sleep keeps wake events enabled and does not attempt automatic elevation.
; =============================================================================

class PH_Utilities {
    __New(app) {
        this.app := app
        this.speakerRestore := 0
        this.speakerSound := A_WinDir "\Media\Windows Balloon.wav"
        this.wakeVolume := 0.16
        this.sleepPolicy := PH_SleepPolicy(SuiteState.App.Settings.directory)
    }

    WakeSpeakers(job) {
        if !this.app.JobValid(job)
            return
        if !FileExist(this.speakerSound)
            throw Error("The speaker wake sound was not found:`n" this.speakerSound)
        endpointPointer := SoundGetInterface("{5CDF2C82-841E-4546-9722-0CF74078229A}")
        if !endpointPointer
            throw Error("The playback device does not expose endpoint volume control.")
        endpoint := ComValue(13, endpointPointer) ; owned IAudioEndpointVolume
        ComCall(9, endpoint, "float*", &originalVolume := 0) ; GetMasterVolumeLevelScalar
        try {
            if originalVolume < this.wakeVolume {
                previousCritical := A_IsCritical
                Critical "On"
                try {
                    this.speakerRestore := {endpoint: endpoint, original: originalVolume,
                        boosted: this.wakeVolume}
                    ComCall(7, endpoint, "float", this.wakeVolume, "ptr", 0)
                    ComCall(9, endpoint, "float*", &appliedVolume := 0)
                    this.speakerRestore.boosted := appliedVolume
                }
                finally Critical previousCritical
                Sleep(100)
            }
            if this.app.JobValid(job)
                SoundPlay(this.speakerSound, true)
        }
        finally this.RestoreSpeakerVolume()
    }

    RestoreSpeakerVolume() {
        restoration := this.speakerRestore
        if !IsObject(restoration)
            return
        ComCall(9, restoration.endpoint, "float*", &currentVolume := 0)
        if PH_Utilities.ShouldRestoreVolume(currentVolume, restoration.boosted)
            ComCall(7, restoration.endpoint, "float", restoration.original, "ptr", 0)
        ; Retain the record if COM failed, so exit cleanup can attempt it again.
        this.speakerRestore := 0
    }

    static ShouldRestoreVolume(current, boosted) => Abs(current - boosted) < 0.0001

    SleepComputer(job) {
        if !this.app.JobValid(job) || !this.app.InputsReleased(job.event)
            return
        this.app.CancelWork()
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
            this.sleepPolicy.Begin()
            this.sleepPolicy.Arm()
            ; BOOLEAN is one byte. FALSE for the last argument preserves wake events.
            if !DllCall("PowrProf\SetSuspendState", "uchar", 0, "uchar", 0,
                "uchar", 0, "uchar")
                throw OSError(A_LastError, "SetSuspendState", "Windows could not enter sleep.")
            sleepAccepted := true
        }
        finally {
            if !sleepAccepted {
                try this.sleepPolicy.Restore()
                catch Error as failure
                    SuiteState.Log.Error("Power-Up Utilities / sleep restoration", failure)
            }
            if token {
                if adjusted && NumGet(previousPrivileges, 0, "uint") {
                    restored := DllCall("Advapi32\AdjustTokenPrivileges", "ptr", token,
                        "int", false, "ptr", previousPrivileges, "uint", 0,
                        "ptr", 0, "ptr", 0, "int")
                    if !restored
                        this.app.Report("could not restore the previous shutdown-privilege state")
                }
                DllCall("CloseHandle", "ptr", token)
            }
        }
    }
}

; An explicit sleep request may otherwise become Away Mode. Journal the original
; plan's AC/DC values before changing either, and restore without switching plans.
class PH_SleepPolicy {
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
        subgroup := PH_SleepPolicy.Guid(PH_SleepPolicy.sleepSubgroup)
        setting := PH_SleepPolicy.Guid(PH_SleepPolicy.awaySetting)
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
        subgroup := PH_SleepPolicy.Guid(PH_SleepPolicy.sleepSubgroup)
        setting := PH_SleepPolicy.Guid(PH_SleepPolicy.awaySetting)
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
        scheme := PH_SleepPolicy.Guid(schemeId)
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
                SuiteState.Log.Error("Power-Up Utilities / sleep rollback", restoreFailure)
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
            SuiteState.Log.Error("Power-Up Utilities / sleep restoration", failure)
            TrayTip("Could not restore the previous Away Mode settings: " failure.Message,
                "Power-Up Utilities", 2)
        }
    }

    Restore(*) {
        SetTimer(this.restoreCallback, 0)
        if !FileExist(this.path) {
            this.pending := false
            return
        }
        record := this.ReadJournal()
        scheme := PH_SleepPolicy.Guid(record.scheme)
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
