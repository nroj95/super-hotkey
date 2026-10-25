; Wonder Windows: hotkeys, deferred window commands, compatibility checks,
; settings page and guide. Window commands themselves live in the other files.
class WonderWindowsModule extends SuiteModule {
    hasSettings := true

    __New(app) {
        super.__New(app, "wonder-windows")
        WW_InitializeState()
        this.manager := 0
        this.stopping := false
        this.generation := 0
        this.pending := Map()
        this.catalog := Map()
        this.drainCallback := ObjBindMethod(this, "Drain")
        this.pollCallback := ObjBindMethod(this, "PollCompatibility")
        this.optionalAvailability := "0000"
        ; Adoption by Cascade Kingdom must first undo Wonder Windows' own state.
        SuiteWindowOwnership.OnRelease(WW_PrepareWindowForAdoption)
    }

    ; Registration order is the Keybindings display order.
    Register(manager) {
        this.manager := manager
        manager.AddAction("wonder-windows.help", "show Wonder Windows help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Caps + Win + H"],
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available")})
        focusLabels := Map(
            "up", "focus nearest window above",
            "down", "focus nearest window below",
            "left", "focus nearest window to the left",
            "right", "focus nearest window to the right")
        for direction in ["up", "down", "left", "right"]
            this.Add("focus-" direction, focusLabels[direction], WW_FocusNearestWindow,
                ["Win + Alt + " direction], [direction])
        this.Add("cycle-stacked", "cycle windows on this monitor", WW_CycleMonitorWindows, ["Win + Enter"])
        this.Add("cycle-expanded", "cycle maximized / fullscreen windows", WW_CycleMaximizedFullscreenWindows,
            ["Caps + Win + Enter"])
        this.Add("maximize", "cycle maximized / upper half / lower half", WW_MaximizeWindowTarget, ["Win + Up"])
        this.Add("restore", "restore normal window size / position", WW_RestoreWindowTarget, ["Win + Down"])
        this.Add("minimize", "minimize / restore last minimized window", WW_MinimizeActiveWindow, ["Win + Backspace"])
        this.Add("move-monitor", "cycle active window to next monitor", WW_CycleWindowMonitor, ["Caps + Win + Backspace"])
        for side in ["left", "right"]
            this.Add("layout-" side, "cycle " side " layouts", WW_CycleWindowSnap, ["Win + " side], [side])
        for tile in [["top-left", "Insert"], ["top", "Home"], ["top-right", "PgUp"],
            ["bottom-left", "Delete"], ["bottom", "End"], ["bottom-right", "PgDn"]] {
            if InStr(tile[1], "-")
                this.Add("tile-" tile[1], "place " tile[1] " tile", WW_PlaceCornerTile, ["Win + " tile[2]], [tile[1]])
            else
                this.Add("tile-" tile[1], "cycle " tile[1] "-center tiles", WW_PlaceCenterTile, ["Win + " tile[2]], [tile[1]])
        }
        for side in ["left", "right"]
            this.Add("stretch-" side, "stretch " side " to obstacle / restore", WW_ToggleHorizontalStretch,
                ["Win + Shift + " side], [side])
        this.Add("stretch-height", "stretch vertically until obstacles", WW_StretchWindowVertically, ["Win + Shift + Up"])
        this.Add("stretch-full-cycle", "cycle full-height / full-width stretch", WW_CycleFullStretch, ["Shift + Win + Enter"])
        this.Add("reset-stretch", "undo window stretch", WW_ResetWindowStretch, ["Win + Shift + Down"])
        for direction in ["up", "down", "left", "right"]
            this.Add("swap-" direction, "swap with nearest window to the " direction,
                WW_SwapWindow, ["Caps + Win + " direction], [direction])
        this.Add("isolate", "isolate active window / restore", WW_ToggleOtherWindows, ["Win + Shift + Home"])
        this.Add("minimize-all", "minimize / restore all windows", WW_ToggleAllWindows, ["Win + M"])
        for direction in ["up", "down", "left", "right"]
            this.Add("zone-" direction, "FancyZones: move " direction, WW_MoveWindowThroughFancyZones,
                ["Ctrl + Alt + " direction], [direction], true)
        manager.AddMigration("wonderDefaults", "1", WW_MigrateKeybindingDefaults)
    }

    Add(id, label, command, bindings, arguments := unset, fancyZones := false) {
        actionId := "wonder-windows." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments, fancyZones: fancyZones}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: fancyZones ? "Wonder Windows / FancyZones" : "Wonder Windows",
                available: fancyZones ? ObjBindMethod(this, "FancyZonesAvailable", arguments[1])
                    : ObjBindMethod(this, "Available"),
                context: fancyZones ? ObjBindMethod(this, "FancyZonesContext", arguments[1])
                    : ObjBindMethod(this, "WindowContext")})
    }

    Available(*) => this.app.ModuleActive(this.id)

    ; Zone index navigation uses only left/right; relative position uses all four.
    static FancyZonesReady(direction) {
        global WW_fancyzones_process_id, WW_fancyzones_integration_state
        state := WW_fancyzones_integration_state
        return WW_fancyzones_process_id && IsObject(state) && state.override_snap_enabled
            && (state.relative_position_enabled || direction = "left" || direction = "right")
    }

    FancyZonesAvailable(direction, *) => this.Available() && WonderWindowsModule.FancyZonesReady(direction)

    WindowContext(*) => SuiteWindowOwnership.AllowsWonderWindows(DllCall("GetForegroundWindow", "ptr"))

    FancyZonesContext(direction, *) => this.WindowContext() && WonderWindowsModule.FancyZonesReady(direction)

    ; FancyZones hotkeys are registered only while it can receive them.
    RefreshOptionalActions(*) {
        signature := ""
        for direction in ["left", "right", "up", "down"]
            signature .= this.FancyZonesAvailable(direction) ? "1" : "0"
        if signature = this.optionalAvailability || !this.manager.running
            return
        this.optionalAvailability := signature
        try {
            this.manager.Apply(this.manager.GetConfiguration())
            this.manager.editor.Render()
        }
        catch Error as failure {
            SuiteState.Log.Error("Wonder Windows / optional hotkeys", failure)
            if !this.app.dryRun
                TrayTip("FancyZones hotkeys could not activate. Resolve the hotkey conflict in Keybindings.",
                    SuiteApplication.Name, 2)
        }
    }

    Start() {
        ; The observer is passive and shares its callback group with Cascade Kingdom.
        for key in ["LButton", "RButton", "MButton"]
            this.manager.Observe("~*" key, ObjBindMethod(this, "Available"), WW_ForgetLastMinimizedWindow)
        this.PollCompatibility()
        SetTimer(this.pollCallback, 5000)
    }

    PollCompatibility(*) {
        if this.stopping || this.app.dryRun
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
            && !this.app.systemSuspended
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
        if this.app.dryRun {
            SuiteState.Log.Write("Wonder Windows", "dry run: " event.actionId)
            return
        }
        if !this.CanRun() || this.pending.Count >= 16
            return
        this.pending[token] := {action: this.catalog[event.actionId], event: event.Clone(),
            pid: WindowProcessId(event.foregroundHwnd), generation: this.generation,
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
                || WindowProcessId(job.event.foregroundHwnd) != job.pid
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

    Stop(*) {
        this.stopping := true
        this.CancelWork()
        SetTimer(this.pollCallback, 0)
        SetTimer(WW_ReassertFancyZonesKeyboardHook, 0)
        WW_RunWindowCommand(WW_ClearSwapZones)
    }

    ; Explicit compatibility actions only; nothing is changed at startup.
    ShowSettings(ui) {
        key := "settings:wonder-windows"
        if ui.Existing(key)
            return
        window := ui.NewWindow(key, "Wonder Windows - Settings", true)
        snap := WW_GetNativeWindowsSnapState()
        window.AddText("x20 y20 w760",
            "Use one drag-snapping tool at a time. ScreenGrid is optional; FancyZones remains supported.")
        WonderWindowsModule.AddStatus(window, "Windows Snap", snap < 0 ? "unknown" : snap ? "on" : "off",
            80, "snapStatus")
        WonderWindowsModule.AddStatus(window, "ScreenGrid", WW_IsScreenGridRunning() ? "running" : "not running",
            105, "screenGridStatus")
        WonderWindowsModule.AddStatus(window, "FancyZones", WW_IsFancyZonesRunning() ? "running" : "not running",
            130, "fancyZonesStatus")
        window.AddText("x20 y180 w760", "Windows and PowerToys preferences are not changed at startup."
            . "`nThe actions below either open settings or ask for confirmation before applying changes."
            . "`nFancyZones owns its zone-window switching hotkeys; they are not registered twice here.")
        ui.Footer(window, [["Windows Snap...", ObjBindMethod(this, "CompatibilityAction", ui, "snap"), 145],
            ["Disable Snap...", ObjBindMethod(this, "CompatibilityAction", ui, "disable"), 140],
            ["ScreenGrid...", ObjBindMethod(this, "CompatibilityAction", ui, "screengrid"), 125],
            ["FancyZones...", ObjBindMethod(this, "CompatibilityAction", ui, "fancyzones"), 135],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 90]], 290)
        ui.ShowPage(key, 800, 340, 740, 320)
    }

    static StatusColor(value) {
        switch value {
            case "on", "running": return "008000"
            case "off", "not running": return "B02020"
            default: return "505050"
        }
    }

    static AddStatus(window, label, value, y, controlName) {
        window.AddText("x20 y" y " w150 h23", label ":")
        window.SetFont("s10 c" WonderWindowsModule.StatusColor(value), "Cascadia Mono")
        window.AddText("x175 y" y " w220 h23 v" controlName, value)
        window.SetFont("s10 cDefault", "Cascadia Mono")
    }

    CompatibilityAction(ui, action, *) {
        if this.app.dryRun {
            MsgBox("Compatibility actions are inactive in the dry run.", SuiteApplication.Name, "Iconi")
            return
        }
        try {
            switch action {
                case "snap": WW_OpenWindowsSnapSettings()
                case "disable": WW_PromptToDisableNativeWindowsSnap()
                case "screengrid": WW_OpenScreenGridReleases()
                case "fancyzones": WW_CheckFancyZonesIntegration()
            }
        }
        catch Error as failure
            ui.Report(failure, "Wonder Windows / compatibility")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nWindows already has window-management shortcuts, but I found many of them "
            . "frustrating or incomplete. I wanted something more powerful, consistent "
            . "and predictable, without constantly reaching for the mouse."
            . "`r`n`r`nARRANGE YOUR WINDOWS"
            . "`r`nUse the left and right layout actions to cycle through positions such as "
            . "quarter-width, half-width and near-center. Corner and top/bottom tiles offer "
            . "more precise placement. Stretch toward neighboring windows or cycle "
            . "between full-height and full-width. Restore brings back the original shape."
            . "`r`n`r`nFOCUS, SWAP AND FULLSCREEN"
            . "`r`nMove focus to the nearest window in a direction, swap with a nearby window, "
            . "or temporarily minimize a group. Cycle the windows on the active monitor without moving them, "
            . "and cycle a window between maximized and half-height positions. Moving a "
            . "window to another display preserves cascade membership only where cascading "
            . "is allowed. Layout actions exit F11 fullscreen before repositioning a window. "
            . "The isolate action hides other windows in a group; use it again to restore them. "
            . "Keybindings below shows the current hotkey for each action."
    }
}

; Shift legacy Wonder Windows defaults in memory without rewriting custom keys.
; Files that recorded debugDefaults=2 were written after these defaults changed.
WW_MigrateKeybindingDefaults(configuration, meta := 0)
{
    if IsObject(meta) && meta.Has("debugDefaults") && meta["debugDefaults"] = "2"
        return
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

; Before automatic placement adopts a manually positioned window, leave F11
; fullscreen and forget Wonder Windows' layout state. Returning false keeps
; the window manual.
WW_PrepareWindowForAdoption(hwnd)
{
    global WW_horizontal_stretch_windows, WW_vertical_stretch_windows
    global WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements
    global WW_full_stretch_windows
    if !WW_SetNativeFullscreen(hwnd, false)
        return false
    WW_ForgetSwapZone(hwnd)
    for states in [WW_horizontal_stretch_windows, WW_vertical_stretch_windows,
        WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements,
        WW_full_stretch_windows]
        if states.Has(hwnd)
            states.Delete(hwnd)
    return true
}
