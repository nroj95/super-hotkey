; Power-Up Utilities: sleep policy recovery, the stay-awake steps, the keys
; that hold macros back and a night of bedtime messages on a fake clock.
; Disposable preferences, dry-run inputs and test-owned windows only; staying
; awake is never requested from Windows here, and bedtime never sleeps.
class PowerUpChecks {
    static Run() {
        this.SleepPolicyRecovery()
        this.StayAwakeCycles()
        this.BlockingKeys()
        this.BedtimeSettings()
        this.BedtimeNight()
    }

    ; Saved rows load with their defaults filling in anything unusable.
    static BedtimeSettings() {
        this.Assert(PU_Bedtime.ValidTime("0230") && PU_Bedtime.ValidTime("2359")
            && !PU_Bedtime.ValidTime("2400") && !PU_Bedtime.ValidTime("1260"),
            "bedtime times are HHmm within a day")
        this.Assert(PU_Bedtime.CleanText("  ", "Good night") = "Good night"
            && PU_Bedtime.CleanText(" Off`tto  bed ", "x") = "Off to bed"
            && StrLen(PU_Bedtime.CleanText(StrReplace(Format("{:80}", ""), " ", "z"), "x")) = PU_Bedtime.TextLimit,
            "an empty message means its default words, and a long one is cut to one short line")
        folder := SuiteChecks.directory "\bedtime-settings"
        DirCreate(folder)
        path := folder "\settings.ini"
        bedtime := PU_Bedtime({}, path)
        allOff := !bedtime.sleeps
        for row in bedtime.rows
            allOff := allOff && !row.show
        this.Assert(allOff && bedtime.rows[1].time = "0000" && bedtime.rows[3].text = "Good night"
            && bedtime.awakeText = "Stay awake prevented sleep",
            "every bedtime message and the sleep start off, at 00:00, 01:00 and 02:00")
        IniWrite(1, path, "Bedtime", "Show2")
        IniWrite("0130", path, "Bedtime", "Time2")
        IniWrite("9999", path, "Bedtime", "Time3")
        IniWrite("Off to bed", path, "Bedtime", "Text1")
        IniWrite("Up late again", path, "Bedtime", "AwakeText")
        bedtime.Load()
        this.Assert(bedtime.rows[2].show && bedtime.rows[2].time = "0130" && bedtime.rows[2].text = "zzz…"
            && bedtime.rows[3].time = "0200" && bedtime.rows[1].text = "Off to bed"
            && bedtime.awakeText = "Up late again",
            "saved bedtime rows load, and an unusable time falls back to its default")
    }

    ; One night on a fake clock. A row shows only if its minute passes between
    ; two close ticks while the user is at the unlocked computer.
    static BedtimeNight() {
        reports := []
        app := {suspended: false, systemSuspended: false, sessionLocked: false,
            ModuleActive: (app, id) => true}
        module := {app: app, id: "power-up-utilities", stopping: false, dryRun: true,
            Name: "Power-Up Utilities", stayAwake: {index: 0},
            Report: (module, text) => reports.Push(text)}
        bedtime := PU_Bedtime(module, SuiteChecks.directory "\bedtime-night\settings.ini")
        night := (last, now) => (bedtime.last := "20261103" last, bedtime.Check(
            (now < last ? "20261104" : "20261103") now))
        shown := (list) => list.Length ? list[1] : 0
        this.Assert(!night("235955", "000005").Length, "turned-off messages never show")
        for row in bedtime.rows
            row.show := true
        bedtime.sleeps := true
        this.Assert(shown(night("235955", "000005")) = 1 && this.ShownEverywhere("It's getting late"),
            "a message shows on every display when its time passes, across midnight too")
        this.Assert(!night("000005", "000010").Length, "a message shows once")
        this.Assert(!night("005000", "011000").Length,
            "a time passed while the computer slept is skipped, not caught up")
        bedtime.last := "20261104" "000010"
        this.Assert(!bedtime.Check("20261103235950").Length, "a clock turned back shows nothing")
        app.sessionLocked := true
        this.Assert(!night("005955", "010005").Length, "a locked computer skips its message")
        app.sessionLocked := false
        this.Assert(!night("010005", "010010").Length, "unlocking afterwards shows nothing late")
        module.stayAwake.index := 1
        this.Assert(shown(night("005955", "010005")) = 2 && this.ShownEverywhere("zzz…"),
            "messages still show while staying awake")
        this.Assert(shown(night("015955", "020005")) = 3 && this.ShownEverywhere("Stay awake prevented sleep")
            && InStr(reports[-1], "prevented"),
            "stay awake prevents only the sleep, and says so instead of Good night")
        SetTimer(bedtime.sleepCallback, 0)
        module.stayAwake.index := 0
        this.Assert(shown(night("015955", "020005")) = 3 && this.ShownEverywhere("Good night"),
            "the last message shows its Good night")
        ; Checks run uninterruptible, so the sleep's timer is called by hand.
        SetTimer(bedtime.sleepCallback, 0)
        module.stayAwake.index := 1
        bedtime.SleepAfterMessage()
        this.Assert(reports[-1] != "dry run: bedtime sleep",
            "stay awake started during Good night keeps the computer up")
        module.stayAwake.index := 0
        app.sessionLocked := true
        bedtime.SleepAfterMessage()
        this.Assert(reports[-1] = "dry run: bedtime sleep",
            "then the computer sleeps, even if locked meanwhile")
        app.sessionLocked := false
        bedtime.sleeps := false
        night("015955", "020005")
        SetTimer(bedtime.sleepCallback, 0)
        this.Assert(reports[-1] = "bedtime message 3" && this.ShownEverywhere("Good night"),
            "without its sleep, Good night is only a message")
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
