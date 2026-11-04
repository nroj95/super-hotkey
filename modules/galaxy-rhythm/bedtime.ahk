; =============================================================================
; bedtime.ahk - two reminders at times the user chooses, then a last message
; that fades the displays to grey and puts the computer to sleep
; =============================================================================
; Each message shows on every display when the clock reaches its time while the
; user is at the unlocked computer. A minute that passes while the computer
; sleeps or is locked is simply gone: nothing catches up later, so the rows
; never depend on each other or on their order.
;
; The last row is the sleep, and from its time until the day starts
; (wakeTime, Your day starts at) it is lights-out: whenever the user is at
; the unlocked computer, its message shows, the displays fade to grey over
; the fade time, the last word shows, and once it has gone the computer
; sleeps; locking meanwhile changes nothing. Waking the computer before the
; day starts begins it all again, so a quick look is fine but the night
; stays a night, and the day starting ends a fade. A fade starts from any
; grey already showing, the energy bar's frozen grey, and darkens from there,
; so the screen never clears before it greys. Stay awake prevents only
; the sleep. On at bedtime, or switched on during the fade or the last word,
; it shows its own message and clears the grey; ending before the day
; starts, it lets the fade begin again. A night off, or Super Hotkey
; suspended, shows nothing and fades nothing. The module itself starts
; disabled, so every row starts on: enabling Galaxy Rhythm is the opt-in.
; settings.ini [Bedtime] holds them.
; =============================================================================

class GR_Bedtime {
    static Defaults := [["0000", "It's getting late"], ["0100", "zzz…"], ["0200", "You feel sleepy"]]
    static SleepDefault := "Good night"
    static AwakeDefault := "Stay awake prevented sleep"
    static WakeDefault := "0600"
    static FadeDefault := 10  ; minutes
    static FadeLimit := 120
    static TextLimit := 60
    ; Ticks further apart follow sleep or a clock change: the minutes in
    ; between were not spent at the computer.
    static GapSeconds := 120
    static TickMs := 5000
    static FadeStepMs := 1000
    ; Keys that could stay stuck down if held as the computer sleeps.
    static HeldKeys := ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]

    __New(module, path) {
        this.module := module
        this.path := path
        this.rows := []
        this.fadeMinutes := GR_Bedtime.FadeDefault
        this.wakeTime := GR_Bedtime.WakeDefault
        this.sleepText := GR_Bedtime.SleepDefault
        this.awakeText := GR_Bedtime.AwakeDefault
        this.last := ""        ; A_Now at the previous tick
        this.fadeStarted := 0  ; A_TickCount while fading
        this.fadeFrom := 0     ; the grey other sources showed as the fade began
        this.saying := false   ; the last word shows, the sleep is armed
        this.tickCallback := ObjBindMethod(this, "Tick")
        this.fadeCallback := ObjBindMethod(this, "FadeStep")
        this.sleepCallback := ObjBindMethod(this, "SleepAfterMessage")
        this.Load()
    }

    static ValidTime(text) => RegExMatch(text, "^([01]\d|2[0-3])[0-5]\d$")

    ; One line of at most TextLimit characters; empty means the default words.
    static CleanText(text, fallback) {
        text := Trim(RegExReplace(text, "\s+", " "))
        return text = "" ? fallback : SubStr(text, 1, GR_Bedtime.TextLimit)
    }

    static CleanMinutes(text) => IsInteger(text) && text >= 1 && text <= GR_Bedtime.FadeLimit
        ? Integer(text) : GR_Bedtime.FadeDefault

    ; Lights-out: since the day last started, the clock has passed the sleep's
    ; time (HHmm).
    static InNight(now, sleepTime, wakeTime) => DateDiff(GR_Energy.LastAt(now, sleepTime),
        GR_Energy.LastAt(now, wakeTime), "Seconds") > 0

    Night(now) => this.rows[-1].show && GR_Bedtime.InNight(now, this.rows[-1].time, this.wakeTime)

    ; The first moment after now at the HHmm time.
    static NextMoment(now, time) {
        moment := SubStr(now, 1, 8) time "00"
        return DateDiff(moment, now, "Seconds") > 0 ? moment : DateAdd(moment, 1, "Days")
    }

    Load() {
        this.rows := []
        for index, defaults in GR_Bedtime.Defaults {
            time := IniRead(this.path, "Bedtime", "Time" index, defaults[1])
            this.rows.Push({show: IniRead(this.path, "Bedtime", "Show" index, 1) = "1",
                time: GR_Bedtime.ValidTime(time) ? time : defaults[1],
                text: GR_Bedtime.CleanText(IniRead(this.path, "Bedtime", "Text" index, ""), defaults[2])})
        }
        this.fadeMinutes := GR_Bedtime.CleanMinutes(IniRead(this.path, "Bedtime", "FadeMinutes", ""))
        wake := IniRead(this.path, "Bedtime", "WakeTime", GR_Bedtime.WakeDefault)
        this.wakeTime := GR_Bedtime.ValidTime(wake) ? wake : GR_Bedtime.WakeDefault
        this.sleepText := GR_Bedtime.CleanText(IniRead(this.path, "Bedtime", "SleepText", ""),
            GR_Bedtime.SleepDefault)
        this.awakeText := GR_Bedtime.CleanText(IniRead(this.path, "Bedtime", "AwakeText", ""),
            GR_Bedtime.AwakeDefault)
        if !this.rows[-1].show
            this.CancelFade()
    }

    Start() {
        this.last := A_Now
        SetTimer(this.tickCallback, GR_Bedtime.TickMs)
    }

    Stop() {
        SetTimer(this.tickCallback, 0)
        this.CancelFade()
    }

    Tick(*) => this.Check(A_Now)

    ; Shows each row whose minute lies after the previous tick and at or before
    ; now, then fades whenever the user is there during lights-out, and stops
    ; a fade the day's start has overtaken. Returns the indexes shown.
    Check(now) {
        last := this.last
        this.last := now
        shown := []
        if last != "" {
            gap := DateDiff(now, last, "Seconds")
            if gap > 0 && gap <= GR_Bedtime.GapSeconds && this.Present(now)
                for index, row in this.rows {
                    if !row.show
                        continue
                    ; Around midnight the two ticks fall on different days.
                    for day in [SubStr(last, 1, 8), SubStr(now, 1, 8)] {
                        moment := day row.time "00"
                        if DateDiff(moment, last, "Seconds") > 0 && DateDiff(moment, now, "Seconds") <= 0 {
                            shown.Push(index)
                            this.Show(index, now)
                            break
                        }
                    }
                }
        }
        if this.Night(now) {
            if !this.fadeStarted && !SuiteStayAwake.active && this.Present(now)
                this.StartFade()
        }
        else if this.fadeStarted
            this.CancelFade()
        return shown
    }

    Present(now) {
        app := this.module.app
        return app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked && !this.module.Off(now)
    }

    Show(index, now) {
        if index != this.rows.Length {
            SuiteNotice.ShowEverywhere("status", this.rows[index].text)
            this.module.Report("bedtime message " index)
            return
        }
        if SuiteStayAwake.active
            this.Prevented()
        else
            this.StartFade()
    }

    StartFade() {
        SuiteNotice.ShowEverywhere("status", this.rows[-1].text)
        this.module.Report("bedtime message " this.rows.Length ", fading to sleep over " this.fadeMinutes " min")
        this.fadeStarted := A_TickCount
        this.fadeFrom := 0
        for source, level in this.module.grey.levels
            if source != "bedtime"
                this.fadeFrom := Max(this.fadeFrom, level)
        this.saying := false
        SetTimer(this.fadeCallback, GR_Bedtime.FadeStepMs)
    }

    ; Greys a little more each second; fully grey, the last word shows and
    ; arms the sleep. Stay awake switched on meanwhile ends the fade.
    FadeStep(tick := "") {
        if !this.fadeStarted
            return
        if SuiteStayAwake.active {
            this.Prevented()
            return
        }
        elapsed := ((tick = "" ? A_TickCount : tick) - this.fadeStarted) & 0xFFFFFFFF
        progress := elapsed / (this.fadeMinutes * 60000)
        this.module.grey.Set("bedtime", this.fadeFrom + (1 - this.fadeFrom) * progress)
        if progress < 1 || this.saying
            return
        this.saying := true
        SuiteNotice.ShowEverywhere("status", this.sleepText)
        SetTimer(this.sleepCallback, -SuiteNotice.NewsMs)
    }

    ; Lights-out goes on: its sleep waits for stay awake to end.
    Prevented() {
        this.CancelFade()
        SuiteNotice.ShowEverywhere("status", this.awakeText)
        this.module.Report("bedtime sleep prevented by stay awake")
    }

    CancelFade() {
        SetTimer(this.fadeCallback, 0)
        SetTimer(this.sleepCallback, 0)
        if this.fadeStarted
            this.module.grey.Set("bedtime", 0)
        this.fadeStarted := 0
        this.saying := false
    }

    ; Locking meanwhile still sleeps. Held keys could stay stuck after waking,
    ; so it waits; the grey stays until the computer is asleep.
    SleepAfterMessage(*) {
        app := this.module.app
        if !this.saying || this.module.stopping || !app.ModuleActive(this.module.id)
            || app.suspended || app.systemSuspended
            return
        if SuiteStayAwake.active {
            this.Prevented()
            return
        }
        for key in GR_Bedtime.HeldKeys
            if GetKeyState(key, "P") {
                SetTimer(this.sleepCallback, -250)
                return
            }
        SetTimer(this.fadeCallback, 0)
        if this.module.dryRun {
            this.module.Report("dry run: bedtime sleep")
            this.CancelFade()
            return
        }
        try SuiteSleep.Now()
        catch Error as failure {
            this.CancelFade()
            SuiteState.Log.Error("Galaxy Rhythm / bedtime sleep", failure)
            TrayTip(failure.Message, this.module.Name, 2)
            return
        }
        ; This clears the grey even if Windows accepted the sleep without
        ; sleeping; woken before the day starts, Check fades again.
        SetTimer(ObjBindMethod(this, "CancelFade"), -5000)
    }
}
