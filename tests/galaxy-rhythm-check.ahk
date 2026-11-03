; Galaxy Rhythm: the grey screen's levels, a night of bedtime messages and
; fading, and a day of the energy bar, all on a fake clock.
; Disposable preferences and dry-run modules only: bedtime and fainting never
; sleep, the displays never turn grey, and staying awake is only pretended.
class GalaxyRhythmChecks {
    static Run() {
        this.GreyLevels()
        this.BedtimeSettings()
        this.BedtimeNight()
        this.BedtimeFade()
        this.EnergyRefill()
        this.EnergySettings()
        this.EnergyDay()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static EnergyFixture(name) {
        reports := []
        app := {suspended: false, systemSuspended: false, sessionLocked: false,
            ModuleActive: (app, id) => true}
        module := {app: app, id: "galaxy-rhythm", stopping: false, dryRun: true,
            Name: "Galaxy Rhythm", grey: GR_GreyScreen(true),
            reports: reports, Report: (module, text) => reports.Push(text)}
        folder := SuiteChecks.directory "\" name
        DirCreate(folder)
        return GR_Energy(module, folder "\settings.ini", folder "\energy.ini")
    }

    static EnergyRefill() {
        full := 720, night := 480
        this.Assert(Abs(GR_Energy.Refill(30, full, night) - 90) < 1,
            "a 30-minute walk gives back about 1.5 hours")
        this.Assert(GR_Energy.Refill(480, full, night) >= full
            && GR_Energy.Refill(240, full, night) > full / 2 && GR_Energy.Refill(240, full, night) < full,
            "a full night fills the bar, and asleep from 02:00 to 06:00 only half fills it")
        this.Assert(GR_Energy.Refill(10, full, night) / 10 > 2 * GR_Energy.Refill(240, full, night) / 240,
            "breaks pay most in their first minutes")
        this.Assert(GR_Energy.Restarted("20261103120000", "20261103130000", 1800000)
            && !GR_Energy.Restarted("20261103120000", "20261103130000", 7200000)
            && !GR_Energy.Restarted("", "20261103130000", 1800000),
            "a computer started after the suite last ticked was off meanwhile")
    }

    ; Settings load within their ranges, and the level survives a restart.
    static EnergySettings() {
        energy := this.EnergyFixture("energy-settings")
        this.Assert(energy.show && energy.grey && energy.faint && energy.level = 720
            && energy.fullHours = 12 && energy.nightHours = 8 && energy.breakMinutes = 10,
            "once the module is on, a full 12-hour bar shows with the grey and the faint")
        this.Assert(energy.position = "bottom-right" && energy.display = "Primary",
            "the bar sits bottom right on the primary display")
        IniWrite(30, energy.settingsPath, "Energy", "FullHours")
        IniWrite(6, energy.settingsPath, "Energy", "NightHours")
        IniWrite(0, energy.settingsPath, "Energy", "Faint")
        IniWrite("top-center", energy.settingsPath, "Energy", "Position")
        IniWrite("\\.\DISPLAY2", energy.settingsPath, "Energy", "Display")
        energy.LoadSettings()
        this.Assert(energy.fullHours = 12 && energy.nightHours = 6 && !energy.faint
            && energy.position = "top-center" && energy.display = "\\.\DISPLAY2",
            "saved energy settings load, and one out of range falls back to its default")
        IniWrite("middle", energy.settingsPath, "Energy", "Position")
        IniWrite("DISPLAY2", energy.settingsPath, "Energy", "Display")
        energy.LoadSettings()
        this.Assert(energy.position = "bottom-right" && energy.display = "Primary",
            "an unknown position or display falls back to bottom right on the primary display")
        placed := ""
        for corner in GR_EnergyBar.Corners {
            GR_EnergyBar.Place(corner[1], 100, 0, 1100, 800, 180, 8, &x, &y)
            placed .= corner[1] "=" x "," y " "
        }
        this.Assert(placed = "bottom-right=908,780 bottom-center=510,780 bottom-left=112,780 "
            . "top-right=908,12 top-center=510,12 top-left=112,12 ",
            "each position keeps the bar 12 px inside its corner or centered on its edge")
        this.Assert(GR_EnergyBar.Monitors("Primary").Length = 1
            && GR_EnergyBar.Monitors("Primary")[1] = MonitorGetPrimary()
            && GR_EnergyBar.Monitors("All").Length = MonitorGetCount()
            && GR_EnergyBar.Monitors(MonitorGetName(MonitorGetPrimary()))[1] = MonitorGetPrimary()
            && GR_EnergyBar.Monitors("\\.\DISPLAY99")[1] = MonitorGetPrimary(),
            "the primary display, every display, the one chosen, or the primary while that one is disconnected")
        IniWrite(6, energy.settingsPath, "Energy", "FullHours")
        energy.LoadSettings()
        this.Assert(energy.level = 360, "a smaller bar caps the energy already there")
        energy.level := 123.45
        energy.lastInput := energy.lastSeen := "20261103120000"
        energy.module.dryRun := false  ; writes only to the check's own folder
        energy.SaveState()
        reloaded := GR_Energy(energy.module, energy.settingsPath, energy.statePath)
        this.Assert(reloaded.level = 123.45 && reloaded.lastInput = "20261103120000",
            "the energy level and the last input survive a restart")
    }

    ; One day on a fake clock: Tick takes the time and idle milliseconds.
    static EnergyDay() {
        energy := this.EnergyFixture("energy-day")
        module := energy.module, app := module.app, grey := module.grey
        at := (time) => "20261103" time
        tick := 1 / 6  ; minutes in an active tick
        try {
            energy.Tick(at("090000"), 0)
            this.Assert(Abs(energy.level - (720 - tick)) < 0.001, "an active tick costs its ten seconds")
            before := energy.level
            energy.Tick(at("090010"), 120000)
            this.Assert(energy.level = before, "idle time costs nothing")
            energy.level := 72.1
            energy.Tick(at("090020"), 0)
            this.Assert(this.ShownEverywhere(GR_Energy.Low), "10 % left says so")
            energy.Tick(at("090030"), 0)
            this.Assert(!this.ShownEverywhere(GR_Energy.Low), "only once")
            energy.level := 0.1
            energy.Tick(at("090040"), 0)
            this.Assert(energy.level < 0 && this.ShownEverywhere(GR_Energy.Road) && grey.level > 0,
                "at zero you run on fumes, and the grey begins")
            energy.level := -30
            energy.Tick(at("090050"), 0)
            this.Assert(Abs(grey.level - (30 + tick) / 60) < 0.001,
                "the grey deepens with every active minute on the road")
            SuiteStayAwake.active := true
            energy.Tick(at("090100"), 0)
            this.Assert(energy.level = 0 && grey.level = 0, "stay awake holds the bar at zero, without grey")
            energy.Tick(at("090110"), 0)
            this.Assert(energy.level = 0 && !this.ShownEverywhere(GR_Energy.Road), "and keeps quiet there")
            SuiteStayAwake.active := false
            energy.Tick(at("090120"), 0)
            this.Assert(energy.level < 0 && this.ShownEverywhere(GR_Energy.Road),
                "when stay awake ends, the road starts over from zero with its notice")
            energy.level := -59.9
            energy.Tick(at("090130"), 0)
            this.Assert(energy.fainting && grey.level = 1 && this.ShownEverywhere(GR_Energy.Faint),
                "an hour on the road: fully grey, and Lights out")
            ; Checks run uninterruptible, so the faint's timer is called by hand.
            SetTimer(energy.faintCallback, 0)
            energy.FaintNow()
            this.Assert(module.reports[-1] = "dry run: energy faint" && energy.level = 0 && grey.level = 0,
                "then the computer sleeps")
            app.systemSuspended := true
            energy.Tick(at("090500"), 0)
            app.systemSuspended := false
            energy.Tick(at("090510"), 0)
            this.Assert(energy.level < 0 && this.ShownEverywhere(GR_Energy.Road),
                "back from a faint without a real break, the road starts over")

            energy.level := 100
            energy.Tick(at("100000"), 0)
            app.sessionLocked := true
            energy.Tick(at("101500"), 900000)
            app.sessionLocked := false
            energy.Tick(at("103000"), 0)
            this.Assert(Abs(energy.level - (100 - 2 * tick + GR_Energy.Refill(30, 720, 480))) < 0.001
                && this.ShownEverywhere("Rested: +13 %"),
                "a locked 30-minute walk refills from the last input before leaving, and says so")
            before := energy.level
            app.sessionLocked := true
            energy.Tick(at("103300"), 180000)
            app.sessionLocked := false
            energy.Tick(at("103500"), 0)
            this.Assert(Abs(energy.level - (before - tick)) < 0.001 && !this.ShownEverywhere("Rested: +1 %"),
                "a five-minute break is too short to count")
            before := energy.level
            energy.displayOff := true
            energy.Tick(at("110000"), 1500000)
            energy.displayOff := false
            energy.Tick(at("112000"), 0)
            this.Assert(energy.level > before + 60, "screens turned off by Windows count as rest too")
            before := energy.level
            app.suspended := true
            energy.Tick(at("120000"), 0)
            app.suspended := false
            energy.Tick(at("130000"), 0)
            this.Assert(Abs(energy.level - (before - tick)) < 0.001, "a suspended suite is no rest")

            energy.faint := false
            energy.level := -59.95
            energy.Tick(at("130010"), 0)
            energy.Tick(at("130020"), 0)
            this.Assert(energy.level = -60 && !energy.fainting && grey.level = 1,
                "without the faint, the bar stays empty and the screen grey")
        }
        finally {
            SuiteStayAwake.active := false
            SetTimer(energy.faintCallback, 0)
            grey.Clear()
            loop MonitorGetCount()
                SuiteNotice.Hide("status-" A_Index)
        }
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
        allOn := bedtime.sleeps
        for row in bedtime.rows
            allOn := allOn && row.show
        this.Assert(allOn && bedtime.rows[1].time = "0000" && bedtime.rows[3].text = "You feel sleepy",
            "once the module is on, every bedtime message and the sleep are on, at 00:00, 01:00 and 02:00")
        this.Assert(bedtime.fadeMinutes = 10 && bedtime.wakeTime = "0600"
            && bedtime.sleepText = "Good night" && bedtime.awakeText = "Stay awake prevented sleep",
            "the sleep fades over 10 min, says Good night and lasts the night until 06:00")
        IniWrite(0, path, "Bedtime", "Show2")
        IniWrite("0130", path, "Bedtime", "Time2")
        IniWrite("9999", path, "Bedtime", "Time3")
        IniWrite("Off to bed", path, "Bedtime", "Text1")
        IniWrite("Up late again", path, "Bedtime", "AwakeText")
        IniWrite("25", path, "Bedtime", "FadeMinutes")
        IniWrite("0615", path, "Bedtime", "WakeTime")
        bedtime.Load()
        this.Assert(!bedtime.rows[2].show && bedtime.rows[2].time = "0130" && bedtime.rows[2].text = "zzz…"
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
        for row in bedtime.rows
            row.show := false
        bedtime.sleeps := false
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
