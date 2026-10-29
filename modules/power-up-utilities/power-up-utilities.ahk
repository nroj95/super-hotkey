; Power-Up Utilities: extra keys, text and Terminal macros, and system actions.
; Macros run after their trigger keys are released, outside input callbacks.

class PowerUpUtilities extends SuiteModule {
    __New(app) {
        super.__New(app, "power-up-utilities")
        this.manager := 0
        this.stopping := false
        this.pending := Map()
        this.generation := 0
        this.activeJob := 0
        this.catalog := Map()
        this.pollCallback := ObjBindMethod(this, "CheckPending")
        this.powerCallback := ObjBindMethod(this, "PowerEvent")
        this.keyboard := PU_Keyboard(this)
        this.terminal := PU_Terminal(this)
        this.utilities := PU_Utilities(this)
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
        if !this.dryRun
            this.utilities.sleepPolicy.Restore()
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
        token := event.actionId "|" event.slot
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
        if event.phase != "down" || !this.CanDispatch(event.actionId)
            return
        if this.pending.Count >= 16
            return
        targetPid := 0
        if action.needsFocus {
            targetPid := WindowProcessId(event.foregroundHwnd)
            if !targetPid || !this.TargetActive(event.foregroundHwnd, targetPid)
                return
        }
        this.pending[token] := {action: action, event: event.Clone(), pid: targetPid,
            generation: this.generation, created: A_TickCount, completed: false, worker: 0}
        SetTimer(this.pollCallback, 15)
    }

    CheckPending(*) {
        if this.stopping {
            SetTimer(this.pollCallback, 0)
            return
        }
        for token, job in this.pending.Clone() {
            if !this.JobValid(job) || ((A_TickCount - job.created) & 0xFFFFFFFF) > 5000 {
                this.pending.Delete(token)
                continue
            }
            if IsObject(this.activeJob) || !job.completed || !this.InputsReleased(job.event)
                continue
            this.pending.Delete(token)
            this.activeJob := job
            job.worker := ObjBindMethod(this, "RunJob", job)
            ; Slow macros do not run inside Keybindings' serialized event callback.
            SetTimer(job.worker, -1)
            break
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

    InputsReleased(event) {
        if !InStr(event.key, "Wheel") && GetKeyState(event.key, "P")
            return false
        ; Include both layer keys even for ordinary bindings: they may have been
        ; pressed after this command was queued. Never emit into a held layer.
        for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]
            if GetKeyState(key, "P")
                return false
        return true
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
            . "Terminal copy and clear operate only in Windows Terminal. "
            . "Required Terminal shortcuts are checked before keys are sent; "
            . "incompatible settings are reported without being changed. "
            . "Text commands wait for your triggering keys to be released before typing."
            . "`r`n`r`nSYSTEM UTILITIES"
            . "`r`nWake speakers that automatically enter standby, or put your computer "
            . "to sleep."
    }
}
