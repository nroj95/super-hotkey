; Galaxy Rhythm: bedtime messages, the fade to sleep and the energy bar, with
; their settings page and guide; bedtime.ahk runs the night, energy.ahk the
; bar and grey-screen.ahk the grey both share. Stay awake and sleeping come
; from core (SuiteStayAwake, SuiteSleep), so Power-Up Utilities' Pause + End
; keeps the computer up here too.
class GalaxyRhythmModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Bedtime", "Energy"]

    __New(app) {
        super.__New(app, "galaxy-rhythm")
        this.stopping := false
        this.grey := GR_GreyScreen(app.dryRun)
        folder := app.Settings.directory "\" this.id
        this.bedtime := GR_Bedtime(this, folder "\settings.ini")
        this.energy := GR_Energy(this, folder "\settings.ini", folder "\energy.ini")
    }

    dryRun => this.app.dryRun

    ; Help starts unassigned; the guide is also in the tray menu.
    Register(manager) {
        manager.AddAction("galaxy-rhythm.help", "show Galaxy Rhythm help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), [],
            {category: "Galaxy Rhythm", available: (*) => this.app.ModuleActive(this.id)})
    }

    Start() {
        this.bedtime.Start()
        this.energy.Start()
    }

    Stop(*) {
        this.stopping := true
        this.bedtime.Stop()
        this.energy.Stop()
        this.grey.Clear()
    }

    ; Suspending Super Hotkey or the computer sleeping ends a bedtime night:
    ; the user asked for quiet, or the computer has slept. Locking or sleeping
    ; starts the user's rest; a suspended suite only pauses the energy bar.
    Suspend() {
        if this.app.suspended || this.app.systemSuspended
            this.bedtime.EndNight()
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
        rows.Text("Bedtime messages show on every display at their time while you use the unlocked"
            . " computer. The last one can then fade the screen to grey and put the computer to sleep,"
            . " unless stay awake is on.")
        for index, row in this.bedtime.rows {
            y := rows.y
            show := window.AddCheckbox("x20 y" (y + 4) " w90 vshow" index, "Show at")
            show.Value := row.show
            window.AddDateTime("x115 y" y " w75 +0x1 vtime" index, "HH:mm").Value := "20000101" row.time "00"
            final := index = this.bedtime.rows.Length
            text := window.AddEdit("x200 y" y " w" (final ? 260 : 400) " Limit" GR_Bedtime.TextLimit
                . " vtext" index, row.text)
            rows.Advance(text)
        }
        sleepBox := window.AddCheckbox("x475 y" (y + 4) " w140 vsleep", "then sleep")
        sleepBox.Value := this.bedtime.sleeps
        ; The sleep's fields, indented under the row they belong to.
        sleepControls := []
        y := rows.y
        sleepControls.Push(window.AddText("x44 y" (y + 4) " w150", "Fade to grey over"))
        fade := window.AddEdit("x200 y" y " w60 Number vfade")
        sleepControls.Push(fade, window.AddUpDown("Range1-" GR_Bedtime.FadeLimit, this.bedtime.fadeMinutes),
            window.AddText("x268 y" (y + 4) " w40", "min"),
            window.AddText("x330 y" (y + 4) " w120", "Wake-up time"))
        wake := window.AddDateTime("x455 y" y " w75 +0x1 vwake", "HH:mm")
        wake.Value := "20000101" this.bedtime.wakeTime "00"
        sleepControls.Push(wake)
        rows.Advance(fade)
        for field in [["At sleep:", "sleepText", this.bedtime.sleepText],
            ["If staying awake:", "awakeText", this.bedtime.awakeText]] {
            y := rows.y
            sleepControls.Push(window.AddText("x44 y" (y + 4) " w150", field[1]))
            box := window.AddEdit("x200 y" y " w400 Limit" GR_Bedtime.TextLimit " v" field[2], field[3])
            sleepControls.Push(box)
            rows.Advance(box)
        }
        refresh(*) {
            sleepBox.Enabled := show.Value
            for control in sleepControls
                control.Enabled := show.Value && sleepBox.Value
        }
        refresh()
        show.OnEvent("Click", refresh)
        sleepBox.OnEvent("Click", refresh)
        rows.Text("The energy bar drains while you use the computer and refills while you rest away"
            . " from it: locked, with the screens off, asleep or off. A full night fills it.")
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
        energyControls.Push(window.AddText("x44 y" (y + 4) " w150", "Breaks count from"))
        breaks := window.AddEdit("x200 y" y " w60 Number vbreakMinutes")
        energyControls.Push(breaks, window.AddUpDown("Range1-60", energy.breakMinutes),
            window.AddText("x268 y" (y + 4) " w40", "min"),
            window.AddText("x330 y" (y + 4) " w120", "Full night"))
        night := window.AddEdit("x455 y" y " w60 Number vnightHours")
        energyControls.Push(night, window.AddUpDown("Range4-12", energy.nightHours),
            window.AddText("x523 y" (y + 4) " w30", "h"))
        rows.Advance(breaks)
        for option in [["greyEnergy", "Grey screen when running on fumes", energy.grey],
            ["faintEnergy", "Faint: sleep when the bar runs out", energy.faint]] {
            y := rows.y
            box := window.AddCheckbox("x44 y" y " w500 v" option[1], option[2])
            box.Value := option[3]
            energyControls.Push(box)
            rows.Advance(box)
        }
        refreshEnergy(*) {
            for control in energyControls
                control.Enabled := showEnergy.Value
        }
        refreshEnergy()
        showEnergy.OnEvent("Click", refreshEnergy)
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 100],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 90]])
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
            values["Sleep"] := window["sleep"].Value ? 1 : 0
            values["FadeMinutes"] := GR_Bedtime.CleanMinutes(window["fade"].Value)
            values["WakeTime"] := SubStr(window["wake"].Value, 9, 4)
            values["SleepText"] := GR_Bedtime.CleanText(window["sleepText"].Value, GR_Bedtime.SleepDefault)
            values["AwakeText"] := GR_Bedtime.CleanText(window["awakeText"].Value, GR_Bedtime.AwakeDefault)
            energy := Map("Show", window["showEnergy"].Value ? 1 : 0,
                "FullHours", GR_Energy.Whole(window["fullHours"].Value, 4, 24, 12),
                "NightHours", GR_Energy.Whole(window["nightHours"].Value, 4, 12, 8),
                "BreakMinutes", GR_Energy.Whole(window["breakMinutes"].Value, 1, 60, 10),
                "Grey", window["greyEnergy"].Value ? 1 : 0,
                "Faint", window["faintEnergy"].Value ? 1 : 0)
            this.app.Settings.WritePreferences(this.id, Map("Bedtime", values, "Energy", energy))
            this.bedtime.Load()
            this.energy.LoadSettings()
            ui.CloseWindow(key)
        }
        catch Error as failure
            ui.Report(failure, "Galaxy Rhythm / settings")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nMy sleep rhythm has always been a mess, and the more projects I have going, "
            . "the worse it gets. I wanted some structure without being nagged: a few gentle "
            . "nudges at night, like the cozy nights of a farming game, and a computer that "
            . "knows when to call it a day."
            . "`r`n`r`nBEDTIME MESSAGES"
            . "`r`nSettings can show up to three messages at times you choose: by default "
            . "It's getting late at 00:00, zzz… at 01:00 and You feel sleepy at 02:00. Each "
            . "shows on every display at its time while you use the unlocked computer; a time "
            . "missed while the computer slept or was locked is skipped, never shown late."
            . "`r`n`r`nFADE TO SLEEP"
            . "`r`nWith then sleep checked, the last message starts the night: the screen fades "
            . "to grey over 10 minutes, Good night shows, and the computer sleeps, even if you "
            . "lock it meanwhile. Stay awake (Pause + End in Power-Up Utilities) keeps it up, "
            . "even during the fade, and says so; if it ends before your wake-up time, 06:00 by "
            . "default, the fade starts over. One sleep ends the night, and so does the wake-up "
            . "time."
            . "`r`n`r`nENERGY BAR"
            . "`r`nA small bar in the bottom-left corner drains with every minute you use the "
            . "computer: 12 hours of activity empty it. It refills while you rest away from it, "
            . "locked, with the screens off, asleep or off: breaks of 10 minutes or more count, "
            . "a 30-minute walk gives back about 1.5 hours, and a full night of 8 hours fills it. "
            . "Near empty it says so; at zero you're running on fumes, the screen greys over an "
            . "hour of activity, and then Lights out puts the computer to sleep. Stay awake "
            . "holds the bar at zero instead."
            . "`r`n`r`nTurn Galaxy Rhythm on in Modules and all of this is on; every time, length "
            . "and message can be changed in Settings."
    }
}
