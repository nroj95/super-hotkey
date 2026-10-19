; Deterministic release regressions: inert callbacks and test-owned windows only.
class SuiteHardeningChecks {
    static Run() {
        this.InputQueueCancellation()
        this.SleepPolicyRecovery()
        this.FocusBorderLifecycle()
        this.SwapRollback()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

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

            SuiteFocusBorder.Show(window.Hwnd, "cascade-close")
            this.Assert(!SuiteFocusBorder.Hide("wonder-windows")
                && SuiteFocusBorder.owner = "cascade-close",
                "old module cleanup cannot hide another module's outline")
            SuiteFocusBorder.Expire()
            for probe in probes
                this.Assert(!probe.visible && probe.hideCritical > 0,
                    "timer expiry hides border segments inside the critical section")

            SuiteFocusBorder.Show(window.Hwnd, "cascade-close")
            app.CancelInputs()
            this.Assert(SuiteFocusBorder.owner = "", "input cancellation clears the shared border owner")
            for probe in probes
                this.Assert(!probe.visible, "input cancellation hides a Cascade-owned border")

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
