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
        manager.Observe("~*Escape", HasCascadeWindowDrag, (*) => CancelCascadeWindowDrop())
        manager.Observe("~*Space", IsExplorerSpaceReshowIntentContext,
            (*) => CaptureExplorerSpaceReshowIntent())
        ; Wait until the suite is ready before showing any conflict warning.
        SetTimer(CheckCompatibilitySettings, -500)
    }

    static Stop() {
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
