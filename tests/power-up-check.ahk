; Power-Up Utilities: sleep policy recovery, the stay-awake steps, the keys
; that hold macros back, the grey screen's levels and a night of bedtime
; messages and fading on a fake clock.
; Disposable preferences, dry-run inputs and test-owned windows only; staying
; awake is never requested from Windows here, bedtime never sleeps and the
; displays never turn grey.
class PowerUpChecks {
    static Run() {
        this.SleepPolicyRecovery()
        this.StayAwakeCycles()
        this.BlockingKeys()
        this.GreyLevels()
        this.BedtimeSettings()
        this.BedtimeNight()
        this.BedtimeFade()
    }

    static GreyLevels() {
        grey := PU_GreyScreen(true)
        grey.Set("bedtime", 0.3)
        grey.Set("energy", 0.7)
        this.Assert(grey.level = 0.7, "the greyest request wins")
        grey.Set("energy", 0)
        this.Assert(grey.level = 0.3, "a request withdrawn leaves the others")
        grey.Set("bedtime", 2)
        this.Assert(grey.level = 1, "grey never goes past fully grey")
        grey.Clear()
        this.Assert(grey.level = 0 && !grey.levels.Count, "clearing restores the colors")
    }

    ; A dry-run module on a fake clock: nothing sleeps or turns grey.
    static BedtimeFixture(name) {
        reports := []
        app := {suspended: false, systemSuspended: false, sessionLocked: false,
            ModuleActive: (app, id) => true}
        module := {app: app, id: "power-up-utilities", stopping: false, dryRun: true,
            Name: "Power-Up Utilities", stayAwake: {index: 0}, grey: PU_GreyScreen(true),
            reports: reports, Report: (module, text) => reports.Push(text)}
        return PU_Bedtime(module, SuiteChecks.directory "\" name "\settings.ini")
    }

    ; Steps a fixture's clock from last to now, both HHmmss on one night.
    static Night(bedtime, last, now) {
        bedtime.last := "20261103" last
        return bedtime.Check((now < last ? "20261104" : "20261103") now)
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
        bedtime := this.BedtimeFixture("bedtime-settings")
        allOff := !bedtime.sleeps
        for row in bedtime.rows
            allOff := allOff && !row.show
        this.Assert(allOff && bedtime.rows[1].time = "0000" && bedtime.rows[3].text = "You feel sleepy",
            "every bedtime message and the sleep start off, at 00:00, 01:00 and 02:00")
        this.Assert(bedtime.fadeMinutes = 10 && bedtime.wakeTime = "0600"
            && bedtime.sleepText = "Good night" && bedtime.awakeText = "Stay awake prevented sleep",
            "the sleep fades over 10 min, says Good night and lasts the night until 06:00")
        IniWrite(1, path, "Bedtime", "Show2")
        IniWrite("0130", path, "Bedtime", "Time2")
        IniWrite("9999", path, "Bedtime", "Time3")
        IniWrite("Off to bed", path, "Bedtime", "Text1")
        IniWrite("Up late again", path, "Bedtime", "AwakeText")
        IniWrite("25", path, "Bedtime", "FadeMinutes")
        IniWrite("0615", path, "Bedtime", "WakeTime")
        bedtime.Load()
        this.Assert(bedtime.rows[2].show && bedtime.rows[2].time = "0130" && bedtime.rows[2].text = "zzz…"
            && bedtime.rows[3].time = "0200" && bedtime.rows[1].text = "Off to bed"
            && bedtime.awakeText = "Up late again" && bedtime.fadeMinutes = 25 && bedtime.wakeTime = "0615",
            "saved bedtime rows load, and an unusable time falls back to its default")
        this.Assert(PU_Bedtime.CleanMinutes("0") = 10 && PU_Bedtime.CleanMinutes("121") = 10
            && PU_Bedtime.CleanMinutes("x") = 10 && PU_Bedtime.CleanMinutes("120") = 120,
            "a fade lasts 1 to 120 minutes")
    }

    ; The messages on a fake clock. A row shows only if its minute passes
    ; between two close ticks while the user is at the unlocked computer.
    static BedtimeNight() {
        bedtime := this.BedtimeFixture("bedtime-night")
        module := bedtime.module, app := module.app
        night := (last, now) => this.Night(bedtime, last, now)
        shown := (list) => list.Length ? list[1] : 0
        this.Assert(!night("235955", "000005").Length, "turned-off messages never show")
        for row in bedtime.rows
            row.show := true
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
        module.stayAwake.index := 0
        this.Assert(shown(night("015955", "020005")) = 3 && this.ShownEverywhere("You feel sleepy")
            && module.reports[-1] = "bedtime message 3" && !bedtime.fadeStarted,
            "without its sleep, the last row is only a message")
        bedtime.Stop()
    }

    ; One night of the sleep: the fade, stay awake on and off, the last word,
    ; and the wake-up time. FadeStep takes the tick it pretends it is.
    static BedtimeFade() {
        bedtime := this.BedtimeFixture("bedtime-fade")
        module := bedtime.module, app := module.app, grey := module.grey
        night := (last, now) => this.Night(bedtime, last, now)
        minutes := (count) => bedtime.fadeStarted + count * 60000
        bedtime.rows[3].show := true
        bedtime.sleeps := true
        try {
            module.stayAwake.index := 1
            night("015955", "020005")
            this.Assert(this.ShownEverywhere("Stay awake prevented sleep") && !bedtime.fadeStarted
                && bedtime.until = "20261103060000",
                "stay awake at bedtime says so, and the night lasts until the wake-up time")
            night("020005", "020010")
            this.Assert(!bedtime.fadeStarted, "nothing fades while stay awake lasts")
            module.stayAwake.index := 0
            night("020010", "020015")
            this.Assert(bedtime.fadeStarted && this.ShownEverywhere("You feel sleepy"),
                "stay awake ending in the night starts the fade with the last message")
            bedtime.FadeStep(minutes(5))
            this.Assert(grey.level = 0.5 && !bedtime.saying, "halfway through the fade, half grey")
            module.stayAwake.index := 1
            bedtime.FadeStep(minutes(6))
            this.Assert(!bedtime.fadeStarted && grey.level = 0
                && this.ShownEverywhere("Stay awake prevented sleep"),
                "stay awake switched on mid-fade clears the grey and says so")
            module.stayAwake.index := 0
            night("021000", "021005")
            this.Assert(bedtime.fadeStarted && this.ShownEverywhere("You feel sleepy"),
                "the fade starts over when stay awake ends again")
            bedtime.FadeStep(minutes(10))
            this.Assert(grey.level = 1 && bedtime.saying && this.ShownEverywhere("Good night"),
                "fully grey, the last word shows")
            ; Checks run uninterruptible, so the sleep's timer is called by hand.
            module.stayAwake.index := 1
            bedtime.SleepAfterMessage()
            this.Assert(!bedtime.fadeStarted && grey.level = 0 && module.reports[-1] != "dry run: bedtime sleep"
                && this.ShownEverywhere("Stay awake prevented sleep"),
                "Pause + End during the last word keeps the computer up")
            module.stayAwake.index := 0
            night("023000", "023005")
            bedtime.FadeStep(minutes(10))
            SuiteNotice.Hide("status-1")
            app.sessionLocked := true
            bedtime.SleepAfterMessage()
            this.Assert(module.reports[-1] = "dry run: bedtime sleep" && bedtime.until = "" && grey.level = 0,
                "then the computer sleeps, even if locked meanwhile, and that ends the night")
            app.sessionLocked := false
            night("024000", "024005")
            this.Assert(!bedtime.fadeStarted, "one sleep per night")
            module.stayAwake.index := 1
            night("015955", "020005")
            module.stayAwake.index := 0
            night("055955", "060005")
            this.Assert(!bedtime.fadeStarted && bedtime.until = "",
                "stay awake ending after the wake-up time starts nothing")
        }
        finally {
            bedtime.Stop()
            loop MonitorGetCount()
                SuiteNotice.Hide("status-" A_Index)
        }
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
