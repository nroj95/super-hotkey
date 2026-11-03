; =============================================================================
; bedtime.ahk - up to three messages at times the user chooses, the last of
; which can also put the computer to sleep
; =============================================================================
; Each message shows on every display when the clock reaches its time while the
; user is at the unlocked computer. A minute that passes while the computer
; sleeps or is locked is simply gone: nothing catches up later, so the rows
; never depend on each other or on their order. The sleep waits until its
; message has gone, so it is read first; stay awake prevents only the sleep,
; and the last row then shows its own stay awake message instead. Every row
; and the sleep start off; settings.ini [Bedtime] holds them.
; =============================================================================

class PU_Bedtime {
    static Defaults := [["0000", "It's getting late"], ["0100", "zzz…"], ["0200", "Good night"]]
    static AwakeDefault := "Stay awake prevented sleep"
    static TextLimit := 60
    ; Ticks further apart follow sleep or a clock change: the minutes in
    ; between were not spent at the computer.
    static GapSeconds := 120
    static TickMs := 5000

    __New(module, path) {
        this.module := module
        this.path := path
        this.rows := []
        this.sleeps := false
        this.awakeText := PU_Bedtime.AwakeDefault
        this.last := ""  ; A_Now at the previous tick
        this.tickCallback := ObjBindMethod(this, "Tick")
        this.sleepCallback := ObjBindMethod(this, "SleepAfterMessage")
        this.Load()
    }

    static ValidTime(text) => RegExMatch(text, "^([01]\d|2[0-3])[0-5]\d$")

    ; One line of at most TextLimit characters; empty means the default words.
    static CleanText(text, fallback) {
        text := Trim(RegExReplace(text, "\s+", " "))
        return text = "" ? fallback : SubStr(text, 1, PU_Bedtime.TextLimit)
    }

    Load() {
        this.rows := []
        for index, defaults in PU_Bedtime.Defaults {
            time := IniRead(this.path, "Bedtime", "Time" index, defaults[1])
            this.rows.Push({show: IniRead(this.path, "Bedtime", "Show" index, 0) = "1",
                time: PU_Bedtime.ValidTime(time) ? time : defaults[1],
                text: PU_Bedtime.CleanText(IniRead(this.path, "Bedtime", "Text" index, ""), defaults[2])})
        }
        this.sleeps := IniRead(this.path, "Bedtime", "Sleep", 0) = "1"
        this.awakeText := PU_Bedtime.CleanText(IniRead(this.path, "Bedtime", "AwakeText", ""),
            PU_Bedtime.AwakeDefault)
    }

    Start() {
        this.last := A_Now
        SetTimer(this.tickCallback, PU_Bedtime.TickMs)
    }

    Stop() {
        SetTimer(this.tickCallback, 0)
        SetTimer(this.sleepCallback, 0)
    }

    Tick(*) => this.Check(A_Now)

    ; Shows each row whose minute lies after the previous tick and at or before
    ; now. Returns the indexes shown.
    Check(now) {
        last := this.last
        this.last := now
        shown := []
        if last = ""
            return shown
        gap := DateDiff(now, last, "Seconds")
        if gap <= 0 || gap > PU_Bedtime.GapSeconds || !this.Present()
            return shown
        for index, row in this.rows {
            if !row.show
                continue
            ; Around midnight the two ticks fall on different days.
            for day in [SubStr(last, 1, 8), SubStr(now, 1, 8)] {
                moment := day row.time "00"
                if DateDiff(moment, last, "Seconds") > 0 && DateDiff(moment, now, "Seconds") <= 0 {
                    shown.Push(index)
                    this.Show(index)
                    break
                }
            }
        }
        return shown
    }

    Present() {
        app := this.module.app
        return app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked
    }

    Show(index) {
        sleeping := index = this.rows.Length && this.sleeps
        prevented := sleeping && this.module.stayAwake.index
        SuiteNotice.ShowEverywhere("status", prevented ? this.awakeText : this.rows[index].text)
        this.module.Report("bedtime message " index
            . (prevented ? ", sleep prevented by stay awake" : sleeping ? ", then sleep" : ""))
        if sleeping && !prevented
            SetTimer(this.sleepCallback, -SuiteNotice.NewsMs)
    }

    ; Locking meanwhile still sleeps; suspending, staying awake or turning the
    ; sleep off does not. Held keys could stay stuck after waking, so it waits.
    SleepAfterMessage(*) {
        app := this.module.app
        if !this.sleeps || this.module.stopping || !app.ModuleActive(this.module.id)
            || app.suspended || app.systemSuspended || this.module.stayAwake.index
            return
        for key in PowerUpUtilities.BlockingKeys("sleep")
            if GetKeyState(key, "P") {
                SetTimer(this.sleepCallback, -250)
                return
            }
        if this.module.dryRun {
            this.module.Report("dry run: bedtime sleep")
            return
        }
        try this.module.utilities.Sleep()
        catch Error as failure {
            SuiteState.Log.Error("Power-Up Utilities / bedtime sleep", failure)
            TrayTip(failure.Message, this.module.Name, 2)
        }
    }
}
