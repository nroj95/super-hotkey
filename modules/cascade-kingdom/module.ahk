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
        manager.AddBindingCheck(CascadeMouseKeyBindingWarning)
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
        ObserveMouseKeyClicks(manager)
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
        CascadeState.mouseKeyLast := 0
    }

    ; SuiteManagedWindows: other modules leave these windows to Cascade Kingdom.
    ManagedMonitor(hwnd) => GetManagedCascadeMonitor(hwnd)
    IsLentWindow(hwnd) => CascadeState.lentWindows.Has(hwnd)

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
        rows.Text("Add windows with Caps + Insert, or hold the click-to-focus key and double-click one.")
        choices := ui.DisplayChoices(CascadeState.targetDisplay, true)
        this.displayChoices := choices.values
        rows.Field("Cascade on", "DropDownList", "w300 vdisplay", choices.names).Choose(choices.selected)
        sizes := []
        for size in CascadeState.windowSizeChoices
            sizes.Push(size " %")
        rows.Field("Window size", "DropDownList", "w120 vwindowSize", sizes).Choose(CascadeState.windowSize " %")
        rows.Field("Click to focus while holding", "DropDownList", "w120 vclickKey", CascadeState.mouseKeyChoices)
            .Choose(CascadeState.mouseKey)
        rows.Checkbox("Mirror: cascade toward the left", "vmirrored").Value := CascadeState.mirrored
        rows.Checkbox("Show focus tabs", "vtabs").Value := CascadeState.focusCornerVisible
        colors := []
        for name in CascadeState.focusTabColorPresets
            colors.Push(name)
        rows.Field("Inactive-slot tab color", "DropDownList", "w210 vinactiveColor", colors)
            .Choose(CascadeState.focusCornerInactiveSlotColorName)
        rows.Text("Window size is a share of the display's width and height; bigger windows leave room for fewer slots."
            . "`nCaps and Pause need Secret Layers."
            . "`nActive tabs and drop guides use the Windows accent color."
            . "`nDisplay changes release other displays without moving windows."
            . "`nClick Apply to use these settings.")
        rows.Show(ui, key, [["Apply", ObjBindMethod(this, "SaveSettings", ui)],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id)]])
    }

    RestoreSettings(window) {
        window["display"].Choose(SuiteInterface.DisplayIndex(this.displayChoices, "All"))
        window["windowSize"].Choose("80 %")
        window["clickKey"].Choose("Caps")
        window["mirrored"].Value := 0
        window["tabs"].Value := 1
        window["inactiveColor"].Choose("White")
    }

    ; Applies without a restart; routing changes first release in-flight work,
    ; and mirroring or a new window size re-lays out every cascade as a display
    ; change does, moving windows from slots that no longer fit into the last one.
    SaveSettings(ui, *) {
        key := "settings:cascade-kingdom"
        window := ui.windows[key]
        try {
            display := this.displayChoices[window["display"].Value]
            size := CascadeState.windowSizeChoices[window["windowSize"].Value]
            clickKey := window["clickKey"].Text
            if !IsCascadeMouseKeyChoice(clickKey)
                throw ValueError("Select a valid click-to-focus key.")
            mirrored := window["mirrored"].Value != 0
            visible := window["tabs"].Value != 0
            inactiveName := window["inactiveColor"].Text
            if !CascadeState.focusTabColorPresets.Has(inactiveName)
                throw ValueError("Select a valid inactive tab color.")
            this.app.Settings.WritePreferences(this.id, Map(
                "Controls", Map("Display", display, "WindowSize", size, "ClickKey", clickKey,
                    "Mirrored", mirrored ? 1 : 0),
                "FocusTabs", Map("Visible", visible ? 1 : 0, "InactiveSlotColor", inactiveName)))
            CascadeState.mouseKey := clickKey
            CascadeState.mouseKeyLast := 0
            if CascadeState.mirrored != mirrored || CascadeState.windowSize != size {
                CascadeState.mirrored := mirrored
                CascadeState.windowSize := size
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
            ui.Applied(key)
        }
        catch Error as failure
            ui.Report(failure, "Cascade Kingdom / settings")
    }

    HelpText() => "
    (
        WHY I MADE THIS
        I wanted an easier way to manage lots of open windows: keep them large and neatly organized, switch between them effortlessly, and avoid digging through a messy pile of overlapping windows.

        ADD A WINDOW
        Press Caps + Insert to add the active window, and Caps + Shift + Insert to take it out again: it returns to where it was before it joined.
        Or hold Caps and double-click anywhere on a window to add it, and double-click it again to take it out, back to where it was.
        While Caps is held, clicks only focus windows and never reach what is inside them.
        Settings can use Pause or Win for this instead, or turn it off.
        Caps and Pause need Secret Layers; Win works without it.
        With one display selected in Settings, added windows move there.
        A disconnected selected display pauses adding until it returns or you change Settings.

        MOVE A WINDOW
        Dragging a window in a cascade shows corner guides on the slots it can take: those the cascade can fill.
        The bigger guide in your accent color is the slot it will take, on this display or another, and releasing moves it there.
        It swaps with the window there instead of sliding back into its own place.
        With no guide lit, releasing leaves the cascade where you dropped it, at the size it had before it joined.
        With one display selected in Settings, dragging a window to another display takes it out too.
        Resizing it by any edge also takes it out, as large and where you left it.

        FOCUS TABS
        Each slot has a focus tab on both sides: at the lower left and the upper right.
        Click either to select a slot.
        Click again to cycle windows sharing that slot.
        Active tabs and drop guides use your Windows accent color; choose the inactive tab color in Settings.
        A cascade of one window shows no tabs.
    )"
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
