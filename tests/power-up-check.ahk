; Power-Up Utilities: the stay-awake steps and sleep timer, the keys that hold
; macros back and keeping speakers awake.
; Disposable preferences, dry-run inputs and test-owned windows only; staying
; awake is never requested from Windows here, the sleep timer only reports a
; dry-run sleep, and no nudge plays.
class PowerUpChecks {
    static Run() {
        this.StayAwakeCycles()
        this.BlockingKeys()
        this.SleepKeys()
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
        speakers.DisplaysChanged(false)  ; as core's display watcher reports it
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

    static SleepKeys() {
        for kind in ["sleep", "lock"] {
            keys := ""
            for key in PowerUpUtilities.BlockingKeys(kind)
                keys .= key " "
            this.Assert(InStr(keys, "CapsLock") && InStr(keys, "Shift"),
                kind " waits for every key, so none stays stuck down after waking or unlocking")
        }
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
        ; The sleep timer, always in a dry run: running out only reports.
        reports := [], statuses := []
        app := {dryRun: true, systemSuspended: false, sessionLocked: false}
        awake := PU_StayAwake({app: app,
            SetTrayStatus: (module, text) => statuses.Push(text), Report: (module, text) => reports.Push(text)})
        idle := 0
        awake.DefineProp("IdleTime", {call: (*) => idle})
        ; A timed step that runs out in seconds from now.
        start(seconds) {
            awake.index := 1
            awake.deadline := DateAdd(A_NowUTC, seconds, "Seconds")
            awake.warned := 0, awake.waiting := awake.waitingShown := false
            reports.Length := 0, statuses.Length := 0
        }
        slept() {
            for text in reports
                if text = "dry run: sleep"
                    return true
            return false
        }
        try {
            start(600)
            awake.Advance()
            this.Assert(awake.warned = 0 && awake.index && !slept(), "minutes before the end, nothing warns")
            start(60)
            awake.Advance()
            this.Assert(awake.warned = 1 && this.ShownEverywhere("Sleeping in 1 minute."),
                "a minute before the end, a warning shows on every display")
            awake.deadline := DateAdd(A_NowUTC, 30, "Seconds")
            awake.Advance()
            this.Assert(awake.warned = 2 && this.ShownEverywhere("Sleeping in 30 seconds."),
                "and again 30 seconds before")
            start(20)
            awake.Advance()
            this.Assert(awake.warned = 2 && !this.ShownEverywhere("Sleeping in 30 seconds."),
                "a warning noticed late never tells the wrong time")
            start(60)
            app.sessionLocked := true
            awake.Advance()
            this.Assert(awake.warned = 1 && !this.ShownEverywhere("Sleeping in 1 minute."),
                "a locked computer shows no warnings")
            start(0)
            awake.Advance()
            this.Assert(slept() && !awake.index && statuses[-1] = "", "a locked computer sleeps on time")
            app.sessionLocked := false
            start(0)
            idle := 5000
            awake.Advance()
            this.Assert(!slept() && awake.index && awake.waiting
                && statuses[-1] = "Sleeping when you step away" && this.ShownEverywhere("Sleeping when you step away"),
                "someone using the computer keeps it awake when the time runs out, and every display says so")
            idle := PU_StayAwake.IdleMs
            awake.Advance()
            this.Assert(slept() && !awake.index, "and it sleeps once they leave it alone for 30 seconds")
            start(-PU_StayAwake.LateSeconds - 60)
            awake.Advance()
            this.Assert(!slept() && !awake.index, "a computer asleep when the time ran out stays awake on waking")
            start(0)
            app.systemSuspended := true
            awake.Advance()
            this.Assert(!slept() && !awake.index, "and so does one still waking up")
            app.systemSuspended := false
            start(0)
            awake.index := 0
            awake.Advance()
            this.Assert(!slept(), "a stay awake already ended never sleeps")

            ; How long is left shows on request, in the status notice.
            this.Assert(PU_StayAwake.DescribeLeft(45 * 60) = "45 min" && PU_StayAwake.DescribeLeft(61) = "2 min"
                && PU_StayAwake.DescribeLeft(72 * 60) = "1 h 12 min" && PU_StayAwake.DescribeLeft(7200) = "2 h",
                "time left reads in whole minutes, rounded up")
            start(7200)
            this.Assert(awake.StatusText() = "Sleeping in 2 h", "the status says how long a timed stay awake has left")
            awake.waiting := true
            this.Assert(awake.StatusText() = "Sleeping when you step away",
                "and that it waits for the computer to be left alone")
            awake.waiting := false, awake.deadline := ""
            this.Assert(awake.StatusText() = "Awake until turned off", "and that no limit stays awake")
            awake.index := 0
            this.Assert(awake.StatusText() = "", "staying awake off adds nothing")
        }
        finally {
            SetTimer(awake.timer, 0)
            loop MonitorGetCount()
                SuiteNotice.Hide("awake-" A_Index)
        }
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
}
