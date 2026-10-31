; Power-Up Utilities: sleep policy recovery, the stay-awake steps and the keys
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
        last := durations.Length
        this.Assert(durations[1] = 30 && durations[5] = 480 && durations[last] = 0,
            "stay awake steps from 30 min to no limit")
        this.Assert(PU_StayAwake.NextIndex(0, 0) = 1 && PU_StayAwake.NextIndex(2, 300) = 3,
            "a press while the notice shows steps to the next duration")
        this.Assert(PU_StayAwake.NextIndex(last, 300) = last,
            "stepping stays on no limit instead of turning off")
        this.Assert(PU_StayAwake.NextIndex(3, PU_StayAwake.NoticeMs) = 1
            && PU_StayAwake.NextIndex(last, 3600000) = 1,
            "once the notice has gone, a press starts over")
        this.Assert(PU_StayAwake.Describe(30) = "30 min" && PU_StayAwake.Describe(480) = "8 h",
            "notices name minutes and hours")
        statuses := []
        awake := PU_StayAwake({SetTrayStatus: (module, text) => statuses.Push(text)})
        awake.End()
        this.Assert(awake.index = 0 && statuses.Length = 1 && statuses[1] = "",
            "ending without a request only clears the tray status")
        reports := []
        app := {systemSuspended: true, sessionLocked: true}
        awake := PU_StayAwake({app: app, SetTrayStatus: (module, text) => 0,
            Report: (module, text) => reports.Push(text)})
        awake.index := 1
        awake.Expire()
        this.Assert(awake.index = 0 && awake.missed && reports.Length = 1,
            "running out while asleep or locked allows sleep at once")
        awake.ShowMissed()
        this.Assert(awake.missed, "the notice still waits while the session is locked")
        app.systemSuspended := app.sessionLocked := false
        awake.Returned()
        this.Assert(awake.missed, "the notice waits a second after the unlock")
        ; Checks run uninterruptible, so the second's timer is called by hand.
        SetTimer(awake.missedTimer, 0)
        awake.missedTimer.Call()
        this.Assert(!awake.missed && this.ShownEverywhere("Sleep allowed again"),
            "then it shows on every display")
        awake.index := 1
        awake.Expire()
        this.Assert(!awake.missed && this.ShownEverywhere("Sleep allowed again"),
            "running out while the user is there shows on every display at once")
    }

    ; Whether text shows on each display, hiding it afterwards.
    static ShownEverywhere(text) {
        everywhere := true
        loop MonitorGetCount() {
            notice := SuiteNotice.notices["status-" A_Index]
            everywhere := everywhere && notice.shown && notice.monitor = A_Index && notice.text = text
            SuiteNotice.Hide("status-" A_Index)
        }
        return everywhere
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
