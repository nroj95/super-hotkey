; Cascade Kingdom destination policy: which displays may hold a cascade.

ResolveCascadeDestination(preferred_monitor, displays := 0)
{
    if CascadeState.targetDisplay = "All"
        return preferred_monitor
    if !IsObject(displays)
        displays := CascadeState.displays
    ; A missing selected display is not permission to move to another screen.
    ; The setting names a monitor device path, or a device name saved before paths.
    for monitor_index, display in displays
        if display.device = CascadeState.targetDisplay || display.path = CascadeState.targetDisplay
            return monitor_index
    return 0
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
