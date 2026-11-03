; Galaxy Rhythm: the grey screen's levels and a night of bedtime messages and
; fading on a fake clock.
; Disposable preferences and dry-run modules only: bedtime never sleeps, the
; displays never turn grey, and staying awake is only pretended.
class GalaxyRhythmChecks {
    static Run() {
        this.GreyLevels()
        this.BedtimeSettings()
        this.BedtimeNight()
        this.BedtimeFade()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

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

    static GreyLevels() {
        grey := GR_GreyScreen(true)
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
        module := {app: app, id: "galaxy-rhythm", stopping: false, dryRun: true,
            Name: "Galaxy Rhythm", grey: GR_GreyScreen(true),
            reports: reports, Report: (module, text) => reports.Push(text)}
        return GR_Bedtime(module, SuiteChecks.directory "\" name "\settings.ini")
    }

    ; Steps a fixture's clock from last to now, both HHmmss on one night.
    static Night(bedtime, last, now) {
        bedtime.last := "20261103" last
        return bedtime.Check((now < last ? "20261104" : "20261103") now)
    }

    ; Saved rows load with their defaults filling in anything unusable.
    static BedtimeSettings() {
        this.Assert(GR_Bedtime.ValidTime("0230") && GR_Bedtime.ValidTime("2359")
            && !GR_Bedtime.ValidTime("2400") && !GR_Bedtime.ValidTime("1260"),
            "bedtime times are HHmm within a day")
        this.Assert(GR_Bedtime.CleanText("  ", "Good night") = "Good night"
            && GR_Bedtime.CleanText(" Off`tto  bed ", "x") = "Off to bed"
            && StrLen(GR_Bedtime.CleanText(StrReplace(Format("{:80}", ""), " ", "z"), "x")) = GR_Bedtime.TextLimit,
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
        this.Assert(GR_Bedtime.CleanMinutes("0") = 10 && GR_Bedtime.CleanMinutes("121") = 10
            && GR_Bedtime.CleanMinutes("x") = 10 && GR_Bedtime.CleanMinutes("120") = 120,
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
        SuiteStayAwake.active := true
        this.Assert(shown(night("005955", "010005")) = 2 && this.ShownEverywhere("zzz…"),
            "messages still show while staying awake")
        SuiteStayAwake.active := false
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
            SuiteStayAwake.active := true
            night("015955", "020005")
            this.Assert(this.ShownEverywhere("Stay awake prevented sleep") && !bedtime.fadeStarted
                && bedtime.until = "20261103060000",
                "stay awake at bedtime says so, and the night lasts until the wake-up time")
            night("020005", "020010")
            this.Assert(!bedtime.fadeStarted, "nothing fades while stay awake lasts")
            SuiteStayAwake.active := false
            night("020010", "020015")
            this.Assert(bedtime.fadeStarted && this.ShownEverywhere("You feel sleepy"),
                "stay awake ending in the night starts the fade with the last message")
            bedtime.FadeStep(minutes(5))
            this.Assert(grey.level = 0.5 && !bedtime.saying, "halfway through the fade, half grey")
            SuiteStayAwake.active := true
            bedtime.FadeStep(minutes(6))
            this.Assert(!bedtime.fadeStarted && grey.level = 0
                && this.ShownEverywhere("Stay awake prevented sleep"),
                "stay awake switched on mid-fade clears the grey and says so")
            SuiteStayAwake.active := false
            night("021000", "021005")
            this.Assert(bedtime.fadeStarted && this.ShownEverywhere("You feel sleepy"),
                "the fade starts over when stay awake ends again")
            bedtime.FadeStep(minutes(10))
            this.Assert(grey.level = 1 && bedtime.saying && this.ShownEverywhere("Good night"),
                "fully grey, the last word shows")
            ; Checks run uninterruptible, so the sleep's timer is called by hand.
            SuiteStayAwake.active := true
            bedtime.SleepAfterMessage()
            this.Assert(!bedtime.fadeStarted && grey.level = 0 && module.reports[-1] != "dry run: bedtime sleep"
                && this.ShownEverywhere("Stay awake prevented sleep"),
                "Pause + End during the last word keeps the computer up")
            SuiteStayAwake.active := false
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
            SuiteStayAwake.active := true
            night("015955", "020005")
            SuiteStayAwake.active := false
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
}
