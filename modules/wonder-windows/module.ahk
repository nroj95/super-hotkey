; Wonder Windows: hotkeys, deferred window commands, logging, the FancyZones
; check, settings page and guide. Window commands live in the other files.
; The Windows keys it improves stay claimed after their actions move, unless
; Settings gives them back to Windows.
class WonderWindowsModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Keys", "ZoneStops"]

    __New(app) {
        super.__New(app, "wonder-windows")
        WW_InitializeState()
        this.settingsPath := app.Settings.directory "\wonder-windows\settings.ini"
        this.givesBackWindowsKeys := IniRead(this.settingsPath, "Keys", "GiveBackToWindows", 0) = "1"
        this.LoadZoneStops()
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
    ; mode, then one subcategory per section of the guide. replaces names the
    ; Windows key an action improves. Zone mode's other keys answer only in
    ; zone mode (the zone-cycling scope), so outside it those keys keep their
    ; usual actions, and Windows keeps Win + Shift + Left and Right.
    Register(manager) {
        this.manager := manager
        manager.RegisterScope("zone-cycling", WW_IsCyclingZones)
        manager.AddAction("wonder-windows.help", "show Wonder Windows help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), ["Ctrl + Alt + H", "Caps + Win + H"],
            {category: "Wonder Windows", available: ObjBindMethod(this, "Available")})
        this.Add("zones-from-left", "left half, then zone mode", WW_ZoneSide, ["Win + Left"], ["left"],
            {replaces: ["Win + Left"]})
        this.Add("zones-from-right", "right half, then zone mode", WW_ZoneSide, ["Win + Right"], ["right"],
            {replaces: ["Win + Right"]})
        this.Add("zone-row-up", "zone mode: top half, then slide up", WW_ZoneRow, ["Win + Up"],
            ["up"], {scope: "zone-cycling"})
        this.Add("zone-row-down", "zone mode: bottom half, then slide down", WW_ZoneRow, ["Win + Down"],
            ["down"], {scope: "zone-cycling"})
        for side in [["left", "side edge left"], ["right", "side edge right"], ["up", "top or bottom edge up"],
            ["down", "top or bottom edge down"]]
            this.Add("zone-edge-" side[1], "zone mode: move the " side[2], WW_ZoneEdge,
                ["Win + Shift + " side[1]], [side[1]], {scope: "zone-cycling"})
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
        this.Add("full-height", "toggle full height", WW_ToggleFullSpan, ["Win + Shift + Up"], ["height"],
            {section: keys, replaces: ["Win + Shift + Up"]})
        this.Add("full-width", "toggle full width", WW_ToggleFullSpan, ["Win + Shift + Down"], ["width"],
            {section: keys, replaces: ["Win + Shift + Down"]})
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
        this.Add("cycle-stacked", "cycle windows in current stack", WW_CycleMonitorWindows, ["Win + Shift + PgDn"],
            , {section: focus})
        this.Add("cycle-stacked-previous", "cycle windows in current stack backwards", WW_CycleMonitorWindows,
            ["Win + Shift + PgUp"], ["previous"], {section: focus})
        this.Add("cycle-expanded-next", "show next maximized or fullscreen window",
            WW_CycleMaximizedFullscreenWindows, ["Win + Enter"], ["next"],
            {section: focus})
        this.Add("cycle-expanded-previous", "show previous maximized or fullscreen window",
            WW_CycleMaximizedFullscreenWindows, ["Win + Shift + Enter"],
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
                scope: Keybindings.Option(options, "scope", ""),
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
        ; so a fast spin cannot fling a window several steps on.
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

    ; [ZoneStops] Long|ShortSixths, Fourths and Thirds turn zone mode's stop
    ; pairs on (1) or off (0) along a display's long and short side.
    static StopPairs := [["Sixths", "1/6 and 5/6"], ["Fourths", "1/4 and 3/4"], ["Thirds", "1/3 and 2/3"]]

    ; By default the long side has fourths and thirds and the short side thirds
    ; only, so a half there moves straight between top and bottom.
    static DefaultStop(side, pair) => pair = "Thirds" || pair = "Fourths" && side = "long"
    LoadZoneStops() {
        global WW_zone_stops
        for side, stops in WW_zone_stops
            for pair in WonderWindowsModule.StopPairs
                stops[StrLower(pair[1])] := IniRead(this.settingsPath, "ZoneStops",
                    (side = "long" ? "Long" : "Short") pair[1], WonderWindowsModule.DefaultStop(side, pair[1]) ? 1 : 0) = "1"
    }

    ShowSettings(ui) {
        global WW_zone_stops
        key := "settings:wonder-windows"
        if ui.Existing(key)
            return
        rows := SuitePageRows(ui.NewWindow(key, "Wonder Windows - Settings", true), 800)
        ; Zone mode's stops: one row per side of the display, a checkbox per pair.
        for side in ["long", "short"] {
            prefix := side = "long" ? "Long" : "Short"
            first := rows.Field(side = "long" ? "Zone stops, long side:" : "Zone stops, short side:", "Checkbox",
                "v" prefix "Sixths", WonderWindowsModule.StopPairs[1][2])
            first.Value := WW_zone_stops[side]["sixths"]
            first.GetPos(&x, &y)
            for index, pair in WonderWindowsModule.StopPairs
                if index > 1
                    rows.window.AddCheckbox("x" (x + (index - 1) * 170) " y" y " v" prefix pair[1], pair[2])
                        .Value := WW_zone_stops[side][StrLower(pair[1])]
        }
        rows.Caption("The stops Shift steps through in zone mode, besides halves and full. The long side is a"
            . " display's width in landscape and its height in portrait.")
        rows.Checkbox("Give Windows back its own keys when you move or clear their actions", "vgiveBack")
            .Value := this.givesBackWindowsKeys
        rows.Caption("Win + Left, Right, Up, Down, M, Shift + M, Home and D. Unchecked, they do nothing"
            . " once moved or cleared, so Windows' own versions never surprise you.", true)
        status := WW_IsFancyZonesRunning() ? "running, not supported" : "not running, you're all set!"
        rows.Field("FancyZones:", "Text", "w540 vfancyZonesStatus c" WonderWindowsModule.StatusColor(status), status)
        rows.Text("FancyZones also moves windows and takes hotkeys, so it isn't supported; disable it in PowerToys.")
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui)],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id)]])
    }

    RestoreSettings(window) {
        window["giveBack"].Value := 0
        for side in ["Long", "Short"]
            for pair in WonderWindowsModule.StopPairs
                window[side pair[1]].Value := WonderWindowsModule.DefaultStop(StrLower(side), pair[1])
    }

    SaveSettings(ui, *) {
        key := "settings:wonder-windows"
        try {
            window := ui.windows[key]
            giveBack := window["giveBack"].Value != 0
            stops := Map()
            for side in ["Long", "Short"]
                for pair in WonderWindowsModule.StopPairs
                    stops[side pair[1]] := window[side pair[1]].Value ? 1 : 0
            this.app.Settings.WritePreferences(this.id, Map("Keys", Map("GiveBackToWindows", giveBack ? 1 : 0),
                "ZoneStops", stops))
            this.givesBackWindowsKeys := giveBack
            this.LoadZoneStops()
            WW_EndZoneCycle()
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

        ZONE MODE
        Win + Left or Right starts zone mode, which lasts while you hold Win.
        A window already in a zone keeps its size and moves one place that way; any other snaps to the closest size against that side; a maximized window becomes that half, as in Windows.
        In zone mode a window sits only where both its edges land on stops: halves, fourths and thirds, so a half sits left, in the middle or right, and windows always fit together.
        Left and Right slide it to its next place; past the side, they move it to the next display that way, onto the facing side, and from the last display around to the first, as Windows does.
        Down and Up make it the bottom or top quarter, as Windows does, then slide it the same way.
        Along a display's short side, the height on a landscape display, only halves and thirds count by default, since fourths are too thin there, so a half moves straight between top and bottom.
        Plain arrows move the window, and Shift with an arrow resizes it: one size bigger or smaller, snapped into the place that size fits that overlaps it most, ties going toward the arrow.
        Toward the side it hugs it shrinks and away from it it grows; a window as wide or tall as the display shrinks toward the arrow, and one in the middle grows, so a middle third becomes the middle half.
        Settings can add sixths or fourths, or leave out fourths or thirds, separately along the display's long and short side; halves and full are always there.
        Outside zone mode, Win + Up and Down maximize and restore, and Win + Shift + Left and Right stay Windows' own, moving windows between displays.

        ARRANGE YOUR WINDOWS
        Win + Backspace minimizes the active window; focus stays on that display while it has windows left, then moves to the next display.
        Win + Shift + Backspace brings back the windows it minimized, newest first.

        BETTER WINDOWS KEYS
        Windows' own keys work as you know them, with fewer surprises.
        Win + M, Win + Home and Win + D take Shift to bring back what they minimized, however much you do in between.
        They act on your display only, except Win + D, which reaches every display, and focus stays on your display.
        Win + Up maximizes the window, then steps to the upper and lower half.
        Win + Down takes it back to normal size, out of maximized or fullscreen, a zone, a half or a stretch; it never minimizes.
        Win + Shift + Up stretches the window to the full height of the display and back, and Win + Shift + Down to the full width and back; each undoes only its own direction. A maximized window is already both, so they only say so.
        A cascade window keeps its place in its cascade while it's maximized, minimized, in a zone, a half or a stretch, and Win + Down puts it back there.

        FOCUS, STACKS AND FULLSCREEN
        Win + PgDn and PgUp step focus through every window on screen in reading order: displays left to right, columns left to right, top before bottom, and outline the window they reach; double-tap Caps to outline where you are.
        A stack of overlapping windows counts once, as its front window.
        Move a window onto its nearest neighbor to stack it in front.
        Win + Shift + PgDn brings forward the next window stacked with the active one, and Win + Shift + PgUp the previous one.
        Layout actions exit F11 fullscreen before repositioning a window.
        Win + Enter shows the next maximized or fullscreen window on your display, minimized or not, and minimizes the others there, so one big window is out at a time; add Shift to go back.
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
