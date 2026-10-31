; Cascade Kingdom: lifecycle, settings page and guide. Window state lives in
; CascadeState, initialized by InitializeCascadeState().
class CascadeKingdomModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Controls", "FocusTabs"]

    __New(app) {
        super.__New(app, "cascade-kingdom")
        InitializeCascadeState()
        SuiteManagedWindows.provider := this
        this.manager := 0
        this.displayChoices := []
    }

    Register(manager) {
        this.manager := manager
        RegisterCascadeActions(manager)
    }

    Start() {
        manager := this.manager
        InitializeCascadeDisplays()
        if IsCascadeEnabled()
            RestoreSavedCascades()
        StartWindowHooks()
        StartCascadeActivity()
        manager.Observe("*LButton", CanStartFocusTabClick, (*) => BeginFocusTabClick())
        manager.Observe("*LButton Up", HasFocusTabClick, (*) => FinishFocusTabClick(), true)
        manager.Observe("~*LButton", IsCascadeEnabled, (*) => CaptureCascadeMousePress())
        manager.Observe("~*LButton Up", IsCascadeEnabled, (*) => CaptureCascadeMouseRelease())
        manager.Observe("~*Escape", HasCascadeWindowDrag, (*) => CancelCascadeWindowDrop())
        SuiteWindowOwnership.OnClaim(CascadeForgetManualWindow)
        SuiteWindowOwnership.OnReturn(CascadeTakeBackWindow)
    }

    Suspend() {
        ; Invalidate queued work so it cannot replay when the app resumes.
        CascadeState.compactionPending.Clear()
        CascadeState.compactionTimerPending := false
        SetTimer(FlushCascadeCompactions, 0)
        SetTimer(RunQueuedFocusCornerUpdate, 0)
        CascadeState.focusCornerUpdatePending := false
        CancelCascadeWindowDrop()
        if HasCascadeWindowDrag()
            StopCascadeWindowDrag()
        CascadeState.mousePress := 0
        for hwnd in CascadeState.placementStabilizationGenerations.Clone()
            CancelPlacementStabilization(hwnd)
        for hwnd in CascadeState.focusCornerOverlays
            HideFocusCornerOverlay(hwnd)
    }

    Resume() => SetTimer(QueueFocusCornerUpdate, -1)

    CancelWork() {
        CancelCascadeWindowDrop()
        CascadeState.commandQueue := []
        StopFocusTabClick()
    }

    ; SuiteManagedWindows: other modules leave these windows to Cascade Kingdom.
    ManagedMonitor(hwnd) => GetManagedCascadeMonitor(hwnd)

    Stop(*) {
        ; A restart keeps the cascades; a dry run or a module that never
        ; started leaves the saved ones alone.
        if this.started && !this.app.dryRun
            SaveCascades()
        SuiteWindowOwnership.OffClaim(CascadeForgetManualWindow)
        SuiteWindowOwnership.OffReturn(CascadeTakeBackWindow)
        CascadeDropGuides.Destroy()
        CascadeState.commandQueue := []
        SetTimer(DrainCascadeCommandQueue, 0)
        StopFocusTabClick()
        StopWindowHooks()
        StopCascadeDisplays()
        RestoreMinimizedCascadeWindowsOnExit()
    }

    ShowSettings(ui) {
        key := "settings:cascade-kingdom"
        if ui.Existing(key)
            return
        rows := SuitePageRows(ui.NewWindow(key, "Cascade Kingdom - Settings", true), 600)
        rows.Text("Add windows with Caps + Insert or by dragging one onto a slot.")
        choices := ui.DisplayChoices(CascadeState.targetDisplay, true)
        this.displayChoices := choices.values
        rows.Field("Cascade on", "DropDownList", "w300 vdisplay", choices.names).Choose(choices.selected)
        rows.Checkbox("Mirror: cascade toward the left", "vmirrored").Value := CascadeState.mirrored
        rows.Checkbox("Show focus tabs", "vtabs").Value := CascadeState.focusCornerVisible
        colors := []
        for name in CascadeState.focusTabColorPresets
            colors.Push(name)
        rows.Field("Inactive-slot tab color", "DropDownList", "w210 vinactiveColor", colors)
            .Choose(CascadeState.focusCornerInactiveSlotColorName)
        rows.Text("Active tabs and drop guides use the Windows accent color."
            . "`nDisplay changes release other displays without moving windows."
            . "`nClick Apply to use these settings.")
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 120],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]])
    }

    ; Applies without a restart; routing changes first release in-flight work,
    ; and mirroring re-lays out every cascade as a display change does.
    SaveSettings(ui, *) {
        key := "settings:cascade-kingdom"
        window := ui.windows[key]
        try {
            display := this.displayChoices[window["display"].Value]
            mirrored := window["mirrored"].Value != 0
            visible := window["tabs"].Value != 0
            inactiveName := window["inactiveColor"].Text
            if !CascadeState.focusTabColorPresets.Has(inactiveName)
                throw ValueError("Select a valid inactive tab color.")
            this.app.Settings.WritePreferences(this.id, Map(
                "Controls", Map("Display", display, "Mirrored", mirrored ? 1 : 0),
                "FocusTabs", Map("Visible", visible ? 1 : 0, "InactiveSlotColor", inactiveName)))
            if CascadeState.mirrored != mirrored {
                CascadeState.mirrored := mirrored
                QueueCascadeDisplayRefresh()
            }
            routingChanged := CascadeState.targetDisplay != display
            if routingChanged {
                this.app.CancelInputs()
                this.Suspend()
            }
            CascadeState.targetDisplay := display
            if routingChanged
                CascadeReleaseExcludedDisplays()
            if CascadeState.focusCornerVisible != visible
                ToggleFocusCornerVisibility()
            CascadeState.focusCornerInactiveSlotColorName := inactiveName
            CascadeState.focusCornerInactiveSlotColor := CascadeState.focusTabColorPresets[inactiveName]
            if routingChanged && this.started && IsCascadeEnabled()
                this.Resume()
            QueueFocusCornerUpdate()
            ui.CloseWindow(key)
        }
        catch Error as failure
            ui.Report(failure, "Cascade Kingdom / settings")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nI wanted an easier way to manage lots of open windows: keep them large "
            . "and neatly organized, switch between them effortlessly, and avoid digging "
            . "through a messy pile of overlapping windows."
            . "`r`n`r`nADD A WINDOW"
            . "`r`nPress Caps + Insert to add the active window, and Caps + Shift + Insert to take "
            . "it out again: it returns to where it was before it joined. Or drag a window: "
            . "corner guides mark the slots, and releasing with its "
            . "top-left corner on one adds it. Resizing never adds a window, and dragging a "
            . "member away from its slot releases it. With one display selected in Settings, "
            . "added windows move there and dragging to another display leaves a window "
            . "outside the cascade. A disconnected selected display pauses adding until it "
            . "returns or you change Settings."
            . "`r`n`r`nFOCUS TABS"
            . "`r`nEach slot has a focus tab on both sides: at the lower left and the upper "
            . "right. Click either to select a slot. Click again to cycle windows sharing "
            . "that slot. Active tabs and drop guides use your Windows accent color; "
            . "choose the inactive tab color in Settings."
    }
}

; A window that Wonder Windows positions by hand leaves its cascade at once,
; lent rather than lost: its slot is kept until it returns, closes or joins anew.
CascadeForgetManualWindow(hwnd)
{
    monitor := GetManagedCascadeMonitor(hwnd)
    if monitor && !CascadeState.windowSlots.Has(hwnd)
        RememberCascadeSlot(hwnd, monitor)
    if monitor && CascadeState.windowSlots.Has(hwnd)
        CascadeState.lentWindows[hwnd] := CascadeState.windowSlots[hwnd].Clone()
    CancelPlacementStabilization(hwnd)
    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)
    if monitor
        QueueCascadeCompaction(monitor)
    QueueFocusCornerUpdate()
}

; Wonder Windows returned a lent window to its original shape: it rejoins its
; slot, and Caps + Shift + Insert later returns it to the shape Wonder Windows
; had given it, the last one the user saw outside the cascade.
CascadeTakeBackWindow(hwnd, shape)
{
    if !CascadeState.lentWindows.Has(hwnd)
        return
    lent := CascadeState.lentWindows.Delete(hwnd)
    try {
        if WinGetPID(hwnd) != lent.pid
            return
    }
    catch
        return
    monitor := FindCascadeMonitorDevice(lent.device)
    if !CascadeDisplayAllowed(monitor)
        return
    slots := CascadeState.displays[monitor].geometry.slots
    if !PlaceCascadeWindowOnMonitor(hwnd, monitor, slots[Min(lent.slot, slots.Length)])
        return
    RememberCascadeJoinPosition(hwnd, shape, true)
    QueueCascadeCompaction(monitor, hwnd)
}
