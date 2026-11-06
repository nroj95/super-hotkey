; Galaxy Rhythm: bedtime messages, the fade to sleep and the energy bar, with
; their settings page and guide; bedtime.ahk runs the night, energy.ahk the
; bar and grey-screen.ahk the grey both share; GR_Sleep below is how both
; bedtime's sleep and the energy bar's faint end. Stay awake and sleeping come
; from core (SuiteStayAwake, SuiteSleep), so Power-Up Utilities' Pause + End
; keeps the computer up through bedtime too; the energy bar ignores it.
;
; One time, Your day starts at (the bedtime wakeTime), ends both bedtime's
; night and a night off. Help's Tonight off button starts a night off: it
; asks first, then until the day starts there are no bedtime messages or
; sleep, and the energy bar keeps counting out of sight, without notices,
; grey or faint, so the next morning pays for what was spent and nothing
; more. Meanwhile the button reads Back on, which ends the night off early.
; It asks first only on the energy bar's road before bedtime's night, where
; the grey comes back at once and Lights out follows; in bedtime's night the
; fade to sleep starts with bedtime's own message, and otherwise a notice
; says it's back on. night.ini keeps a night off across restarts.
class GalaxyRhythmModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Bedtime", "Energy"]
    static OffLabel := "Tonight off"
    static OnLabel := "Back on"
    static WindLabel := "Second wind"

    __New(app) {
        super.__New(app, "galaxy-rhythm")
        this.stopping := false
        this.displayChoices := []  ; the settings page's Display values
        this.grey := GR_GreyScreen(app.dryRun)
        folder := app.Settings.directory "\" this.id
        this.nightPath := folder "\night.ini"
        saved := IniRead(this.nightPath, "Night", "OffUntil", "")
        this.offUntil := IsTime(saved) ? saved : ""  ; A_Now when a night off ends
        this.syncCallback := ObjBindMethod(this, "SyncNightOff")
        this.bedtime := GR_Bedtime(this, folder "\settings.ini")
        this.energy := GR_Energy(this, folder "\settings.ini", folder "\energy.ini")
    }

    dryRun => this.app.dryRun

    ; A night off lasts until the day starts.
    Off(now := "") => this.offUntil != "" && DateDiff(now = "" ? A_Now : now, this.offUntil, "Seconds") < 0

    ; The energy bar's Lights out has shown and its sleep is on the way.
    Fainting() => this.energy.fainting

    ; The displays are off, as Windows reports to the energy bar: nobody is
    ; looking, as when Windows wakes the computer on its own for updates.
    DisplaysOff() => this.energy.displayOff

    HelpButtons() => this.app.ModuleActive(this.id)
        ? [[GalaxyRhythmModule.WindLabel, ObjBindMethod(this, "TakeSecondWind")],
            [this.NightLabel(), ObjBindMethod(this, "ToggleNightOff")]] : []

    NightLabel() => this.Off() ? GalaxyRhythmModule.OnLabel : GalaxyRhythmModule.OffLabel

    ; Once a day, a quarter of a full bar back, from Help, once all of it fits.
    TakeSecondWind(*) {
        result := this.energy.SecondWind()
        SuiteNotice.Show("status", result = "given" ? Format("Second wind: +{1} %", Round(GR_Energy.WindShare * 100))
            : result = "early" ? Format("Too early: second wind works at {1} % or less", Round((1 - GR_Energy.WindShare) * 100))
            : "Second wind already taken today", 1400)
    }

    ; Tonight off asks first; Back on asks only before what it brings back at once.
    ToggleNightOff(*) {
        if this.Off() {
            this.BackOn()
            return
        }
        ends := FormatTime(GR_Bedtime.NextMoment(A_Now, this.bedtime.wakeTime), "HH:mm")
        if MsgBox(Format("Turn Galaxy Rhythm off until {1}?", ends)
            . "`n`nBedtime goes quiet and the energy bar hides until your day starts, though it keeps counting."
            . " Back on in Help turns it on again.", this.Name, "YesNo Default2 Icon?") = "Yes"
            this.SetNightOff()
    }

    ; What Back on asks first: on the energy bar's road before bedtime's
    ; night, the grey comes back at once and Lights out follows. "" otherwise.
    BackOnQuestion(now) {
        energy := this.energy
        if !energy.show || !energy.faint || energy.level > 0 || this.bedtime.Night(now)
            return ""
        if energy.level <= -energy.roadMinutes
            return "Your energy is empty: back on means Lights out, and the computer sleeps."
                . " Anything online or still running stops.`n`nTurn Galaxy Rhythm back on?"
        return Format("You're running on fumes: back on, the screen greys and Lights out comes after about"
            . " {1} min of activity.`n`nTurn Galaxy Rhythm back on?", Ceil(energy.roadMinutes + energy.level))
    }

    ; Ends a night off early. In bedtime's night the fade starts at once with
    ; bedtime's own message; the energy bar's notices and faint follow within
    ; a second as its hold lifts.
    BackOn(now := "") {
        now := now = "" ? A_Now : now
        if !this.Off(now)
            return
        question := this.BackOnQuestion(now)
        if question != "" && MsgBox(question, this.Name, "YesNo Default2 Icon!") != "Yes"
            return
        this.offUntil := ""
        this.SaveNight()
        this.Report("night off ended early")
        this.SyncNightOff()
        if this.bedtime.Night(now)
            this.bedtime.Check(now)
        else if question = ""
            SuiteNotice.Show("status", "Galaxy Rhythm is back on", 1400)
    }

    ; Help's night button, if Help is open; modules start before the
    ; interface exists.
    NightButton() {
        if IsObject(this.app.ui) && this.app.ui.windows.Has("help:" this.id)
            for hwnd, control in this.app.ui.windows["help:" this.id]
                if control.Type = "Button" && (control.Text = GalaxyRhythmModule.OffLabel
                    || control.Text = GalaxyRhythmModule.OnLabel)
                    return control
        return 0
    }

    ; Help's button follows the night off, also as it ends with Help open.
    SyncNightOff(*) {
        if button := this.NightButton()
            this.app.ui.SetFooterText(button, this.NightLabel())
        SetTimer(this.syncCallback, this.Off() ? -(DateDiff(this.offUntil, A_Now, "Seconds") + 1) * 1000 : 0)
    }

    SaveNight() {
        if this.dryRun
            return
        try {
            SplitPath(this.nightPath, , &directory)
            DirCreate(directory)
            IniWrite(this.offUntil, this.nightPath, "Night", "OffUntil")
        }
        catch Error as failure
            SuiteState.Log.Error("Galaxy Rhythm / night off", failure)
    }

    SetNightOff(now := "") {
        now := now = "" ? A_Now : now
        this.offUntil := GR_Bedtime.NextMoment(now, this.bedtime.wakeTime)
        this.SaveNight()
        this.bedtime.CancelFade()
        this.energy.Shade()
        SuiteNotice.Show("status", Format("Galaxy Rhythm is off until {1}", FormatTime(this.offUntil, "HH:mm")), 1400)
        this.Report("night off until " this.offUntil)
        this.SyncNightOff()
    }

    ; Help sits on the Pause layer with sleep, the displays and stay awake;
    ; it answers only while the module is on.
    Register(manager) {
        manager.AddAction("galaxy-rhythm.help", "show Galaxy Rhythm help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Pause + G"],
            {category: "Galaxy Rhythm", available: (*) => this.app.ModuleActive(this.id)})
    }

    Start() {
        this.bedtime.Start()
        this.energy.Start()
        this.SyncNightOff()
    }

    Stop(reason := "Exit", *) {
        this.stopping := true
        SetTimer(this.syncCallback, 0)
        this.bedtime.Stop()
        this.energy.Stop(reason)
        this.grey.Clear()
    }

    ; Suspending Super Hotkey or the computer sleeping ends a bedtime night:
    ; the user asked for quiet, or the computer has slept. Locking or sleeping
    ; starts the user's rest; a suspended suite only pauses the energy bar.
    Suspend() {
        if this.app.suspended || this.app.systemSuspended
            this.bedtime.CancelFade()
        if this.app.sessionLocked || this.app.systemSuspended
            this.energy.Left()
    }

    Report(text) => SuiteState.Log.Write("Galaxy Rhythm", text)

    ; One row per bedtime message: Show at, its time and its words. The last
    ; row's sleep checkbox, and below it the sleep's own fields, stay grey
    ; until they can apply.
    ShowSettings(ui) {
        key := "settings:" this.id
        if ui.Existing(key)
            return
        window := ui.NewWindow(key, this.Name " - Settings", true)
        rows := SuitePageRows(window, 640)
        rows.Heading("YOUR DAY")
        rows.Text("One time for every morning: it ends bedtime's night and a night off, and starts the energy"
            . " bar over. Tonight off and Second wind are buttons in Help.")
        y := rows.y
        window.AddText("x20 y" (y + 4) " w170", "Your day starts at")
        wake := window.AddDateTime("x200 y" y " w75 +0x1 vwake", "HH:mm")
        wake.Value := "20000101" this.bedtime.wakeTime "00"
        rows.Advance(wake)
        rows.Heading("BEDTIME")
        rows.Text("Two reminders, then the sleep: each message shows on every display at its time"
            . " while you use the unlocked computer. The last one fades the screen to grey and puts"
            . " the computer to sleep, unless stay awake is on.")
        for index, row in this.bedtime.rows {
            y := rows.y
            final := index = this.bedtime.rows.Length
            show := window.AddCheckbox("x20 y" (y + 4) " w90 vshow" index, final ? "Sleep at" : "Show at")
            show.Value := row.show
            window.AddDateTime("x115 y" y " w75 +0x1 vtime" index, "HH:mm").Value := "20000101" row.time "00"
            text := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vtext" index, row.text)
            rows.Advance(text)
        }
        ; The sleep's fields, indented under its row: what stay awake says
        ; first, then the fade and the last word.
        sleepControls := []
        y := rows.y
        sleepControls.Push(window.AddText("x44 y" (y + 4) " w150", "If staying awake:"))
        awakeText := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vawakeText",
            this.bedtime.awakeText)
        sleepControls.Push(awakeText)
        rows.Advance(awakeText)
        y := rows.y
        sleepControls.Push(window.AddText("x44 y" (y + 4) " w150", "Fade to grey over"))
        fade := window.AddEdit("x200 y" y " w60 Number vfade")
        sleepControls.Push(fade, window.AddUpDown("Range1-" GR_Bedtime.FadeLimit, this.bedtime.fadeMinutes),
            window.AddText("x268 y" (y + 4) " w40", "min"))
        rows.Advance(fade)
        y := rows.y
        sleepControls.Push(window.AddText("x44 y" (y + 4) " w150", "At sleep:"))
        sleepText := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vsleepText",
            this.bedtime.sleepText)
        sleepControls.Push(sleepText)
        rows.Advance(sleepText)
        refresh(*) {
            for control in sleepControls
                control.Enabled := show.Value
        }
        refresh()
        show.OnEvent("Click", refresh)
        rows.Heading("ENERGY BAR")
        rows.Text("The energy bar is your energy for the day: it drains while you use the computer,"
            . " breaks give some back, short ones the most, and it starts over when your day starts,"
            . " with less after a late night.")
        energy := this.energy
        y := rows.y
        showEnergy := window.AddCheckbox("x20 y" (y + 4) " w240 vshowEnergy", "Show energy bar")
        showEnergy.Value := energy.show
        energyControls := [window.AddText("x330 y" (y + 4) " w120", "Full bar")]
        hours := window.AddEdit("x455 y" y " w60 Number vfullHours")
        energyControls.Push(hours, window.AddUpDown("Range4-24", energy.fullHours),
            window.AddText("x523 y" (y + 4) " w30", "h"))
        rows.Advance(hours)
        y := rows.y
        energyControls.Push(window.AddText("x44 y" (y + 4) " w150", "Position"))
        corners := []
        for corner in GR_EnergyBar.Corners
            corners.Push(corner[2])
        position := window.AddDropDownList("x200 y" y " w200 vposition", corners)
        for index, corner in GR_EnergyBar.Corners
            if corner[1] = energy.position
                position.Choose(index)
        energyControls.Push(position)
        rows.Advance(position)
        y := rows.y
        choices := ui.DisplayChoices(energy.display, true)
        this.displayChoices := choices.values
        energyControls.Push(window.AddText("x44 y" (y + 4) " w150", "Display"))
        display := window.AddDropDownList("x200 y" y " w400 vdisplay", choices.names)
        display.Choose(choices.selected)
        energyControls.Push(display)
        rows.Advance(display)
        y := rows.y
        energyControls.Push(window.AddText("x44 y" (y + 4) " w150", "Running low:"))
        lowText := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vlowText", energy.lowText)
        energyControls.Push(lowText)
        rows.Advance(lowText)
        y := rows.y
        energyControls.Push(window.AddText("x44 y" (y + 4) " w150", "At zero:"))
        roadText := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vroadText", energy.roadText)
        energyControls.Push(roadText)
        rows.Advance(roadText)
        ; The grey always leads to the faint, so they are one choice, and its
        ; fields follow it like bedtime's sleep fields.
        faint := window.AddCheckbox("x44 y" rows.y " w540 vfaintEnergy",
            "Run out: fade to grey, then faint into sleep")
        faint.Value := energy.faint
        energyControls.Push(faint)
        rows.Advance(faint)
        y := rows.y
        faintControls := [window.AddText("x68 y" (y + 4) " w130", "Fade over")]
        energyFade := window.AddEdit("x200 y" y " w60 Number venergyFade")
        faintControls.Push(energyFade, window.AddUpDown("Range10-180", energy.roadMinutes),
            window.AddText("x268 y" (y + 4) " w300", "min of activity"))
        rows.Advance(energyFade)
        y := rows.y
        faintControls.Push(window.AddText("x68 y" (y + 4) " w130", "At faint:"))
        faintText := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " vfaintText", energy.faintText)
        faintControls.Push(faintText)
        rows.Advance(faintText)
        refreshEnergy(*) {
            for control in energyControls
                control.Enabled := showEnergy.Value
            for control in faintControls
                control.Enabled := showEnergy.Value && faint.Value
        }
        refreshEnergy()
        showEnergy.OnEvent("Click", refreshEnergy)
        faint.OnEvent("Click", refreshEnergy)
        this.refreshSettings := () => (refresh(), refreshEnergy())
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui)],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id)]])
    }

    ; Bedtime and the energy bar as they start; a night off, the bar's level
    ; and a second wind are state, not settings, and stay as they are.
    RestoreSettings(window) {
        for index, defaults in GR_Bedtime.Defaults {
            window["show" index].Value := 1
            window["time" index].Value := "20000101" defaults[1] "00"
            window["text" index].Value := defaults[2]
        }
        window["wake"].Value := "20000101" GR_Bedtime.WakeDefault "00"
        window["awakeText"].Value := GR_Bedtime.AwakeDefault
        window["fade"].Value := GR_Bedtime.FadeDefault
        window["sleepText"].Value := GR_Bedtime.SleepDefault
        window["showEnergy"].Value := 1
        window["fullHours"].Value := GR_Energy.FullDefault
        for index, corner in GR_EnergyBar.Corners
            if corner[1] = "bottom-right"
                window["position"].Choose(index)
        window["display"].Choose(SuiteInterface.DisplayIndex(this.displayChoices, "Primary"))
        window["lowText"].Value := GR_Energy.Low
        window["roadText"].Value := GR_Energy.Road
        window["faintEnergy"].Value := 1
        window["energyFade"].Value := GR_Energy.FadeDefault
        window["faintText"].Value := GR_Energy.Faint
        this.refreshSettings.Call()
    }

    SaveSettings(ui, *) {
        key := "settings:" this.id
        window := ui.windows[key]
        try {
            values := Map()
            for index, defaults in GR_Bedtime.Defaults {
                values["Show" index] := window["show" index].Value ? 1 : 0
                values["Time" index] := SubStr(window["time" index].Value, 9, 4)
                values["Text" index] := GR_Bedtime.CleanText(window["text" index].Value, defaults[2])
            }
            values["FadeMinutes"] := GR_Bedtime.CleanMinutes(window["fade"].Value)
            values["WakeTime"] := SubStr(window["wake"].Value, 9, 4)
            values["SleepText"] := GR_Bedtime.CleanText(window["sleepText"].Value, GR_Bedtime.SleepDefault)
            values["AwakeText"] := GR_Bedtime.CleanText(window["awakeText"].Value, GR_Bedtime.AwakeDefault)
            energy := Map("Show", window["showEnergy"].Value ? 1 : 0,
                "FullHours", GR_Energy.Whole(window["fullHours"].Value, 4, 24, GR_Energy.FullDefault),
                "Faint", window["faintEnergy"].Value ? 1 : 0,
                "FadeMinutes", GR_Energy.Whole(window["energyFade"].Value, 10, 180, GR_Energy.FadeDefault),
                "LowText", GR_Bedtime.CleanText(window["lowText"].Value, GR_Energy.Low),
                "RoadText", GR_Bedtime.CleanText(window["roadText"].Value, GR_Energy.Road),
                "FaintText", GR_Bedtime.CleanText(window["faintText"].Value, GR_Energy.Faint),
                "Position", GR_EnergyBar.Corners[window["position"].Value][1],
                "Display", this.displayChoices[window["display"].Value])
            this.app.Settings.WritePreferences(this.id, Map("Bedtime", values, "Energy", energy))
            this.bedtime.Load()
            this.energy.LoadSettings()
            ui.Applied(key)
        }
        catch Error as failure
            ui.Report(failure, "Galaxy Rhythm / settings")
    }

    HelpText() => "
    (
        WHY I MADE THIS
        My sleep rhythm has always been a mess, and the more projects I have going, the worse it gets.
        I wanted some structure without being nagged: a few gentle nudges at night, like the cozy nights of a farming game, and a computer that knows when to call it a day.

        BEDTIME MESSAGES
        Settings can show up to three messages at times you choose: by default It's getting late at 00:00, zzz… at 01:00 and You feel sleepy at 02:00.
        Each shows on every display at its time while you use the unlocked computer; a time missed while the computer slept, was locked or had its screens off is skipped, never shown late.

        FADE TO SLEEP
        The last message starts the night: the screen fades to grey over 10 minutes, Good night shows, and the computer sleeps, even if you lock it meanwhile.
        Stay awake (Pause + End in Power-Up Utilities) keeps it up, even during the fade, and says so; if it ends before your day starts, 06:00 by default, the fade starts over.
        Until your day starts it's night: waking the computer begins the fade again, so a quick look is fine but the night stays a night.
        A wake Windows makes on its own for updates, with the screens still off, is left alone.

        ENERGY BAR
        A small upright bar marked E, bottom right on the primary display unless Settings moves it, is your energy for the day: every minute you use the computer, game controller included, costs a minute, and 8 hours of activity empty it.
        Watching or reading without touching anything costs half, though it never greys the screen or runs your day dry.
        Only your day starting fills it: when your day starts, 06:00 by default, it starts over.
        As in Stardew Valley, a late night costs you: leave the computer before the first bedtime message, 00:00 by default, and the next day starts full; stay later and it starts with less, down to half if you're still there at the sleep, 02:00, and half of that again if the bar ran dry.
        What happens after the sleep doesn't count, since the night sends you back to bed.
        During the night the bar drains quietly while you're there: it doesn't warn, grey further or faint, but running dry then still counts for tomorrow, and bedtime's fade takes over from any grey already showing.
        Breaks give some back, short ones the most: 5 minutes away gives back 15, 10 gives 25 and 30 gives 45, up to an hour, even out of the grey.
        As you come back, what the break gave back shows in purple at the top of the bar for a moment.
        A break starts when the computer sees you go, as it locks, turns its screens off, sleeps or you sign out; quiet time before that might have been reading or a film, so it doesn't count.
        So when you step away, lock the computer, turn its screens off or put it to sleep, any way you like; Win + L, and Pause + Pause and Pause + Escape in Power-Up Utilities, do it in one press.
        If your phone goes where you go, Windows' Dynamic Lock, in Sign-in options, can lock the computer within about a minute of you walking away with it.
        If you often just walk off, set the screens to turn off after a few minutes in Windows' power settings.
        Near empty it says so; at zero you're running on fumes, the screen greys over half an hour of activity by default, and then Lights out puts the computer to sleep.
        A tenth of the way along, 3 minutes by default, your day has run dry: the bar's E turns red until your day starts over, a reminder that tomorrow starts tired, even after a break or Second wind refills it.
        You wake halfway back into the grey, with time to save your work, until a break or Second wind lifts you out; the day still counts as having run dry.
        Stay awake doesn't touch the bar, and suspending Super Hotkey pauses it, though how late you're at the computer still counts.

        Turn Galaxy Rhythm on in Modules and all of this is on; every time, length and message can be changed in Settings.
        For a game night, Tonight off below silences bedtime and hides the bar until your day starts.
        The bar keeps counting out of sight, without warnings, grey or a faint, so the next morning pays for what you spend and how late you stay up, nothing more.
        It asks first, then its button turns into Back on, which ends the night off early.
        Back on asks first only if the bar is on the road before your bedtime, since the grey and Lights out come back with it; after your bedtime, the fade to sleep starts right away.
        Once a day, Second wind below gives back a quarter of a full bar, even out of the grey, and shows it in purple like a break.
        It waits until the bar is at 75 % or less, so none of it is wasted.
    )"
}

; How bedtime's sleep and the energy bar's faint both end: once no key is
; held, since a key held into sleep could stay stuck after waking, the
; computer sleeps, or in a dry run only says so.
class GR_Sleep {
    static HeldKeys := ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]

    static KeyHeld() {
        for key in GR_Sleep.HeldKeys
            if GetKeyState(key, "P")
                return true
        return false
    }

    ; False if Windows refused, which is logged and shown.
    static Now(module, what) {
        if module.dryRun {
            module.Report("dry run: " what)
            return true
        }
        try SuiteSleep.Now()
        catch Error as failure {
            SuiteState.Log.Error("Galaxy Rhythm / " what, failure)
            TrayTip(failure.Message, module.Name, 2)
            return false
        }
        return true
    }
}
