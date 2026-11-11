; Power-Up Utilities: extra keys, text and Terminal macros, system actions, the
; break reminder and the settings page for it and for keeping speakers awake.
; Sleep works as Start's Sleep does, and locking as Win + L does. Macros run
; once their trigger key and modifiers are released, outside input callbacks,
; with Caps or Pause still allowed down; staying awake, the break reminder and
; keeping speakers awake type nothing and answer each press at once.

class PowerUpUtilities extends SuiteModule {
    hasSettings := true
    resetSections := ["Breaks", "Speakers"]

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
        this.speakers := PU_Speakers(this, this.settingsPath)
        this.breaks := PU_Breaks(this, this.settingsPath)
    }

    dryRun => this.app.dryRun

    ; Registration order is the Keybindings display order.
    Register(manager) {
        this.manager := manager
        manager.AddAction("power-up-utilities.help", "Power-Up Utilities help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Pause + H"],
            {category: "Power-Up Utilities", available: (*) => this.app.ModuleActive(this.id)})
        this.AddAction("awake", "system.stay-awake", "stay awake, then sleep",
            "awake-step", "", "Pause + End")
        this.AddAction("awake", "system.allow-sleep", "cancel stay awake",
            "awake-end", "", "Pause + Shift + End")
        this.AddAction("breaks", "system.break-reminder", "toggle break reminder",
            "breaks", "", "Pause + B")
        ; Terminal copy shares Caps + C with F23: the Terminal scope wins there.
        this.AddAction("terminal", "terminal.copy", "copy terminal buffer as Markdown",
            "terminal-copy", "", "Caps + C", true)
        this.AddAction("terminal", "terminal.clear", "clear terminal buffer",
            "terminal-clear", "", "Caps + K", true)
        ; Few speakers need it, so it has no default hotkey.
        this.AddAction("speakers", "system.keep-speakers-awake", "toggle keep speakers awake",
            "speakers", "", "")
        ; Sleeping and locking end the main list.
        this.AddAction("sleep", "system.sleep", "put computer to sleep", "sleep", "", "Pause + Escape")
        ; Win + L does the same everywhere, so it has no default hotkey.
        this.AddAction("lock", "system.lock", "lock computer", "lock", "", "")
        ; The few text actions come before the long runs of virtual keys.
        this.AddAction("text", "text.apostrophe", "insert curly apostrophe (’)", "text", "’", "Pause + '", true)
        this.AddAction("text", "text.en-dash", "insert en dash (–)", "text", "–", "Pause + -", true)
        this.AddAction("text", "text.nbsp", "insert &nbsp;", "text", "&nbsp;", "Pause + N", true)
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

    Start() {
        this.speakers.Start()
        this.breaks.Start()
    }

    ; Staying awake, the next break and keeping speakers awake, for the
    ; status notice.
    StatusLines() {
        lines := []
        if (text := this.stayAwake.StatusText()) != ""
            lines.Push(text)
        if (text := this.breaks.StatusText()) != ""
            lines.Push(text)
        if this.speakers.on
            lines.Push("Keeping speakers awake")
        return lines
    }

    Stop(*) {
        if this.stopping
            return
        this.stopping := true
        this.CancelWork()
        this.stayAwake.End()
        try this.speakers.Stop()
        this.breaks.Stop()
    }

    ; Suspending Super Hotkey hands everything back to Windows, staying awake
    ; included, without sleeping, and stops nudging the speakers; a locked
    ; session or system sleep keeps staying awake. Any of them is a break.
    Suspend() {
        this.breaks.Pause()
        if this.app.suspended {
            this.stayAwake.End()
            try this.speakers.Silence()
        }
    }

    ; Back at the desktop: wake the speakers and count to the next break.
    Resume() {
        this.speakers.Check()
        this.breaks.Back()
    }

    ShowSettings(ui) {
        key := "settings:" this.id
        if ui.Existing(key)
            return
        rows := SuitePageRows(ui.NewWindow(key, "Power-Up Utilities - Settings", true), 640)
        rows.Heading("Break reminder")
        rows.Text("Shows a message on every display while you're at the computer."
            . " Locking it or the screens turning off counts as a break and restarts the timer."
            . " Its hotkey in Keybindings turns it on or off.")
        y := rows.y
        rows.Field("Remind every", "Edit", "w60 Number vbreakMinutes")
        rows.window.AddUpDown("Range1-" PU_Breaks.MinutesLimit, this.breaks.minutes)
        rows.window.AddText("x" (SuitePageRows.FieldX + 68) " y" (y + 4) " w60", "min")
        rows.Field("Message", "Edit", "w300 vbreakMessage", this.breaks.Text)
        choice := rows.Field("At break time", "DropDownList", "w210 vbreakAction", PowerUpUtilities.BreakActionNames())
        choice.Choose(PowerUpUtilities.BreakActionIndex(this.breaks.action))
        ; Sized for the longest caption; the chosen action fills it in.
        rows.Caption(PowerUpUtilities.BreakActionCaption("screens")).Name := "breakActionCaption"
        choice.OnEvent("Change", (control, *) => PowerUpUtilities.ShowBreakActionCaption(control.Gui))
        PowerUpUtilities.ShowBreakActionCaption(rows.window)
        rows.Heading("Keep speakers awake")
        rows.Text("Nudges speakers that fall asleep in silence while you're at the computer."
            . " Give it a hotkey in Keybindings to turn it on or off.")
        y := rows.y
        rows.Field("Nudge every", "Edit", "w60 Number vminutes")
        rows.window.AddUpDown("Range1-" PU_Speakers.MinutesLimit, this.speakers.minutes)
        rows.window.AddText("x" (SuitePageRows.FieldX + 68) " y" (y + 4) " w60", "min")
        rows.Caption("8 suits most speakers; choose fewer if yours fall asleep sooner.")
        rows.Checkbox("Play a soft chime instead of the silent tone", "vchime").Value := this.speakers.chime
        rows.Caption("For speakers that the silent tone doesn't keep awake.", true)
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui)],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id)]])
    }

    ; The break action choices, in PU_Breaks.Actions order.
    static BreakActionNames() => ["Only show the message", "Turn off the screens", "Lock the computer"]

    ; What the chosen action does, under the list.
    static BreakActionCaption(action) {
        switch action {
            case "screens": return "The screens turn off 10 seconds after the message, unless an app is in fullscreen."
            case "lock": return "The computer locks 10 seconds after the message, unless an app is in fullscreen."
            default: return "The message shows on every display for 3 seconds, and nothing else happens."
        }
    }

    static ShowBreakActionCaption(window) {
        window["breakActionCaption"].Text := PowerUpUtilities.BreakActionCaption(
            PU_Breaks.Actions[Max(1, window["breakAction"].Value)])
    }

    static BreakActionIndex(action) {
        for index, name in PU_Breaks.Actions
            if name = action
                return index
        return 1
    }

    RestoreSettings(window) {
        window["breakMinutes"].Value := PU_Breaks.MinutesDefault
        window["breakMessage"].Value := PU_Breaks.MessageDefault
        window["breakAction"].Choose(1)
        PowerUpUtilities.ShowBreakActionCaption(window)
        window["minutes"].Value := PU_Speakers.MinutesDefault
        window["chime"].Value := 0
    }

    SaveSettings(ui, *) {
        key := "settings:" this.id
        window := ui.windows[key]
        try {
            breakMinutes := PU_Breaks.CleanMinutes(window["breakMinutes"].Value)
            ; The default message is saved as empty, so it follows the default.
            message := Trim(StrReplace(StrReplace(window["breakMessage"].Value, "`r"), "`n", " "))
            if message = PU_Breaks.MessageDefault
                message := ""
            action := PU_Breaks.Actions[Max(1, window["breakAction"].Value)]
            minutes := PU_Speakers.CleanMinutes(window["minutes"].Value)
            chime := window["chime"].Value != 0
            this.app.Settings.WritePreferences(this.id,
                Map("Breaks", Map("Minutes", breakMinutes, "Message", message, "Action", action),
                    "Speakers", Map("Minutes", minutes, "Chime", chime ? 1 : 0)))
            this.breaks.Apply(breakMinutes, message, action)
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
        ; Staying awake, the break reminder and keeping speakers awake type
        ; nothing, so each press answers at once, with Pause still held for
        ; the next step.
        if InStr(action.kind, "awake-") = 1 || action.kind = "speakers" || action.kind = "breaks" {
            if this.dryRun {
                this.Report("dry run: " event.actionId " via " event.binding)
                return
            }
            try {
                if action.kind = "speakers"
                    this.speakers.Toggle()
                else if action.kind = "breaks"
                    this.breaks.Toggle()
                else if action.kind = "awake-end"
                    this.stayAwake.AllowSleep()
                else
                    this.stayAwake.Step()
            }
            catch Error as failure
                SuiteState.Log.Error("Power-Up Utilities / " (InStr(action.kind, "awake-") = 1
                    ? "stay awake" : action.kind), failure)
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
                case "lock": this.utilities.LockComputer(job)
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
    ; keeps from the app; other macros wait for it to come up. Sleeping and
    ; locking also wait for the layer keys, so none can stay stuck down after
    ; waking or unlocking.
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
        if kind = "sleep" || kind = "lock"
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
        WHY
        Practical shortcuts for everyday tasks that don't fit into the other modules.

        STAY AWAKE
        Pause + End keeps the computer awake for 30 minutes, then puts it to sleep once you're no longer using it.
        Press again while its notice shows for 1, 2, 4 or 8 hours or no limit.
        Pause + Shift + End cancels it.
        Pause + Pause shows how long is left.

        For more reliable sleep, turn off Windows' Away Mode and let only your keyboard wake the computer.

        BREAKS
        Pause + B reminds you to take a break every 45 minutes, on every display.
        Locking the computer or letting the screens go dark counts as a break, so the timer restarts when you're back.
        Settings can also turn off the screens or lock the computer 10 seconds after the message.

        MORE KEYS WITHOUT A NEW KEYBOARD
        Caps + QWER/ASDF/ZXCV sends F13–F24; Caps + 0–9 provides a virtual number pad, even if your keyboard lacks those keys.

        HANDY EXTRAS
        Insert symbols such as ’, – or ß, the HTML entity &nbsp; or a timestamp such as 20261110-203729.
        Terminal copy and clear operate only in Windows Terminal and use its default Ctrl + Shift + A, C and K shortcuts.
    )"
}
