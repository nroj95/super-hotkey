; Wonder Windows: hotkeys, deferred window commands, compatibility checks,
; settings page and guide. Window commands themselves live in the other files.
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
        this.Add("zones-from-left", "cycle zones, starting from the left", WW_CycleZone,
            ["Win + WheelDown", "Caps + Win + PgDn"], ["down"])
        this.Add("zones-from-right", "cycle zones, starting from the right", WW_CycleZone,
            ["Win + WheelUp", "Caps + Win + PgUp"], ["up"])
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
        manager.AddMigration("wonderDefaults", "1", WW_MigrateKeybindingDefaults)
    }

    Add(id, label, command, bindings, arguments := unset) {
        actionId := "wonder-windows." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available"),
                context: ObjBindMethod(this, "WindowContext")})
    }

    Available(*) => this.app.ModuleActive(this.id)

    WindowContext(*) => SuiteWindowOwnership.AllowsWonderWindows(DllCall("GetForegroundWindow", "ptr"))

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
        WW_EndFocusNavigationSession()
        WW_EndZoneCycle()
    }

    Stop(*) {
        this.stopping := true
        this.CancelWork()
        SetTimer(this.pollCallback, 0)
        WW_RunWindowCommand(WW_ClearSwapZones)
    }

    ; Windows Snap changes need explicit confirmation; nothing changes at startup.
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
        snap := WW_GetNativeWindowsSnapState()
        WonderWindowsModule.AddStatus(window, "Windows Snap", snap < 0 ? "unknown" : snap ? "on" : "off",
            110, "snapStatus")
        WonderWindowsModule.AddStatus(window, "FancyZones",
            WW_IsFancyZonesRunning() ? "running, not supported" : "not running", 135, "fancyZonesStatus")
        window.AddText("x20 y185 w760", "Use one window-snapping tool at a time. Windows Snap is only"
            . " changed after you confirm. FancyZones is not supported; close it in PowerToys.")
        ui.Footer(window, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 100],
            ["Windows Snap...", ObjBindMethod(this, "CompatibilityAction", ui, "snap"), 145],
            ["Disable Snap...", ObjBindMethod(this, "CompatibilityAction", ui, "disable"), 140],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 90]], 260)
        ui.ShowPage(key, 800, 310, 740, 290)
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
            case "on", "not running": return "008000"
            case "off", "running, not supported": return "B02020"
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
            . "`r`n`r`nCYCLE ZONES"
            . "`r`nHold Win and scroll, or hold Caps + Win and press PgDn or PgUp, to walk the "
            . "window through fourths and halves: full height first, then upper and lower "
            . "fourths, then upper and lower halves. Scroll down starts at the left, scroll up at the right; the "
            . "other direction steps back. Release the keys to start over next time. Settings "
            . "can switch the cycle to thirds. Sizes an app cannot shrink to are skipped."
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
