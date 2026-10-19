; Existing command dispatch and safety checks, using the suite-owned manager.

class PowerUpUtilities {
    static Version := "suite-preview.1"

    __New(manager, dryRun := false) {
        this.manager := manager
        this.dryRun := dryRun
        this.name := "Power-Up Utilities"
        this.stopping := false
        this.systemSuspended := false
        this.pending := Map()
        this.generation := 0
        this.activeJob := 0
        this.enabledActions := Map()
        this.catalog := Map()
        this.modules := PH_Modules.Catalog()
        this.pollCallback := ObjBindMethod(this, "CheckPending")
        this.keyboard := PH_Keyboard(this)
        this.terminal := PH_Terminal(this)
        this.utilities := PH_Utilities(this)
        PH_Modules.RegisterActions(this)
    }

    AddAction(moduleId, actionId, label, kind, value, defaultBinding, needsFocus := false) {
        static subcategories := Map("terminal", "Windows Terminal",
            "function-keys", "Extra function keys",
            "number-pad", "Virtual number pad", "text", "Text and symbols",
            "timestamp", "Text and symbols")
        category := subcategories.Has(moduleId)
            ? "Power-Up Utilities / " subcategories[moduleId] : "Power-Up Utilities"
        actionId := "power-up-utilities." actionId
        this.catalog[actionId] := {id: actionId, moduleId: moduleId, kind: kind,
            value: value, needsFocus: needsFocus}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Dispatch"),
            [defaultBinding], {category: category, help: moduleId = "interface",
                scope: moduleId = "terminal" ? "windows-terminal" : "",
                available: (*) => SuiteState.App.ModuleActive("power-up-utilities")})
    }

    Start(*) {
        this.SyncEnabledActions()
        if !this.dryRun {
            try this.utilities.sleepPolicy.Recover()
            catch Error as failure {
                SuiteState.Log.Error("Power-Up Utilities / sleep recovery", failure)
                TrayTip("Could not restore the previous Away Mode settings: " failure.Message,
                    this.name, 2)
            }
        }
    }

    Stop(*) {
        if this.stopping
            return
        this.stopping := true
        this.CancelWork()
        if !this.dryRun
            this.utilities.sleepPolicy.Restore()
    }

    SyncEnabledActions() {
        this.enabledActions := Map()
        for actionId, setting in this.manager.GetConfiguration()
            this.enabledActions[actionId] := setting.enabled
    }

    Enabled(actionId) {
        return SuiteState.App.ModuleActive("power-up-utilities")
            && this.enabledActions.Has(actionId) && this.enabledActions[actionId]
    }

    CanDispatch(actionId) {
        return !this.stopping && !this.systemSuspended && this.Enabled(actionId)
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
            ; Layer events remain authoritative when another process consumed
            ; the physical key before our local keyboard hook could observe it.
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
            targetPid := this.WindowPid(event.foregroundHwnd)
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
        if job.event.layer != "normal" {
            client := this.manager.client
            if !IsObject(client) || !client.session || !client.ServiceMatches()
                return false
        }
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
                case "interface": SuiteState.App.ui.ToggleHelp("power-up-utilities")
                default: throw Error("Unknown action kind: " job.action.kind)
            }
        }
        catch Error as commandError {
            SuiteState.Log.Error("Power-Up Utilities", commandError)
            this.Report(job.action.id ": " commandError.Message)
            TrayTip(commandError.Message, this.name, 2)
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

    WindowPid(hwnd) {
        processId := 0
        if hwnd
            DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &processId, "uint")
        return processId
    }

    TargetActive(hwnd, pid) {
        return hwnd && pid && DllCall("GetForegroundWindow", "ptr") = hwnd
            && this.WindowPid(hwnd) = pid
    }

















    Report(text) => SuiteState.Log.Write("Power-Up Utilities", text)


}
