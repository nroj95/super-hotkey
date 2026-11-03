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
            Name: "Galaxy Rhythm", grey: GR_GreyScreen(true), nightOff: false, Off: (module, now := "") => module.nightOff,
            reports: reports, Report: (module, text) => reports.Push(text)}
        folder := SuiteChecks.directory "\" name
        DirCreate(folder)
        return GR_Energy(module, folder "\settings.ini", folder "\energy.ini")
    }

    static EnergyRefill() {
        full := 720, night := 480
        perMinute := (minutes) => GR_Energy.Refill(minutes, full, night) / minutes
        this.Assert(Abs(GR_Energy.Refill(10, full, night) - 50) < 2,
            "a 10-minute break gives back about 50 minutes")
        this.Assert(GR_Energy.Refill(480, full, night) >= full
            && GR_Energy.Refill(240, full, night) > full / 2 && GR_Energy.Refill(240, full, night) < full,
            "a full night fills the bar, and asleep from 02:00 to 06:00 only half fills it")
        this.Assert(GR_Energy.Refill(1, full, night) < 1 && perMinute(5) < perMinute(10)
            && perMinute(9) < perMinute(10) && perMinute(11) < perMinute(10) && perMinute(20) < perMinute(10),
            "a minute away is almost nothing, and breaks pay most per minute at 10 minutes")
        this.Assert(Abs(GR_Energy.Recover(-20, 10, full, night) + 5) < 0.001
            && Abs(GR_Energy.Recover(-20, 40 / 3, full, night)) < 0.001
            && Abs(GR_Energy.Recover(-20, 30, full, night)
                - (GR_Energy.Refill(30, full, night) - GR_Energy.Refill(40 / 3, full, night))) < 0.001
            && GR_Energy.Recover(-20, 480, full, night) > full * 0.9
            && Abs(GR_Energy.Recover(100, 10, full, night) - (100 + GR_Energy.Refill(10, full, night))) < 0.001,
            "rest in the grey pays at a night's pace without the bonus, then goes on along the curve")
        this.Assert(GR_Energy.Restarted("20261103120000", "20261103130000", 1800000)
            && !GR_Energy.Restarted("20261103120000", "20261103130000", 7200000)
            && !GR_Energy.Restarted("", "20261103130000", 1800000),
            "a computer started after the suite last ticked was off meanwhile")
    }

    ; Settings load within their ranges, and the level survives a restart.
    static EnergySettings() {
        energy := this.EnergyFixture("energy-settings")
        this.Assert(energy.show && energy.faint && energy.level = 720
            && energy.fullHours = 12 && energy.nightHours = 8 && energy.rested,
            "once the module is on, a full 12-hour bar shows with the grey and the faint")
        this.Assert(energy.position = "bottom-right" && energy.display = "Primary",
            "the bar sits bottom right on the primary display")
        this.Assert(energy.roadMinutes = 30 && energy.roadText = "You're running on fumes"
            && energy.faintText = "Lights out",
            "running on fumes greys over half an hour of activity before Lights out")
        IniWrite(45, energy.settingsPath, "Energy", "FadeMinutes")
        IniWrite("Out of juice", energy.settingsPath, "Energy", "RoadText")
        IniWrite("Bedtime, champ", energy.settingsPath, "Energy", "FaintText")
        energy.LoadSettings()
        this.Assert(energy.roadMinutes = 45 && energy.roadText = "Out of juice"
            && energy.faintText = "Bedtime, champ",
            "the fade length and the words at zero and at the faint load from Settings")
        IniWrite(5, energy.settingsPath, "Energy", "FadeMinutes")
        IniWrite("", energy.settingsPath, "Energy", "RoadText")
        energy.LoadSettings()
        this.Assert(energy.roadMinutes = 30 && energy.roadText = "You're running on fumes",
            "a fade under 10 minutes falls back to half an hour, and an empty message to its default words")
        IniWrite(30, energy.settingsPath, "Energy", "FullHours")
        IniWrite(6, energy.settingsPath, "Energy", "NightHours")
        IniWrite(0, energy.settingsPath, "Energy", "Faint")
        IniWrite("top-left", energy.settingsPath, "Energy", "Position")
        IniWrite("\\.\DISPLAY2", energy.settingsPath, "Energy", "Display")
        energy.LoadSettings()
        this.Assert(energy.fullHours = 12 && energy.nightHours = 6 && !energy.faint
            && energy.position = "top-left" && energy.display = "\\.\DISPLAY2",
            "saved energy settings load, and one out of range falls back to its default")
        IniWrite("sideways", energy.settingsPath, "Energy", "Position")
        IniWrite("DISPLAY2", energy.settingsPath, "Energy", "Display")
        energy.LoadSettings()
        this.Assert(energy.position = "bottom-right" && energy.display = "Primary",
            "an unknown position or display falls back to bottom right on the primary display")
        placed := ""
        for corner in GR_EnergyBar.Corners {
            GR_EnergyBar.Place(corner[1], 100, 0, 1100, 800, 18, 180, &x, &y)
            placed .= corner[1] "=" x "," y " "
        }
        this.Assert(placed = "bottom-right=1070,604 bottom-left=112,604 top-right=1070,16 top-left=112,16 ",
            "each corner keeps the upright bar 12 px in from the side and 16 px from the top or bottom")
        this.Assert(GR_EnergyBar.Colors(1) = "3CB043 Background303030"
            && GR_EnergyBar.Colors(0.5) = "E0B000 Background303030"
            && GR_EnergyBar.Colors(0.25) = "D87018 Background303030"
            && GR_EnergyBar.Colors(0.001) = "D03030 Background303030"
            && GR_EnergyBar.Colors(-0.5) = "D03030 Background5A1414",
            "the bar blends from green through yellow to red, with a dark red track on the road")
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
        energy.lastSeen := "20261103120000"
        energy.Left("20261103115000")
        energy.module.dryRun := false  ; writes only to the check's own folder
        energy.SaveState()
        reloaded := GR_Energy(energy.module, energy.settingsPath, energy.statePath)
        this.Assert(reloaded.level = 123.45 && reloaded.lastSeen = "20261103120000"
            && reloaded.awaySince = "20261103115000",
            "the energy level, the last tick and when the user left survive a restart")
        energy.Stop("Exit")
        closed := GR_Energy(energy.module, energy.settingsPath, energy.statePath)
        energy.lastSeen := "20261103120000"
        energy.Stop("Shutdown")
        afterShutdown := GR_Energy(energy.module, energy.settingsPath, energy.statePath)
        this.Assert(closed.lastSeen = "" && afterShutdown.lastSeen = "20261103120000",
            "closing the suite by hand counts no rest until it starts again, while a Windows shutdown does")
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
            this.Assert(Abs(energy.level - (before - tick / 2)) < 0.001, "watching or reading costs half")
            energy.level := 0.05
            energy.Tick(at("090011"), 120000)
            this.Assert(energy.level = 0 && grey.level = 0, "and stops at zero, never greying the screen")
            energy.level := before
            used := (buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY) => (
                energy.padUsed := 0,
                energy.NotePad(0, buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY, 5000),
                energy.padUsed = 5000)
            ; One controller's readings in order, each with whether it counts.
            readings := [[[0, 0, 0, 0, 0, 0, 0], false], [[0, 12, 20, 3000, -4000, 5000, 6000], false],
                [[0x1000, 0, 0, 0, 0, 0, 0], true], [[0x1000, 0, 0, 0, 0, 0, 0], false],
                [[0, 0, 0, 0, 0, 0, 0], true], [[0, 31, 0, 0, 0, 0, 0], true],
                [[0, 0, 0, 0, 8000, 0, 0], true], [[0, 0, 0, 0, 0, -6200, 6200], true], [[0, 0, 0, 0, 0, 0, 0], false]]
            judged := true
            for reading in readings
                judged := judged && used(reading[1]*) = reading[2]
            this.Assert(judged, "a controller counts only real input: a button pressed or released, a trigger"
                . " pulled or a stick beyond its dead zone, not a resting thumb or a button held down")
            energy.level := 72.1
            energy.Tick(at("090020"), 0)
            this.Assert(this.ShownEverywhere(GR_Energy.Low), "10 % left says so")
            energy.Tick(at("090030"), 0)
            this.Assert(!this.ShownEverywhere(GR_Energy.Low), "only once")
            energy.level := 0.1
            energy.Tick(at("090040"), 0)
            this.Assert(energy.level < 0 && this.ShownEverywhere(GR_Energy.Road) && grey.level > 0,
                "at zero you run on fumes, and the grey begins")
            energy.level := -15
            energy.Tick(at("090050"), 0)
            this.Assert(Abs(grey.level - (15 + tick) / 30) < 0.001,
                "the grey deepens with every active minute on the road")
            SuiteStayAwake.active := true
            held := energy.level
            energy.Tick(at("090100"), 0)
            SuiteStayAwake.active := false
            this.Assert(Abs(energy.level - (held - tick)) < 0.001 && grey.level > 0,
                "stay awake doesn't touch the bar: it drains and greys as ever")
            module.nightOff := true
            energy.Draw()
            this.Assert(grey.level = 0, "a night off clears the grey within a second, without waiting for a tick")
            held := energy.level
            energy.Tick(at("090110"), 0)
            this.Assert(energy.level = held && grey.level = 0, "a night off holds the bar where it is, without grey")
            app.sessionLocked := true
            energy.Left(at("090110"))
            energy.Tick(at("091000"), 0)
            app.sessionLocked := false
            energy.Tick(at("094110"), 0)
            this.Assert(energy.level > 0 && !InStr(module.reports[-1], "energy:"),
                "rest still counts on a night off, quietly")
            energy.level := -29.9
            energy.Tick(at("094120"), 0)
            this.Assert(!energy.fainting && grey.level = 0, "and nobody faints on a night off")
            module.nightOff := false
            energy.level := -29.9
            energy.Tick(at("090130"), 0)
            this.Assert(energy.fainting && grey.level = 1 && this.ShownEverywhere(GR_Energy.Faint),
                "half an hour on the road: fully grey, and Lights out")
            ; Checks run uninterruptible, so the faint's timer is called by hand.
            SetTimer(energy.faintCallback, 0)
            energy.FaintNow()
            this.Assert(module.reports[-1] = "dry run: energy faint" && energy.level = -15
                && Abs(grey.level - 0.5) < 0.001,
                "then the computer sleeps, and you wake halfway back into the grey")
            app.systemSuspended := true
            energy.Tick(at("090135"), 0)
            app.systemSuspended := false
            energy.Tick(at("090140"), 0)
            this.Assert(Abs(energy.level - (-15 + 1.5 / 6 - tick)) < 0.001 && this.ShownEverywhere(GR_Energy.Road),
                "back straight after a faint, the nap since Lights out pays a little, and the notice says so")

            energy.level := 100
            energy.Tick(at("100000"), 0)
            app.sessionLocked := true
            energy.Left(at("100000"))
            energy.Tick(at("101500"), 900000)
            app.sessionLocked := false
            energy.Tick(at("103000"), 0)
            this.Assert(Abs(energy.level - (100 - 2 * tick + GR_Energy.Refill(30, 720, 480))) < 0.001
                && this.ShownEverywhere("Rested: +14 %"),
                "a locked 30-minute walk refills from the lock, and says so")
            before := energy.level
            app.sessionLocked := true
            energy.Left(at("103000"))
            energy.Tick(at("103300"), 180000)
            app.sessionLocked := false
            energy.Tick(at("103500"), 0)
            this.Assert(Abs(energy.level - (before + GR_Energy.Refill(5, 720, 480) - tick)) < 0.001
                && !InStr(module.reports[-1], "energy:"),
                "a five-minute break gives a little back, too little to say so")
            before := energy.level
            energy.rested := false
            app.sessionLocked := true
            energy.Left(at("103500"))
            energy.Tick(at("104500"), 600000)
            app.sessionLocked := false
            energy.Tick(at("105500"), 0)
            energy.rested := true
            this.Assert(energy.level > before + 60 && !InStr(module.reports[-1], "energy:"),
                "with Rested off, a break refills quietly")
            before := energy.level
            energy.displayOff := true
            energy.Tick(at("110000"), 1500000)
            energy.displayOff := false
            energy.Tick(at("112000"), 0)
            this.Assert(Abs(energy.level - (before + GR_Energy.Refill(20, 720, 480) - tick)) < 0.001,
                "screens turned off by Windows count as rest from then, not from the reading before")
            before := energy.level
            app.suspended := true
            energy.Tick(at("120000"), 0)
            app.sessionLocked := true
            energy.Left(at("125000"))
            energy.Tick(at("125000"), 0)
            app.sessionLocked := false
            app.suspended := false
            energy.Tick(at("130000"), 0)
            this.Assert(Abs(energy.level - (before - tick)) < 0.001,
                "a suspended suite is no rest, even locked meanwhile")
            app.suspended := true
            energy.Tick(at("130010"), 0)
            app.suspended := false
            app.sessionLocked := true
            energy.Left(at("130010"))
            energy.Tick(at("133000"), 1200000)
            app.sessionLocked := false
            energy.Tick(at("134000"), 0)
            this.Assert(energy.level > before + 60, "a break straight after a suspension counts from its end")
            energy.level := -20
            app.sessionLocked := true
            energy.Left(at("134000"))
            energy.Tick(at("134100"), 60000)
            app.sessionLocked := false
            energy.Tick(at("134200"), 0)
            this.Assert(Abs(energy.level - (-20 + 2 * 1.5 - tick)) < 0.001 && grey.level > 0,
                "a moment away on the road pays off a little of the debt and keeps the grey")

            energy.faint := false
            energy.level := -29.95
            energy.Tick(at("130010"), 0)
            energy.Tick(at("130020"), 0)
            this.Assert(energy.level = -30 && !energy.fainting && grey.level = 0,
                "without the faint there is no grey either: the bar just stays empty")
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
            Name: "Galaxy Rhythm", grey: GR_GreyScreen(true), nightOff: false, Off: (module, now := "") => module.nightOff,
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
        allOn := true
        for row in bedtime.rows
            allOn := allOn && row.show
        this.Assert(allOn && bedtime.rows[1].time = "0000" && bedtime.rows[3].text = "You feel sleepy",
            "once the module is on, both reminders and the sleep are on, at 00:00, 01:00 and 02:00")
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
        this.Assert(!night("235955", "000005").Length, "turned-off messages never show")
        bedtime.rows[1].show := bedtime.rows[2].show := true
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
        module.nightOff := true
        this.Assert(!night("235955", "000005").Length, "a night off shows no messages")
        module.nightOff := false
        this.Assert(!night("015955", "020005").Length && !bedtime.fadeStarted,
            "with the sleep row off, nothing happens at bedtime")
        bedtime.Stop()
    }

    ; One night of the sleep: the fade, stay awake on and off, the last word,
    ; and the end of the night. FadeStep takes the tick it pretends it is.
    static BedtimeFade() {
        bedtime := this.BedtimeFixture("bedtime-fade")
        module := bedtime.module, app := module.app, grey := module.grey
        night := (last, now) => this.Night(bedtime, last, now)
        minutes := (count) => bedtime.fadeStarted + count * 60000
        bedtime.rows[3].show := true
        try {
            SuiteStayAwake.active := true
            night("015955", "020005")
            this.Assert(this.ShownEverywhere("Stay awake prevented sleep") && !bedtime.fadeStarted
                && bedtime.until = "20261103060000",
                "stay awake at bedtime says so, and the night lasts until it ends at 06:00")
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
                "stay awake ending after the night has ended starts nothing")
        }
        finally {
            bedtime.Stop()
            loop MonitorGetCount()
                SuiteNotice.Hide("status-" A_Index)
        }
    }
}
