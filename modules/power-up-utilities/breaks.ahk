; =============================================================================
; breaks.ahk - the break reminder: a notice on every display every Minutes,
; and if chosen, the screens turning off or the computer locking after it
; =============================================================================
; While it is on, a reminder shows on every display for 3 s every Minutes, 45
; by default: studies favor a short walk every half hour, while a reminder
; that interrupts too often gets switched off. ActionDelayMs after the
; message, Action locks the computer by default, or turns the screens off or
; does nothing more, as Settings says, and the turn-on notice names it; the notice shows only the message, which may be the user's
; own text. The action is skipped while Windows reports a fullscreen app or
; a presentation, and locking waits until no key the suite watches is down,
; as the lock action does. Turning the reminder off, or leaving, cancels it.
;
; Sound, Proximity by default, plays a Windows sound, or none, with the message
; at Windows' own volume, except during a presentation. LeadMs before it,
; the speakers get keep speakers awake's nudge, its silent tone or chime as
; that setting says, since sleeping speakers take seconds to wake and lose a
; short sound entirely; speaker-standby.md has the measurements. Settings
; previews a sound once as it is chosen.
;
; Time away is a break: locking the computer, the displays turning off,
; sleep and suspending Super Hotkey stop the countdown, and coming back
; starts it over, so the next reminder is a whole interval away and none
; waits from while you were gone. The status notice (Pause + Pause) shows
; when the next one comes. The hotkey action switches it on and off;
; settings.ini [Breaks] keeps that, Minutes, Message, where empty means the
; default, Action and Sound. A dry run never starts it, and checks only report
; the screens or lock action, the nudge and the sound.
; =============================================================================

class PU_Breaks {
    static MinutesDefault := 45
    static MinutesLimit := 240
    static MessageDefault := "Time for a break"
    static NoticeMs := 1400
    ; What follows the message, in the order Settings lists them. Locking is
    ; the default: anyone who turns the reminder on wants the break to happen.
    static Actions := ["message", "screens", "lock"]
    static ActionDefault := "lock"
    static ActionDelayMs := 10000
    static KeysRetryMs := 250
    ; The sounds Settings offers, from C:\Windows\Media, each with its file's
    ; length, silent tail included, so stopping it never cuts it short.
    ; Sounds that mean something in Windows, such as errors, low battery or a
    ; device plugged in, are left out, and so are the ringtones, which sound
    ; like a call.
    static Sounds := ["none", "chimes", "calendar", "proximity", "messagenudge", "tada", "logon",
        "alarm1", "alarm2", "alarm3", "alarm4", "alarm5", "alarm6", "alarm7", "alarm8", "alarm9", "alarm10"]
    static SoundDefault := "proximity"
    static SoundFiles := Map("chimes", {file: "chimes.wav", ms: 1200},
        "calendar", {file: "Windows Notify Calendar.wav", ms: 2000},
        "proximity", {file: "Windows Proximity Notification.wav", ms: 1700},
        "messagenudge", {file: "Windows Message Nudge.wav", ms: 1300},
        "tada", {file: "tada.wav", ms: 1700},
        "logon", {file: "Windows Logon.wav", ms: 4400},
        "alarm1", {file: "Alarm01.wav", ms: 5600},
        "alarm2", {file: "Alarm02.wav", ms: 3700},
        "alarm3", {file: "Alarm03.wav", ms: 4000},
        "alarm4", {file: "Alarm04.wav", ms: 4600},
        "alarm5", {file: "Alarm05.wav", ms: 8300},
        "alarm6", {file: "Alarm06.wav", ms: 6800},
        "alarm7", {file: "Alarm07.wav", ms: 6400},
        "alarm8", {file: "Alarm08.wav", ms: 5700},
        "alarm9", {file: "Alarm09.wav", ms: 5500},
        "alarm10", {file: "Alarm10.wav", ms: 3800})
    ; The measured speakers lit up 1.2 s after a sound began; others take 3 to 5 s.
    static LeadMs := 5000

    __New(module, path) {
        this.module := module
        this.on := IniRead(path, "Breaks", "On", 0) = "1"
        this.minutes := PU_Breaks.CleanMinutes(IniRead(path, "Breaks", "Minutes", PU_Breaks.MinutesDefault))
        this.message := Trim(IniRead(path, "Breaks", "Message", ""))
        this.action := PU_Breaks.CleanAction(IniRead(path, "Breaks", "Action", PU_Breaks.ActionDefault))
        this.sound := PU_Breaks.CleanSound(IniRead(path, "Breaks", "Sound", PU_Breaks.SoundDefault))
        this.due := 0  ; A_TickCount when the next reminder shows, 0 while stopped
        this.displayOff := false
        this.timer := ObjBindMethod(this, "Remind")
        this.leadTimer := ObjBindMethod(this, "Lead")
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
        return PU_Breaks.ActionDefault
    }

    static CleanSound(value) {
        for sound in PU_Breaks.Sounds
            if value = sound
                return sound
        return PU_Breaks.SoundDefault
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
        this.ScheduleLead()
    }

    ; The speakers' nudge, LeadMs before a reminder with a sound.
    ScheduleLead() {
        SetTimer(this.leadTimer, 0)
        if !this.due || this.sound = "none"
            return
        wait := this.due - A_TickCount - PU_Breaks.LeadMs
        if wait > 0
            SetTimer(this.leadTimer, -wait)
    }

    ; Stops the countdown, the nudge and any screens or lock action to come.
    Pause() {
        SetTimer(this.timer, 0)
        SetTimer(this.leadTimer, 0)
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
        this.PlaySound()
        this.Restart()
        if this.action != "message"
            SetTimer(this.actionTimer, -PU_Breaks.ActionDelayMs)
    }

    ; Wakes sleeping speakers for the sound to come.
    Lead(*) {
        SetTimer(this.leadTimer, 0)
        if !this.Present() || this.sound = "none" || this.Presenting()
            return
        try this.module.speakers.Nudge()
        catch Error as failure
            SuiteState.Log.Error("Power-Up Utilities / breaks", failure)
    }

    PlaySound() {
        if this.sound != "none" && !this.Presenting()
            this.Play(this.sound)
    }

    ; Settings plays a sound once as it is chosen; no sound stops it.
    Preview(sound) {
        if sound != "none"
            return this.Play(sound)
        try this.module.speakers.Silence()
    }

    Play(sound) {
        if this.module.dryRun {
            this.module.Report("dry run: break sound " sound)
            return
        }
        entry := PU_Breaks.SoundFiles[sound]
        try this.module.speakers.PlayFile(A_WinDir "\Media\" entry.file, entry.ms)
        catch Error as failure
            SuiteState.Log.Error("Power-Up Utilities / breaks", failure)
    }

    ; QUNS_PRESENTATION_MODE; checks replace it.
    Presenting() {
        state := 0
        return !DllCall("shell32\SHQueryUserNotificationState", "int*", &state, "int") && state = 4
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
        SuiteNotice.Show("status", this.on ? this.OnText() : "Break reminder off", PU_Breaks.NoticeMs)
        this.module.Report(this.on ? "break reminder on" : "break reminder off")
        this.Restart()
    }

    ; Switched on, the notice also says what follows the message, so the first
    ; lock is no surprise.
    OnText() {
        switch this.action {
            case "lock": return "Break reminder every " this.minutes " min, then locks"
            case "screens": return "Break reminder every " this.minutes " min, then screens off"
            default: return "Break reminder every " this.minutes " min"
        }
    }

    ; New choices from Settings; a new interval starts over.
    Apply(minutes, message, action, sound := this.sound) {
        changed := minutes != this.minutes
        this.minutes := minutes
        this.message := message
        this.action := action
        this.sound := sound
        if changed
            this.Restart()
        else
            this.ScheduleLead()
    }

    ; When the next reminder comes, for the status notice, or "" when stopped.
    StatusText() {
        if !this.due
            return ""
        return "Break in " PU_StayAwake.DescribeLeft(Max(0, (this.due - A_TickCount) // 1000))
    }
}
