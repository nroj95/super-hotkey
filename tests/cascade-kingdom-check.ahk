; Cascade Kingdom: policy, settings, launches, drop guides, focus tabs and adoption.
; Disposable preferences, dry-run inputs and test-owned windows only.
class CascadeChecks {
    static Run() {
        this.LiveCascadeSettings()
        this.CascadeOptInLaunch()
        this.CascadeLaunchMonitors()
        this.CascadeLaunchHandoff()
        this.FocusTabDpi()
        WW_RunWindowCommand(ObjBindMethod(this, "MaximizedAdoption"))
        this.Policy()
        this.Settings()
        this.Guides()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static Policy() {
        global cascade_gesture_key, cascade_target_display, cascade_displays, cascade_history
        global cascade_auto_placement_enabled, cascade_opt_in_intent, cascade_titlebar_click
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-policy")
        app.modules["cascade-kingdom"] := CascadeKingdomModule(app)
        previousCritical := Critical("On")
        try {
            for automatic in [false, true]
                for held in [false, true]
                    this.Assert(CascadeShouldLaunch(automatic, held) = (automatic != held),
                        "cascade launch override: automatic=" automatic ", held=" held)
            for key in ["CapsLock", "Pause"] {
                cascade_gesture_key := key
                layer := key = "Pause" ? "pause" : "caps"
                for moduleEnabled in [false, true] {
                    app.activeModules["secret-layers"] := moduleEnabled
                    for layerEnabled in [false, true] {
                        app.activeLayers[layer] := layerEnabled
                        this.Assert(CascadeGestureEnabled() = (moduleEnabled && layerEnabled),
                            "cascade gesture requires its module and selected layer: " key)
                    }
                }
                app.activeLayers[layer] := true
            }
            cascade_gesture_key := "CapsLock"
            app.activeModules["secret-layers"] := true
            cascade_displays := Map(1, {device: "left"}, 2, {device: "right"})
            this.Assert(ResolveCascadeDestination(2) = 2,
                "All displays retains the requested destination")
            this.Assert(!cascade_history.Count && HasCascadeDropDestination(1)
                && HasCascadeDropDestination(2),
                "empty cascades allow dropping onto either display")
            cascade_target_display := "right"
            this.Assert(ResolveCascadeDestination(1) = 2 && CascadeDisplayAllowed(2)
                && !CascadeDisplayAllowed(1),
                "a single display redirects adoption and excludes other drop zones")
            this.Assert(!HasCascadeDropDestination(1) && HasCascadeDropDestination(2),
                "an excluded display cannot remain a drag destination")
            this.Assert(ResolveCascadePlacementMonitor({monitor_device: "left"}, 1) = 2,
                "queued launches use the configured destination, not their source")
            cascade_displays := Map(1, {device: "right"}, 2, {device: "left"})
            this.Assert(ResolveCascadeDestination(2) = 1,
                "the selected destination follows device name through index changes")
            cascade_target_display := "disconnected"
            this.Assert(!ResolveCascadeDestination(1)
                && !ResolveCascadePlacementMonitor({monitor_device: "right"}, 1),
                "a disconnected selected display never redirects onto another screen")
            cascade_target_display := "right"
            cascade_auto_placement_enabled := false
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: true}
            this.Assert(CascadeTakeOptInMonitor(11, &reason) = 1
                && reason = "gesture-launch" && !IsObject(cascade_opt_in_intent),
                "a captured opt-in redirects once after the key is released")
            cascade_auto_placement_enabled := true
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: false}
            this.Assert(!CascadeTakeOptInMonitor(11, &reason)
                && reason = "gesture-opt-out" && !IsObject(cascade_opt_in_intent),
                "a captured opt-out suppresses both cascading and relocation")
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: false}
            app.activeLayers["caps"] := false
            this.Assert(CascadeTakeOptInMonitor(11) = 1 && !IsObject(cascade_opt_in_intent),
                "disabling the selected layer ignores its gesture but preserves automatic mode")
            cascade_opt_in_intent := {tick: A_TickCount, monitor_device: "left",
                source_hwnd: 10, cascade: true}
            cascade_titlebar_click := {hwnd: 10}
            app.CancelInputs()
            this.Assert(!IsObject(cascade_opt_in_intent) && !IsObject(cascade_titlebar_click),
                "input cancellation expires launch and caption gestures")
        }
        finally {
            InitializeCascadeState()
            Critical(previousCritical)
        }
    }

    static Settings() {
        global cascade_gesture_key, cascade_target_display, cascade_drop_guide_color_name
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-settings")
        cascade := CascadeKingdomModule(app)
        app.modules["cascade-kingdom"] := cascade
        app.modules["paper-pad"] := PaperPadModule(app)
        app.ui := SuiteInterface(app)
        try {
            choices := app.ui.DisplayChoices("Primary")
            this.Assert(choices.values.Length = MonitorGetCount()
                && choices.values[choices.selected] = MonitorGetName(MonitorGetPrimary()),
                "Paper Pad lists each display once and defaults to the actual primary display")
            for value in choices.values
                this.Assert(value != "Primary", "the duplicate primary-display alias is not a choice")
            all := app.ui.DisplayChoices("All", true)
            this.Assert(all.values.Length = MonitorGetCount() + 1
                && all.values[all.selected] = "All" && all.names[all.selected] = "All displays",
                "Cascade Kingdom adds exactly one All displays choice")
            missing := app.ui.DisplayChoices("disconnected", true)
            this.Assert(missing.values[missing.selected] = "disconnected"
                && InStr(missing.names[missing.selected], "unavailable"),
                "missing saved displays remain visible without silently changing the preference")
            app.ui.ShowModuleSettings("cascade-kingdom")
            window := app.ui.windows["settings:cascade-kingdom"]
            this.Assert(window["cascadeKey"].Text = "CapsLock"
                && window["activeColor"].Text = "Yellow"
                && window["inactiveColor"].Text = "White"
                && window["guideColor"].Text = "Pink"
                && focus_corner_active_slot_alpha = 255
                && focus_corner_inactive_slot_alpha = 128,
                "cascade settings default to Yellow/White/Pink and 50% inactive opacity")
            window["cascadeKey"].Choose("Pause")
            window["guideColor"].Choose("Cyan")
            window["autoCascade"].Value := true
            ; Use a real device, not the dropdown index, in the saved preference.
            window["display"].Choose(2)
            expectedDisplay := cascade.displayChoices[2]
            cascade.SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && IniRead(path, "Controls", "CascadeKey") = "Pause"
                && IniRead(path, "Controls", "Display") = expectedDisplay
                && IniRead(path, "DropGuides", "Color") = "Cyan",
                "Apply persists the cascade key, destination device and guide color")
            InitializeCascadeState()
            this.Assert(cascade_gesture_key = "Pause" && cascade_target_display = expectedDisplay
                && cascade_drop_guide_color_name = "Cyan",
                "cascade choices survive state initialization")
            app.Settings.ResetModulePreferences(Map("cascade-kingdom", cascade.resetSections))
            this.Assert(IniRead(path, "DropGuides", "Color", "missing") = "missing",
                "factory reset includes the new guide preference")
            InitializeCascadeState()
            app.ui.ShowModuleSettings("paper-pad")
            window := app.ui.windows["settings:paper-pad"]
            displays := app.modules["paper-pad"].displayChoices
            this.Assert(displays.Length = MonitorGetCount()
                && displays[window["display"].Value] = MonitorGetName(MonitorGetPrimary()),
                "the Paper Pad dropdown uses the deduplicated primary selection")
        }
        finally app.ui.CloseAll()
    }

    static LiveCascadeSettings() {
        global cascade_auto_placement_enabled
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        global focus_corner_active_slot_color, focus_corner_inactive_slot_color
        global cascade_history
        app := SuiteApplication(true, SuiteChecks.directory "\live-cascade-settings")
        app.InitializeCatalog()
        manager := app.manager
        previous := {autoCascade: cascade_auto_placement_enabled,
            visible: focus_corner_visible,
            activeName: focus_corner_active_slot_color_name,
            inactiveName: focus_corner_inactive_slot_color_name,
            activeColor: focus_corner_active_slot_color,
            inactiveColor: focus_corner_inactive_slot_color}
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowModuleSettings("cascade-kingdom")
            settings := app.ui.windows["settings:cascade-kingdom"]
            expectedAuto := !previous.autoCascade
            settings["autoCascade"].Value := expectedAuto
            expectedVisible := !previous.visible
            activeName := previous.activeName = "Pink" ? "Green" : "Pink"
            inactiveName := previous.inactiveName = "Blue" ? "Grey" : "Blue"
            settings["tabs"].Value := expectedVisible
            settings["activeColor"].Choose(activeName)
            settings["inactiveColor"].Choose(inactiveName)
            existingHistorySize := cascade_history.Count
            this.Assert(app.ui.pageFooters[settings.Hwnd].buttons[1].button.Text = "Apply",
                "Cascade Kingdom Settings use Apply without restart")
            app.modules["cascade-kingdom"].SaveSettings(app.ui)
            path := app.Settings.directory "\cascade-kingdom\settings.ini"
            this.Assert(!app.ui.windows.Has("settings:cascade-kingdom")
                && cascade_auto_placement_enabled = expectedAuto
                && focus_corner_visible = expectedVisible
                && focus_corner_active_slot_color_name = activeName
                && focus_corner_inactive_slot_color_name = inactiveName
                && focus_corner_active_slot_color = focus_tab_color_presets[activeName]
                && focus_corner_inactive_slot_color = focus_tab_color_presets[inactiveName],
                "Cascade Kingdom applies automatic-cascade and focus-tab preferences without reload")
            this.Assert(IniRead(path, "Controls", "AutoCascadeNewWindows") = (expectedAuto ? "1" : "0")
                && IniRead(path, "FocusTabs", "Visible") = (expectedVisible ? "1" : "0")
                && IniRead(path, "FocusTabs", "ActiveSlotColor") = activeName
                && IniRead(path, "FocusTabs", "InactiveSlotColor") = inactiveName,
                "Cascade Kingdom persists its automatic-cascade toggle and focus-tab preferences")
            this.Assert(cascade_history.Count = existingHistorySize,
                "applying Cascade Kingdom preferences preserves in-memory cascade history")
        }
        finally {
            cascade_auto_placement_enabled := previous.autoCascade
            focus_corner_visible := previous.visible
            focus_corner_active_slot_color_name := previous.activeName
            focus_corner_inactive_slot_color_name := previous.inactiveName
            focus_corner_active_slot_color := previous.activeColor
            focus_corner_inactive_slot_color := previous.inactiveColor
            if IsObject(app.ui)
                app.ui.CloseAll()
            manager.Stop()
        }
    }

    static CascadeOptInLaunch() {
        global cascade_opt_in_intent, cascade_auto_placement_enabled
        global cascade_launch_hint, cascade_displays, new_window_focus_timeout_ms
        global pending_windows, known_windows, startup_windows
        app := SuiteApplication(true, SuiteChecks.directory "\release-opt-in")
        try {
            InitializeCascadeState()
            this.Assert(!CascadeIsOptInIntentFresh(0) && !cascade_auto_placement_enabled,
                "normal launches default to no cascading")
            cascade_auto_placement_enabled := true
            this.Assert(CascadeTakeOptInMonitor(987654321, &reason) = SuiteWorkingMonitor.Get(987654321)
                && reason = "automatic-working-monitor",
                "optional automatic cascading targets the working monitor, not the pointer")
            ; A taskbar click picks its own display, here another one when available.
            cascade_displays := Map()
            loop MonitorGetCount()
                cascade_displays[A_Index] := {device: MonitorGetName(A_Index)}
            working := SuiteWorkingMonitor.Get(987654321)
            clicked := 0, clickedDevice := ""
            for index, display in cascade_displays
                if !clicked || index != working
                    clicked := index, clickedDevice := display.device
            cascade_launch_hint := {tick: A_TickCount, monitor_device: clickedDevice}
            this.Assert(CascadeTakeOptInMonitor(987654321, &reason) = clicked
                && reason = "automatic-taskbar-click",
                "a fresh taskbar click chooses the display of the window it launches")
            cascade_launch_hint.placement_cancelled := true
            this.Assert(CascadeTakeOptInMonitor(987654321, &reason) = working
                && reason = "automatic-working-monitor",
                "a key typed after the taskbar click returns the choice to the working monitor")
            cascade_launch_hint := {tick: A_TickCount - new_window_focus_timeout_ms - 1,
                monitor_device: clickedDevice}
            this.Assert(CascadeTakeOptInMonitor(987654321, &reason) = working,
                "an expired taskbar click no longer chooses the display")
            cascade_launch_hint := 0
            cascade_auto_placement_enabled := false
            intent := {tick: A_TickCount, monitor_device: "unused", source_hwnd: 98765}
            this.Assert(CascadeIsOptInIntentFresh(intent)
                && !CascadeIsOptInIntentFresh({tick: A_TickCount - 8001}),
                "Caps launch intents expire without being reused")
            this.Assert(CascadeIsSecondCaptionClick(
                {hwnd: 42, pid: 8, x: 100, y: 150, tick: 200},
                42, 8, 102, 151, 260, 500, 4, 4)
                && !CascadeIsSecondCaptionClick(
                    {hwnd: 42, pid: 8, x: 100, y: 150, tick: 200},
                    43, 8, 102, 151, 260, 500, 4, 4)
                && !CascadeIsSecondCaptionClick(
                    {hwnd: 42, pid: 8, x: 100, y: 150, tick: 200},
                    42, 8, 102, 151, 801, 500, 4, 4),
                "title-bar adoption requires two timely clicks on the same window")
            this.Assert(CascadeWasMaximizeRestore(0, 1)
                && CascadeWasMaximizeRestore(1, 0)
                && !CascadeWasMaximizeRestore(0, 0)
                && !CascadeWasMaximizeRestore(1, 1)
                && !CascadeWasMaximizeRestore(0, -1)
                && !CascadeWasMaximizeRestore(-1, 0),
                "custom title-bar adoption requires a genuine maximize/restore transition")
            this.Assert(SuiteCloseWindow.Decision(true, false) = "preserve"
                && SuiteCloseWindow.Decision(true, true) = "preserve"
                && SuiteCloseWindow.Decision(false, true) = "wait"
                && SuiteCloseWindow.Decision(false, false) = "recover",
                "closing preserves genuine focus and recovers only after closing")
            this.Assert(SuiteCloseWindow.ShouldHighlight("preserve", false)
                && !SuiteCloseWindow.ShouldHighlight("preserve", true)
                && !SuiteCloseWindow.ShouldHighlight("wait", true)
                && !SuiteCloseWindow.ShouldHighlight("recover", false),
                "closing highlights native focus only after the close completes")
            clip := (rect) => (clipped := SuiteFocusBorder.Clip(rect, [0, 0, 1920, 1080]))
                ? clipped[1] "," clipped[2] "," clipped[3] "," clipped[4] : "hidden"
            this.Assert(clip([-10, 100, 12, 300]) = "0,100,2,300"
                && clip([1918, 100, 12, 300]) = "1918,100,2,300"
                && clip([1920, 100, 12, 300]) = "hidden"
                && clip([90, -10, 500, 12]) = "90,0,500,2"
                && clip([90, 90, 500, 12]) = "90,90,500,12",
                "the focus border keeps only the part on its window's display")
            this.Assert(SuiteFocusBorder.durationMs = 1500
                && SuiteFocusBorder.thickness = 12
                && SuiteFocusBorder.overlap = 2
                && SuiteFocusBorder.CanHide("wonder-windows", "wonder-windows")
                && !SuiteFocusBorder.CanHide("wonder-windows", "close-window")
                && SuiteFocusBorder.CanHide("", "close-window"),
                "shared core border preserves appearance and respects module ownership")
            hwnd := 987654321
            RememberUnmanagedCascadeWindow(hwnd)
            this.Assert(known_windows.Has(hwnd) && startup_windows.Has(hwnd)
                && !pending_windows.Has(hwnd),
                "normal windows stay outside the cascade")
        }
        finally {
            cascade_opt_in_intent := 0
            cascade_launch_hint := 0
            cascade_auto_placement_enabled := false
            for windows in [known_windows, startup_windows]
                if windows.Has(987654321)
                    windows.Delete(987654321)
        }
    }

    static CascadeLaunchMonitors() {
        global cascade_displays, cascade_launch_hint, new_window_focus_timeout_ms
        global cascade_opt_in_intent, pending_windows, handled_windows
        global placement_reservations, placement_stabilization_generations
        global placement_startup_confirmation_ms, placement_stabilize_retry_ms
        app := SuiteApplication(true, SuiteChecks.directory "\release-launch-monitors")
        InitializeCascadeState()
        source := SuiteGui("+Resize", "Launch monitor source")
        target := SuiteGui("+Resize", "Launch monitor target")
        previousCritical := Critical("On")
        try {
            SuiteShowCentered(source, 320, 240)
            SuiteShowCentered(target, 340, 260)
            sourceMonitor := GetMonitorForWindow(source.Hwnd)
            WinMinimize(source.Hwnd)
            this.Assert(WindowMonitorIndex(source.Hwnd) = sourceMonitor,
                "a minimized source retains its restored monitor")
            WinRestore(source.Hwnd)

            cascade_displays := Map(1, {device: "left"}, 2, {device: "right"})
            observer := InputHook("V L0")
            hint := {tick: A_TickCount, monitor_device: "right", key_observer: observer}
            cascade_launch_hint := hint
            CancelCascadeTaskbarPlacementIntent(observer)
            this.Assert(hint.HasOwnProp("placement_cancelled")
                && !GetHandledWindowReshowIntent(source.Hwnd),
                "a later keyboard launch cancels an unused taskbar hint")
            newerObserver := InputHook("V L0")
            cascade_launch_hint := {tick: A_TickCount, monitor_device: "right", key_observer: newerObserver}
            newerObserver.Start()
            CancelCascadeTaskbarPlacementIntent(observer)
            this.Assert(newerObserver.InProgress && !cascade_launch_hint.HasOwnProp("placement_cancelled"),
                "a stale key observer cannot cancel a newer taskbar click")
            CancelNewWindowFocus()
            this.Assert(!IsObject(cascade_launch_hint) && !newerObserver.InProgress,
                "cancelling launch work releases its short-lived key observer")

            request := {monitor_device: "right"}
            this.Assert(ResolveCascadePlacementMonitor(request, 1) = 2,
                "the captured display wins over later pointer or source choices")
            cascade_displays := Map(1, {device: "right"}, 2, {device: "left"})
            this.Assert(ResolveCascadePlacementMonitor(request, 2) = 1,
                "queued placement follows display identity through an index reorder")
            cascade_displays.Delete(1)
            this.Assert(ResolveCascadePlacementMonitor(request, 2) = MonitorGetPrimary(),
                "a removed destination falls back to the primary display, not the stale index")

            this.Assert(ShouldCorrectCascadeMonitorPromptly(false, 1, 2, 0),
                "equal-DPI wrong-monitor placement gets a prompt correction")
            this.Assert(ShouldCorrectCascadeMonitorPromptly(false, 2, 1, 2)
                && !ShouldCorrectCascadeMonitorPromptly(false, 2, 1, 3),
                "prompt monitor corrections stop after three attempts")
            this.Assert(!ShouldCorrectCascadeMonitorPromptly(false, 2, 2, 0)
                && !ShouldCorrectCascadeMonitorPromptly(false, 0, 2, 0),
                "same-monitor or unknown geometry retains the passive backoff")
            this.Assert(ShouldCorrectCascadeMonitorPromptly(true, 2, 2, 0),
                "DPI transitions retain their prompt correction path")
            this.Assert(GetCascadeConfirmationDelay(true, false, 0) = placement_startup_confirmation_ms
                && GetCascadeConfirmationDelay(false, false, 1) = 0,
                "a matched new window gets exactly one trailing startup check")
            this.Assert(GetCascadeConfirmationDelay(false, true, 0) = placement_stabilize_retry_ms
                && GetCascadeConfirmationDelay(false, true, 1) = 0,
                "ordinary DPI transfer confirmation remains bounded")

            ; Exercise real discovery without hooks or a chance for queued timers
            ; to move anything. Only these test-owned windows can enter the queue.
            cascade_displays := Map(sourceMonitor, {device: MonitorGetName(sourceMonitor)})
            cascade_launch_hint := 0
            cascade_opt_in_intent := {tick: A_TickCount,
                monitor_device: MonitorGetName(sourceMonitor), source_hwnd: source.Hwnd, cascade: true}
            app.dryRun := false
            QueueWindowPlacement(target.Hwnd, source.Hwnd)
            captured := pending_windows[target.Hwnd]
            this.Assert(captured.monitor_device = MonitorGetName(sourceMonitor)
                && captured.monitor_reason = "gesture-launch" && !IsObject(cascade_opt_in_intent),
                "discovery consumes a one-shot opt-in and snapshots its display")
            SuiteSizeGrip.Detach(source)
            source.Destroy()
            this.Assert(ResolveCascadePlacementMonitor(captured, 987) = sourceMonitor,
                "closing the source cannot change an already queued destination")
            pending_windows.Clear()

            ; Simulate a successful first placement. The existing ignore marker
            ; is removed only from this fixture, never from a personal window.
            DllCall("RemovePropW", "ptr", target.Hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr")
            GetVisibleWindowBounds(target.Hwnd, &x, &y, &width, &height)
            handled_windows[target.Hwnd] := true
            placement_stabilization_generations[target.Hwnd] := 101
            placement_reservations[target.Hwnd] := Map("monitor", sourceMonitor, "x", x, "y", y)
            StabilizePlacedWindow(target.Hwnd, x, y, width, height, 101, 500, 0, 0, 0, true)
            this.Assert(placement_stabilization_generations.Has(target.Hwnd),
                "the first geometry match keeps the startup guard alive")
            StabilizePlacedWindow(target.Hwnd, x, y, width, height, 101, 1500, 0, 0, 1, false)
            this.Assert(!placement_stabilization_generations.Has(target.Hwnd)
                && !placement_reservations.Has(target.Hwnd),
                "the final matching startup check releases its reservation")
            StabilizePlacedWindow(target.Hwnd, x + 100, y + 100, width, height, 101, 500)
            GetVisibleWindowBounds(target.Hwnd, &afterX, &afterY, &afterWidth, &afterHeight)
            this.Assert(afterX = x && afterY = y && afterWidth = width && afterHeight = height,
                "an expired startup callback cannot move a window")
        }
        finally {
            app.stopping := true
            app.dryRun := true
            pending_windows.Clear()
            cascade_opt_in_intent := 0
            CancelNewWindowFocus()
            try SuiteSizeGrip.Detach(source)
            try source.Destroy()
            SuiteSizeGrip.Detach(target)
            target.Destroy()
            SetTimer(RunQueuedFocusCornerUpdate, 0)
            Critical(previousCritical)
        }
    }

    ; Firefox hands a taskbar launch's foreground to its hidden remote window
    ; and may never activate the new one; that hand-off still proves the launch.
    static CascadeLaunchHandoff() {
        global cascade_launch_hint, current_foreground_hwnd, new_window_focus_request
        app := SuiteApplication(true, SuiteChecks.directory "\release-launch-handoff")
        InitializeCascadeState()
        target := SuiteGui(, "Launch hand-off target")
        helper := SuiteGui(, "Launch hand-off helper")
        sibling := SuiteGui(, "Launch hand-off sibling")
        previousForeground := current_foreground_hwnd
        try {
            sibling.Show("NA w200 h100")
            taskbar := WinExist("ahk_class Shell_TrayWnd")
            this.Assert(IsLaunchHandoffWindow(helper.Hwnd, target.Hwnd)
                && !IsLaunchHandoffWindow(sibling.Hwnd, target.Hwnd)
                && !IsLaunchHandoffWindow(target.Hwnd, target.Hwnd)
                && !IsLaunchHandoffWindow(taskbar, target.Hwnd)
                && !IsLaunchHandoffWindow(0, target.Hwnd),
                "only a hidden window of the new window's own app is a launch hand-off")
            this.Assert(IsLaunchSettleNoise(helper.Hwnd, target.Hwnd)
                && (!taskbar || IsLaunchSettleNoise(taskbar, target.Hwnd))
                && !IsLaunchSettleNoise(sibling.Hwnd, target.Hwnd),
                "launch settling ignores the shell and the hand-off, not a visible app window")

            cascade_launch_hint := 0
            current_foreground_hwnd := helper.Hwnd
            context := CaptureNewWindowFocusContext(target.Hwnd)
            this.Assert(IsObject(context) && context.proved_foreground && !IsObject(context.hint),
                "a hand-off as the latest foreground proves a launch")
            current_foreground_hwnd := sibling.Hwnd
            this.Assert(!CaptureNewWindowFocusContext(target.Hwnd),
                "a visible window of the same app proves nothing")
            cascade_launch_hint := {tick: A_TickCount, foreground: sibling.Hwnd}
            current_foreground_hwnd := helper.Hwnd
            context := CaptureNewWindowFocusContext(target.Hwnd)
            this.Assert(context.proved_foreground && context.foreground = sibling.Hwnd,
                "a taskbar launch keeps its source and gains the hand-off proof")

            app.dryRun := false
            this.Assert(IsCascadeEnabled(), "the hand-off fixture runs the live foreground rules")
            request := {hwnd: target.Hwnd, context: {foreground: sibling.Hwnd},
                saw_target_foreground: false, visual_synced: false}
            new_window_focus_request := request
            ObserveNewWindowForeground(helper.Hwnd)
            this.Assert(new_window_focus_request = request && request.saw_target_foreground,
                "the hand-off foreground event arms recovery instead of cancelling it")
            if taskbar {
                ObserveNewWindowForeground(taskbar)
                this.Assert(new_window_focus_request = request,
                    "the taskbar taking foreground back keeps recovery armed")
            }
            ObserveNewWindowForeground(sibling.Hwnd)
            this.Assert(!IsObject(new_window_focus_request),
                "a real switch after the hand-off still cancels recovery")
        }
        finally {
            app.stopping := true
            app.dryRun := true
            CancelNewWindowFocus()
            current_foreground_hwnd := previousForeground
            target.Destroy()
            helper.Destroy()
            sibling.Destroy()
        }
    }

    static FocusTabDpi() {
        global focus_corner_overlays
        app := SuiteApplication(true, SuiteChecks.directory "\release-focus-tabs")
        InitializeCascadeState()
        window := SuiteGui("+Resize", "Release focus-tab target")
        previousCritical := Critical("On")
        try {
            window.Show("NA w300 h200")
            app.dryRun := false
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(focus_corner_overlays.Has(window.Hwnd)
                && focus_corner_overlays[window.Hwnd].dpi = 144,
                "focus tabs use the DPI supplied by the validated rendering snapshot")
            overlay := focus_corner_overlays[window.Hwnd]
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 144)
            this.Assert(focus_corner_overlays[window.Hwnd] = overlay,
                "unchanged focus-tab rendering reuses its GUI")
            ShowFocusCornerOverlay(window.Hwnd, 100, 100, 300, 200, 96)
            this.Assert(overlay.dpi = 96, "a changed DPI snapshot updates the existing focus tab")
        }
        finally {
            DestroyFocusCornerOverlay(window.Hwnd)
            SuiteSizeGrip.Detach(window)
            window.Destroy()
            app.dryRun := true
            Critical(previousCritical)
        }
    }

    static Guides() {
        app := SuiteApplication(true, SuiteChecks.directory "\cascade-guide-tests")
        cascade := CascadeKingdomModule(app)
        MonitorGetWorkAreaPixels(MonitorGetPrimary(), &left, &top, &right, &bottom)
        slots := [[left + 30, top + 30], [left + 58, top + 54]]
        foreground := DllCall("GetForegroundWindow", "ptr")
        try {
            CascadeDropGuides.Show(slots, 96, "808080")
            this.Assert(CascadeDropGuides.windows.Length = 2, "one guide is created per visible slot")
            first := CascadeDropGuides.windows[1].Hwnd
            for window in CascadeDropGuides.windows {
                style := WinGetExStyle(window.Hwnd)
                this.Assert((style & 0x08000020) = 0x08000020
                    && WinGetTransparent(window.Hwnd) = 255 && IsIgnoredByCascade(window.Hwnd),
                    "drop guides are opaque, non-activating, click-through and excluded from adoption")
            }
            this.Assert(DllCall("GetForegroundWindow", "ptr") = foreground,
                "showing guides does not steal focus")
            region := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
            try {
                this.Assert(region && DllCall("GetWindowRgn", "ptr", first, "ptr", region, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 1, "int", 10, "int")
                    && DllCall("gdi32\PtInRegion", "ptr", region, "int", 10, "int", 1, "int")
                    && !DllCall("gdi32\PtInRegion", "ptr", region, "int", 10, "int", 10, "int"),
                    "guide regions contain only the top and left strokes")
            }
            finally {
                if region
                    DllCall("gdi32\DeleteObject", "ptr", region)
            }
            CascadeDropGuides.Show(slots, 96, "808080")
            this.Assert(CascadeDropGuides.windows[1].Hwnd = first,
                "unchanged drag guides reuse their windows")
            CancelCascadeWindowDrop()
            this.Assert(!DllCall("IsWindowVisible", "ptr", first, "int"),
                "cancelling a drag hides its guides immediately")
            CascadeDropGuides.Show(slots, 144, "00BCD4")
            this.Assert(CascadeDropGuides.windows[1].Hwnd = first,
                "DPI and color changes reuse the guide windows")
            cascade.Suspend()
            this.Assert(!DllCall("IsWindowVisible", "ptr", first, "int"),
                "suspension hides all drag guides")
            CascadeDropGuides.Destroy()
            this.Assert(!DllCall("IsWindow", "ptr", first, "int") && !CascadeDropGuides.windows.Length,
                "guide cleanup destroys every owned window")
        }
        finally CascadeDropGuides.Destroy()
    }

    static MaximizedAdoption() {
        global cascade_history, cascade_window_drag, pending_adoption_undo
        global cascade_displays
        app := SuiteApplication(true, SuiteChecks.directory "\maximized-adoption")
        InitializeCascadeState()
        window := SuiteGui("+Resize -DPIScale", "Maximized adoption fixture")
        previousCritical := Critical("On")
        try {
            ; Stay in dry run: no hooks, desktop discovery or real adoption.
            ; Only the test-owned window is restored/moved by the undo check.
            ; Populate display geometry without starting hooks or discovery.
            cascade_displays := ReadCascadeDisplays().displays
            window.Show("x60 y60 w320 h220")
            hwnd := window.Hwnd
            original := CaptureWindowPlacement(hwnd)
            WinMaximize(hwnd)
            WinActivate(hwnd)
            this.Assert(!!WinWaitActive(hwnd, , 1),
                "maximized adoption fixture owns foreground")
            this.Assert(ActiveWindowBlocksCascadeCommands()
                && !ActiveWindowBlocksCascadeCommands(true),
                "only explicit adoption bypasses the maximized-window command guard")
            cascade_window_drag := {}
            this.Assert(ActiveWindowBlocksCascadeCommands(true),
                "maximized adoption still respects an active native drag")
            cascade_window_drag := 0

            pending_adoption_undo := CaptureAdoptionUndoSnapshot(hwnd)
            this.Assert(IsObject(pending_adoption_undo)
                && IsObject(pending_adoption_undo["maximized_placement"]),
                "maximized adoption snapshots native placement before restoring")
            WinRestore(hwnd)
            WinMove(100, 100, 420, 280, hwnd)
            this.Assert(UndoPendingAdoption() && WinGetMinMax(hwnd) = 1,
                "adoption undo restores maximized state")
            restored := CaptureWindowPlacement(hwnd)
            sameRectangle := true
            for offset in [28, 32, 36, 40]
                sameRectangle := sameRectangle
                    && NumGet(original, offset, "int") = NumGet(restored, offset, "int")
            this.Assert(sameRectangle,
                "maximized adoption undo preserves the original normal restore rectangle")

            monitor := GetMonitorForWindow(hwnd)
            cascade_history := Map(monitor, [hwnd])
            WinRestore(hwnd)
            this.Assert(CascadeCanAdoptCaptionWindow(hwnd, 1),
                "a restored maximized member can be adopted from its captured caption gesture")
            this.Assert(!CascadeCanAdoptCaptionWindow(hwnd, 0),
                "ordinary managed title-bar double-clicks retain their existing behavior")
            cascade_history.Clear()
            this.Assert(CascadeCanAdoptCaptionWindow(hwnd, 0)
                && CascadeCanAdoptCaptionWindow(hwnd, 1),
                "unmanaged caption adoption accepts normal and maximized starting states")
            normalSnapshot := CaptureAdoptionUndoSnapshot(hwnd)
            this.Assert(IsObject(normalSnapshot) && !normalSnapshot["maximized_placement"],
                "normal-window adoption retains its existing geometry-only undo")

            WinSetStyle((WinGetStyle(hwnd) & ~0xC40000) | 0x80000000, hwnd)
            WinSetExStyle(WinGetExStyle(hwnd) & ~0x300, hwnd)
            WonderWindowsChecks.RefreshFrame(hwnd)
            WW_GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
            WinMove(left, top, right - left, bottom - top, hwnd)
            this.Assert(WW_IsNativeFullscreen(hwnd) && ActiveWindowBlocksCascadeCommands(true),
                "allowing maximized adoption does not bypass the fullscreen guard")
        }
        finally {
            CancelPendingAdoptionUndo()
            StopCascadeDisplays()
            InitializeCascadeState()
            try SuiteSizeGrip.Detach(window)
            window.Destroy()
            Critical(previousCritical)
        }
    }
}
