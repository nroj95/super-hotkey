; Cascade Kingdom destination policy: which displays may hold a cascade.

ResolveCascadeDestination(preferred_monitor, displays := 0)
{
    if CascadeState.targetDisplay = "All"
        return preferred_monitor
    ; A missing selected display is not permission to move to another screen.
    return FindCascadeMonitorDevice(CascadeState.targetDisplay, displays)
}

CascadeDisplayAllowed(monitor, displays := 0)
{
    return monitor && ResolveCascadeDestination(monitor, displays) = monitor
}

CascadeReleaseExcludedDisplays()
{
    for monitor, history in CascadeState.history.Clone() {
        if !CascadeDisplayAllowed(monitor)
            for hwnd in history.Clone()
                ReleaseCascadeWindow(hwnd)
    }
}
