; Cascade Kingdom: lifecycle, settings page and guide. Window state lives in
; the module's globals, initialized by InitializeCascadeState().
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
        StartWindowHooks()
        StartCascadeActivity()
        manager.Observe("*LButton", CanStartFocusTabClick, (*) => BeginFocusTabClick())
        manager.Observe("*LButton Up", HasFocusTabClick, (*) => FinishFocusTabClick(), true)
        manager.Observe("~*LButton", IsCascadeEnabled, (*) => CaptureCascadeMousePress())
        for key in ["RButton", "MButton", "XButton1", "XButton2"]
            manager.Observe("~*" key, IsCascadeEnabled, (*) => CancelCascadePendingMouseActions())
        manager.Observe("~*LButton Up", IsCascadeEnabled, (*) => CaptureCascadeMouseRelease())
        manager.Observe("~*Escape", HasCascadeWindowDrag, (*) => CancelCascadeWindowDrop())
        SuiteWindowOwnership.OnClaim(CascadeForgetManualWindow)
    }

    Suspend() {
        global cascade_compaction_pending, cascade_compaction_timer_pending
        global placement_stabilization_generations, cascade_mouse_press
        global focus_corner_overlays, focus_corner_update_pending

        ; Invalidate queued work so it cannot replay when the app resumes.
        cascade_compaction_pending.Clear()
        cascade_compaction_timer_pending := false
        SetTimer(FlushCascadeCompactions, 0)
        SetTimer(RunQueuedFocusCornerUpdate, 0)
        focus_corner_update_pending := false
        CancelCascadeWindowDrop()
        if HasCascadeWindowDrag()
            StopCascadeWindowDrag()
        cascade_mouse_press := 0
        for hwnd in placement_stabilization_generations.Clone()
            CancelPlacementStabilization(hwnd)
        for hwnd in focus_corner_overlays
            HideFocusCornerOverlay(hwnd)
    }

    Resume() => SetTimer(QueueFocusCornerUpdate, -1)

    CancelWork() {
        global cascade_command_queue
        CancelCascadeWindowDrop()
        cascade_command_queue := []
        StopFocusTabClick()
    }

    ; SuiteManagedWindows: other modules leave these windows to Cascade Kingdom.
    ManagedMonitor(hwnd) => GetManagedCascadeMonitor(hwnd)

    CanMoveToMonitor(hwnd, monitor) {
        return IsCascadeEnabled() && GetManagedCascadeMonitor(hwnd) && CascadeDisplayAllowed(monitor)
    }

    ; A managed window joins the destination cascade instead of becoming manual.
    MoveToMonitor(hwnd, monitor) {
        RemoveWindowFromMinimizeState(hwnd)
        if !PlaceCascadeWindowOnMonitor(hwnd, monitor)
            return false
        QueueFocusCornerUpdate()
        return true
    }

    Stop(*) {
        global cascade_command_queue
        SuiteWindowOwnership.OffClaim(CascadeForgetManualWindow)
        CascadeDropGuides.Destroy()
        cascade_command_queue := []
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
        global cascade_target_display, focus_corner_visible, focus_tab_color_presets
        global focus_corner_inactive_slot_color_name
        window := ui.NewWindow(key, "Cascade Kingdom - Settings", true)
        window.AddText("x20 y18 w560", "Add windows with Caps + Insert or by dragging one onto a slot.")
        choices := ui.DisplayChoices(cascade_target_display, true)
        this.displayChoices := choices.values
        window.AddText("x20 y65 w200", "Cascade on")
        window.AddDropDownList("x240 y60 w300 vdisplay", choices.names).Choose(choices.selected)
        window.AddCheckbox("x20 y103 w550 vtabs", "Show focus tabs").Value := focus_corner_visible
        colors := []
        for name in focus_tab_color_presets
            colors.Push(name)
        window.AddText("x20 y148 w200", "Inactive-slot tab color")
        window.AddDropDownList("x240 y143 w210 vinactiveColor", colors).Choose(focus_corner_inactive_slot_color_name)
        window.AddText("x20 y188 w560", "Active tabs and drop guides use the Windows accent color."
            . "`nDisplay changes release other displays without moving windows."
            . "`nClick Apply to use these settings.")
        ui.Footer(window, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 120],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]], 293, 600)
        ui.ShowPage(key, 600, 343, 560, 318)
    }

    ; Applies without a restart; routing changes first release in-flight work.
    SaveSettings(ui, *) {
        global cascade_target_display, focus_corner_visible, focus_tab_color_presets
        global focus_corner_inactive_slot_color_name, focus_corner_inactive_slot_color
        key := "settings:cascade-kingdom"
        window := ui.windows[key]
        try {
            display := this.displayChoices[window["display"].Value]
            visible := window["tabs"].Value != 0
            inactiveName := window["inactiveColor"].Text
            if !focus_tab_color_presets.Has(inactiveName)
                throw ValueError("Select a valid inactive tab color.")
            this.app.Settings.WritePreferences(this.id, Map(
                "Controls", Map("Display", display),
                "FocusTabs", Map("Visible", visible ? 1 : 0, "InactiveSlotColor", inactiveName)))
            routingChanged := cascade_target_display != display
            if routingChanged {
                this.app.CancelInputs()
                this.Suspend()
            }
            cascade_target_display := display
            if routingChanged
                CascadeReleaseExcludedDisplays()
            if focus_corner_visible != visible
                ToggleFocusCornerVisibility()
            focus_corner_inactive_slot_color_name := inactiveName
            focus_corner_inactive_slot_color := focus_tab_color_presets[inactiveName]
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
            . "`r`nPress Caps + Insert to add the active window; press it again straight away "
            . "to undo. Or drag a window: corner guides mark the slots, and releasing with its "
            . "top-left corner on one adds it. Resizing never adds a window, and dragging a "
            . "member away from its slot releases it. With one display selected in Settings, "
            . "added windows move there and dragging to another display leaves a window "
            . "outside the cascade. A disconnected selected display pauses adding until it "
            . "returns or you change Settings."
            . "`r`n`r`nFOCUS TABS"
            . "`r`nClick a focus tab to select a slot. Click again to cycle windows sharing "
            . "that slot. Active tabs and drop guides use your Windows accent color; "
            . "choose the inactive tab color in Settings."
    }
}

; A window that Wonder Windows positions by hand leaves its cascade at once.
CascadeForgetManualWindow(hwnd)
{
    global placement_reservations
    monitor := GetManagedCascadeMonitor(hwnd)
    CancelPlacementStabilization(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)
    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)
    if monitor
        QueueCascadeCompaction(monitor)
    QueueFocusCornerUpdate()
}
