; =============================================================================
; utilities.ahk - the sleep hotkey, turning the displays off and stay
; awake's steps; simple text actions live in dispatch, keeping speakers awake
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
; makes. Screens still turn off and lock, and Sleep chosen by hand, the lid and
; the battery stay Windows' to decide. Pause + End steps through the durations
; while its notice shows and starts over once it has gone; each step counts
; from now. Pause + Shift + End allows sleep again.
class PU_StayAwake {
    ; Minutes; 0 means no limit.
    static Durations := [30, 60, 120, 240, 480, 0]
    ; A press steps further only while the last step's notice shows.
    static NoticeMs := 1400

    __New(module) {
        this.module := module
        this.index := 0
        this.stepped := 0  ; A_TickCount of the last step
        this.missed := false  ; ran out, its notice not yet shown
        this.timer := ObjBindMethod(this, "Expire")
        this.missedTimer := ObjBindMethod(this, "ShowMissed")
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
        SetTimer(this.timer, minutes ? -minutes * 60000 : 0)
        this.module.SetTrayStatus(minutes
            ? "Awake until " FormatTime(DateAdd(A_Now, minutes, "Minutes"), "HH:mm") : "Awake until turned off")
        text := minutes ? "Awake for " PU_StayAwake.Describe(minutes) : "Awake until turned off"
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

    ; Running out was not a press, so the active window says little about
    ; where the user looks: the notice shows on every display. A timer that ran
    ; out during sleep fires on waking, behind the lock screen: sleep is
    ; allowed at once, and the notice waits until the user is back (Returned).
    Expire(*) {
        if !this.index
            return
        app := this.module.app
        away := app.systemSuspended || app.sessionLocked
        this.End()
        this.missed := true
        this.module.Report(away ? "stay awake ended while asleep or locked" : "stay awake ended")
        if !away
            this.ShowMissed()
    }

    ; Back at the desktop: a second lets the unlock settle, so the short notice
    ; is not spent while the lock screen slides away.
    Returned() {
        if this.missed
            SetTimer(this.missedTimer, -1000)
    }

    ; Locked again in that second: the notice waits for the next unlock.
    ShowMissed(*) {
        app := this.module.app
        if !this.missed || app.systemSuspended || app.sessionLocked
            return
        this.missed := false
        SuiteNotice.ShowEverywhere("status", "Sleep allowed again")
    }

    ; Withdraws the request; safe when none is active.
    End() {
        SetTimer(this.timer, 0)
        SetTimer(this.missedTimer, 0)
        SuiteStayAwake.Release()
        this.index := 0
        this.missed := false
        this.module.SetTrayStatus("")
    }
}
