; Cascade Kingdom destination policy: which displays may hold a cascade.

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
