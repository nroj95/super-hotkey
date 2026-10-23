; Shared launch, gesture and destination policy. Geometry remains in existing code.

CascadeGestureEnabled()
{
    global cascade_gesture_key
    app := SuiteState.App
    layer := cascade_gesture_key = "Pause" ? "pause" : "caps"
    return IsObject(app) && app.ModuleActive("secret-layers")
        && app.activeLayers.Has(layer) && app.activeLayers[layer]
}

CascadeGestureHeld()
{
    global cascade_gesture_key
    app := SuiteState.App
    return CascadeGestureEnabled() && app.InputIsCurrent(app.inputGeneration)
        && (GetKeyState(cascade_gesture_key, "P")
        || (cascade_gesture_key = "Pause" && GetKeyState("CtrlBreak", "P")))
}

CascadeConsumeGesture()
{
    global cascade_gesture_key
    ; A mouse gesture is not an unused prefix tap or a speaker-wake double tap.
    SuiteState.App.modules["secret-layers"].ConsumeGesture(cascade_gesture_key = "Pause" ? "pause" : "caps")
}

CascadeShouldLaunch(automatic_enabled, gesture_held)
{
    return !!automatic_enabled != !!gesture_held
}

ResolveCascadeDestination(preferred_monitor, displays := 0)
{
    global cascade_target_display
    if cascade_target_display = "All"
        return preferred_monitor
    ; A missing selected display is not permission to move to another screen.
    return FindCascadeMonitorDevice(cascade_target_display, displays)
}

CascadeDisplayAllowed(monitor, displays := 0)
{
    return monitor && ResolveCascadeDestination(monitor, displays) = monitor
}

CascadeReleaseExcludedDisplays()
{
    global cascade_history
    for monitor, history in cascade_history.Clone() {
        if !CascadeDisplayAllowed(monitor)
            for hwnd in history.Clone()
                ReleaseCascadeWindow(hwnd)
    }
}

CascadeQueueGesture(callback, delay, arguments*)
{
    ; Use the suite's existing cancellation generation for delayed caption work.
    app := SuiteState.App
    SetTimer(ObjBindMethod(app, "RunInput", app.inputGeneration, callback, arguments*), -delay)
}
