; Release regressions use inert callbacks, temporary settings and test-owned windows.
#Include "%A_ScriptDir%\tests\cascade-settings-check.ahk"
class SuiteReleaseChecks {
    static calls := 0

    static Run() {
        this.PowerCancellation()
        this.NativeNewPolicy()
        this.NativeSaveDelegation()
        this.LargeDebugLog()
        this.CascadeOptInLaunch()
        this.CascadeLaunchMonitors()
        this.WorkingMonitor()
        this.OversizedTile()
        this.CenteredNotices()
        this.DeferredInputsAndSessions()
        this.WindowSizingAndCloaking()
        this.PaperPadTopmostRestoration()
        this.PaperPadDialogOwnership()
        this.FocusTabDpi()
        SuiteHardeningChecks.Run()
        CascadeSettingsChecks.Run()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static NativeNewPolicy() {
        this.Assert(!PaperPadController.UntitledHasEdits(false, ""),
            "clean native New can be converted into a managed page")
        this.Assert(PaperPadController.UntitledHasEdits(true, "")
            && PaperPadController.UntitledHasEdits(false, "typed text"),
            "native New never replaces an edited untitled document")
    }

    static NativeSaveDelegation() {
        path := SuiteChecks.directory "\release-native-save.md"
        savedPath := SuiteChecks.directory "\release-native-save-as.md"
        FileAppend "original", path, "UTF-8-RAW"
        window := SuiteGui("+ToolWindow", "Paper Pad native Save As regression")
        pad := SuiteReleaseNativeSavePad(path, window.Hwnd)
        try {
            ; A previous disk version must not prevent native Save.
            FileDelete path
            FileAppend "native version", path, "UTF-8-RAW"
            pad.bridge.text := "native version plus new edits"
            pad.bridge.dirty := true
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") == pad.bridge.text,
                "native Save works without shortcut tracking")

            ; Notepad3 can reload an externally changed document.
            FileDelete path
            FileAppend "externally reloaded", path, "UTF-8-RAW"
            pad.bridge.text := "externally reloaded"
            pad.bridge.dirty := false
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") = "externally reloaded",
                "native reload becomes the current document")

            ; An unsuccessful native Save must not count as success.
            pad.bridge.text := "unsaved editor text"
            pad.bridge.dirty := true
            pad.bridge.suppress_save := true
            SuiteChecks.Rejects((*) => pad.SaveCurrentPage(false),
                "a failed native Save cannot be accepted")
            this.Assert(FileRead(path, "UTF-8") = "externally reloaded",
                "a failed native Save preserves the disk contents")

            pad.bridge.suppress_save := false
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") = "unsaved editor text",
                "native Save succeeds after a previous failure")

            ; A clean document can recover a paused autosave.
            pad.autosave_paused := true
            this.Assert(pad.ResumeAutosaveAfterCleanNativeSave(path)
                && !pad.autosave_paused,
                "clean native Save resumes autosave")

            pad.bridge.dirty := true
            pad.autosave_paused := true
            this.Assert(!pad.ResumeAutosaveAfterCleanNativeSave(path),
                "dirty documents do not falsely resume autosave")

            ; The watcher must adopt native Save As while autosave is paused.
            FileAppend "saved under a new name", savedPath, "UTF-8-RAW"
            pad.bridge.path := savedPath
            pad.bridge.text := "saved under a new name"
            pad.bridge.dirty := false
            pad.autosave_paused := true
            pad.SyncPageLock()
            this.Assert(!pad.autosave_paused && pad.current_path = savedPath
                && pad.page_lock_path = savedPath,
                "clean native Save As resumes autosave on the new page")

            pad.bridge.text := "new page edits"
            pad.bridge.dirty := true
            pad.last_verified_save_tick := A_TickCount - PaperPadController.AutosaveMaxMs
            pad.last_autosave_attempt_tick := A_TickCount - PaperPadController.AutosaveIdleMs
            pad.Autosave()
            this.Assert(FileRead(savedPath, "UTF-8") = "new page edits"
                && FileRead(path, "UTF-8") = "unsaved editor text",
                "recovered autosave writes the new page and leaves the original intact")
        }
        finally {
            window.Destroy()
            FileDelete path
            if FileExist(savedPath)
                FileDelete savedPath
        }
    }

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
            this.Assert(app.ui.ClearLogNow() && FileExist(SuiteState.Log.path ".old")
                && InStr(SuiteState.Log.Read(), "log cleared; previous log retained"),
                "debug hotkey clears a disposable log without a confirmation dialog")
        }
        finally app.ui.CloseAll()
    }

    ; Keyboard-only users never see a parked pointer choose a display.
    static WorkingMonitor() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-working-monitor")
        work := SuiteGui(, "Working monitor app")
        older := SuiteGui(, "Working monitor older app")
        passage := SuiteGui("+ToolWindow", "Working monitor shell surface")
        try {
            SuiteShowCentered(older, 320, 240)
            SuiteShowCentered(work, 320, 240)
            passage.Show("NoActivate w200 h100")
            workMonitor := WindowMonitorIndex(work.Hwnd)
            olderMonitor := WindowMonitorIndex(older.Hwnd)
            last := MonitorGetCount()
            MonitorGetPixels(last, &left, &top, &right, &bottom)
            press := {tick: A_TickCount, x: left + (right - left) // 2, y: top + (bottom - top) // 2}
            this.Assert(SuiteWorkingMonitor.IsWorkWindow(work.Hwnd)
                && !SuiteWorkingMonitor.IsWorkWindow(passage.Hwnd),
                "app windows are work windows; tool surfaces are passed through")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: work.Hwnd, click: 0}]) = workMonitor,
                "the active app window chooses its display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: passage.Hwnd, click: 0},
                {hwnd: older.Hwnd, click: 0}]) = olderMonitor,
                "a surface opened from the keyboard defers to the previous app window")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: passage.Hwnd, click: press},
                {hwnd: older.Hwnd, click: 0}]) = last,
                "a surface opened by a click chooses the clicked display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: work.Hwnd, click: 0},
                {hwnd: older.Hwnd, click: 0}], work.Hwnd) = olderMonitor,
                "a window being placed never chooses its own display")
            this.Assert(SuiteWorkingMonitor.Choose([{hwnd: 987654321, click: press}]) = MonitorGetPrimary()
                && SuiteWorkingMonitor.Choose([]) = MonitorGetPrimary(),
                "closed windows are skipped and the primary display is the last resort")
        }
        finally {
            for window in [work, older, passage]
                window.Destroy()
        }
    }

    ; Apps such as Discord refuse a quarter-screen tile. They must grow toward
    ; the middle of the display instead of past its edges.
    static OversizedTile() {
        global WW_layout_cycle_windows
        if !IsSet(WW_layout_cycle_windows)
            WW_InitializeState()
        app := SuiteApplication(true, SuiteChecks.directory "\release-oversized-tile")
        window := SuiteGui("+Resize -DPIScale", "Oversized tile target")
        try {
            window.Show("NA w300 h200")
            work_area := WW_GetLayoutWorkArea(window.Hwnd)
            for position, ratios in Map("top-right", [3, 1, 0, "top"], "bottom-right", [3, 1, 0, "bottom"],
                "bottom-left", [0, 1, 3, "bottom"]) {
                tile := WW_BuildRatioLayout(work_area, ratios, ratios[4])
                window.Opt("+MinSize" (tile[3] + 200) "x" (tile[4] + 150))
                minimum := WW_GetMinimumVisibleSize(window.Hwnd)
                this.Assert(minimum[1] >= tile[3] + 200 && minimum[2] >= tile[4] + 150,
                    "the app's minimum size is known before the " position " tile moves it")
                WW_ApplyTrackedLayout(window.Hwnd, "corner-" position, work_area, [tile], 1)
                rect := WW_GetWindowLayoutRectangle(window.Hwnd)
                this.Assert(rect[3] > tile[3] && rect[4] > tile[4]
                    && rect[1] >= work_area[1] - 2 && rect[2] >= work_area[2] - 2
                    && rect[1] + rect[3] <= work_area[3] + 2 && rect[2] + rect[4] <= work_area[4] + 2,
                    "an app larger than its " position " tile grows inward and stays on-screen")
            }
        }
        finally {
            SuiteWindowOwnership.Release(window.Hwnd, false)
            SuiteSizeGrip.Detach(window)
            window.Destroy()
        }
    }

    ; Keyboard users read notices in the middle of the working display.
    static CenteredNotices() {
        app := SuiteApplication(true, SuiteChecks.directory "\release-notices")
        try {
            SuiteNotice.Show("layer", "Caps held")
            SuiteNotice.Show("status", "Debug log copied", 150)
            layer := SuiteNotice.notices["layer"].window
            status := SuiteNotice.notices["status"].window
            layer.GetPos(&x, &y, &width, &height)
            status.GetPos(, &statusY)
            MonitorGetWorkArea(SuiteWorkingMonitor.Get(), &left, &top, &right, &bottom)
            this.Assert(Abs(x + width // 2 - (left + right) // 2) <= 2
                && Abs(y + height // 2 - (top + bottom) // 2) <= 2,
                "a notice is centered on the working display")
            this.Assert(statusY >= y + height,
                "a status notice stacks below the layer indicator")
            exStyle := WinGetExStyle(layer.Hwnd)
            this.Assert(DllCall("IsWindowVisible", "ptr", layer.Hwnd, "int")
                && (exStyle & 0x08080028) = 0x08080028 && !WinActive(layer.Hwnd),
                "notices are topmost, click-through and never take focus")
            SuiteNotice.Show("layer", "Pause - next key")
            this.Assert(SuiteNotice.notices["layer"].window != layer,
                "new notice text rebuilds the notice at its own size")
            ; Timers cannot interrupt a critical thread; let the expiry run.
            previousCritical := Critical("Off")
            Sleep 300
            Critical(previousCritical)
            this.Assert(!DllCall("IsWindowVisible", "ptr", status.Hwnd, "int"),
                "a timed notice hides itself")
            SuiteNotice.Hide("layer")
            this.Assert(!DllCall("IsWindowVisible", "ptr", SuiteNotice.notices["layer"].window.Hwnd, "int"),
                "hiding a notice removes it from the screen")
            ; Tap Pause, then F2: the one-shot indicator hides before the status shows.
            SuiteNotice.Show("status", "Debug log copied")
            SuiteNotice.notices["status"].window.GetPos(, &statusY, , &statusHeight)
            this.Assert(Abs(statusY + statusHeight // 2 - (top + bottom) // 2) <= 2,
                "a status notice takes the center when no indicator shows")
        }
        finally SuiteNotice.Destroy()
        this.Assert(!SuiteNotice.notices.Count, "notices release every window")
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

    static CascadeOptInLaunch() {
        global cascade_opt_in_intent, cascade_auto_placement_enabled
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
            this.Assert(WW_CloseFocusDecision(true, false) = "preserve"
                && WW_CloseFocusDecision(true, true) = "preserve"
                && WW_CloseFocusDecision(false, true) = "wait"
                && WW_CloseFocusDecision(false, false) = "recover",
                "closing preserves genuine focus and recovers only after closing")
            this.Assert(WW_ShouldHighlightCloseFocus("preserve", false)
                && !WW_ShouldHighlightCloseFocus("preserve", true)
                && !WW_ShouldHighlightCloseFocus("wait", true)
                && !WW_ShouldHighlightCloseFocus("recover", false),
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
                && !SuiteFocusBorder.CanHide("wonder-windows", "wonder-windows-close")
                && SuiteFocusBorder.CanHide("", "wonder-windows-close"),
                "shared core border preserves appearance and respects module ownership")
            hwnd := 987654321
            RememberUnmanagedCascadeWindow(hwnd)
            this.Assert(known_windows.Has(hwnd) && startup_windows.Has(hwnd)
                && !pending_windows.Has(hwnd),
                "normal windows stay outside the cascade")
        }
        finally {
            cascade_opt_in_intent := 0
            cascade_auto_placement_enabled := false
            known_windows.Delete(987654321)
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
            power := app.modules["power-up-utilities"]
            ; Exercise dispatch without registering active input or emitting effects.
            power.DefineProp("CanDispatch", {Call: (self, actionId) => !self.stopping})
            power.DefineProp("InputsReleased", {Call: (self, event) => true})
            event := {actionId: "power-up-utilities.system.sleep", slot: 1,
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

    static PaperPadTopmostRestoration() {
        window := SuiteGui("+ToolWindow", "Paper Pad topmost regression")
        pad := SuiteReleaseTopmostPad(window.Hwnd)
        try {
            window.Show("NA w160 h100")
            pad.SetDrawerTopmost(true)
            this.Assert(!!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad can become topmost")
            pad.SetDrawerTopmost(false)
            this.Assert(!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad can yield to a real dialog")
            pad.SetDrawerTopmost(true)
            this.Assert(!!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad restores topmost after yielding")
        }
        finally window.Destroy()
    }

    static PaperPadDialogOwnership() {
        windows := []
        try {
            drawer := SuiteGui("+ToolWindow", "Paper Pad ownership test")
            windows.Push(drawer)
            owner := SuiteGui("+ToolWindow", "External dialog owner")
            windows.Push(owner)
            unrelated := SuiteGui("+ToolWindow", "Unrelated same-process window")
            windows.Push(unrelated)
            helper := SuiteGui("+ToolWindow +E0x1 +Owner" owner.Hwnd, "Owned helper")
            windows.Push(helper)
            nested := SuiteGui("+ToolWindow +Owner" helper.Hwnd, "Nested modal dialog")
            windows.Push(nested)
            padDialog := SuiteGui("+ToolWindow +Owner" drawer.Hwnd, "Paper Pad dialog")
            windows.Push(padDialog)
            for window in [drawer, owner, unrelated, helper]
                window.Show("NA w160 h100")
            pad := SuiteReleaseTopmostPad(drawer.Hwnd)
            pad.last_external_window := owner.Hwnd

            ; Explicit candidates keep the test independent of personal windows.
            this.Assert(!PaperPadIsDialogWindow(helper.Hwnd)
                && !pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd]),
                "an owned framed helper cannot lower Paper Pad while its owner is enabled")
            owner.Opt("+Disabled")
            this.Assert(PaperPadIsDialogWindow(helper.Hwnd)
                && pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd]) = helper.Hwnd,
                "a custom modal dialog is recognized through its disabled owner")
            this.Assert(!pad.FindYieldDialog(unrelated.Hwnd, [helper.Hwnd]),
                "sharing a process with the foreground window is not a dialog relationship")

            helper.Opt("+Disabled")
            nested.Show("NA w160 h100")
            this.Assert(!PaperPadIsDialogWindow(helper.Hwnd)
                && pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd, nested.Hwnd]) = nested.Hwnd,
                "nested owner chains select the enabled modal dialog, not its disabled parent")
            nested.Hide()
            helper.Opt("-Disabled")
            owner.Opt("-Disabled")
            this.Assert(!pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd, nested.Hwnd]),
                "reenabling the owner and hiding the nested dialog removes the yield target")

            drawer.Opt("+Disabled")
            padDialog.Show("NA w160 h100")
            this.Assert(pad.FindYieldDialog(unrelated.Hwnd, [padDialog.Hwnd]) = padDialog.Hwnd,
                "Paper Pad's own modal dialog remains eligible when another window is active")
        }
        finally {
            while windows.Length
                windows.Pop().Destroy()
        }
    }

    static WindowSizingAndCloaking() {
        owner := SuiteGui("+Disabled +ToolWindow", "Release dialog owner")
        window := SuiteGui("+Resize +E0x1 +Owner" owner.Hwnd, "Release sizing test")
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
            this.Assert(PaperPadIsDialogWindow(window.Hwnd), "a visible test dialog can yield Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("PseudoConsoleWindow", 0x1, 123),
                "owned pseudoconsole helpers never count as dialogs")
            this.Assert(!PaperPadIsDialogCandidate("Button", 0x1, 123),
                "Explorer Button controls cannot lower Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("#32768", 0x1, 123)
                && !PaperPadIsDialogCandidate("Desktop User Picture", 0x1, 123),
                "native popup menus and Start-menu chrome do not lower Paper Pad")
            this.Assert(PaperPadIsDialogCandidate("#32770", 0, 0)
                && PaperPadIsDialogCandidate("OperationStatusWindow", 0, 0),
                "standard and operation-status dialogs remain eligible")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0x1, 0)
                && !PaperPadIsDialogCandidate("OtherWindow", 0, 123),
                "a dialog border or ownership alone cannot lower Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0, 123)
                && !PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0x1, 123),
                "Edge helper windows with an enabled owner are not dialogs")
            this.Assert(PaperPadIsDialogCandidate("OtherWindow", 0, 123, false)
                && PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0, 123, false),
                "custom modal dialogs remain eligible without a Chromium blacklist")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0x08000000, 123, false),
                "non-activating helpers do not become dialogs when their owner is disabled")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0, 0),
                "ordinary unowned windows do not count as dialogs")
            cloaked := Buffer(4, 0)
            NumPut("uint", 1, cloaked)
            result := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int") ; DWMWA_CLOAK
            this.Assert(result = 0 && IsWindowCloaked(window.Hwnd), "the test owns its cloaked dialog")
            this.Assert(!PaperPadIsDialogWindow(window.Hwnd),
                "a cloaked dialog on another desktop does not lower Paper Pad")
            NumPut("uint", 0, cloaked)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int")
        }
        finally {
            SuiteSizeGrip.Detach(window)
            window.Destroy()
            owner.Destroy()
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

class SuiteReleasePad extends PaperPadController {
    __New() {
        this.busy := false
        this.command_queue := []
        this.executed := []
        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
    }

    ExecuteCommand(request) => this.executed.Push(request.name)
}

class SuiteReleaseNativeSavePad extends PaperPadController {
    __New(path, hwnd) {
        this.window_hwnd := hwnd
        this.current_path := path
        this.bridge := SuiteReleaseNativeSaveBridge(path)
        SplitPath(path, , &directory)
        this.notes_directory := directory
        this.allowed_extensions := "|md|"
        this.busy := false
        this.command_queue := []
        this.page_lock_path := ""
        this.disk_stamp := PaperPadFileStamp(path)
        this.autosave_paused := false
        this.autosave_tracking := {sampled: false, text: "", last_change: 0}
    }

    HasWindow() => true
    IsVisible() => true
    SyncZOrder() => 0
    ProtectPage(path) => this.page_lock_path := path
    ReleasePageLock() => this.page_lock_path := ""
    PersistCurrentState() => 0

    AcceptSave(path, stamp) {
        this.disk_stamp := stamp
    }

    ReportError(failure, notification := false) {
        throw failure
    }
}

class SuiteReleaseNativeSaveBridge {
    __New(path) {
        this.path := path
        this.text := FileRead(path, "UTF-8")
        this.dirty := false
        this.tainted := false
        this.suppress_save := false
    }

    CheckReady() => 0
    CurrentPath() => this.path
    DocumentText() => this.text
    MatchesDisk(path) => FileRead(path, "UTF-8") == this.text
    MatchesDiskText(path, text) => FileRead(path, "UTF-8") == text
    IsDirty() => this.dirty

    Save() {
        if this.suppress_save
            return
        FileDelete this.path
        FileAppend this.text, this.path, "UTF-8-RAW"
        this.dirty := false
    }
}

class SuiteReleaseTopmostPad extends PaperPadController {
    __New(hwnd) => this.window_hwnd := hwnd
}
