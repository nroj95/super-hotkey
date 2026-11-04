; Power-Up Utilities: extra keys, text and Terminal macros, system actions and
; the settings page for real sleep and keeping speakers awake. Real sleep,
; on by default, keeps Away Mode from replacing the sleep hotkey's sleep;
; unticked, it sleeps as Start's Sleep does. Macros run once their trigger
; key and modifiers are released, outside input callbacks, with Caps or Pause
; still allowed down; staying awake and keeping speakers awake type nothing
; and answer each press at once.

class PowerUpUtilities extends SuiteModule {
    hasSettings := true
    resetSections := ["Sleep", "Speakers"]

    __New(app) {
        super.__New(app, "power-up-utilities")
        this.manager := 0
        this.stopping := false
        this.pending := Map()
        this.pressTokens := Map()  ; action|slot -> its latest text press
        this.sequence := 0
        this.generation := 0
        this.activeJob := 0
        this.catalog := Map()
        this.pollCallback := ObjBindMethod(this, "CheckPending")
        this.keyboard := PU_Keyboard(this)
        this.terminal := PU_Terminal(this)
        this.utilities := PU_Utilities(this)
        this.stayAwake := PU_StayAwake(this)
        this.settingsPath := app.Settings.directory "\" this.id "\settings.ini"
        this.realSleep := IniRead(this.settingsPath, "Sleep", "Real", 1) != "0"
        this.speakers := PU_Speakers(this, this.settingsPath)
    }

    dryRun => this.app.dryRun

    ; Registration order is the Keybindings display order.
    Register(manager) {
        this.manager := manager
        manager.AddAction("power-up-utilities.help", "show Power-Up Utilities help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Pause + H"],
            {category: "Power-Up Utilities", available: (*) => this.app.ModuleActive(this.id)})
        this.AddAction("sleep", "system.sleep", "put computer to sleep", "sleep", "", "Pause + Escape")
        this.AddAction("displays", "system.displays-off", "turn off the displays", "displays-off", "", "Pause + Pause")
        this.AddAction("awake", "system.stay-awake", "stay awake: 30 min, 1, 2, 4, 8 h, no limit",
            "awake-step", "", "Pause + End")
        this.AddAction("awake", "system.allow-sleep", "allow sleep again",
            "awake-end", "", "Pause + Shift + End")
        ; Terminal copy shares Caps + C with F23: the Terminal scope wins there.
        this.AddAction("terminal", "terminal.copy", "copy terminal buffer as Markdown",
            "terminal-copy", "", "Caps + C", true)
        this.AddAction("terminal", "terminal.clear", "clear terminal buffer",
            "terminal-clear", "", "Caps + K", true)
        ; Few speakers need it, so it comes last, without a default hotkey.
        this.AddAction("speakers", "system.keep-speakers-awake", "keep speakers awake: on / off",
            "speakers", "", "")
        ; The few text actions come before the long runs of virtual keys.
        this.AddAction("text", "text.apostrophe", "insert curly apostrophe (’)", "text", "’", "Pause + '", true)
        this.AddAction("text", "text.en-dash", "insert en dash (–)", "text", "–", "Pause + -", true)
        this.AddAction("text", "text.nbsp", "insert HTML entity (&nbsp;)", "text", "&nbsp;", "Pause + N", true)
        this.AddAction("text", "text.sharp-s", "insert sharp s (ß)", "text", "ß", "Pause + S", true)
        this.AddAction("text", "text.timestamp", "insert timestamp", "timestamp", "", "Pause + T", true)
        for index, key in ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"] {
            output := "F" (12 + index)
            this.AddAction("function-keys", "keyboard." StrLower(output), "send " output,
                "virtual", output, "Caps + " key)
        }
        loop 10 {
            digit := A_Index - 1
            this.AddAction("number-pad", "keyboard.numpad" digit, "send Numpad" digit,
                "virtual", "Numpad" digit, "Caps + " digit)
        }
    }

    AddAction(group, actionId, label, kind, value, defaultBinding, needsFocus := false) {
        static subcategories := Map("function-keys", "Extra function keys",
            "number-pad", "Virtual number pad", "text", "Text and symbols")
        category := subcategories.Has(group)
            ? "Power-Up Utilities / " subcategories[group] : "Power-Up Utilities"
        actionId := "power-up-utilities." actionId
        this.catalog[actionId] := {id: actionId, kind: kind, value: value, needsFocus: needsFocus}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Dispatch"),
            [defaultBinding], {category: category,
                scope: group = "terminal" ? "windows-terminal" : "",
                ; A held character repeats like a real key.
                repeat: kind = "text",
                available: (*) => this.app.ModuleActive(this.id)})
    }

    Start() => this.speakers.Start()

    ; Core restores an interrupted sleep transaction.
    Stop(*) {
        if this.stopping
            return
        this.stopping := true
        this.CancelWork()
        this.stayAwake.End()
        try this.speakers.Stop()
    }

    ; Suspending Super Hotkey hands everything back to Windows, staying awake
    ; included, and stops nudging the speakers; a locked session or system
    ; sleep keeps staying awake.
    Suspend() {
        if this.app.suspended {
            this.stayAwake.End()
            try this.speakers.Silence()
        }
    }

    ; Back at the desktop: show a stay awake that ran out while away, and
    ; wake the speakers.
    Resume() {
        this.stayAwake.Returned()
        this.speakers.Check()
    }

    ShowSettings(ui) {
        key := "settings:" this.id
        if ui.Existing(key)
            return
        rows := SuitePageRows(ui.NewWindow(key, "Power-Up Utilities - Settings", true), 640)
        rows.Heading("Sleep")
        rows.Checkbox("Sleep for real, even where Away Mode is allowed", "vrealSleep").Value := this.realSleep
        rows.Caption("Some computers let Away Mode replace sleep, keeping them running with their screens dark."
            . " Unticked, Pause + Escape sleeps as Start's Sleep does.", true)
        rows.Heading("Keep speakers awake")
        rows.Text("Keep speakers awake, an action you can give a hotkey in Keybindings, nudges speakers"
            . " that fall asleep in silence while you're at the computer.")
        y := rows.y
        rows.Field("Nudge every", "Edit", "w60 Number vminutes")
        rows.window.AddUpDown("Range1-" PU_Speakers.MinutesLimit, this.speakers.minutes)
        rows.window.AddText("x" (SuitePageRows.FieldX + 68) " y" (y + 4) " w60", "min")
        rows.Caption("8 suits most speakers; choose fewer if yours fall asleep sooner.")
        rows.Checkbox("Play a soft chime instead of the silent tone", "vchime").Value := this.speakers.chime
        rows.Caption("For speakers that the silent tone doesn't keep awake.", true)
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 100],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 90]])
    }

    RestoreSettings(window) {
        window["realSleep"].Value := 1
        window["minutes"].Value := PU_Speakers.MinutesDefault
        window["chime"].Value := 0
    }

    SaveSettings(ui, *) {
        key := "settings:" this.id
        window := ui.windows[key]
        try {
            minutes := PU_Speakers.CleanMinutes(window["minutes"].Value)
            chime := window["chime"].Value != 0
            realSleep := window["realSleep"].Value != 0
            this.app.Settings.WritePreferences(this.id, Map("Sleep", Map("Real", realSleep ? 1 : 0),
                "Speakers", Map("Minutes", minutes, "Chime", chime ? 1 : 0)))
            this.realSleep := realSleep
            this.speakers.minutes := minutes
            this.speakers.chime := chime
            ui.Applied(key)
        }
        catch Error as failure
            ui.Report(failure, "Power-Up Utilities / settings")
    }

    SetTrayStatus(text) {
        if IsObject(this.app.ui)
            this.app.ui.SetTrayStatus(this.id, text)
    }

    Enabled(actionId) {
        configuration := this.manager.configuration
        return this.app.ModuleActive(this.id)
            && configuration.Has(actionId) && configuration[actionId].enabled
    }

    CanDispatch(actionId) {
        return !this.stopping && this.Enabled(actionId)
            && this.manager.running && !this.manager.gated && !this.manager.paused
            && !this.manager.applying
    }

    CancelWork() {
        this.generation += 1
        this.pending.Clear()
        this.pressTokens.Clear()
        SetTimer(this.pollCallback, 0)
        this.keyboard.ReleaseAll()
        try this.terminal.RestoreClipboard()
    }

    Dispatch(event) {
        if !this.catalog.Has(event.actionId)
            return
        action := this.catalog[event.actionId]
        if action.kind = "virtual" {
            ; up/cancel must still be handled after a module was disabled.
            this.keyboard.Event(action.value, event)
            return
        }
        press := event.actionId "|" event.slot
        token := this.pressTokens.Get(press, press)
        if event.phase = "cancel" {
            if this.pending.Has(token)
                this.pending.Delete(token)
            if !this.pending.Count
                SetTimer(this.pollCallback, 0)
            return
        }
        if event.phase = "up" {
            if this.pending.Has(token)
                this.pending[token].completed := true
            return
        }
        typing := action.kind = "text" || action.kind = "timestamp"
        if !(event.phase = "down" || event.phase = "repeat" && typing) || !this.CanDispatch(event.actionId)
            return
        ; Staying awake and keeping speakers awake type nothing, so each press
        ; answers at once, with Pause still held for the next step.
        if InStr(action.kind, "awake-") = 1 || action.kind = "speakers" {
            if this.dryRun {
                this.Report("dry run: " event.actionId " via " event.binding)
                return
            }
            try {
                if action.kind = "speakers"
                    this.speakers.Toggle()
                else if action.kind = "awake-end"
                    this.stayAwake.AllowSleep()
                else
                    this.stayAwake.Step()
            }
            catch Error as failure
                SuiteState.Log.Error("Power-Up Utilities / " (action.kind = "speakers" ? "speakers" : "stay awake"), failure)
            return
        }
        if this.pending.Count >= 16
            return
        targetPid := 0
        if action.needsFocus {
            targetPid := WindowProcessId(event.foregroundHwnd)
            if !targetPid || !this.TargetActive(event.foregroundHwnd, targetPid)
                return
        }
        ; Text types on the press, like a real key, and every press and repeat is
        ; kept and typed in order: Pause held with - - types two dashes. Other
        ; macros wait for their key to come up and keep one press, so a double
        ; sleep never sleeps twice.
        this.sequence += 1
        if typing {
            token := press "|" this.sequence
            this.pressTokens[press] := token
        }
        this.pending[token] := {action: action, event: event.Clone(), pid: targetPid,
            generation: this.generation, created: A_TickCount, completed: typing, worker: 0,
            sequence: this.sequence}
        SetTimer(this.pollCallback, 15)
    }

    CheckPending(*) {
        if this.stopping {
            SetTimer(this.pollCallback, 0)
            return
        }
        ; Run the earliest ready press, one at a time, in the order pressed.
        next := ""
        for token, job in this.pending.Clone() {
            if !this.JobValid(job) || ((A_TickCount - job.created) & 0xFFFFFFFF) > 5000 {
                this.pending.Delete(token)
                continue
            }
            if IsObject(this.activeJob) || !job.completed || !this.InputsReleased(job.event)
                continue
            if next = "" || job.sequence < this.pending[next].sequence
                next := token
        }
        if next != "" {
            job := this.pending[next]
            this.pending.Delete(next)
            this.activeJob := job
            job.worker := ObjBindMethod(this, "RunJob", job)
            ; Slow macros do not run inside Keybindings' serialized event callback.
            SetTimer(job.worker, -1)
        }
        if !this.pending.Count
            SetTimer(this.pollCallback, 0)
    }

    JobValid(job) {
        if job.generation != this.generation || !this.CanDispatch(job.action.id)
            return false
        if job.action.needsFocus && !this.TargetActive(job.event.foregroundHwnd, job.pid)
            return false
        return true
    }

    RunJob(job) {
        try {
            if !this.JobValid(job) || !this.InputsReleased(job.event)
                return
            if InStr(job.action.kind, "terminal-") = 1 && !this.terminal.Ready(job)
                return
            if this.dryRun {
                this.Report("dry run: " job.action.id " via " job.event.binding)
                return
            }
            switch job.action.kind {
                case "text": SendText(job.action.value)
                case "timestamp": SendText(FormatTime(, "yyyyMMdd-HHmmss"))
                case "terminal-copy": this.terminal.Copy(job)
                case "terminal-clear": this.terminal.Clear(job)
                case "sleep": this.utilities.SleepComputer(job)
                case "displays-off": this.utilities.DisplaysOff(job)
                default: throw Error("Unknown action kind: " job.action.kind)
            }
        }
        catch Error as commandError {
            SuiteState.Log.Error("Power-Up Utilities", commandError)
            TrayTip(commandError.Message, this.Name, 2)
        }
        finally {
            if this.activeJob = job
                this.activeJob := 0
            if this.pending.Count && !this.stopping
                SetTimer(this.pollCallback, 15)
        }
    }

    ; Macros wait for every modifier, which would turn typed characters into
    ; shortcuts. A held Caps or Pause never holds them back, so a layer types
    ; like a real key. Text types while its own key is down, which the hotkey
    ; keeps from the app; other macros wait for it to come up. Sleep and
    ; turning the displays off also wait for the layer keys, so none can stay
    ; stuck down after waking, nor wake the displays by coming up.
    InputsReleased(event) {
        kind := this.catalog.Has(event.actionId) ? this.catalog[event.actionId].kind : ""
        if kind != "text" && kind != "timestamp" && !InStr(event.key, "Wheel")
            && GetKeyState(event.key, "P")
            return false
        for key in PowerUpUtilities.BlockingKeys(kind)
            if GetKeyState(key, "P")
                return false
        return true
    }

    static BlockingKeys(kind) {
        keys := ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
        if kind = "sleep" || kind = "displays-off"
            keys.Push("CapsLock", "Pause", "CtrlBreak")
        return keys
    }

    TargetActive(hwnd, pid) {
        return hwnd && pid && DllCall("GetForegroundWindow", "ptr") = hwnd
            && WindowProcessId(hwnd) = pid
    }

    Report(text) => SuiteState.Log.Write("Power-Up Utilities", text)

    HelpText() => "
    (
        WHY I MADE THIS
        I wanted a collection of practical shortcuts for everyday tasks that didn't fit into the other modules.

        MORE KEYS WITHOUT A NEW KEYBOARD
        Send F13-F24 or Numpad 0-9 using shortcuts, even if your keyboard doesn't have those keys.
        The virtual numpad is especially useful on compact keyboards without a number pad, while F13-F24 provides extra keys for shortcuts in compatible applications.
        Held virtual keys are released when you release their triggering hotkey.

        TEXT AND TERMINAL ACTIONS
        Insert punctuation, special spaces or a yyyyMMdd-HHmmss timestamp.
        Terminal copy and clear operate only in Windows Terminal and use its default Ctrl + Shift + A, C and K shortcuts.
        Characters type as you press them and repeat while held, like real keys, so holding Pause and tapping - twice types two dashes.
        Text waits while Shift, Ctrl, Alt or Win is held, and Terminal actions run once you let go.

        SYSTEM UTILITIES
        Pause + Escape puts your computer to sleep once you let go of every key, so none stays stuck after waking.
        It sleeps for real even where Away Mode is allowed to replace sleep; Settings can leave that to Windows.
        Pause + Pause turns the displays off, as Windows' screen timeout does, for a break or to save power, and any touch wakes them; off is also the kindest to an OLED screen.

        STAY AWAKE
        Pause + End keeps the computer from sleeping for 30 minutes.
        Press again while its notice shows for 1, 2, 4 or 8 hours or no limit, counted from now; once the notice has gone, the next press starts over at 30 minutes.
        Pause + Shift + End allows sleep again.
        The tray icon's tooltip shows how long.
        The screen still turns off and locks as usual, and choosing Sleep or closing a laptop lid still sleeps.
        So when you leave work running, lock with Win + L or turn the screens off with Pause + Pause: it keeps running, and Galaxy Rhythm's energy bar counts the time as a break.
        Suspending or exiting Super Hotkey ends it.

        KEEP SPEAKERS AWAKE
        Some speakers fall asleep after minutes of silence and wake a few seconds late, so notifications and the starts of videos go missing.
        Keep speakers awake, an action you can give a hotkey in Keybindings, switches on a nudge every 8 minutes while you're at the computer, and stays on until you switch it off.
        It also nudges them as you come back, so they're awake before anything plays.
        The nudge is a 25 Hz tone too low for most speakers to play, sized to reach them at any Windows volume; muted, nothing plays.
        Settings can nudge more often for speakers that fall asleep sooner, or play a soft chime for speakers the tone doesn't keep awake.
    )"
}
