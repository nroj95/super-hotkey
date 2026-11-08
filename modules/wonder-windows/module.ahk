; Wonder Windows: hotkeys, deferred window commands, logging, the FancyZones
; check, settings page and guide. Window commands live in the other files.
; The Windows keys it improves stay claimed after their actions move, unless
; Settings gives them back to Windows.
class WonderWindowsModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Zones", "ZoneLayouts", "ZoneCustom", "Keys"]

    __New(app) {
        super.__New(app, "wonder-windows")
        WW_InitializeState()
        this.settingsPath := app.Settings.directory "\wonder-windows\settings.ini"
        this.LoadZoneLayouts()
        this.zoneControls := []
        this.pageSeparate := false
        this.givesBackWindowsKeys := IniRead(this.settingsPath, "Keys", "GiveBackToWindows", 0) = "1"
        this.manager := 0
        this.stopping := false
        this.generation := 0
        this.pending := Map()
        this.pressTokens := Map()  ; action|slot -> its latest key tap
        this.sequence := 0
        this.catalog := Map()
        this.drainCallback := ObjBindMethod(this, "Drain")
        this.pollCallback := ObjBindMethod(this, "PollCompatibility")
        ; Adoption by Cascade Kingdom must first undo Wonder Windows' own state.
        SuiteWindowOwnership.OnRelease(WW_PrepareWindowForAdoption)
    }

    ; Registration order is the Keybindings display order: Help and zone
    ; cycling, then one subcategory per section of the guide. replaces names
    ; the Windows key an action improves.
    Register(manager) {
        this.manager := manager
        manager.AddAction("wonder-windows.help", "show Wonder Windows help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Ctrl + Alt + H", "Caps + Win + H"],
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available")})
        this.Add("zones-from-left", "cycle zones from the left", WW_CycleZone,
            ["Win + WheelDown", "Win + Left"], ["down"], {replaces: ["Win + Left"]})
        this.Add("zones-from-right", "cycle zones from the right", WW_CycleZone,
            ["Win + WheelUp", "Win + Right"], ["up"], {replaces: ["Win + Right"]})
        arrange := "Arrange your windows"
        for side in [["up", "above"], ["down", "below"], ["left", "to the left"], ["right", "to the right"]]
            this.Add("move-onto-" side[1], "stack on nearest window " side[2],
                WW_MoveOntoWindow, ["Win + Alt + " side[1], "Caps + Win + " side[1]], [side[1]], {section: arrange})
        this.Add("minimize", "minimize active window", WW_MinimizeActiveWindow, ["Win + Backspace"],
            , {section: arrange})
        this.Add("restore-minimized", "restore last minimized window", WW_RestoreMinimizedWindow,
            ["Win + Shift + Backspace"], , {section: arrange})
        ; Each key beside its Shift twin. The display-wide ones answer from any window.
        keys := "Better Windows keys"
        this.Add("maximize", "maximize, then upper / lower half", WW_MaximizeWindowTarget, ["Win + Up"],
            , {section: keys, replaces: ["Win + Up"]})
        this.Add("restore", "back to normal size", WW_RestoreToNormalSize, ["Win + Down"],
            , {section: keys, replaces: ["Win + Down"]})
        this.Add("full-span", "full height, then full width, then back", WW_CycleFullSpan,
            ["Win + Shift + Up"], , {section: keys, replaces: ["Win + Shift + Up"]})
        this.Add("stretch-to-neighbors", "stretch to neighbors, then back", WW_ToggleNeighborStretch,
            ["Win + Shift + Down"], , {section: keys, replaces: ["Win + Shift + Down"]})
        this.Add("minimize-all", "minimize all windows on this display", WW_MinimizeAllWindows, ["Win + M"],
            , {section: keys, replaces: ["Win + M"], anyWindow: true})
        this.Add("restore-all", "restore windows minimized on this display", WW_RestoreAllWindows,
            ["Win + Shift + M"], , {section: keys, replaces: ["Win + Shift + M"], anyWindow: true})
        this.Add("minimize-others", "minimize other windows on this display", WW_MinimizeOtherWindows,
            ["Win + Home"], , {section: keys, replaces: ["Win + Home"], anyWindow: true})
        this.Add("restore-others", "restore windows behind the active window", WW_RestoreOtherWindows,
            ["Win + Shift + Home"], , {section: keys, anyWindow: true})
        this.Add("minimize-everywhere", "minimize all windows on every display", WW_MinimizeEveryDisplay,
            ["Win + D"], , {section: keys, replaces: ["Win + D"], anyWindow: true})
        this.Add("restore-everywhere", "restore windows minimized on every display", WW_RestoreEveryDisplay,
            ["Win + Shift + D"], , {section: keys, anyWindow: true})
        focus := "Focus, stacks and fullscreen"
        this.Add("focus-up", "focus previous visible window", WW_CycleWindowFocus, ["Win + PgUp"], ["up"],
            {section: focus})
        this.Add("focus-down", "focus next visible window", WW_CycleWindowFocus, ["Win + PgDn"], ["down"],
            {section: focus})
        this.Add("cycle-stacked", "cycle windows in current stack", WW_CycleMonitorWindows, ["Win + Enter"],
            , {section: focus})
        this.Add("cycle-stacked-previous", "cycle windows in current stack backwards", WW_CycleMonitorWindows,
            ["Win + Shift + Enter"], ["previous"], {section: focus})
        this.Add("cycle-expanded-next", "show next maximized or fullscreen window",
            WW_CycleMaximizedFullscreenWindows, ["Win + Alt + Enter", "Caps + Win + Enter"], ["next"],
            {section: focus})
        this.Add("cycle-expanded-previous", "show previous maximized or fullscreen window",
            WW_CycleMaximizedFullscreenWindows, ["Win + Alt + Shift + Enter", "Caps + Win + Shift + Enter"],
            ["previous"], {section: focus})
    }

    ; section is the Keybindings subcategory. anyWindow drops the check that
    ; the active window is one Wonder Windows may arrange.
    Add(id, label, command, bindings, arguments := unset, options := {}) {
        actionId := "wonder-windows." id
        arguments := IsSet(arguments) ? arguments : []
        this.catalog[actionId] := {command: command, arguments: arguments}
        section := Keybindings.Option(options, "section", "")
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Event"), bindings,
            {category: "Wonder Windows" (section = "" ? "" : " / " section),
                available: ObjBindMethod(this, "Available"),
                context: Keybindings.Option(options, "anyWindow", false) ? 0 : ObjBindMethod(this, "WindowContext"),
                replaces: Keybindings.Option(options, "replaces", []),
                keepsReplaced: ObjBindMethod(this, "KeepsWindowsKeys")})
    }

    Available(*) => this.app.ModuleActive(this.id)

    KeepsWindowsKeys(*) => !this.givesBackWindowsKeys

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
        press := event.actionId "|" event.slot
        token := this.pressTokens.Get(press, press)
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
        ; Taps held back by a slow move arrive together; each counts, and the
        ; numbered tokens drain in the order pressed. Wheel notches share one,
        ; so a fast spin cannot fling a window several zones on.
        if !InStr(event.key, "Wheel") {
            this.sequence += 1
            token := Format("{:010}", this.sequence) "|" press
            this.pressTokens[press] := token
        }
        this.pending[token] := {action: this.catalog[event.actionId], event: event.Clone(),
            pid: WindowProcessId(event.foregroundHwnd), generation: this.generation,
            created: A_TickCount}
        SetTimer(this.drainCallback, 15)
    }

    Drain(*) {
        for token, job in this.pending.Clone() {
            foreground := DllCall("GetForegroundWindow", "ptr")
            dropped := !this.CanRun() ? "not running"
                : job.generation != this.generation ? "reconfigured"
                : ((A_TickCount - job.created) & 0xFFFFFFFF) > 5000 ? "expired"
                : foreground != job.event.foregroundHwnd ? "focus moved"
                : WindowProcessId(job.event.foregroundHwnd) != job.pid ? "window replaced"
                : !this.manager.ContextActive(this.manager.actions[job.event.actionId]) ? "out of context"
                : ""
            if dropped {
                this.pending.Delete(token)
                if SuiteState.Log.verbose
                    WW_DebugLog("Key dropped. | action=" job.event.actionId " | reason=" dropped
                        . " | pressed-in=" DescribeWindow(job.event.foregroundHwnd)
                        . " | foreground=" DescribeWindow(foreground))
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
        this.pressTokens.Clear()
        SetTimer(this.drainCallback, 0)
        WW_EndZoneCycle()
    }

    Stop(*) {
        this.stopping := true
        this.CancelWork()
        SetTimer(this.pollCallback, 0)
        WW_RunWindowCommand(WW_ClearLogicalZones)
    }

    ; [ZoneLayouts] holds device|orientation=layout, empty for its default;
    ; [ZoneCustom] the last custom line each one used, so its list offers it
    ; again. [Zones] Cycle=thirds, from earlier versions, makes thirds the
    ; landscape default.
    LoadZoneLayouts() {
        global WW_zone_layouts, WW_zone_custom, WW_zone_landscape_default, WW_zone_separate
        WW_zone_landscape_default := IniRead(this.settingsPath, "Zones", "Cycle", "fourths") = "thirds"
            ? "thirds" : "fourths"
        WW_zone_separate := IniRead(this.settingsPath, "Zones", "Separate", 0) = "1"
        WW_zone_layouts := Map(), WW_zone_custom := Map()
        for section, target in Map("ZoneLayouts", WW_zone_layouts, "ZoneCustom", WW_zone_custom) {
            try lines := IniRead(this.settingsPath, section)
            catch
                continue
            for line in StrSplit(lines, "`n", "`r") {
                parts := StrSplit(line, "=", , 2)
                if parts.Length = 2 && Trim(parts[2]) != ""
                    target[parts[1]] := Trim(parts[2])
            }
        }
    }

    ; One row per connected display: a layout for its current orientation, or
    ; with the checkbox one for each orientation. Each list offers the presets
    ; and the display's last custom line, and takes a typed line too.
    ; pending holds unsaved values, by device|orientation, when the checkbox
    ; rebuilds the page.
    ShowSettings(ui, pending := 0) {
        global WW_zone_layouts, WW_zone_custom, WW_zone_separate
        key := "settings:wonder-windows"
        if !pending && ui.Existing(key)
            return
        separate := pending ? pending["separate"] : WW_zone_separate
        this.pageSeparate := separate
        rows := SuitePageRows(ui.NewWindow(key, "Wonder Windows - Settings", true), 800)
        choices := ui.DisplayChoices("Primary")
        this.zoneControls := []
        for index, device in choices.values {
            current := WonderWindowsModule.DeviceOrientation(device)
            for orientation in separate ? ["landscape", "portrait"] : [current] {
                zoneKey := device "|" orientation
                label := choices.names[index] (separate ? ", " orientation : " (" orientation ")")
                items := []
                for preset in WW_ZoneLayouts.Presets
                    items.Push(preset[2])
                if WW_zone_custom.Has(zoneKey)
                    items.Push(WW_zone_custom[zoneKey])
                name := "zone" this.zoneControls.Length + 1
                control := rows.Field(label, "ComboBox", "w300 v" name, items)
                layout := WW_zone_layouts.Has(zoneKey) ? WW_zone_layouts[zoneKey] : WW_DefaultZoneLayout(zoneKey)
                control.Text := pending && pending.Has(zoneKey) ? pending[zoneKey]
                    : WW_ZoneLayouts.IsPreset(layout) ? WW_ZoneLayouts.Name(layout) : layout
                this.zoneControls.Push({name: name, key: zoneKey, label: label})
            }
        }
        rows.Caption("Pick a layout, or type your own with : between columns, / between rows and > for"
            . " and then, such as 1:1:1:1 > 1:1 / 1:1. A display left on its default follows its orientation.")
        rows.Checkbox("Choose separate layouts for landscape and portrait", "vseparate").Value := separate
        rows.window["separate"].OnEvent("Click", ObjBindMethod(this, "RebuildSettings", ui))
        rows.Checkbox("Give Windows back its own keys when you move or clear their actions", "vgiveBack")
            .Value := pending ? pending["giveBack"] : this.givesBackWindowsKeys
        rows.Caption("Win + Left, Right, Up, Down, M, Shift + M, Home and D. Unchecked, they do nothing"
            . " once moved or cleared, so Windows' own versions never surprise you.", true)
        status := WW_IsFancyZonesRunning() ? "running, not supported" : "not running, you're all set!"
        rows.Field("FancyZones:", "Text", "w540 vfancyZonesStatus c" WonderWindowsModule.StatusColor(status), status)
        rows.Text("FancyZones also moves windows and takes hotkeys, so it isn't supported; disable it in PowerToys.")
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui)],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id)]])
        if pending {
            ; The page now shows unsaved changes: keep Apply lit.
            ui.pageLayouts[key].saved := ""
            ui.PageChanged(key)
        }
    }

    ; The checkbox shows or hides the second column, keeping what was typed.
    RebuildSettings(ui, *) {
        key := "settings:wonder-windows"
        window := ui.windows[key]
        pending := Map("separate", window["separate"].Value != 0, "giveBack", window["giveBack"].Value)
        for item in this.zoneControls
            pending[item.key] := window[item.name].Text
        ui.CloseWindow(key)
        this.ShowSettings(ui, pending)
    }

    ; landscape or portrait, from the display's bounds; landscape when the
    ; display is gone.
    static DeviceOrientation(device) {
        loop MonitorGetCount() {
            if MonitorGetName(A_Index) = device {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                return bottom - top > right - left ? "portrait" : "landscape"
            }
        }
        return "landscape"
    }

    RestoreSettings(window) {
        for item in this.zoneControls
            window[item.name].Text := WW_ZoneLayouts.Name(InStr(item.key, "|portrait") ? "corners" : "fourths")
        window["separate"].Value := 0
        window["giveBack"].Value := 0
    }

    ; Checks every typed line before saving anything. A choice equal to its
    ; default is saved empty, so the display keeps following its orientation.
    SaveSettings(ui, *) {
        key := "settings:wonder-windows"
        window := ui.windows[key]
        try {
            layouts := Map()
            custom := Map()
            for item in this.zoneControls {
                layout := WW_ZoneLayouts.FromText(window[item.name].Text)
                if !WW_ZoneLayouts.IsPreset(layout) {
                    try WW_ParseZoneLine(layout)
                    catch ValueError as problem
                        throw ValueError(item.label ": " problem.Message)
                    custom[item.key] := layout
                }
                ; Saving resets an earlier version's Cycle=thirds, so a choice
                ; of thirds is saved by display from here on.
                layouts[item.key] := layout = (InStr(item.key, "|portrait") ? "corners" : "fourths") ? "" : layout
            }
            separate := window["separate"].Value != 0
            giveBack := window["giveBack"].Value != 0
            changes := Map("Zones", Map("Cycle", "fourths", "Separate", separate ? 1 : 0),
                "Keys", Map("GiveBackToWindows", giveBack ? 1 : 0))
            if layouts.Count
                changes["ZoneLayouts"] := layouts
            if custom.Count
                changes["ZoneCustom"] := custom
            this.app.Settings.WritePreferences(this.id, changes)
            this.LoadZoneLayouts()
            this.givesBackWindowsKeys := giveBack
            WW_EndZoneCycle()
            if separate != this.pageSeparate {
                ui.CloseWindow(key)
                this.ShowSettings(ui)
                return
            }
            ui.Applied(key)
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

    HelpText() => "
    (
        WHY I MADE THIS
        Windows already has window-management shortcuts, but I found many of them frustrating or incomplete.
        I wanted something more powerful, consistent and predictable, without constantly reaching for the mouse.

        CYCLE ZONES
        Hold Win and scroll, or press Win + Left or Right, to walk the window through fourths and halves: full height first, then upper and lower fourths, then upper and lower halves.
        Left and scroll down start at the left fourth; Right and scroll up start at the right fourth.
        The other key steps back, so Left then Right jumps to the last zone.
        Release the keys to start over next time.
        Each display has its own layout in Settings: fourths, thirds, halves and corners, or rows for a portrait display.
        Or type your own there, with : between columns, / between rows and > for and then: 1:1:1:1 > 1:1 / 1:1 walks four columns, then four corners.
        A display left on its default uses fourths in landscape and halves and corners in portrait; Settings can also give each orientation its own layout.
        Sizes an app cannot shrink to are skipped.

        ARRANGE YOUR WINDOWS
        Win + Backspace minimizes the active window; focus stays on that display while it has windows left, then moves to the next display.
        Win + Shift + Backspace brings back the windows it minimized, newest first.

        BETTER WINDOWS KEYS
        Windows' own keys work as you know them, with fewer surprises.
        Win + M, Win + Home and Win + D take Shift to bring back what they minimized, however much you do in between.
        They act on your display only, except Win + D, which reaches every display, and focus stays on your display.
        Win + Up maximizes the window, then steps to the upper and lower half.
        Win + Down takes it back to normal size, out of maximized or fullscreen, a zone, a half or a stretch; it never minimizes.
        Win + Shift + Up stretches the window to the full height of the display, then to the full width, then puts it back.
        Win + Shift + Down stretches it into the free space around it, up to the windows you can see, and again puts it back; with nothing beside it, it maximizes.
        A cascade window keeps its place in its cascade while it's maximized, minimized, in a zone, a half or a stretch, and Win + Down puts it back there.

        FOCUS, STACKS AND FULLSCREEN
        Win + PgDn and PgUp step focus through every window on screen in reading order: displays left to right, columns left to right, top before bottom, and outline the window they reach; double-tap Caps to outline where you are.
        A stack of overlapping windows counts once, as its front window.
        Move a window onto its nearest neighbor to stack it in front.
        Win + Enter brings forward the next window stacked with the active one; add Shift to go the other way.
        Layout actions exit F11 fullscreen before repositioning a window.
        Win + Alt + Enter shows the next maximized or fullscreen window on your display, minimized or not, and minimizes the others there, so one big window is out at a time; add Shift to go back.
        Keybindings below shows the current hotkey for each action.
    )"
}

; Before Cascade Kingdom adopts a manually positioned window, leave F11
; fullscreen and forget Wonder Windows' layout state. Returning false keeps
; the window manual.
WW_PrepareWindowForAdoption(hwnd)
{
    global WW_layout_cycle_windows, WW_normal_window_placements
    if !WW_SetNativeFullscreen(hwnd, false)
        return false
    WW_ForgetLogicalZone(hwnd)
    WW_ForgetStretches(hwnd)
    for states in [WW_layout_cycle_windows, WW_normal_window_placements]
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
