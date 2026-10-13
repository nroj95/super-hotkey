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
                        this.app.Report("could not restore the previous shutdown-privilege state")
                }
                DllCall("CloseHandle", "ptr", token)
            }
        }
    }
}
