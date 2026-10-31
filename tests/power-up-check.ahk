; Power-Up Utilities: sleep policy recovery, the stay-awake cycles and the keys
; that hold macros back.
; Disposable preferences, dry-run inputs and test-owned windows only; staying
; awake is never requested from Windows here.
class PowerUpChecks {
    static Run() {
        this.SleepPolicyRecovery()
        this.StayAwakeCycles()
        this.BlockingKeys()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static BlockingKeys() {
        textKeys := ""
        for key in PowerUpUtilities.BlockingKeys("text")
            textKeys .= key " "
        sleepKeys := ""
        for key in PowerUpUtilities.BlockingKeys("sleep")
            sleepKeys .= key " "
        this.Assert(InStr(textKeys, "Shift") && InStr(textKeys, "Ctrl") && InStr(textKeys, "Alt")
            && InStr(textKeys, "LWin") && !InStr(textKeys, "CapsLock") && !InStr(textKeys, "Pause"),
            "text waits for modifiers, not for a held Caps or Pause")
        this.Assert(InStr(sleepKeys, "CapsLock") && InStr(sleepKeys, "Pause") && InStr(sleepKeys, "Shift"),
            "sleep still waits for every key, layer keys included")
    }

    static StayAwakeCycles() {
        durations := PU_StayAwake.Durations
        this.Assert(durations["short"][1] = 30 && durations["short"][3] = 120
            && durations["long"][1] = 240 && durations["long"][3] = 0,
            "stay awake cycles 30 min to 2 h, and 4 h to until turned off")
        this.Assert(PU_StayAwake.NextIndex("short", "", 0) = 1
            && PU_StayAwake.NextIndex("short", "short", 2) = 3,
            "each press steps to the next duration")
        this.Assert(PU_StayAwake.NextIndex("short", "short", 3) = 0
            && PU_StayAwake.NextIndex("long", "long", 3) = 0,
            "after the last duration, sleep is allowed again")
        this.Assert(PU_StayAwake.NextIndex("long", "short", 2) = 1
            && PU_StayAwake.NextIndex("short", "long", 3) = 1,
            "switching cycles starts the other one from its first duration")
        this.Assert(PU_StayAwake.Describe(30) = "30 min" && PU_StayAwake.Describe(480) = "8 h",
            "notices name minutes and hours")
        statuses := []
        awake := PU_StayAwake({SetTrayStatus: (module, text) => statuses.Push(text)})
        awake.End()
        this.Assert(awake.cycle = "" && statuses.Length = 1 && statuses[1] = "",
            "ending without a request only clears the tray status")
    }

    static SleepPolicyRecovery() {
        folder := SuiteChecks.directory "\sleep-policy"
        policy := PU_SleepPolicyProbe(folder)
        policy.Begin()
        this.Assert(policy.values["AC"] = 0 && policy.values["DC"] = 0
            && FileExist(policy.path), "sleep changes both power sources with a recovery record")
        recovered := PU_SleepPolicyProbe(folder, policy.values)
        recovered.Recover()
        this.Assert(recovered.values["AC"] = 1 && recovered.values["DC"] = 1
            && !FileExist(policy.path), "a new process restores an interrupted sleep transaction")
        recovered.Begin()
        recovered.activeScheme := "{22222222-2222-2222-2222-222222222222}"
        activeCalls := recovered.applyCount
        recovered.Restore()
        this.Assert(recovered.values["AC"] = 1 && recovered.values["DC"] = 1
            && recovered.applyCount = activeCalls,
            "restoration does not reactivate a power plan switched by another process")
        recovered.values["AC"] := 0
        recovered.values["DC"] := 0
        recovered.Begin()
        this.Assert(!FileExist(recovered.path),
            "already disabled Away Mode requires no disk transaction")
    }
}

class PU_SleepPolicyProbe extends PU_SleepPolicy {
    __New(directory, values := 0) {
        super.__New(directory)
        this.activeScheme := "{11111111-1111-1111-1111-111111111111}"
        this.values := IsObject(values) ? values : Map("AC", 1, "DC", 1)
        this.applyCount := 0
    }

    GetActiveGuid() => this.activeScheme
    ReadValue(scheme, source) => this.values[source]
    WriteValue(scheme, source, value) => this.values[source] := value
    Apply(scheme) => this.applyCount += 1
}
