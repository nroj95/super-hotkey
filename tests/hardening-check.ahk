; Deterministic release regressions: inert callbacks and test-owned windows only.
class SuiteHardeningChecks {
    static Run() {
        this.InputQueueCancellation()
        this.SleepPolicyRecovery()
        this.FocusBorderLifecycle()
        this.SwapRollback()
        this.ExpandedWindowCycle()
        this.MonitorWindowCycle()
        WW_RunWindowCommand(ObjBindMethod(this, "MaximizedAdoption"))
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    ; Apply a fixture's changed frame styles (SWP_FRAMECHANGED without moving).
    static RefreshFrame(hwnd) => DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
        "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37, "int")

    static ExpandedWindowCycle() {
        cycle := [101, 102, 103]
        this.Assert(WW_NextMaximizedFullscreenWindow([], 0, 0) = 0,
            "an empty expanded-window cycle has no target")
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 0, 0) = 101
            && WW_NextMaximizedFullscreenWindow(cycle, 101, 101) = 102
            && WW_NextMaximizedFullscreenWindow(cycle, 102, 102) = 103
            && WW_NextMaximizedFullscreenWindow(cycle, 103, 103) = 0,
            "expanded cycling visits each window before the all-minimized step")
        this.Assert(WW_NextMaximizedFullscreenWindow(cycle, 999, 102) = 102
            && WW_NextMaximizedFullscreenWindow(cycle, 999, 0) = 101
            && WW_NextMaximizedFullscreenWindow(cycle, 999, 999) = 101,
            "outside focus resumes the last expanded window or restarts after reset or closure")
        this.Assert(WW_NextMaximizedFullscreenWindow([101], 101, 101) = 0
            && WW_NextMaximizedFullscreenWindow([101], 0, 0) = 101,
            "one expanded window alternates between minimized and visible")

        placement := Buffer(44, 0)
        monitorInfo := Buffer(40, 0)
        NumPut("int", -1920, "int", -1080, "int", 0, "int", 0, monitorInfo, 4)
        NumPut("int", -1880, "int", -1040, "int", 0, "int", 0, monitorInfo, 20)
        NumPut("int", -1960, "int", -1120, "int", -40, "int", -40, placement, 28)
        this.Assert(WW_WindowPlacementFillsPhysicalMonitor(placement, monitorInfo),
            "minimized fullscreen geometry accounts for workspace offsets and negative monitors")
        NumPut("int", -140, placement, 36)
        this.Assert(!WW_WindowPlacementFillsPhysicalMonitor(placement, monitorInfo),
            "a smaller restore rectangle is not fullscreen")

        WW_RunWindowCommand(ObjBindMethod(this, "ExpandedWindowCycleWindows"))
    }

    static MonitorWindowCycle() {
        cycle := [101, 102, 103]
        this.Assert(WW_NextMonitorCycleWindow(cycle, 101, 101) = 102
            && WW_NextMonitorCycleWindow(cycle, 102, 102) = 103
            && WW_NextMonitorCycleWindow(cycle, 103, 103) = 101,
            "monitor cycling visits every window and wraps around")
        this.Assert(WW_NextMonitorCycleWindow(cycle, 102, 101) = 103
            && WW_NextMonitorCycleWindow(cycle, 103, 101) = 102,
            "a refused target is stepped past without returning to the active window")
        this.Assert(WW_NextMonitorCycleWindow([101], 101, 101) = 0
            && WW_NextMonitorCycleWindow([], 0, 0) = 0,
            "a display with no other window has no target")

        ; Activating 102 moves it to the front; its place in the cycle stays.
        merged := WW_MergeCycleOrder(cycle, [102, 104, 101, 103])
        this.Assert(merged.Length = 4 && merged[1] = 101 && merged[2] = 102
            && merged[3] = 103 && merged[4] = 104,
            "cycle order survives Z-order changes and appends new windows")
        merged := WW_MergeCycleOrder(cycle, [103, 101])
        this.Assert(merged.Length = 2 && merged[1] = 101 && merged[2] = 103,
            "closed, minimized and moved windows leave the cycle")

        display := [-1920, 0, 1920, 1080]
        this.Assert(WW_IntersectionArea([-100, 500, 400, 300], display) = 30000
            && !WW_IntersectionArea([-32000, -32000, 160, 28], display)
            && !WW_IntersectionArea([0, 0, 400, 300], display)
            && !WW_IntersectionArea([-500, 200, 0, 0], display),
            "only windows sharing area with the display count as on it")

        maximized := [0, 0, 1920, 1080]
        this.Assert(WW_WindowsStack([100, 100, 800, 600], [140, 120, 800, 600])
            && !WW_WindowsStack([0, 0, 640, 1080], [640, 0, 640, 1080])
            && !WW_WindowsStack([0, 0, 960, 1080], maximized)
            && !WW_WindowsStack([0, 0, 640, 1080], maximized)
            && !WW_WindowsStack([0, 0, 200, 150], [0, 0, 800, 600]),
            "only windows sharing most of each other's area stack")

        ; Explorer over Terminal on the left, VS Code over Firefox in the middle,
        ; a lone window on the right and a maximized window behind them all.
        stacks := WW_GroupWindowStacks([
            {hwnd: 201, rect: [0, 0, 640, 1080]}, {hwnd: 301, rect: [640, 0, 640, 1080]},
            {hwnd: 202, rect: [10, 20, 630, 1060]}, {hwnd: 401, rect: [1280, 0, 640, 1080]},
            {hwnd: 302, rect: [640, 0, 640, 1080]}, {hwnd: 501, rect: maximized}])
        this.Assert(stacks.Length = 4
            && stacks[1].Length = 2 && stacks[1][1] = 201 && stacks[1][2] = 202
            && stacks[2].Length = 2 && stacks[2][1] = 301 && stacks[2][2] = 302
            && stacks[3].Length = 1 && stacks[3][1] = 401
            && stacks[4].Length = 1 && stacks[4][1] = 501,
            "stacks group overlapping windows front to back and leave lone windows apart")
        stacks := WW_GroupWindowStacks([{hwnd: 601, rect: [0, 0, 800, 600]},
            {hwnd: 603, rect: [400, 0, 800, 600]}, {hwnd: 602, rect: [200, 0, 800, 600]}])
        this.Assert(stacks.Length = 1 && stacks[1].Length = 3
            && stacks[1][1] = 601 && stacks[1][2] = 603 && stacks[1][3] = 602,
            "a window linking two others joins them into one stack")
    }

    static ExpandedWindowCycleWindows() {
        windows := []
        try {
            Loop 3 {
                window := SuiteGui("+Resize -DPIScale", "Expanded cycle fixture " A_Index)
                windows.Push(window)
                SuiteFullscreen.Enable(window)
                window.Show("NA x60 y60 w320 h220")
            }
            normal := windows[1].Hwnd
            maximized := windows[2].Hwnd
            fullscreen := windows[3].Hwnd
            WinMaximize(maximized)
            WinMinimize(maximized)
            WinMinimize(normal)
            this.Assert(WW_IsMaximizedFullscreenSwitcherWindow(maximized)
                && !WW_IsMaximizedFullscreenSwitcherWindow(normal),
                "initially minimized maximized windows qualify without admitting normal windows")
            this.Assert(!IsSwitchableWindow(maximized)
                && !IsSwitchableWindow(normal)
                && IsSwitchableWindow(maximized, true),
                "other window commands retain their default exclusion of minimized windows")
            WinRestore(normal)

            ; A native-style borderless fixture, without SuiteFullscreen.placements.
            WinSetStyle((WinGetStyle(fullscreen) & ~0xC40000) | 0x80000000, fullscreen)
            WinSetExStyle(WinGetExStyle(fullscreen) & ~0x300, fullscreen)
            SuiteHardeningChecks.RefreshFrame(fullscreen)
            WW_GetWindowMonitorBounds(fullscreen, &left, &top, &right, &bottom)
            WinMove(left, top, right - left, bottom - top, fullscreen)
            this.Assert(WW_IsNativeFullscreen(fullscreen), "borderless fixture is native fullscreen")
            WinMinimize(fullscreen)
            this.Assert(WW_IsMaximizedFullscreenSwitcherWindow(fullscreen),
                "initially minimized native fullscreen windows qualify without cycle history")

            ; Only explicit test-owned handles reach the executor; never enumerate the desktop.
            cycle := [maximized, fullscreen]
            this.Assert(WW_ShowMaximizedFullscreenCycleWindow(cycle, maximized)
                && WinGetMinMax(maximized) = 1 && WinGetMinMax(fullscreen) = -1,
                "cycling restores maximized state and leaves the other candidate minimized")
            this.Assert(WW_ShowMaximizedFullscreenCycleWindow(cycle, fullscreen)
                && WinGetMinMax(maximized) = -1 && WinGetMinMax(fullscreen) != -1
                && WW_IsNativeFullscreen(fullscreen),
                "cycling to fullscreen minimizes the previously visible maximized window")
            this.Assert(WW_ShowMaximizedFullscreenCycleWindow(cycle, 0)
                && WinGetMinMax(maximized) = -1 && WinGetMinMax(fullscreen) = -1,
                "the final cycle step leaves every candidate minimized")
            target := WW_NextMaximizedFullscreenWindow(cycle, normal, 0)
            this.Assert(WW_ShowMaximizedFullscreenCycleWindow(cycle, target)
                && WinGetMinMax(maximized) = 1 && WinGetMinMax(fullscreen) = -1
                && WinGetMinMax(normal) = 0,
                "cycling restarts at the first window and leaves unrelated normal windows untouched")
        }
        finally {
            for window in windows {
                try SuiteSizeGrip.Detach(window)
                try window.Destroy()
            }
        }
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
            SuiteHardeningChecks.RefreshFrame(hwnd)
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

    static SleepPolicyRecovery() {
        folder := SuiteChecks.directory "\sleep-policy"
        policy := PH_SleepPolicyProbe(folder)
        policy.Begin()
        this.Assert(policy.values["AC"] = 0 && policy.values["DC"] = 0
            && FileExist(policy.path), "sleep changes both power sources with a recovery record")
        recovered := PH_SleepPolicyProbe(folder, policy.values)
        recovered.Recover()
        this.Assert(recovered.values["AC"] = 1 && recovered.values["DC"] = 1
            && !FileExist(policy.path), "a new process restores an interrupted sleep transaction")
        recovered.Begin()
        recovered.activeScheme := "{22222222-2222-2222-2222-222222222222}"
        activeCalls := recovered.applyCount
        recovered.Restore()
        this.Assert(recovered.values["AC"] = 1 && recovered.values["DC"] = 1
            && recovered.applyCount = activeCalls,
            "restoration does not reactivate a power plan switched by another process")
        recovered.values["AC"] := 0
        recovered.values["DC"] := 0
        recovered.Begin()
        this.Assert(!FileExist(recovered.path),
            "already disabled Away Mode requires no disk transaction")
    }

    static InputQueueCancellation() {
        app := SuiteApplication(true, SuiteChecks.directory "\hardening-input")
        manager := Keybindings("hardening-input", "Hardening input",
            {directory: app.Settings.directory "\keybindings"})
        app.manager := manager
        events := []
        previousCritical := Critical("On")
        try {
            manager.AddAction("fixture.input", "inert input", (event) => events.Push(event.phase),
                ["Ctrl + Alt + F24"], {repeat: true})
            ; Build real routes without registering hotkeys or enabling feature modules.
            candidate := manager._CandidateRoutes(manager._DefaultConfiguration())
            manager.configuration := candidate.configuration
            manager.routes := candidate.routes
            route := manager.routes[1]
            route.enabled := true
            manager.running := true

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.SetPaused(true)
            manager.SetPaused(false)
            manager._Drain()
            this.Assert(!events.Length && !manager.delivered.Count,
                "a complete queued shortcut cannot replay after pause/resume")

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager._Drain()
            this.Assert(events.Length = 2 && events[1] = "down" && events[2] = "up",
                "fresh shortcuts remain usable after cancellation")
            events.Length := 0

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.externalCapture := true
            manager._RefreshGate()
            manager.externalCapture := false
            manager._RefreshGate()
            manager._Drain()
            this.Assert(!events.Length, "entering and leaving recording expires queued input")

            manager._QueueEvent(route, "down", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager._Deactivate()
            route.enabled := true ; model restoring old routes after a failed configuration write
            manager._Drain()
            this.Assert(!events.Length, "configuration rollback cannot revive old queued input")

            manager._QueueEvent(route, "down", 0, false)
            manager._Drain()
            manager._QueueEvent(route, "repeat", 0, false)
            manager._QueueEvent(route, "up", 0, false)
            manager.SetPaused(true)
            manager.SetPaused(false)
            manager._Drain()
            this.Assert(events.Length = 2 && events[1] = "down" && events[2] = "cancel"
                && !manager.delivered.Count,
                "delivered output receives one cancel, not a stale repeat or release action")
        }
        finally {
            app.Stop("test")
            Critical(previousCritical)
        }
    }

    static FocusBorderLifecycle() {
        app := SuiteApplication(true, SuiteChecks.directory "\hardening-border")
        window := SuiteGui("+Resize", "Hardening border target")
        probes := []
        previousCritical := Critical("Off")
        try {
            window.Show("NA w320 h220")
            SuiteFocusBorder.Hide("", true)
            Loop 4
                probes.Push(SuiteHardeningBorderProbe())
            SuiteFocusBorder.guis := probes
            this.Assert(SuiteFocusBorder.Show(window.Hwnd, "wonder-windows") && !A_IsCritical,
                "showing the border restores the caller's interruptibility")
            for probe in probes
                this.Assert(probe.visible && probe.showCritical > 0,
                    "each reused border segment is shown inside the critical section")

            SuiteFocusBorder.Show(window.Hwnd, "close-window")
            this.Assert(!SuiteFocusBorder.Hide("wonder-windows")
                && SuiteFocusBorder.owner = "close-window",
                "old module cleanup cannot hide another module's outline")
            SuiteFocusBorder.Expire()
            for probe in probes
                this.Assert(!probe.visible && probe.hideCritical > 0,
                    "timer expiry hides border segments inside the critical section")

            SuiteFocusBorder.Show(window.Hwnd, "close-window")
            app.CancelInputs()
            this.Assert(SuiteFocusBorder.owner = "", "input cancellation clears the shared border owner")
            for probe in probes
                this.Assert(!probe.visible, "input cancellation hides a close-owned border")

            Critical(50)
            SuiteFocusBorder.Show(window.Hwnd, "wonder-windows")
            this.Assert(A_IsCritical = 50, "show preserves an existing critical interval")
            SuiteFocusBorder.Hide("", true)
            this.Assert(A_IsCritical = 50 && !SuiteFocusBorder.guis.Length,
                "destroy preserves an existing critical interval and releases border references")
            for probe in probes
                this.Assert(probe.destroyCritical > 0, "border destruction stays serialized")
        }
        finally {
            SuiteFocusBorder.Hide("", true)
            SuiteSizeGrip.Detach(window)
            window.Destroy()
            Critical(previousCritical)
        }
    }

    static SwapRollback() {
        ; Try each ordering: failure of either window must not skip the other one.
        for missingIndex in [1, 2] {
            windows := []
            handles := []
            raw := []
            visible := []
            try {
                Loop 2 {
                    window := SuiteGui("+Resize", "Hardening swap " A_Index)
                    windows.Push(window)
                    handles.Push(window.Hwnd)
                    window.Show("NA x" (40 * A_Index) " y" (40 * A_Index) " w260 h180")
                    WinGetPos(&x, &y, &width, &height, window.Hwnd)
                    raw.Push([x, y, width, height])
                    visible.Push(WW_GetWindowLayoutRectangle(window.Hwnd))
                }
                survivor := 3 - missingIndex
                original := raw[survivor]
                WinMove(original[1] + 70, original[2] + 60, , , handles[survivor])
                SuiteSizeGrip.Detach(windows[missingIndex])
                windows[missingIndex].Destroy()

                this.Assert(!WW_RestoreSwapRectangles(handles[1], handles[2],
                    raw[1], raw[2], visible[1], visible[2]),
                    "rollback reports failure when one target has closed")
                this.Assert(WW_WindowMatchesVisibleRectangle(handles[survivor], visible[survivor]),
                    "rollback still restores the surviving window in either argument order")
            }
            finally {
                for window in windows {
                    try SuiteSizeGrip.Detach(window)
                    try window.Destroy()
                }
            }
        }
    }
}

class PH_SleepPolicyProbe extends PH_SleepPolicy {
    __New(directory, values := 0) {
        super.__New(directory)
        this.activeScheme := "{11111111-1111-1111-1111-111111111111}"
        this.values := IsObject(values) ? values : Map("AC", 1, "DC", 1)
        this.applyCount := 0
    }

    GetActiveGuid() => this.activeScheme
    ReadValue(scheme, source) => this.values[source]
    WriteValue(scheme, source, value) => this.values[source] := value
    Apply(scheme) => this.applyCount += 1
}

class SuiteHardeningBorderProbe {
    BackColor := ""
    visible := false
    showCritical := 0
    hideCritical := 0
    destroyCritical := 0

    Show(*) {
        this.showCritical := A_IsCritical
        this.visible := true
    }

    Hide() {
        this.hideCritical := A_IsCritical
        this.visible := false
    }

    Destroy() {
        this.destroyCritical := A_IsCritical
        this.visible := false
    }
}
