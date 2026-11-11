; =============================================================================
; breaks.ahk - the break reminder: a notice on every display every Minutes
; =============================================================================
; While it is on, a reminder shows on every display for 3 s every Minutes, 45
; by default: studies favor a short walk every half hour, while a reminder
; that interrupts too often gets switched off. Time away is a break: locking the computer, the displays turning
; off, sleep and suspending Super Hotkey stop the countdown, and coming back
; starts it over, so the next reminder is a whole interval away and none
; waits from while you were gone. The status notice (Pause + Pause) shows when
; the next one comes. The action switches it on and off; settings.ini [Breaks]
; keeps that, Minutes and Message, where an empty Message means the default.
; A dry run never starts it.
; =============================================================================

class PU_Breaks {
    static MinutesDefault := 45
    static MinutesLimit := 240
    static MessageDefault := "Time for a break"
    static NoticeMs := 1400

    __New(module, path) {
        this.module := module
        this.on := IniRead(path, "Breaks", "On", 0) = "1"
        this.minutes := PU_Breaks.CleanMinutes(IniRead(path, "Breaks", "Minutes", PU_Breaks.MinutesDefault))
        this.message := Trim(IniRead(path, "Breaks", "Message", ""))
        this.due := 0  ; A_TickCount when the next reminder shows, 0 while stopped
        this.displayOff := false
        this.timer := ObjBindMethod(this, "Remind")
        this.backCallback := ObjBindMethod(this, "Restart")
        this.displaysCallback := ObjBindMethod(this, "DisplaysChanged")
    }

    static CleanMinutes(value) => IsInteger(value) && value >= 1 && value <= PU_Breaks.MinutesLimit
        ? Integer(value) : PU_Breaks.MinutesDefault

    Text => this.message != "" ? this.message : PU_Breaks.MessageDefault

    Start() {
        this.displayOff := !SuiteDisplays.on
        SuiteDisplays.OnChange(this.displaysCallback)
        this.Restart()
    }

    Stop() {
        SuiteDisplays.OffChange(this.displaysCallback)
        this.Pause()
    }

    ; At the computer, unlocked, awake, displays on and the suite running.
    Present() {
        app := this.module.app
        return this.on && app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked && !this.displayOff
    }

    ; A whole interval from now, when present; otherwise stopped until back.
    Restart() {
        if !this.Present()
            return this.Pause()
        this.due := A_TickCount + this.minutes * 60000
        SetTimer(this.timer, -this.minutes * 60000)
    }

    Pause() {
        SetTimer(this.timer, 0)
        SetTimer(this.backCallback, 0)
        this.due := 0
    }

    ; From the module's Resume, which core calls before it clears the
    ; suspended and asleep flags, so the restart waits a moment.
    Back() => SetTimer(this.backCallback, -1)

    ; From core's display watcher: off is time away, on is coming back.
    DisplaysChanged(on) {
        this.displayOff := !on
        this.Restart()
    }

    Remind(*) {
        if !this.Present()
            return this.Pause()
        SuiteNotice.ShowEverywhere("breaks", this.Text)
        this.module.Report("break reminder shown")
        this.Restart()
    }

    ; The action: on or off, kept across restarts.
    Toggle() {
        this.on := !this.on
        this.module.app.Settings.WritePreferences(this.module.id,
            Map("Breaks", Map("On", this.on ? 1 : 0)))
        SuiteNotice.Show("status", this.on ? "Break reminder every " this.minutes " min" : "Break reminder off",
            PU_Breaks.NoticeMs)
        this.module.Report(this.on ? "break reminder on" : "break reminder off")
        this.Restart()
    }

    ; A new interval or message from Settings; a new interval starts over.
    Apply(minutes, message) {
        changed := minutes != this.minutes
        this.minutes := minutes
        this.message := message
        if changed
            this.Restart()
    }

    ; When the next reminder comes, for the status notice, or "" when stopped.
    StatusText() {
        if !this.due
            return ""
        return "Break in " PU_StayAwake.DescribeLeft(Max(0, (this.due - A_TickCount) // 1000))
    }
}
