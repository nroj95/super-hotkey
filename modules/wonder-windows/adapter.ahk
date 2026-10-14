; Wonder Windows reuses the original layout algorithms with suite-owned inputs and lifecycle.
class WonderWindowsModule {
    __New(manager, dryRun := false) {
        this.manager := manager
        this.dryRun := dryRun
        this.stopping := false
        this.generation := 0
        this.pending := Map()
        this.catalog := Map()
        this.drainCallback := ObjBindMethod(this, "Drain")
        this.pollCallback := ObjBindMethod(this, "PollCompatibility")
        this.optionalAvailability := "0000"
        this.Add("maximize", "maximize / toggle borderless fullscreen", WW_MaximizeWindowTarget, ["Win + Up"])
        this.Add("restore", "restore the normal window rectangle", WW_RestoreWindowTarget, ["Win + Down"])
        for side in ["left", "right"] {
            this.Add("layout-" side, "cycle " side " layouts", WW_CycleWindowSnap, ["Win + " side], [side])
            this.Add("stretch-" side, "toggle " side " edge stretch", WW_ToggleHorizontalStretch,
                ["Win + Shift + " side], [side])
        }
        this.Add("stretch-height", "stretch to full height", WW_StretchWindowVertically, ["Win + Shift + Up"])
        this.Add("reset-stretch", "restore remembered stretch", WW_ResetWindowStretch, ["Win + Shift + Down"])
        this.Add("minimize", "minimize / restore last minimized window", WW_MinimizeActiveWindow, ["Win + Backspace"])
        this.Add("isolate", "isolate active window / restore group", WW_ToggleOtherWindows, ["Win + Shift + Home"])
        this.Add("minimize-all", "minimize / restore window group", WW_ToggleAllWindows, ["Win + M"])
        for corner, key in Map("top-left", "Insert", "bottom-left", "Delete", "top-right", "PgUp", "bottom-right", "PgDn")
            this.Add("tile-" corner, "place " corner " tile", WW_PlaceCornerTile, ["Win + " key], [corner])
        this.Add("tile-top", "cycle top-center tiles", WW_PlaceCenterTile, ["Win + Home"], ["top"])
        this.Add("tile-bottom", "cycle bottom-center tiles", WW_PlaceCenterTile, ["Win + End"], ["bottom"])
        this.Add("swap-next", "swap with next clockwise window", WW_SwapWindow, ["Win + Enter"], ["clockwise"])
        this.Add("swap-previous", "swap with previous clockwise window", WW_SwapWindow,
            ["Win + Shift + Enter"], ["counter-clockwise"])
        for direction in ["left", "right", "up", "down"] {
            this.Add("focus-" direction, "focus window " direction, WW_FocusNearestWindow,
                ["Win + Alt + " direction], [direction])
            this.Add("zone-" direction, "FancyZones: move " direction, WW_MoveWindowThroughFancyZones,
                ["Ctrl + Alt + " direction], [direction], true)
        }
        this.Add("cycle-expanded", "cycle maximized / fullscreen windows", WW_CycleMaximizedFullscreenWindows,
            ["Win + Shift + Tab"])
        this.manager.AddAction("win-key-overhaul.help", "show Wonder Windows help",
            ObjBindMethod(this, "HelpEvent"), ["Win + Ctrl + H"],
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available")})
    }

    Available(*) => SuiteState.App.ModuleActive("win-key-overhaul")

    FancyZonesAvailable(direction, *) {
        global WW_fancyzones_process_id, WW_fancyzones_integration_state
        state := WW_fancyzones_integration_state
        return this.Available() && WW_fancyzones_process_id && IsObject(state)
            && state.override_snap_enabled
            && (state.relative_position_enabled || direction = "left" || direction = "right")
    }

    RefreshOptionalActions(*) {
        signature := ""
        for direction in ["left", "right", "up", "down"]
            signature .= this.FancyZonesAvailable(direction) ? "1" : "0"
        if signature = this.optionalAvailability || !this.manager.running
            return
        this.optionalAvailability := signature
        try {
            this.manager.Apply(this.manager.GetConfiguration())
            if IsObject(this.manager.settings)
                this.manager._RenderSettings()
        }
        catch Error as failure {
            SuiteState.Log.Error("Wonder Windows / optional shortcuts", failure)
            if !this.dryRun
                TrayTip("FancyZones shortcuts could not activate. Resolve the shortcut conflict in Keybindings.",
                    SuiteApplication.Name, 2)
        }
    }

    Add(id, label, command, bindings, arguments := unset, fancyZones := false) {
        actionId := "win-key-overhaul." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments, fancyZones: fancyZones}
        context := fancyZones ? ObjBindMethod(this, "FancyZonesContext", arguments[1])
            : ObjBindMethod(this, "WindowContext")
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: fancyZones ? "Wonder Windows / FancyZones" : "Wonder Windows",
                available: fancyZones ? ObjBindMethod(this, "FancyZonesAvailable", arguments[1])
                    : ObjBindMethod(this, "Available"),
                scope: "!paper-pad", context: context})
    }

    WindowContext(*) => !SuiteWindowOwnership.IsSuiteSurface(DllCall("GetForegroundWindow", "ptr"))

    FancyZonesContext(direction, *) {
        global WW_fancyzones_process_id, WW_fancyzones_integration_state
        state := WW_fancyzones_integration_state
        return this.WindowContext() && WW_fancyzones_process_id && IsObject(state)
            && state.override_snap_enabled
            && (state.relative_position_enabled || direction = "left" || direction = "right")
    }

    Start() {
        ; The observer is passive and shares its callback group with Cascade Kingdom.
        for key in ["LButton", "RButton", "MButton"]
            this.manager.Observe("~*" key, ObjBindMethod(this, "Available"), WW_ForgetLastMinimizedWindow)
        this.PollCompatibility()
        SetTimer(this.pollCallback, 5000)
    }

    PollCompatibility(*) {
        if this.stopping || this.dryRun
            return
        try WW_CheckFancyZonesStartup()
        catch Error as failure
            SuiteState.Log.Error("Wonder Windows / compatibility", failure)
        this.RefreshOptionalActions()
        SuiteWindowOwnership.Prune()
    }

    CanRun() {
        return !this.stopping && this.Available() && this.manager.running
            && !this.manager.gated && !this.manager.paused && !this.manager.applying
            && !SuiteState.App.systemSuspended
    }

    HelpEvent(event) {
        if event.phase = "down" && !this.dryRun
            SetTimer((*) => SuiteState.App.ui.ShowHelp("win-key-overhaul"), -1)
    }

    Event(event) {
        token := event.actionId "|" event.slot
        if event.phase = "cancel" {
            if this.pending.Has(token)
                this.pending.Delete(token)
            return
        }
        if event.phase = "up" {
            if this.pending.Has(token)
                this.pending[token].released := true
            return
        }
        if event.phase != "down" || !this.catalog.Has(event.actionId)
            return
        if this.dryRun {
            SuiteState.Log.Write("Wonder Windows", "dry run: " event.actionId)
            return
        }
        if !this.CanRun() || this.pending.Count >= 16
            return
        this.pending[token] := {action: this.catalog[event.actionId], event: event.Clone(),
            pid: SuiteWindowOwnership.ProcessId(event.foregroundHwnd), generation: this.generation,
            created: A_TickCount, released: false}
        SetTimer(this.drainCallback, 15)
    }

    static InputsReleased(event) {
        if !InStr(event.key, "Wheel") && GetKeyState(event.key, "P")
            return false
        for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]
            if GetKeyState(key, "P")
                return false
        return true
    }

    Drain(*) {
        for token, job in this.pending.Clone() {
            if !this.CanRun() || job.generation != this.generation
                || ((A_TickCount - job.created) & 0xFFFFFFFF) > 5000
                || DllCall("GetForegroundWindow", "ptr") != job.event.foregroundHwnd
                || SuiteWindowOwnership.ProcessId(job.event.foregroundHwnd) != job.pid
                || !this.manager.ContextActive(this.manager.actions[job.event.actionId]) {
                this.pending.Delete(token)
                continue
            }
            ; Forwarding waits for release of the actual configurable trigger,
            ; rather than blocking the shared process with the old KeyWait(arrow).
            if job.action.fancyZones && (!job.released || !WonderWindowsModule.InputsReleased(job.event))
                continue
            this.pending.Delete(token)
            try WW_RunWindowCommand(job.action.command, job.action.arguments*)
            catch Error as failure
                SuiteState.Log.Error("Wonder Windows / " job.event.actionId, failure)
        }
        if !this.pending.Count
            SetTimer(this.drainCallback, 0)
    }

    CancelWork() {
        this.generation += 1
        this.pending.Clear()
        SetTimer(this.drainCallback, 0)
        WW_EndFocusNavigationSession()
    }

    Stop(reason := "Exit", code := 0) {
        this.stopping := true
        this.CancelWork()
        SetTimer(this.pollCallback, 0)
        SetTimer(WW_ReassertFancyZonesKeyboardHook, 0)
        SetTimer(WW_WatchDemotedBorderlessSwitcherWindows, 0)
        WW_ClearFocusHighlight(true)
        WW_RunWindowCommand(WW_RestoreAllVerticalStretches)
        WW_RunWindowCommand(WW_RestoreAllHorizontalStretches)
        WW_RunWindowCommand(WW_RestoreAllBorderlessWindows, reason, code)
    }
}
