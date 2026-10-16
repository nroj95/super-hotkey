; Release regressions use inert callbacks, temporary settings and test-owned windows.
class SuiteReleaseChecks {
    static calls := 0

    static Run() {
        this.PowerCancellation()
        this.LargeDebugLog()
        this.HoldToSkipPlacement()
        this.CascadeLaunchMonitors()
        this.DeferredInputsAndSessions()
        this.WindowSizingAndCloaking()
        this.FocusTabDpi()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static LargeDebugLog() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-large-log")
        app.ui := SuiteInterface(app)
        try {
            ; A full-size verbose log must not exceed the native Edit control limit.
            line := StrReplace(Format("{:1024}", "log entry"), " ", ".") "`n"
            fixture := ""
            Loop 1500
                fixture .= line
            FileAppend(fixture "recent-tail-marker`n", SuiteState.Log.path, "UTF-8-RAW")
            this.Assert(FileGetSize(SuiteState.Log.path) > 1000000,
                "debug viewer regression uses a large disposable log")
            app.ui.OpenLog()
            preview := app.ui.windows["log"]["log"].Value
            this.Assert(StrLen(preview) < 26000 && InStr(preview, "recent-tail-marker"),
                "large debug log opens with a bounded recent preview")
            SuiteState.Log.Write("Core", "refresh-tail-marker")
            app.ui.RefreshLog()
            refreshed := app.ui.windows["log"]["log"].Value
            this.Assert(StrLen(refreshed) < 26000 && InStr(refreshed, "refresh-tail-marker"),
                "refreshing a large log remains bounded and shows newest entries")
            this.Assert(StrLen(SuiteState.Log.Read()) > 1000000,
                "preview does not truncate the full log on disk")
        }
        finally app.ui.CloseAll()
    }

    static CascadeLaunchMonitors() {
        global cascade_displays, cascade_launch_hint, new_window_focus_timeout_ms
        global cascade_hold_to_skip_key, pending_windows, handled_windows
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
            cascade_displays[sourceMonitor] := {device: MonitorGetName(sourceMonitor)}
            this.Assert(GetTargetMonitor(target.Hwnd, source.Hwnd, 987, &reason) = sourceMonitor
                && reason = "source-window", "a real source takes priority over the launch pointer")
            this.Assert(GetTargetMonitor(target.Hwnd, target.Hwnd, 987, &reason) = 987
                && reason = "launch-pointer", "a new window cannot select its own remembered monitor as its source")
            WinMinimize(source.Hwnd)
            this.Assert(GetCascadeSourceMonitor(source.Hwnd) = sourceMonitor,
                "a minimized source retains its restored monitor")
            WinRestore(source.Hwnd)

            cascade_displays := Map(1, {device: "left"}, 2, {device: "right"})
            hint := {tick: A_TickCount, monitor_device: "right"}
            cascade_launch_hint := hint
            context := {hint: hint}
            this.Assert(TakeCascadeTaskbarMonitor(target.Hwnd, context) = 2,
                "a fresh taskbar launch selects the clicked display")
            this.Assert(!TakeCascadeTaskbarMonitor(source.Hwnd, context),
                "one taskbar click cannot redirect a second new window")
            this.Assert(!GetHandledWindowReshowIntent(source.Hwnd),
                "a consumed new-window click cannot retarget an existing window")
            hint := {tick: A_TickCount - new_window_focus_timeout_ms - 1, monitor_device: "right"}
            cascade_launch_hint := hint
            this.Assert(!TakeCascadeTaskbarMonitor(target.Hwnd, {hint: hint}),
                "an expired taskbar click cannot override a later launch")
            hint := {tick: A_TickCount, monitor_device: "right"}
            this.Assert(!TakeCascadeTaskbarMonitor(target.Hwnd, {hint: hint}),
                "a replaced launch context cannot redirect a window")
            cascade_launch_hint := hint
            hint.reshow_hwnd := source.Hwnd
            this.Assert(!TakeCascadeTaskbarMonitor(target.Hwnd, {hint: hint}),
                "an existing-window re-show owns its taskbar click")
            cascade_launch_hint := {tick: A_TickCount, monitor_device: "removed"}
            this.Assert(!TakeCascadeTaskbarMonitor(target.Hwnd, {hint: cascade_launch_hint})
                && !cascade_launch_hint.HasOwnProp("placement_hwnd"),
                "a removed taskbar display is not silently replaced by its old index")
            this.Assert(!TakeCascadeTaskbarMonitor(target.Hwnd, 0),
                "keyboard launches need no taskbar context")
            observer := InputHook("V L0")
            hint := {tick: A_TickCount, monitor_device: "right", key_observer: observer}
            cascade_launch_hint := hint
            CancelCascadeTaskbarPlacementIntent(observer)
            this.Assert(hint.HasOwnProp("placement_cancelled")
                && !TakeCascadeTaskbarMonitor(target.Hwnd, {hint: hint}),
                "a later keyboard launch cancels an unused taskbar monitor hint")
            newerObserver := InputHook("V L0")
            cascade_launch_hint := {tick: A_TickCount, monitor_device: "right", key_observer: newerObserver}
            CancelCascadeTaskbarPlacementIntent(observer)
            this.Assert(!cascade_launch_hint.HasOwnProp("placement_cancelled"),
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
            cascade_hold_to_skip_key := "Disabled"
            app.dryRun := false
            QueueWindowPlacement(target.Hwnd, source.Hwnd)
            captured := pending_windows[target.Hwnd]
            this.Assert(captured.monitor_device = MonitorGetName(sourceMonitor)
                && captured.monitor_reason = "source-window",
                "discovery snapshots the source display before delayed placement")
            SuiteSizeGrip.Detach(source)
            source.Destroy()
            this.Assert(ResolveCascadePlacementMonitor(captured, 987) = sourceMonitor,
                "closing the source cannot change an already queued destination")
            pending_windows.Clear()

            ; Simulate a successful first placement. The existing ignore marker
            ; is removed only from this fixture, never from a personal window.
            DllCall("RemovePropW", "ptr", target.Hwnd, "str", "nroj.WindowCascade.Ignore", "ptr")
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
            CancelNewWindowFocus()
            try SuiteSizeGrip.Detach(source)
            try source.Destroy()
            SuiteSizeGrip.Detach(target)
            target.Destroy()
            SetTimer(RunQueuedFocusCornerUpdate, 0)
            Critical(previousCritical)
        }
    }

    static HoldToSkipPlacement() {
        global cascade_hold_to_skip_key, cascade_hold_to_skip_choice
        global pending_windows, known_windows, startup_windows
        previousKey := cascade_hold_to_skip_key
        previousChoice := cascade_hold_to_skip_choice
        app := SuiteApplication(true, SuiteChecks.directory "\release-hold-skip")
        try {
            InitializeCascadeState()
            this.Assert(cascade_hold_to_skip_key = "CapsLock",
                "CapsLock is the default hold-to-skip placement key")
            app.Settings.WritePreferences("window-cascade", Map(
                "Controls", Map("HoldToSkipKey", "Pause")))
            InitializeCascadeState()
            this.Assert(cascade_hold_to_skip_key = "Pause",
                "Pause hold-to-skip choice survives settings reload")
            app.Settings.WritePreferences("window-cascade", Map(
                "Controls", Map("HoldToSkipKey", "Disabled", "HoldToSkipChoice", "Pause")))
            InitializeCascadeState()
            this.Assert(cascade_hold_to_skip_key = "Disabled"
                && cascade_hold_to_skip_choice = "Pause"
                && !IsCascadeHoldToSkipActive(),
                "disabled hold-to-skip preserves the previous Pause selection")

            hwnd := 987654321
            request := {pid: 0}
            pending_windows[hwnd] := request
            this.Assert(!SkipPendingCascadePlacement(hwnd, request, false)
                && pending_windows.Has(hwnd),
                "an unheld skip key leaves queued placement available")
            this.Assert(!SkipPendingCascadePlacement(hwnd, {pid: 0}, true)
                && pending_windows.Has(hwnd),
                "a stale placement request cannot claim a new window")
            this.Assert(SkipPendingCascadePlacement(hwnd, request, true)
                && !pending_windows.Has(hwnd)
                && known_windows.Has(hwnd) && startup_windows.Has(hwnd),
                "a held skip key permanently excludes the queued window")
        }
        finally {
            cascade_hold_to_skip_key := previousKey
            cascade_hold_to_skip_choice := previousChoice
            if pending_windows.Has(987654321)
                pending_windows.Delete(987654321)
            if known_windows.Has(987654321)
                known_windows.Delete(987654321)
            if startup_windows.Has(987654321)
                startup_windows.Delete(987654321)
        }
    }

    static PowerCancellation() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-power")
        app.InitializeCatalog()
        manager := app.manager
        previousCritical := Critical("On")
        try {
            manager.SetPaused(true)
            manager.Start()
            app.power.Start()
            power := app.power
            ; Exercise dispatch without registering active input or emitting effects.
            power.DefineProp("CanDispatch", {Call: (self, actionId) => !self.stopping})
            power.DefineProp("InputsReleased", {Call: (self, event) => true})
            event := {actionId: "power-hotkey.system.sleep", slot: 1,
                phase: "down", foregroundHwnd: 0, layer: "normal",
                key: "F24", binding: "F24", modifiers: 0, oneShot: false}
            token := event.actionId "|1"
            power.Dispatch(event)
            this.Assert(power.pending.Count = 1, "Power-Up Utilities queues a test press")
            event.phase := "cancel"
            power.Dispatch(event)
            power.CheckPending()
            this.Assert(!power.pending.Count && !IsObject(power.activeJob),
                "cancelling a power command discards it rather than completing it")

            event.phase := "down"
            power.Dispatch(event)
            event.phase := "up"
            power.Dispatch(event)
            job := power.pending[token]
            this.Assert(job.completed, "a genuine release still completes a utility press")
            generation := app.inputGeneration
            manager.Apply(manager.GetConfiguration())
            this.Assert(!power.pending.Count && app.inputGeneration > generation
                && !power.JobValid(job), "reconfiguration invalidates released but unexecuted utilities")

            event.phase := "down"
            power.Dispatch(event)
            event.phase := "up"
            power.Dispatch(event)
            job := power.pending[token]
            power.CheckPending()
            this.Assert(power.activeJob = job, "an eligible test utility can reach its deferred worker")
            power.CancelWork()
            power.RunJob(job)
            SetTimer(job.worker, 0)
            this.Assert(!IsObject(power.activeJob)
                && !InStr(SuiteState.Log.Read(), "dry run: " event.actionId),
                "cancellation also expires a worker already scheduled for execution")

            manager.gated := false
            event.phase := "down"
            power.Dispatch(event)
            manager.SetPaused(true)
            this.Assert(!power.pending.Count, "closing the input gate cancels module-owned work")
        }
        finally {
            app.Stop("test")
            Critical(previousCritical)
        }
    }

    static DeferredInputsAndSessions() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-sessions")
        ; No module startup and no bound keys: only the lifecycle state is exercised.
        app.manager := SuiteReleaseInputGate()
        app.dryRun := false
        pad := SuiteReleasePad()
        previousCritical := Critical("On")
        try {
            this.calls := 0
            callback := (*) => this.calls += 1
            generation := app.inputGeneration
            app.RunInput(generation, callback)
            this.Assert(this.calls = 1, "a current deferred input can execute")
            app.CancelInputs()
            app.RunInput(generation, callback)
            this.Assert(this.calls = 1, "an expired callback cannot replay after inputs resume")
            app.manager.gated := true
            app.RunInput(app.inputGeneration, callback)
            this.Assert(this.calls = 1, "deferred callbacks respect a closed input gate")
            app.manager.gated := false

            pad.QueueCommand("new", app.inputGeneration)
            app.CancelInputs()
            pad.ProcessCommands()
            this.Assert(!pad.executed.Length, "Paper Pad expires queued hotkey commands before execution")
            app.manager.gated := true
            pad.QueueCommand("save")
            pad.ProcessCommands()
            this.Assert(pad.executed.Length = 1 && pad.executed[1] = "save",
                "Paper Pad direct save requests survive the hotkey gate")
            app.manager.gated := false
            pad.QueueCommand("new", app.inputGeneration)
            pad.ProcessCommands()
            this.Assert(pad.executed.Length = 2 && pad.executed[2] = "new",
                "current Paper Pad hotkey requests remain usable")

            app.SessionEvent(7)
            this.Assert(app.sessionLocked && app.manager.gated && !IsCascadeEnabled(),
                "locking the session pauses hotkeys and automatic window management")
            app.PowerEvent(0x12)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(app.sessionLocked && !app.systemSuspended && app.manager.gated
                && !IsCascadeEnabled(), "automatic power resume cannot unlock the input gate")
            app.SessionEvent(8)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(!app.sessionLocked && !app.manager.gated && IsCascadeEnabled(),
                "unlocking restores input after all system pause reasons clear")
            app.SetSuspended(true)
            app.SessionEvent(7)
            app.SessionEvent(8)
            SetTimer(app.resumeCallback, 0)
            app.ResumeInputs()
            this.Assert(app.suspended && app.manager.gated && !IsCascadeEnabled(),
                "unlock never overrides explicit tray suspension")
            app.SetSuspended(false)
            app.PowerEvent(4)
            this.Assert(app.systemSuspended && app.manager.gated && !IsCascadeEnabled(),
                "a fresh power suspend closes the gate again")
        }
        finally {
            SetTimer(app.resumeCallback, 0)
            SetTimer(pad.process_commands_callback, 0)
            app.manager := 0
            app.dryRun := true
            Critical(previousCritical)
        }
    }

    static WindowSizingAndCloaking() {
        window := SuiteGui("+Resize +E0x1", "Release sizing test")
        try {
            SuiteShowCentered(window, 1600, 1200, 0, true)
            rect := Buffer(16, 0)
            DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
            monitor := GetMonitorForWindow(window.Hwnd)
            MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
            this.Assert(NumGet(rect, 0, "int") >= left && NumGet(rect, 4, "int") >= top
                && NumGet(rect, 8, "int") <= right && NumGet(rect, 12, "int") <= bottom,
                "fitted GUI frames stay within the selected work area")
            window.GetClientPos(, , &width, &height)
            unchanged := SuiteFitClientSize(window, width, height, right - left, bottom - top)
            this.Assert(Abs(unchanged.width - width) <= 1 && Abs(unchanged.height - height) <= 1,
                "fitting an already fitting client does not resize it again")
            smaller := SuiteFitClientSize(window, 100, 100, right - left, bottom - top)
            this.Assert(smaller.width = 100 && smaller.height = 100,
                "fitting preserves deliberately small windows")
            this.Assert(ScratchpadIsDialogWindow(window.Hwnd), "a visible test dialog can yield Paper Pad")
            cloaked := Buffer(4, 0)
            NumPut("uint", 1, cloaked)
            result := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int") ; DWMWA_CLOAK
            this.Assert(result = 0 && IsWindowCloaked(window.Hwnd), "the test owns its cloaked dialog")
            this.Assert(!ScratchpadIsDialogWindow(window.Hwnd),
                "a cloaked dialog on another desktop does not lower Paper Pad")
            NumPut("uint", 0, cloaked)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int")
        }
        finally {
            SuiteSizeGrip.Detach(window)
            window.Destroy()
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
}

class SuiteReleaseInputGate {
    running := true
    gated := false
    applying := false
    disposed := false

    SetPaused(paused) => this.gated := paused
}

class SuiteReleasePad extends ScratchpadController {
    __New() {
        this.busy := false
        this.command_queue := []
        this.executed := []
        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
    }

    ExecuteCommand(request) => this.executed.Push(request.name)
}
