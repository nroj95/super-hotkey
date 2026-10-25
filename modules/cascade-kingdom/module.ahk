; Cascade Kingdom: lifecycle, settings page and guide. Window state lives in
; the module's globals, initialized by InitializeCascadeState().
class CascadeKingdomModule extends SuiteModule {
    hasSettings := true
    resetSections := ["Controls", "DropGuides", "FocusTabs"]

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
        SeedStartupWindows()
        StartWindowHooks()
        StartCascadeActivity()
        manager.Observe("*LButton", CanStartFocusTabClick, (*) => BeginFocusTabClick())
        manager.Observe("*LButton Up", HasFocusTabClick, (*) => FinishFocusTabClick(), true)
        manager.Observe("~*LButton", IsCascadeEnabled, (*) => CaptureCascadeMousePress())
        for key in ["RButton", "MButton", "XButton1", "XButton2"]
            manager.Observe("~*" key, IsCascadeEnabled, (*) => CancelCascadePendingMouseActions())
        manager.Observe("~*LButton Up", IsCascadeEnabled, (*) => CaptureCascadeMouseRelease())
        manager.Observe("~*Enter", IsCascadeEnabled, (*) => CascadeCaptureKeyboardLaunch())
        manager.Observe("~*Escape", HasCascadeWindowDrag, (*) => CancelCascadeWindowDrop())
        manager.Observe("~*Space", IsExplorerSpaceReshowIntentContext,
            (*) => CaptureExplorerSpaceReshowIntent())
        SuiteWindowOwnership.OnClaim(CascadeForgetManualWindow)
    }

    Suspend() {
        global pending_windows, cascade_compaction_pending, cascade_compaction_timer_pending
        global placement_stabilization_generations, cascade_mouse_press
        global focus_corner_overlays, focus_corner_update_pending
        global cascade_opt_in_intent, cascade_titlebar_click

        ; Invalidate queued work so it cannot replay when the app resumes.
        CancelNewWindowFocus()
        cascade_opt_in_intent := 0
        cascade_titlebar_click := 0
        pending_windows.Clear()
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

    Resume() {
        ; Windows opened during suspension must not be adopted later.
        RememberWindowsSinceLastResume()
        SetTimer(QueueFocusCornerUpdate, -1)
    }

    CancelWork() {
        global cascade_opt_in_intent, cascade_titlebar_click, cascade_command_queue
        cascade_opt_in_intent := 0
        cascade_titlebar_click := 0
        CancelCascadeWindowDrop()
        cascade_command_queue := []
        CancelNewWindowFocus()
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
        global cascade_auto_placement_enabled, cascade_gesture_key, cascade_target_display
        global cascade_drop_guide_color_name
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        window := ui.NewWindow(key, "Cascade Kingdom - Settings", true)
        window.AddText("x20 y18 w560", "Hold the cascade key to reverse automatic cascading."
            . "`nKey + double-click a title bar always adopts a window."
            . "`nThe key must be enabled in Secret Layers.")
        window.AddCheckbox("x20 y86 w550 vautoCascade",
            "Automatically cascade newly opened windows").Value := cascade_auto_placement_enabled
        window.AddText("x20 y132 w200", "Cascade key")
        window.AddDropDownList("x240 y127 w210 vcascadeKey", ["CapsLock", "Pause"]).Choose(cascade_gesture_key)
        choices := ui.DisplayChoices(cascade_target_display, true)
        this.displayChoices := choices.values
        window.AddText("x20 y177 w200", "Cascade on")
        window.AddDropDownList("x240 y172 w300 vdisplay", choices.names).Choose(choices.selected)
        window.AddCheckbox("x20 y215 w550 vtabs", "Show focus tabs").Value := focus_corner_visible
        colors := []
        for name in focus_tab_color_presets
            colors.Push(name)
        window.AddText("x20 y260 w200", "Active-slot tab color")
        window.AddDropDownList("x240 y255 w210 vactiveColor", colors).Choose(focus_corner_active_slot_color_name)
        window.AddText("x20 y305 w200", "Inactive-slot tab color")
        window.AddDropDownList("x240 y300 w210 vinactiveColor", colors).Choose(focus_corner_inactive_slot_color_name)
        window.AddText("x20 y350 w200", "Drop-guide color")
        window.AddDropDownList("x240 y345 w210 vguideColor", colors).Choose(cascade_drop_guide_color_name)
        window.AddText("x20 y380 w520", "Display changes release other displays without moving windows."
            . "`nClick Apply to use these settings.")
        ui.Footer(window, [["Apply", ObjBindMethod(this, "SaveSettings", ui), 120],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]], 465, 600)
        ui.ShowPage(key, 600, 515, 560, 490)
    }

    ; Applies without a restart; routing changes first release in-flight work.
    SaveSettings(ui, *) {
        global cascade_auto_placement_enabled, cascade_gesture_key, cascade_target_display
        global cascade_drop_guide_color_name
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        global focus_corner_active_slot_color, focus_corner_inactive_slot_color
        key := "settings:cascade-kingdom"
        window := ui.windows[key]
        try {
            autoCascade := window["autoCascade"].Value != 0
            gestureKey := window["cascadeKey"].Text
            display := this.displayChoices[window["display"].Value]
            visible := window["tabs"].Value != 0
            activeName := window["activeColor"].Text
            inactiveName := window["inactiveColor"].Text
            guideName := window["guideColor"].Text
            if !focus_tab_color_presets.Has(activeName) || !focus_tab_color_presets.Has(inactiveName)
                || !focus_tab_color_presets.Has(guideName)
                throw ValueError("Select valid tab and drop-guide colors.")
            if gestureKey != "CapsLock" && gestureKey != "Pause"
                throw ValueError("Select CapsLock or Pause as the cascade key.")
            this.app.Settings.WritePreferences(this.id, Map(
                "Controls", Map("AutoCascadeNewWindows", autoCascade ? 1 : 0,
                    "CascadeKey", gestureKey, "Display", display),
                "DropGuides", Map("Color", guideName),
                "FocusTabs", Map("Visible", visible ? 1 : 0,
                    "ActiveSlotColor", activeName, "InactiveSlotColor", inactiveName)))
            routingChanged := cascade_auto_placement_enabled != autoCascade
                || cascade_gesture_key != gestureKey || cascade_target_display != display
            if routingChanged {
                this.app.CancelInputs()
                this.Suspend()
            }
            cascade_auto_placement_enabled := autoCascade
            cascade_gesture_key := gestureKey
            cascade_target_display := display
            cascade_drop_guide_color_name := guideName
            if routingChanged
                CascadeReleaseExcludedDisplays()
            if focus_corner_visible != visible
                ToggleFocusCornerVisibility()
            focus_corner_active_slot_color_name := activeName
            focus_corner_inactive_slot_color_name := inactiveName
            focus_corner_active_slot_color := focus_tab_color_presets[activeName]
            focus_corner_inactive_slot_color := focus_tab_color_presets[inactiveName]
            CascadeDropGuides.Hide()
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
            . "`r`n`r`nCASCADE ONLY WHEN YOU ASK"
            . "`r`nHold the cascade key while launching to add a new window. Settings "
            . "lets you choose CapsLock or Pause; enable Secret Layers and the selected key. "
            . "You can release the key before it finishes opening. With automatic cascading "
            . "enabled, hold the same key to open normally instead. All displays uses the "
            . "display you launched from: where you clicked, or the active window's display "
            . "for keyboard launches. Selecting one display sends new cascade windows there."
            . "`r`n`r`nFOCUS TABS"
            . "`r`nClick a focus tab to select a slot. Click again to cycle windows sharing "
            . "that slot. Dragging an eligible window shows opaque corner guides on "
            . "valid destination slots. Align its top-left corner and release to join; "
            . "resizing does not adopt windows. Choose guide and tab colors in Settings."
            . "`r`n`r`nADOPT AN EXISTING WINDOW"
            . "`r`nHold the selected key and double-click a title bar to adopt the window, "
            . "even in automatic mode. The adopt action in Keybindings is independent. "
            . "A selected destination redirects adoption too. Dragging to an excluded "
            . "display leaves the window there, outside the cascade. A disconnected "
            . "selected display pauses new adoption until it returns or you change Settings."
    }
}

; A window that Wonder Windows positions by hand leaves its cascade at once.
CascadeForgetManualWindow(hwnd)
{
    global pending_windows, placement_reservations, handled_windows
    monitor := GetManagedCascadeMonitor(hwnd)
    CancelPlacementStabilization(hwnd)
    if pending_windows.Has(hwnd)
        pending_windows.Delete(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)
    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)
    handled_windows[hwnd] := true
    if monitor
        QueueCascadeCompaction(monitor)
    QueueFocusCornerUpdate()
}
