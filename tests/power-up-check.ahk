; Power-Up Utilities: sleep policy recovery, the stay-awake steps, the keys
; that hold macros back and keeping speakers awake.
; Disposable preferences, dry-run inputs and test-owned windows only; staying
; awake is never requested from Windows here, and no nudge plays.
class PowerUpChecks {
    static Run() {
        this.SleepPolicyRecovery()
        this.StayAwakeCycles()
        this.BlockingKeys()
        this.DisplaysOff()
        this.SpeakersAwake()
    }

    static SpeakersAwake() {
        quiet := PU_Speakers.TonePlan(0), lower := PU_Speakers.TonePlan(-20), low := PU_Speakers.TonePlan(-40)
        this.Assert(quiet.fileDb = -36 && quiet.raiseTo = "" && lower.fileDb = -16 && lower.raiseTo = ""
            && low.fileDb = -6 && low.raiseTo = -30,
            "the nudge reaches the jack at -36 dBFS at any Windows volume, raising it only when the file can't")
        wav := PU_Speakers.Tone(-36)
        peak := 0
        loop PU_Speakers.Rate * PU_Speakers.ToneMs // 1000
            peak := Max(peak, Abs(NumGet(wav, 42 + A_Index * 2, "short")))
        this.Assert(wav.Size = 44 + 24000 && NumGet(wav, 0, "uint") = 0x46464952 && NumGet(wav, 24, "uint") = 8000
            && NumGet(wav, 44, "short") = 0 && Abs(peak - 32767 * 10 ** (-36 / 20)) < 2,
            "the tone is 1.5 s of 25 Hz at its level, faded in from silence")
        this.Assert(PU_Speakers.CleanMinutes("5") = 5 && PU_Speakers.CleanMinutes("0") = 8
            && PU_Speakers.CleanMinutes("61") = 8 && PU_Speakers.CleanMinutes("x") = 8,
            "a nudge comes every 1 to 60 minutes, 8 by default")

        reports := [], saved := []
        app := {suspended: false, systemSuspended: false, sessionLocked: false,
            ModuleActive: (app, id) => true,
            Settings: {WritePreferences: (settings, id, changes) => saved.Push(changes["Speakers"]["KeepAwake"])}}
        module := {app: app, id: "power-up-utilities", stopping: false, dryRun: true,
            Report: (module, text) => reports.Push(text)}
        speakers := PU_Speakers(module, SuiteChecks.directory "\speakers\settings.ini")
        nudges := () => PowerUpChecks.CountOf(reports, "dry run: speakers nudged")
        speakers.Check()
        this.Assert(!speakers.on && !nudges(), "keeping speakers awake starts off and nudges nothing")
        speakers.Toggle()
        on := speakers.on && saved[-1] = 1 && SuiteNotice.notices["status"].text = "Keeping speakers awake"
        SuiteNotice.Hide("status")
        this.Assert(on && nudges() = 1, "switched on, it says so, is kept, and nudges at once")
        speakers.Check()
        this.Assert(nudges() = 1, "then it waits")
        speakers.nudged -= 8 * 60000
        speakers.Check()
        this.Assert(nudges() = 2, "and nudges again after 8 minutes")
        app.sessionLocked := true
        speakers.nudged -= 8 * 60000
        speakers.Check()
        this.Assert(nudges() = 2, "locked, the speakers may sleep")
        app.sessionLocked := false
        speakers.Check()
        this.Assert(nudges() = 3, "unlocked, it nudges at once, before anything plays")
        speakers.displayOff := true
        speakers.nudged -= 8 * 60000
        speakers.Check()
        speakers.displayOff := false
        this.Assert(nudges() = 3, "with the displays off it nudges nothing")
        speakers.Toggle()
        off := !speakers.on && saved[-1] = 0 && SuiteNotice.notices["status"].text = "Letting speakers sleep"
        SuiteNotice.Hide("status")
        speakers.nudged -= 8 * 60000
        speakers.Check()
        this.Assert(off && nudges() = 3, "switched off, it says so, is kept, and nudges nothing")
    }

    static DisplaysOff() {
        offKeys := ""
        for key in PowerUpUtilities.BlockingKeys("displays-off")
            offKeys .= key " "
        this.Assert(InStr(offKeys, "CapsLock") && InStr(offKeys, "Shift"),
            "turning the displays off waits for every key, so Caps coming up doesn't wake them")
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static CountOf(list, value) {
        count := 0
        for item in list
            count += item = value
        return count
    }

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

    ; Whether text shows on each display, in whichever slot, hiding it afterwards.
    static ShownEverywhere(text) {
        everywhere := true
        loop MonitorGetCount() {
            monitor := A_Index, found := false
            for slot, notice in SuiteNotice.notices
                if notice.shown && notice.monitor = monitor && notice.text = text {
                    found := true
                    SuiteNotice.Hide(slot)
                }
            everywhere := everywhere && found
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

class PU_SleepPolicyProbe extends SuiteSleepPolicy {
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
