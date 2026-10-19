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
        this.Add("maximize", "cycle maximized / upper half / lower half", WW_MaximizeWindowTarget, ["Win + Up"])
        this.Add("restore", "restore normal window size / position", WW_RestoreWindowTarget, ["Win + Down"])
        for side in ["left", "right"] {
            this.Add("layout-" side, "cycle " side " layouts", WW_CycleWindowSnap, ["Win + " side], [side])
            this.Add("stretch-" side, "stretch " side " to obstacle / restore", WW_ToggleHorizontalStretch,
                ["Win + Shift + " side], [side])
        }
        this.Add("stretch-height", "stretch vertically until obstacles", WW_StretchWindowVertically, ["Win + Shift + Up"])
        this.Add("stretch-full-cycle", "cycle full-height / full-width stretch", WW_CycleFullStretch, ["Shift + Win + Enter"])
        this.Add("reset-stretch", "undo window stretch", WW_ResetWindowStretch, ["Win + Shift + Down"])
        this.Add("minimize", "minimize / restore last minimized window", WW_MinimizeActiveWindow, ["Win + Backspace"])
        this.Add("move-monitor", "cycle active window to next monitor", WW_CycleWindowMonitor, ["Caps + Win + Backspace"])
        this.Add("isolate", "isolate active window / restore", WW_ToggleOtherWindows, ["Win + Shift + Home"])
        this.Add("minimize-all", "minimize / restore all windows", WW_ToggleAllWindows, ["Win + M"])
        for corner, key in Map("top-left", "Insert", "bottom-left", "Delete", "top-right", "PgUp", "bottom-right", "PgDn")
            this.Add("tile-" corner, "place " corner " tile", WW_PlaceCornerTile, ["Win + " key], [corner])
        this.Add("tile-top", "cycle top-center tiles", WW_PlaceCenterTile, ["Win + Home"], ["top"])
        this.Add("tile-bottom", "cycle bottom-center tiles", WW_PlaceCenterTile, ["Win + End"], ["bottom"])
        this.Add("cycle-stacked", "cycle overlapping windows", WW_CycleStackedWindows, ["Win + Enter"])
        focusLabels := Map(
            "left", "focus nearest window to the left",
            "right", "focus nearest window to the right",
            "up", "focus nearest window above",
            "down", "focus nearest window below")
        for direction in ["left", "right", "up", "down"] {
            this.Add("focus-" direction, focusLabels[direction], WW_FocusNearestWindow,
                ["Win + Alt + " direction], [direction])
            this.Add("swap-" direction, "swap with nearest window to the " direction,
                WW_SwapWindow, ["Caps + Win + " direction], [direction])
            this.Add("zone-" direction, "FancyZones: move " direction, WW_MoveWindowThroughFancyZones,
                ["Ctrl + Alt + " direction], [direction], true)
        }
        this.Add("cycle-expanded", "cycle maximized / fullscreen windows", WW_CycleMaximizedFullscreenWindows,
            ["Caps + Win + Enter"])
        this.manager.AddAction("wonder-windows.help", "show Wonder Windows help",
            ObjBindMethod(this, "HelpEvent"), ["Caps + Win + H"],
            {category: "Wonder Windows", help: true,
                available: ObjBindMethod(this, "Available")})
    }

    Available(*) => SuiteState.App.ModuleActive("wonder-windows")

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
            SuiteState.Log.Error("Wonder Windows / optional hotkeys", failure)
            if !this.dryRun
                TrayTip("FancyZones hotkeys could not activate. Resolve the hotkey conflict in Keybindings.",
                    SuiteApplication.Name, 2)
        }
    }

    Add(id, label, command, bindings, arguments := unset, fancyZones := false) {
        actionId := "wonder-windows." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments, fancyZones: fancyZones}
        context := fancyZones ? ObjBindMethod(this, "FancyZonesContext", arguments[1])
            : ObjBindMethod(this, "WindowContext")
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: fancyZones ? "Wonder Windows / FancyZones" : "Wonder Windows",
                available: fancyZones ? ObjBindMethod(this, "FancyZonesAvailable", arguments[1])
                    : ObjBindMethod(this, "Available"),
                scope: "", context: context})
    }

    WindowContext(*) => SuiteWindowOwnership.AllowsWonderWindows(DllCall("GetForegroundWindow", "ptr"))

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

    HelpEvent(event) => SuiteState.App.HelpShortcutEvent("wonder-windows", event)

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
        WW_RunWindowCommand(WW_ClearSwapZones)
    }
}

; Shift legacy Wonder Windows defaults in memory without rewriting custom keys.
WW_MigrateKeybindingDefaults(configuration)
{
    changes := [
        ["wonder-windows.stretch-full-cycle", 1, "Caps + Win + Enter", "Shift + Win + Enter"],
        ["wonder-windows.reset-stretch", 2, "Caps + Win + Backspace", ""],
        ["wonder-windows.cycle-expanded", 1, "Win + Shift + Tab", "Caps + Win + Enter"]
    ]
    for direction in ["left", "right", "up", "down"]
        changes.Push(["wonder-windows.focus-" direction, 1,
            "Caps + Win + " direction, "Win + Alt + " direction])
    for change in changes {
        actionId := change[1]
        if !configuration.Has(actionId)
            continue
        slot := change[2]
        if configuration[actionId].bindings[slot] = Keybindings.Parse(change[3]).signature
            configuration[actionId].bindings[slot] := change[4] = ""
                ? "" : Keybindings.Parse(change[4]).signature
    }
}
