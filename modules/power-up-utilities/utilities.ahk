; =============================================================================
; utilities.ahk - the sleep hotkey, turning the displays off and stay
; awake's steps and sleep timer; simple text actions live in dispatch, keeping speakers awake
; in speakers.ahk
; =============================================================================
; Sleeping and the stay awake request itself live in core (SuiteSleep,
; SuiteStayAwake), shared with every module.
; =============================================================================

class PU_Utilities {
    __New(app) {
        this.app := app
    }

    SleepComputer(job) {
        if !this.app.JobValid(job) || !this.app.InputsReleased(job.event)
            return
        SuiteSleep.Now(!this.app.realSleep)
    }

    ; Turns the displays off as Windows' own screen timeout does; any touch,
    ; a moved mouse included, wakes them, as Windows decides.
    DisplaysOff(job) {
        if !this.app.JobValid(job) || !this.app.InputsReleased(job.event)
            return
        try SendMessage(0x0112, 0xF170, 2, , "Program Manager") ; WM_SYSCOMMAND, SC_MONITORPOWER, off
        catch
            DllCall("PostMessage", "ptr", 0xFFFF, "uint", 0x0112, "ptr", 0xF170, "ptr", 2) ; HWND_BROADCAST
        this.app.Report("displays off")
    }
}

; Keeps the computer from idle sleep with the request a backup or a video call
; makes, then sleeps it when the chosen time runs out. Screens still turn off
; and lock, and Sleep chosen by hand, the lid and the battery stay Windows' to
; decide. Pause + End steps through the durations while its notice shows and
; starts over once it has gone; each step counts from now. Pause + Shift + End
; ends it without sleeping, back to Windows' own sleep rules.
;
; The last minute warns twice, at 60 and 30 seconds, on every display. At the
; end, someone still using the computer keeps it awake until they have left
; it alone for a minute; a locked computer sleeps at once. A computer that
; was asleep when the time ran out stays awake on waking: someone woke it.
; The deadline is wall-clock time, so time asleep counts.
;
; Coming back after half an hour or more, by unlocking, waking the computer
; or turning the displays back on, shows how long is left on every display.
; The time away counts from the last touch before leaving.
class PU_StayAwake {
    ; Minutes; 0 means no limit.
    static Durations := [30, 60, 120, 240, 480, 0]
    ; A press steps further only while the last step's notice shows.
    static NoticeMs := 1400
    ; Seconds before the end that warn, first to last.
    static Warnings := [60, 30]
    ; Input this recent means someone is at the computer.
    static IdleMs := 60000
    ; A run-out noticed this many seconds late happened while asleep.
    static LateSeconds := 10
    ; Away this long, coming back shows how long is left.
    static AwaySeconds := 1800

    __New(module) {
        this.module := module
        this.index := 0
        this.stepped := 0  ; A_TickCount of the last step
        this.deadline := ""  ; A_NowUTC when a timed step runs out
        this.warned := 0  ; how many of Warnings have passed
        this.waiting := false  ; ran out while someone was at the computer
        this.waitingShown := false  ; the tray already says so
        this.lastSeen := ""  ; A_NowUTC of the last touch before leaving
        this.timer := ObjBindMethod(this, "Advance")
    }

    ; Locked, asleep or with the displays off: remember the last touch, the
    ; first time only, since the displays often go off before the lock.
    Left() {
        if this.lastSeen = ""
            this.lastSeen := DateAdd(A_NowUTC, -(this.IdleTime() // 1000), "Seconds")
    }

    ; Unlocked, awake or with the displays back on, at the desktop: after half
    ; an hour away, a timed stay awake says how long is left. The last minute
    ; has its own warnings.
    Returned() {
        if this.lastSeen = ""
            return
        away := DateDiff(A_NowUTC, this.lastSeen, "Seconds")
        this.lastSeen := ""
        if away < PU_StayAwake.AwaySeconds || !this.index || this.deadline = "" || this.waiting
            return
        remaining := DateDiff(this.deadline, A_NowUTC, "Seconds")
        if remaining <= PU_StayAwake.Warnings[1]
            return
        SuiteNotice.ShowEverywhere("awake", "Sleeping in " PU_StayAwake.DescribeLeft(remaining))
        this.module.Report("back after " away // 60 " min; " remaining // 60 " min left")
    }

    ; Whole minutes, rounded up: "45 min", "2 h", "1 h 12 min".
    static DescribeLeft(seconds) {
        minutes := (seconds + 59) // 60
        if minutes < 60
            return minutes " min"
        return (minutes // 60) " h" (Mod(minutes, 60) ? " " Mod(minutes, 60) " min" : "")
    }

    ; The step after currentIndex when pressed elapsedMs after it: the next
    ; duration while its notice shows, staying on the last, otherwise the first.
    static NextIndex(currentIndex, elapsedMs) {
        if !currentIndex || elapsedMs >= PU_StayAwake.NoticeMs
            return 1
        return Min(currentIndex + 1, PU_StayAwake.Durations.Length)
    }

    static Describe(minutes) => minutes < 60 ? minutes " min" : (minutes // 60) " h"

    Step() {
        index := PU_StayAwake.NextIndex(this.index, (A_TickCount - this.stepped) & 0xFFFFFFFF)
        minutes := PU_StayAwake.Durations[index]
        SuiteStayAwake.Request()
        this.index := index
        this.stepped := A_TickCount
        this.deadline := minutes ? DateAdd(A_NowUTC, minutes, "Minutes") : ""
        this.warned := 0
        this.waiting := this.waitingShown := false
        SetTimer(this.timer, 0)
        if minutes
            this.Advance()
        this.module.SetTrayStatus(minutes
            ? "Awake until " FormatTime(DateAdd(A_Now, minutes, "Minutes"), "HH:mm") ", then sleep"
            : "Awake until turned off")
        text := minutes ? "Awake for " PU_StayAwake.Describe(minutes) ", then sleep" : "Awake until turned off"
        SuiteNotice.Show("status", text, PU_StayAwake.NoticeMs)
        this.module.Report(text)
    }

    AllowSleep() {
        active := this.index
        this.End()
        SuiteNotice.Show("status", active ? "Sleep allowed again" : "Sleep already allowed", PU_StayAwake.NoticeMs)
        if active
            this.module.Report("stay awake ended")
    }

    ; Runs at each warning and at the end, and again while waiting for
    ; someone at the computer to leave it alone.
    Advance(*) {
        if !this.index || this.deadline = ""
            return
        if this.waiting
            return this.SleepWhenIdle()
        app := this.module.app
        remaining := DateDiff(this.deadline, A_NowUTC, "Seconds")
        if remaining <= 0 {
            if app.systemSuspended || remaining < -PU_StayAwake.LateSeconds {
                this.End()
                this.module.Report("stay awake ran out while asleep, so the computer stays awake")
                return
            }
            this.waiting := true
            return this.SleepWhenIdle()
        }
        next := 0
        for index, seconds in PU_StayAwake.Warnings {
            if remaining > seconds {
                next := seconds
                break
            }
            if this.warned >= index
                continue
            ; A warning noticed late, or while away, would tell the wrong time.
            this.warned := index
            if remaining > seconds - 5 && !app.systemSuspended && !app.sessionLocked
                SuiteNotice.ShowEverywhere("awake", this.WarningText(seconds))
        }
        SetTimer(this.timer, -(remaining - next) * 1000)
    }

    ; Sleeps once nobody has touched the computer for a minute, at once when
    ; it is locked.
    SleepWhenIdle() {
        app := this.module.app
        idle := this.IdleTime()
        if !app.sessionLocked && idle < PU_StayAwake.IdleMs {
            if !this.waitingShown {
                this.waitingShown := true
                this.module.SetTrayStatus("Sleeping once you leave the computer alone")
                this.module.Report("stay awake ran out while in use; sleeping once idle")
            }
            SetTimer(this.timer, -(PU_StayAwake.IdleMs - idle))
            return
        }
        this.End()
        this.module.Report("stay awake ran out; sleeping")
        if app.dryRun {
            this.module.Report("dry run: sleep")
            return
        }
        try SuiteSleep.Now(!this.module.realSleep)
        catch Error as failure
            SuiteState.Log.Error("Power-Up Utilities / stay awake sleep", failure)
    }

    ; Milliseconds since the last keyboard or mouse input; checks replace it.
    IdleTime() => A_TimeIdlePhysical

    ; "Sleeping in 1 minute" or "in 30 seconds", naming the stay awake hotkey
    ; that gives more time, when it has one.
    WarningText(seconds) {
        text := "Sleeping in " (seconds = 60 ? "1 minute" : seconds " seconds") "."
        try {
            parsed := Keybindings.Parse(
                this.module.manager.configuration["power-up-utilities.system.stay-awake"].bindings[1])
            if IsObject(parsed)
                text .= " " parsed.label " for more time."
        }
        return text
    }

    ; Withdraws the request; safe when none is active.
    End() {
        SetTimer(this.timer, 0)
        SuiteStayAwake.Release()
        this.index := 0
        this.deadline := ""
        this.warned := 0
        this.waiting := this.waitingShown := false
        this.module.SetTrayStatus("")
    }
}
