; The existing window manager keeps its state and placement algorithms.
; Only lifecycle, action ownership, tray ownership and logging move to the suite.
class WindowCascadeModule {
    static Register(manager) {
        InitializeCascadeKeybindings(manager)
    }

    static Start(manager) {
        InitializeDebugLogging()
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
        ; Wait until the suite is ready before showing any conflict warning.
        SetTimer(CheckCompatibilitySettings, -500)
    }

    static Suspend() {
        global pending_windows, cascade_compaction_pending, cascade_compaction_timer_pending
        global placement_stabilization_generations, cascade_mouse_press
        global focus_corner_overlays, focus_corner_update_pending
        global cascade_opt_in_intent, cascade_titlebar_click, cascade_close_focus_request

        ; Invalidate queued work so it cannot replay when the app resumes.
        CancelNewWindowFocus()
        cascade_opt_in_intent := 0
        cascade_titlebar_click := 0
        cascade_close_focus_request := 0
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

    static Resume() {
        ; Windows opened during suspension must not be adopted later.
        RememberWindowsSinceLastResume()
        SetTimer(QueueFocusCornerUpdate, -1)
    }

    static Stop() {
        CascadeDropGuides.Destroy()
        global cascade_command_queue
        cascade_command_queue := []
        SetTimer(DrainCascadeCommandQueue, 0)
        SetTimer(CheckCompatibilitySettings, 0)
        StopFocusTabClick()
        StopWindowHooks()
        StopCascadeDisplays()
        RestoreMinimizedCascadeWindowsOnExit()
        CloseWindowCascadeHelp()
    }
}
