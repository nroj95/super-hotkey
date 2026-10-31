; Power-Up Utilities: extra keys, text and Terminal macros, and system actions.
; Macros run once their trigger key and modifiers are released, outside input
; callbacks, with Caps or Pause still allowed down; staying awake types nothing
; and answers each press at once.

class PowerUpUtilities extends SuiteModule {
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
        this.powerCallback := ObjBindMethod(this, "PowerEvent")
        this.keyboard := PU_Keyboard(this)
        this.terminal := PU_Terminal(this)
        this.utilities := PU_Utilities(this)
        this.stayAwake := PU_StayAwake(this)
    }

    dryRun => this.app.dryRun

    ; Registration order is the Keybindings display order.
    Register(manager) {
        this.manager := manager
        manager.AddAction("power-up-utilities.help", "show Power-Up Utilities help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Pause + H"],
            {category: "Power-Up Utilities", available: (*) => this.app.ModuleActive(this.id)})
        this.AddAction("speaker-wake", "system.wake-speakers", "wake speakers",
            "speaker-wake", "", "Pause + Pause")
        this.AddAction("sleep", "system.sleep", "put computer to sleep", "sleep", "", "Pause + Escape")
        this.AddAction("awake", "system.stay-awake", "stay awake: 30 min, 1 h, 2 h, off",
            "awake-short", "", "Pause + End")
        this.AddAction("awake", "system.stay-awake-long", "stay awake: 4 h, 8 h, until off, off",
            "awake-long", "", "Pause + Shift + End")
        ; Terminal copy shares Caps + C with F23: the Terminal scope wins there.
        this.AddAction("terminal", "terminal.copy", "copy terminal buffer as Markdown",
            "terminal-copy", "", "Caps + C", true)
        this.AddAction("terminal", "terminal.clear", "clear terminal buffer",
            "terminal-clear", "", "Caps + K", true)
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

    Start() {
        OnMessage(0x0218, this.powerCallback) ; WM_POWERBROADCAST
        try this.utilities.sleepPolicy.Recover()
        catch Error as failure {
            SuiteState.Log.Error("Power-Up Utilities / sleep recovery", failure)
            TrayTip("Could not restore the previous Away Mode settings: " failure.Message,
                this.Name, 2)
        }
    }

    ; An interrupted sleep transaction is restored at the latest on exit.
    Stop(*) {
        if this.stopping
            return
        this.stopping := true
        OnMessage(0x0218, this.powerCallback, 0)
        this.CancelWork()
        this.stayAwake.End()
        if !this.dryRun
            this.utilities.sleepPolicy.Restore()
    }

    ; Suspending Super Hotkey hands everything back to Windows, staying awake
    ; included; a locked session or system sleep keeps it.
    Suspend() {
        if this.app.suspended
            this.stayAwake.End()
    }

    SetTrayStatus(text) {
        if IsObject(this.app.ui)
            this.app.ui.SetTrayStatus(this.id, text)
    }

    PowerEvent(event, *) {
        this.utilities.sleepPolicy.OnPowerEvent(event)
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
        try this.utilities.RestoreSpeakerVolume()
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
        ; Staying awake types nothing, so each press answers at once, with Pause
        ; still held for the next step.
        if InStr(action.kind, "awake-") = 1 {
            if this.dryRun {
                this.Report("dry run: " event.actionId " via " event.binding)
                return
            }
            try this.stayAwake.Step(action.kind = "awake-long" ? "long" : "short")
            catch Error as failure
                SuiteState.Log.Error("Power-Up Utilities / stay awake", failure)
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
                case "speaker-wake": this.utilities.WakeSpeakers(job)
                case "sleep": this.utilities.SleepComputer(job)
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
    ; keeps from the app; other macros wait for it to come up. Sleep also
    ; waits for the layer keys, so none can stay stuck down after waking.
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
        if kind = "sleep"
            keys.Push("CapsLock", "Pause", "CtrlBreak")
        return keys
    }

    TargetActive(hwnd, pid) {
        return hwnd && pid && DllCall("GetForegroundWindow", "ptr") = hwnd
            && WindowProcessId(hwnd) = pid
    }

    Report(text) => SuiteState.Log.Write("Power-Up Utilities", text)

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nI wanted a collection of practical shortcuts for everyday tasks that "
            . "didn't fit into the other modules."
            . "`r`n`r`nMORE KEYS WITHOUT A NEW KEYBOARD"
            . "`r`nSend F13-F24 or Numpad 0-9 using shortcuts, even if your keyboard "
            . "doesn't have those keys. The virtual numpad is especially useful on "
            . "compact keyboards without a number pad, while F13-F24 provides extra "
            . "keys for shortcuts in compatible applications. Held virtual keys are "
            . "released when you release their triggering hotkey."
            . "`r`n`r`nTEXT AND TERMINAL ACTIONS"
            . "`r`nInsert punctuation, special spaces or a yyyyMMdd-HHmmss timestamp. "
            . "Terminal copy and clear operate only in Windows Terminal and use its "
            . "default Ctrl + Shift + A, C and K shortcuts. "
            . "Characters type as you press them and repeat while held, like real keys, "
            . "so holding Pause and tapping - twice types two dashes. Text waits while "
            . "Shift, Ctrl, Alt or Win is held, and Terminal actions run once you let go."
            . "`r`n`r`nSYSTEM UTILITIES"
            . "`r`nWake speakers that automatically enter standby, or put your computer "
            . "to sleep."
            . "`r`n`r`nSTAY AWAKE"
            . "`r`nPause + End keeps the computer from sleeping for 30 minutes, 1 or 2 hours; "
            . "Pause + Shift + End for 4 or 8 hours or until you turn it off. Each press "
            . "steps to the next duration, counted from now, and after the last one sleep "
            . "is allowed again. The tray icon's tooltip shows how long. The screen still "
            . "turns off and locks as usual, and choosing Sleep or closing a laptop lid "
            . "still sleeps. Suspending or exiting Super Hotkey ends it."
    }
}
