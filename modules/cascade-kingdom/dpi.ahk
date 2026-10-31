; Cascade Kingdom displays, per-monitor DPI and physical-pixel GUIs.
; All shared geometry is in physical virtual-screen pixels, never system-DPI units.

; =============================================================================
; physical-pixel GUIs (core/windows.ahk owns the shared DPI boundaries)
; =============================================================================

CreatePhysicalGui(options, title) => CallWithDpiContext(-3, SuiteGui, options, title)
ShowPhysicalGui(gui_object, options) => CallWithDpiContext(-3, ObjBindMethod(gui_object, "Show"), options)
ScaleForDpi(value, dpi) => Round(value * dpi / 96)

; =============================================================================
; monitor DPI independent of an external application's awareness
; =============================================================================

; A display's effective DPI at a physical point, or 0. Read in per-monitor
; context: the process is system aware and would see the system DPI everywhere.
; Hidden windows are no substitute: they keep their DPI when a scale changes.
GetCascadePointDpi(x, y)
{
    monitor := PhysicalDllCall("MonitorFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "uint", 0, "ptr")
    dpi_x := dpi_y := 0
    if !monitor || PhysicalDllCall("shcore\GetDpiForMonitor", "ptr", monitor, "int", 0,
        "uint*", &dpi_x, "uint*", &dpi_y, "int") != 0 ; MDT_EFFECTIVE_DPI
        return 0
    return dpi_x
}

ReadCascadeDisplays()
{
    displays := Map()
    live_devices := Map()
    signature := ""
    Loop MonitorGetCount() {
        monitor_index := A_Index
        device := MonitorGetName(monitor_index)
        if live_devices.Has(device)
            throw Error("Monitor enumeration changed during the snapshot.")
        MonitorGetPixels(monitor_index, &left, &top, &right, &bottom)
        MonitorGetWorkAreaPixels(monitor_index, &work_left, &work_top, &work_right, &work_bottom)
        if right <= left || bottom <= top || work_right <= work_left || work_bottom <= work_top
            throw Error("Display geometry is temporarily unavailable.")

        dpi := GetCascadePointDpi(left + (right - left) // 2, top + (bottom - top) // 2)
        if !dpi
            throw Error("Could not read the monitor DPI.", , device)
        live_devices[device] := true
        ; Mirroring changes every slot, so toggling it re-lays out like a display change.
        display_signature := device ":" left "," top "," right "," bottom
            . ":" work_left "," work_top "," work_right "," work_bottom ":" dpi
            . (CascadeState.mirrored ? ":mirrored" : "")
        displays[monitor_index] := {
            device: device, dpi: dpi, signature: display_signature,
            left: left, top: top, right: right, bottom: bottom,
            work_left: work_left, work_top: work_top,
            work_right: work_right, work_bottom: work_bottom,
            geometry: BuildCanonicalCascadeGeometry(work_left, work_top, work_right, work_bottom)
        }
        signature .= monitor_index ":" display_signature "|"
    }
    if !displays.Count
        throw Error("No active display is available.")
    return {displays: displays, signature: signature}
}

GetCascadeMonitorDpi(monitor_index)
{
    if !CascadeState.displays.Has(monitor_index)
        return 96
    display := CascadeState.displays[monitor_index]
    dpi := GetCascadePointDpi(display.left + (display.right - display.left) // 2,
        display.top + (display.bottom - display.top) // 2)
    return dpi ? dpi : display.dpi
}

GetCascadeWindowMonitorDpi(hwnd)
{
    return GetCascadeMonitorDpi(WindowMonitorIndex(hwnd))
}

FindCascadeMonitorDevice(device, displays := 0)
{
    if !IsObject(displays)
        displays := CascadeState.displays
    for monitor_index, display in displays {
        if display.device = device
            return monitor_index
    }
    return 0
}

CascadeMonitorNeedsRefresh(monitor_index)
{
    if IsCascadeDisplayTransition()
        return true
    try {
        if CascadeState.displays.Has(monitor_index) {
            display := CascadeState.displays[monitor_index]
            MonitorGetWorkAreaPixels(monitor_index, &left, &top, &right, &bottom)
            if display.device = MonitorGetName(monitor_index)
                && display.dpi = GetCascadeMonitorDpi(monitor_index)
                && left = display.work_left && top = display.work_top
                && right = display.work_right && bottom = display.work_bottom
                return false
        }
    }
    ; Windows can resize an app before our notification arrives. Protect its old
    ; slot now; the coalesced refresh updates the snapshot instead of pruning it.
    QueueCascadeDisplayRefresh()
    return true
}
