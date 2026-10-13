; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; All shared geometry is in physical virtual-screen pixels, never system-DPI units.

; =============================================================================
; short, exception-safe DPI boundaries
; =============================================================================

CallWithDpiContext(context, callback, args*)
{
    previous_context := DllCall("SetThreadDpiAwarenessContext", "ptr", context, "ptr")
    if !previous_context
        throw OSError(A_LastError, "SetThreadDpiAwarenessContext")
    try return callback(args*)
    finally {
        ; Restoring the context must not replace a native operation's error code.
        last_error := A_LastError
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous_context, "ptr")
        DllCall("SetLastError", "uint", last_error)
    }
}

; Scope each API, not a whole timer/hotkey: modal message dispatch can temporarily
; select the DPI context of the receiving HWND. Always restore the caller's mode.
WinGetPosPixels(args*) => CallWithDpiContext(-3, WinGetPos, args*)
WinMovePixels(args*) => CallWithDpiContext(-3, WinMove, args*)
MonitorGetPixels(args*) => CallWithDpiContext(-3, MonitorGet, args*)
MonitorGetWorkAreaPixels(args*) => CallWithDpiContext(-3, MonitorGetWorkArea, args*)
MouseGetPosPixels(args*) => CallWithDpiContext(-3, MouseGetPos, args*)
PhysicalDllCall(args*) => CallWithDpiContext(-3, DllCall, args*)
CreatePhysicalGui(options, title) => CallWithDpiContext(-3, Gui, options, title)
ShowPhysicalGui(gui_object, options) => CallWithDpiContext(-3, ObjBindMethod(gui_object, "Show"), options)
ScaleForDpi(value, dpi) => Round(value * dpi / 96)

; =============================================================================
; monitor DPI independent of an external application's awareness
; =============================================================================

ReadCascadeDisplays()
{
    global cascade_dpi_probes

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

        center_x := left + Floor((right - left) / 2)
        center_y := top + Floor((bottom - top) / 2)
        if !cascade_dpi_probes.Has(device) {
            ; GetDpiForWindow on a system-aware/unaware target reports its system
            ; DPI/96, not this monitor's scale. Our hidden PM-aware probe avoids that.
            probe_gui := CreatePhysicalGui("-Caption -DPIScale +ToolWindow +E0x08000000",
                "Window Cascade DPI Probe")
            cascade_dpi_probes[device] := {gui: probe_gui, x: "", y: ""}
        }
        probe := cascade_dpi_probes[device]
        if probe.x != center_x || probe.y != center_y {
            ShowPhysicalGui(probe.gui, "Hide x" center_x " y" center_y " w1 h1")
            probe.x := center_x
            probe.y := center_y
        }
        dpi := DllCall("GetDpiForWindow", "ptr", probe.gui.Hwnd, "uint")
        if !dpi
            throw Error("Could not read the monitor DPI.", , device)
        live_devices[device] := true
        display_signature := device ":" left "," top "," right "," bottom
            . ":" work_left "," work_top "," work_right "," work_bottom ":" dpi
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
    for device, probe in cascade_dpi_probes.Clone() {
        if !live_devices.Has(device) {
            try probe.gui.Destroy()
            cascade_dpi_probes.Delete(device)
        }
    }
    return {displays: displays, signature: signature}
}

GetCascadeMonitorDpi(monitor_index)
{
    global cascade_displays, cascade_dpi_probes
    if !cascade_displays.Has(monitor_index)
        return 96
    display := cascade_displays[monitor_index]
    if cascade_dpi_probes.Has(display.device) {
        dpi := DllCall("GetDpiForWindow", "ptr", cascade_dpi_probes[display.device].gui.Hwnd, "uint")
        if dpi
            return dpi
    }
    return display.dpi
}

GetCascadeWindowMonitorDpi(hwnd)
{
    return GetCascadeMonitorDpi(GetMonitorForWindow(hwnd))
}

GetCascadeMonitorDevice(monitor_index)
{
    global cascade_displays
    return cascade_displays.Has(monitor_index) ? cascade_displays[monitor_index].device : ""
}

FindCascadeMonitorDevice(device, displays := 0)
{
    global cascade_displays
    if !IsObject(displays)
        displays := cascade_displays
    for monitor_index, display in displays {
        if display.device = device
            return monitor_index
    }
    return 0
}

CascadeMonitorNeedsRefresh(monitor_index)
{
    global cascade_displays
    if IsCascadeDisplayTransition()
        return true
    try {
        if cascade_displays.Has(monitor_index) {
            display := cascade_displays[monitor_index]
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
