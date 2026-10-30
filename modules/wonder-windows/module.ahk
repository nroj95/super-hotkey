; Wonder Windows: hotkeys, deferred window commands, logging, the FancyZones
; check, settings page and guide. Window commands live in the other files.
class WonderWindowsModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Zones"]
    static ZoneUnits := [["fourths", "Fourths and halves"], ["thirds", "Thirds"]]

    __New(app) {
        global WW_zone_cycle_unit
        super.__New(app, "wonder-windows")
        WW_InitializeState()
        this.settingsPath := app.Settings.directory "\wonder-windows\settings.ini"
        unit := IniRead(this.settingsPath, "Zones", "Cycle", "fourths")
        WW_zone_cycle_unit := unit = "thirds" ? "thirds" : "fourths"
        this.manager := 0
        this.stopping := false
        this.generation := 0
        this.pending := Map()
        this.catalog := Map()
        this.drainCallback := ObjBindMethod(this, "Drain")
        this.pollCallback := ObjBindMethod(this, "PollCompatibility")
        ; Adoption by Cascade Kingdom must first undo Wonder Windows' own state.
        SuiteWindowOwnership.OnRelease(WW_PrepareWindowForAdoption)
    }

    ; Registration order is the Keybindings display order: Help, then by task,
    ; from placing a window to minimizing many.
    Register(manager) {
        this.manager := manager
        manager.AddAction("wonder-windows.help", "show Wonder Windows help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Ctrl + Alt + H", "Caps + Win + H"],
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available")})
        this.Add("zones-from-left", "cycle zones from the left", WW_CycleZone,
            ["Win + WheelDown", "Win + Left"], ["down"])
        this.Add("zones-from-right", "cycle zones from the right", WW_CycleZone,
            ["Win + WheelUp", "Win + Right"], ["up"])
        this.Add("maximize", "maximize, then upper / lower half", WW_MaximizeWindowTarget, ["Win + Up"],
            , {hidden: true})
        this.Add("restore", "undo placement, then minimize", WW_RestoreOrMinimizeWindow, ["Win + Down"],
            , {hidden: true})
        this.Add("stretch", "stretch to neighbors: across / fill / back", WW_CycleNeighborStretch,
            ["Win + Shift + Enter"])
        for side in [["up", "above"], ["down", "below"], ["left", "to the left"], ["right", "to the right"]]
            this.Add("move-onto-" side[1], "stack on nearest window " side[2],
                WW_MoveOntoWindow, ["Win + Alt + " side[1], "Caps + Win + " side[1]], [side[1]])
        this.Add("focus-up", "focus previous visible window", WW_CycleWindowFocus, ["Win + PgUp"], ["up"])
        this.Add("focus-down", "focus next visible window", WW_CycleWindowFocus, ["Win + PgDn"], ["down"])
        this.Add("cycle-stacked", "cycle windows in current stack", WW_CycleMonitorWindows, ["Win + Enter"])
        this.Add("minimize", "minimize active window", WW_MinimizeActiveWindow, ["Win + Backspace"])
        this.Add("restore-minimized", "restore last minimized window", WW_RestoreMinimizedWindow,
            ["Win + Shift + Backspace"])
    }

    Add(id, label, command, bindings, arguments := unset, options := {}) {
        actionId := "wonder-windows." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available"),
                context: ObjBindMethod(this, "WindowContext"),
                hidden: Keybindings.Option(options, "hidden", false)})
    }

    Available(*) => this.app.ModuleActive(this.id)

    WindowContext(*) => SuiteWindowOwnership.AllowsWonderWindows(SuiteWorkingMonitor.UserWindow())

    Start() {
        this.PollCompatibility()
        SetTimer(this.pollCallback, 5000)
    }

    PollCompatibility(*) {
        if this.stopping || this.app.dryRun
            return
        try WW_CheckFancyZones()
        catch Error as failure
            SuiteState.Log.Error("Wonder Windows / compatibility", failure)
        SuiteWindowOwnership.Prune()
    }

    CanRun() {
        return !this.stopping && this.Available() && this.manager.running
            && !this.manager.gated && !this.manager.paused && !this.manager.applying
            && !this.app.systemSuspended
    }

    Event(event) {
        token := event.actionId "|" event.slot
        if event.phase = "cancel" {
            if this.pending.Has(token)
                this.pending.Delete(token)
            return
        }
        if event.phase != "down" || !this.catalog.Has(event.actionId)
            return
        if this.app.dryRun {
            SuiteState.Log.Write("Wonder Windows", "dry run: " event.actionId)
            return
        }
        if !this.CanRun() || this.pending.Count >= 16
            return
        this.pending[token] := {action: this.catalog[event.actionId], event: event.Clone(),
            pid: WindowProcessId(event.foregroundHwnd), generation: this.generation,
            created: A_TickCount}
        SetTimer(this.drainCallback, 15)
    }

    Drain(*) {
        for token, job in this.pending.Clone() {
            if !this.CanRun() || job.generation != this.generation
                || ((A_TickCount - job.created) & 0xFFFFFFFF) > 5000
                || DllCall("GetForegroundWindow", "ptr") != job.event.foregroundHwnd
                || WindowProcessId(job.event.foregroundHwnd) != job.pid
                || !this.manager.ContextActive(this.manager.actions[job.event.actionId]) {
                this.pending.Delete(token)
                continue
            }
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
        WW_EndZoneCycle()
    }

    Stop(*) {
        this.stopping := true
        this.CancelWork()
        SetTimer(this.pollCallback, 0)
        WW_RunWindowCommand(WW_ClearLogicalZones)
    }

    ShowSettings(ui) {
        global WW_zone_cycle_unit
        key := "settings:wonder-windows"
        if ui.Existing(key)
            return
        window := ui.NewWindow(key, "Wonder Windows - Settings", true)
        names := []
        selected := 1
        for index, unit in WonderWindowsModule.ZoneUnits {
            names.Push(unit[2])
            if unit[1] = WW_zone_cycle_unit
                selected := index
        }
        window.AddText("x20 y25 w150", "Zone cycle")
        window.AddDropDownList("x175 y20 w260 vzoneUnit", names).Choose(selected)
        window.AddText("x175 y55 w600", "Full height first, then the upper and lower halves of the display."
            . " Thirds skips the halves.")
        WonderWindowsModule.AddStatus(window, "FancyZones",
            WW_IsFancyZonesRunning() ? "running, not supported" : "not running, you're all set!", 110, "fancyZonesStatus")
        window.AddText("x20 y150 w760", "FancyZones also moves windows and takes hotkeys, so it isn't supported;"
            . " disable it in PowerToys. For drag-and-drop zones that work alongside Super Hotkey, try ScreenGrid.")
        ui.Footer(window, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 100],
            ["ScreenGrid...", ObjBindMethod(this, "OpenScreenGrid", ui), 130],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 90]], 230)
        ui.ShowPage(key, 800, 280, 740, 260)
    }

    static ScreenGridUrl := "https://github.com/TtesseractT/ScreenGrid"

    OpenScreenGrid(ui, *) {
        if this.app.dryRun {
            MsgBox("Opening web pages is inactive in the dry run.", SuiteApplication.Name, "Iconi")
            return
        }
        try Run(WonderWindowsModule.ScreenGridUrl)
        catch Error as failure
            ui.Report(failure, "Wonder Windows / ScreenGrid")
    }

    SaveSettings(ui, *) {
        global WW_zone_cycle_unit
        key := "settings:wonder-windows"
        try {
            unit := WonderWindowsModule.ZoneUnits[ui.windows[key]["zoneUnit"].Value][1]
            this.app.Settings.WritePreferences(this.id, Map("Zones", Map("Cycle", unit)))
            WW_zone_cycle_unit := unit
            WW_EndZoneCycle()
            ui.CloseWindow(key)
        }
        catch Error as failure
            ui.Report(failure, "Wonder Windows / settings")
    }

    static StatusColor(value) {
        switch value {
            case "not running, you're all set!": return "008000"
            case "running, not supported": return "B02020"
            default: return "505050"
        }
    }

    static AddStatus(window, label, value, y, controlName) {
        window.AddText("x20 y" y " w150 h23", label ":")
        window.SetFont("s10 c" WonderWindowsModule.StatusColor(value), "Cascadia Mono")
        window.AddText("x175 y" y " w600 h23 v" controlName, value)
        window.SetFont("s10 cDefault", "Cascadia Mono")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nWindows already has window-management shortcuts, but I found many of them "
            . "frustrating or incomplete. I wanted something more powerful, consistent "
            . "and predictable, without constantly reaching for the mouse."
            . "`r`n`r`nCYCLE ZONES"
            . "`r`nHold Win and scroll, or press Win + Left or Right, to walk the window "
            . "through fourths and halves: full height first, then upper and lower fourths, "
            . "then upper and lower halves. Left and scroll down start at the left fourth; "
            . "Right and scroll up start at the right fourth. The other key steps back, so "
            . "Left then Right jumps to the last zone. Release the keys to start over next "
            . "time. Settings can switch the cycle to thirds. Sizes an app cannot shrink to "
            . "are skipped."
            . "`r`n`r`nARRANGE YOUR WINDOWS"
            . "`r`nWin + Shift + Enter stretches a window across to its neighbors, then "
            . "also up and down so it fills the free space, then back to its original size. "
            . "Win + Down restores a placed window's original shape, and a cascade window "
            . "back in its cascade; pressed again it minimizes the window. "
            . "Win + Backspace minimizes the active window, and Win + Shift + Backspace "
            . "brings back the windows it minimized, newest first."
            . "`r`n`r`nFOCUS, STACKS AND FULLSCREEN"
            . "`r`nWin + PgDn and PgUp step focus through every window on screen in reading "
            . "order: displays left to right, columns left to right, top before bottom, and "
            . "outline the window they reach; double-tap Caps to outline where you are. "
            . "A stack of overlapping windows counts once, as its front window. "
            . "Move a window onto its nearest neighbor to stack it in front. Bring forward the next window stacked with the active one, "
            . "and cycle a window between maximized and half-height positions. Layout actions exit F11 fullscreen before repositioning a window. "
            . "Keybindings below shows the current hotkey for each action."
    }
}

; Before Cascade Kingdom adopts a manually positioned window, leave F11
; fullscreen and forget Wonder Windows' layout state. Returning false keeps
; the window manual.
WW_PrepareWindowForAdoption(hwnd)
{
    global WW_layout_cycle_windows, WW_normal_window_placements, WW_stretched_windows
    if !WW_SetNativeFullscreen(hwnd, false)
        return false
    WW_ForgetLogicalZone(hwnd)
    for states in [WW_layout_cycle_windows, WW_normal_window_placements, WW_stretched_windows]
        if states.Has(hwnd)
            states.Delete(hwnd)
    return true
}

WW_DebugLog(message) => SuiteState.Log.Debug("Wonder Windows", message)

WW_DebugError(context, failure) => SuiteState.Log.Error("Wonder Windows / " context, failure)

WW_IsFancyZonesRunning()
{
    return !!ProcessExist("PowerToys.FancyZones.exe")
}

; FancyZones is not supported: it also moves windows (new windows, display
; changes) and takes hotkeys, competing with Wonder Windows and Cascade
; Kingdom. Say so once per FancyZones process and never touch its settings.
WW_CheckFancyZones()
{
    global WW_fancyzones_process_id
    process_id := ProcessExist("PowerToys.FancyZones.exe")
    if process_id = WW_fancyzones_process_id
        return
    WW_fancyzones_process_id := process_id
    if !process_id
        return
    SuiteState.Log.Write("Wonder Windows", "FancyZones is running; it is not supported")
    SuiteNotice.Show("status", "FancyZones isn't supported alongside Super Hotkey", 5000)
}
