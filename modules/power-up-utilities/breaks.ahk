; =============================================================================
; breaks.ahk - the break reminder: a notice on every display every Minutes,
; and if chosen, the screens turning off or the computer locking after it
; =============================================================================
; While it is on, a reminder shows on every display for 3 s every Minutes, 45
; by default: studies favor a short walk every half hour, while a reminder
; that interrupts too often gets switched off. Action can also turn the
; screens off or lock the computer ActionDelayMs after the message, as
; Settings says; the notice shows only the message, which may be the user's
; own text. The action is skipped while Windows reports a fullscreen app or
; a presentation, and locking waits until no key the suite watches is down,
; as the lock action does. Turning the reminder off, or leaving, cancels it.
;
; Time away is a break: locking the computer, the displays turning off,
; sleep and suspending Super Hotkey stop the countdown, and coming back
; starts it over, so the next reminder is a whole interval away and none
; waits from while you were gone. The status notice (Pause + Pause) shows
; when the next one comes. The hotkey action switches it on and off;
; settings.ini [Breaks] keeps that, Minutes, Message, where empty means the
; default, and Action. A dry run never starts it, and checks only report the
; screens or lock action.
; =============================================================================

class PU_Breaks {
    static MinutesDefault := 45
    static MinutesLimit := 240
    static MessageDefault := "Time for a break"
    static NoticeMs := 1400
    ; What follows the message, in the order Settings lists them.
    static Actions := ["message", "screens", "lock"]
    static ActionDelayMs := 10000
    static KeysRetryMs := 250

    __New(module, path) {
        this.module := module
        this.on := IniRead(path, "Breaks", "On", 0) = "1"
        this.minutes := PU_Breaks.CleanMinutes(IniRead(path, "Breaks", "Minutes", PU_Breaks.MinutesDefault))
        this.message := Trim(IniRead(path, "Breaks", "Message", ""))
        this.action := PU_Breaks.CleanAction(IniRead(path, "Breaks", "Action", "message"))
        this.due := 0  ; A_TickCount when the next reminder shows, 0 while stopped
        this.displayOff := false
        this.timer := ObjBindMethod(this, "Remind")
        this.actionTimer := ObjBindMethod(this, "Act")
        this.backCallback := ObjBindMethod(this, "Restart")
        this.displaysCallback := ObjBindMethod(this, "DisplaysChanged")
    }

    static CleanMinutes(value) => IsInteger(value) && value >= 1 && value <= PU_Breaks.MinutesLimit
        ? Integer(value) : PU_Breaks.MinutesDefault

    static CleanAction(value) {
        for action in PU_Breaks.Actions
            if value = action
                return action
        return "message"
    }

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

    ; Stops the countdown and any screens or lock action still to come.
    Pause() {
        SetTimer(this.timer, 0)
        SetTimer(this.actionTimer, 0)
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
        if this.action != "message"
            SetTimer(this.actionTimer, -PU_Breaks.ActionDelayMs)
    }

    ; Turns the screens off or locks, unless the user left, turned the
    ; reminder off or is in a fullscreen app or a presentation.
    Act(*) {
        SetTimer(this.actionTimer, 0)
        if !this.Present() || this.action = "message"
            return
        if this.Busy() {
            this.module.Report("break " this.action " skipped: fullscreen or presenting")
            return
        }
        if this.action = "lock" && this.KeysDown() {
            SetTimer(this.actionTimer, -PU_Breaks.KeysRetryMs)
            return
        }
        if this.module.dryRun {
            this.module.Report("dry run: break " this.action)
            return
        }
        this.module.Report("break " this.action)
        if this.action = "lock" {
            if !DllCall("LockWorkStation", "int")
                SuiteState.Log.Error("Power-Up Utilities / breaks",
                    OSError(A_LastError, "LockWorkStation", "Windows could not lock the computer."))
            return
        }
        try SendMessage(0x0112, 0xF170, 2, , "Program Manager") ; WM_SYSCOMMAND, SC_MONITORPOWER, off
        catch
            DllCall("PostMessage", "ptr", 0xFFFF, "uint", 0x0112, "ptr", 0xF170, "ptr", 2) ; HWND_BROADCAST
    }

    ; QUNS_BUSY (a window covers a display), QUNS_RUNNING_D3D_FULL_SCREEN or
    ; QUNS_PRESENTATION_MODE; checks replace it.
    Busy() {
        state := 0
        return !DllCall("shell32\SHQueryUserNotificationState", "int*", &state, "int")
            && (state = 2 || state = 3 || state = 4)
    }

    ; A key let go on the lock screen never reaches the suite, so one still
    ; down would stay stuck; checks replace it.
    KeysDown() {
        for key in PowerUpUtilities.BlockingKeys("lock")
            if GetKeyState(key, "P")
                return true
        return false
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

    ; New choices from Settings; a new interval starts over.
    Apply(minutes, message, action) {
        changed := minutes != this.minutes
        this.minutes := minutes
        this.message := message
        this.action := action
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
