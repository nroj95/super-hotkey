; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; stacked window switcher
; =============================================================================

; Each press brings the next window of the active window's stack to the front:
; the windows overlapping it on its display. Other stacks stay put. The stack
; rotates in a stable order, because activation changes the Z-order and
; always-on-top windows never fall to the back.
WW_CycleMonitorWindows()
{
    Critical "On"
    global WW_monitor_cycle, WW_monitor_cycle_refused_hwnd, WW_monitor_cycle_refused_from

    foreground := DllCall("GetForegroundWindow", "ptr")
    ; A dialog stands in for the window that owns it.
    current := foreground ? DllCall("GetAncestor", "ptr", foreground, "uint", 3, "ptr") : 0 ; GA_ROOTOWNER
    if SuiteManagedWindows.Monitor(current) {
        WW_DebugLog("Stacked window cycle skipped: the active window is managed. | " DescribeWindow(current))
        return
    }
    ; The desktop, the taskbar and other surfaces leave the choice to the working display.
    if !IsSwitchableWindow(current) || !(monitor := WindowMonitorIndex(current)) {
        current := 0
        monitor := SuiteWorkingMonitor.Get()
    }

    entries := WW_GetMonitorCycleEntries(monitor)
    windows := []
    for entry in entries
        windows.Push(entry.hwnd)
    WW_monitor_cycle := WW_MergeCycleOrder(WW_monitor_cycle, windows)

    target := 0
    stack := []
    if current {
        for candidate in WW_GroupWindowStacks(entries)
            if WW_FindWindowIndex(candidate, current)
                stack := candidate
        from := current
        ; Step past a window that refused activation instead of requesting it again.
        if WW_monitor_cycle_refused_hwnd && current = WW_monitor_cycle_refused_from
            && WW_FindWindowIndex(stack, WW_monitor_cycle_refused_hwnd)
            from := WW_monitor_cycle_refused_hwnd
        if stack.Length > 1
            target := WW_NextMonitorCycleWindow(WW_MergeCycleOrder(WW_monitor_cycle, stack), from, from)
    }
    ; From the desktop, focus goes to the frontmost window.
    else if windows.Length
        target := windows[1]
    WW_DebugLog("Stacked window cycle step. | monitor=" monitor " | windows=" windows.Length
        . " | stack=" stack.Length " | from=" DescribeWindow(foreground))
    if !target {
        if current
            SuiteNotice.Show("status", "No stacked windows here", 1400)
        return
    }

    WW_ForgetLastMinimizedWindow()
    WW_EndFocusNavigationSession()
    ; A window with an open dialog hands the foreground to that dialog.
    activated := ActivateWindow(target)
        || DllCall("GetAncestor", "ptr", DllCall("GetForegroundWindow", "ptr"), "uint", 3, "ptr") = target
    WW_monitor_cycle_refused_hwnd := activated ? 0 : target
    WW_monitor_cycle_refused_from := activated ? 0 : current
    WW_DebugLog("Stacked window cycle focused a window. | activated=" (activated ? 1 : 0)
        . " | " DescribeWindow(target))
}

; The next window after from, wrapping around and skipping the active one.
; 0 when no other window is left.
WW_NextMonitorCycleWindow(windows, from_hwnd, active_hwnd)
{
    start := WW_FindWindowIndex(windows, from_hwnd)
    Loop windows.Length {
        hwnd := windows[Mod(start + A_Index - 1, windows.Length) + 1]
        if hwnd != active_hwnd
            return hwnd
    }
    return 0
}

; Switchable windows whose visible frame is on this display, front to back,
; as {hwnd, rect}. Some apps keep titled windows off-screen; activating one
; would show nothing.
WW_GetMonitorCycleEntries(monitor)
{
    entries := []
    MonitorGetPixels(monitor, &left, &top, &right, &bottom)
    display := [left, top, right - left, bottom - top]
    for hwnd in WinGetList() {
        if !IsSwitchableWindow(hwnd) || SuiteManagedWindows.Monitor(hwnd)
            || WindowMonitorIndex(hwnd) != monitor
            continue
        if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height) {
            try WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
            catch
                continue
        }
        rect := [x, y, width, height]
        if WW_IntersectionArea(rect, display)
            entries.Push({hwnd: hwnd, rect: rect})
        else
            WW_DebugLog("Stacked window cycle skips an off-screen window. | " DescribeWindow(hwnd))
    }
    return entries
}

; Groups {hwnd, rect} entries, front to back, into stacks of windows linked
; by overlap. Stacks come in order of their frontmost window, and each lists
; its windows front to back.
WW_GroupWindowStacks(entries)
{
    stack_of := Map()  ; entry index -> stack index
    stacks := []
    for index, entry in entries {
        if stack_of.Has(index)
            continue
        stacks.Push([])
        stack_of[index] := stacks.Length
        pending := [index]
        while pending.Length {
            member := entries[pending.Pop()]
            for other_index, other in entries {
                if stack_of.Has(other_index) || !WW_WindowsStack(member.rect, other.rect)
                    continue
                stack_of[other_index] := stacks.Length
                pending.Push(other_index)
            }
        }
    }
    for index, entry in entries
        stacks[stack_of[index]].Push(entry.hwnd)
    return stacks
}

; Windows stack when they share at least 60% of each one's area. Side-by-side
; tiles, and halves or thirds in front of a maximized window, stay apart.
WW_WindowsStack(first, second)
{
    shared := WW_IntersectionArea(first, second) * 5
    return shared > 0 && shared >= first[3] * first[4] * 3 && shared >= second[3] * second[4] * 3
}

; The area two [x, y, width, height] rectangles share.
WW_IntersectionArea(first, second)
{
    width := Min(first[1] + first[3], second[1] + second[3]) - Max(first[1], second[1])
    height := Min(first[2] + first[4], second[2] + second[4]) - Max(first[2], second[2])
    return width > 0 && height > 0 ? width * height : 0
}

; A cycle's established order, keeping only detected windows. Activating a
; window changes the native Z-order, so new windows join at the end, front to back.
WW_MergeCycleOrder(cycle, detected)
{
    detected_set := Map()
    for hwnd in detected
        detected_set[hwnd] := true

    merged := []
    merged_set := Map()
    for hwnd in cycle {
        if !detected_set.Has(hwnd)
            continue
        merged.Push(hwnd)
        merged_set[hwnd] := true
    }
    for hwnd in detected {
        if !merged_set.Has(hwnd)
            merged.Push(hwnd)
    }
    return merged
}

; =============================================================================
; maximized / native fullscreen switcher
; =============================================================================

WW_CycleMaximizedFullscreenWindows()
{
    Critical "On"
    WW_ForgetLastMinimizedWindow()
    WW_EndFocusNavigationSession()

    global WW_maximized_fullscreen_cycle, WW_last_maximized_fullscreen_hwnd

    WW_RefreshMaximizedFullscreenCycle()

    if WW_maximized_fullscreen_cycle.Length = 0 {
        WW_last_maximized_fullscreen_hwnd := 0
        WW_DebugLog("Expanded-window cycle stopped: no candidates detected.")
        return
    }

    active_hwnd := WinExist("A")
    target_hwnd := WW_NextMaximizedFullscreenWindow(WW_maximized_fullscreen_cycle, active_hwnd,
        WW_last_maximized_fullscreen_hwnd)

    WW_DebugLog("Expanded-window cycle step." . " | from=" DescribeWindow(active_hwnd)
        . " | to=" DescribeWindow(target_hwnd))

    if WW_ShowMaximizedFullscreenCycleWindow(WW_maximized_fullscreen_cycle, target_hwnd)
        WW_last_maximized_fullscreen_hwnd := target_hwnd
}

WW_NextMaximizedFullscreenWindow(windows, active_hwnd, last_hwnd)
{
    if !windows.Length
        return 0
    active_index := WW_FindWindowIndex(windows, active_hwnd)
    if active_index
        return active_index = windows.Length ? 0 : windows[active_index + 1]
    if WW_FindWindowIndex(windows, last_hwnd)
        return last_hwnd
    return windows[1]
}

WW_RefreshMaximizedFullscreenCycle()
{
    global WW_maximized_fullscreen_cycle

    ; Minimized members stay; closed and normal-size windows fall out.
    WW_maximized_fullscreen_cycle := WW_MergeCycleOrder(WW_maximized_fullscreen_cycle,
        WW_GetMaximizedFullscreenWindows())
}

WW_GetMaximizedFullscreenWindows()
{
    windows := []

    for hwnd in WinGetList() {
        if WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
            windows.Push(hwnd)
    }

    return windows
}

WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
{
    if !IsSwitchableWindow(hwnd, true)
        return false
    try {
        state := WinGetMinMax(hwnd)
        if state != -1
            return state = 1 || WW_IsNativeFullscreen(hwnd)

        placement := CaptureWindowPlacement(hwnd)
        ; Windows remembers whether an iconic window should restore maximized.
        if (NumGet(placement, 4, "uint") & 0x0002) ; WPF_RESTORETOMAXIMIZED
            || SuiteFullscreen.placements.Has(hwnd)
            return true

        ; Native fullscreen is a normal-state window filling a physical monitor.
        ; Its current minimized rectangle cannot identify that saved geometry.
        return WW_WindowPlacementFillsPhysicalMonitor(placement, WW_GetWindowMonitorInfo(hwnd))
    }
    catch
        return false
}

WW_WindowPlacementFillsPhysicalMonitor(placement, monitor_info, tolerance := 2)
{
    ; Candidates exclude tool windows, so rcNormalPosition uses workspace
    ; coordinates. Convert to screen coordinates, including top/left taskbars.
    offset_x := NumGet(monitor_info, 20, "int") - NumGet(monitor_info, 4, "int")
    offset_y := NumGet(monitor_info, 24, "int") - NumGet(monitor_info, 8, "int")
    return WW_RectCoversMonitor(
        [NumGet(placement, 28, "int") + offset_x, NumGet(placement, 32, "int") + offset_y,
            NumGet(placement, 36, "int") + offset_x, NumGet(placement, 40, "int") + offset_y],
        [NumGet(monitor_info, 4, "int"), NumGet(monitor_info, 8, "int"),
            NumGet(monitor_info, 12, "int"), NumGet(monitor_info, 16, "int")], tolerance)
}

; A window fills its display when it covers every edge. Borderless games such
; as Chrono Trigger may overhang by tens of pixels; a window stretched over
; another display does not count. Rectangles are [left, top, right, bottom].
WW_RectCoversMonitor(rect, monitor, tolerance := 2)
{
    overhang_x := Max(tolerance, (monitor[3] - monitor[1]) // 16)
    overhang_y := Max(tolerance, (monitor[4] - monitor[2]) // 16)
    return rect[1] <= monitor[1] + tolerance && rect[1] >= monitor[1] - overhang_x
        && rect[2] <= monitor[2] + tolerance && rect[2] >= monitor[2] - overhang_y
        && rect[3] >= monitor[3] - tolerance && rect[3] <= monitor[3] + overhang_x
        && rect[4] >= monitor[4] - tolerance && rect[4] <= monitor[4] + overhang_y
}

WW_WindowFillsPhysicalMonitor(hwnd, tolerance := 2)
{
    try {
        if !GetVisibleWindowBounds(hwnd, &window_x, &window_y, &window_width, &window_height) {
            WinGetPos(&window_x, &window_y, &window_width, &window_height, "ahk_id " hwnd)
        }

        WW_GetWindowMonitorBounds(hwnd, &monitor_left, &monitor_top, &monitor_right, &monitor_bottom
        )
    }
    catch {
        return false
    }

    return WW_RectCoversMonitor([window_x, window_y, window_x + window_width, window_y + window_height],
        [monitor_left, monitor_top, monitor_right, monitor_bottom], tolerance)
}

WW_ShowMaximizedFullscreenCycleWindow(windows, target_hwnd)
{
    if target_hwnd && !WW_IsMaximizedFullscreenSwitcherWindow(target_hwnd)
        return false

    ; Minimize the whole snapshot before restoring the next window. Target 0 is
    ; the all-minimized step; clearing the last target starts the next pass at 1.
    for hwnd in windows {
        if hwnd = target_hwnd || !WW_IsMaximizedFullscreenSwitcherWindow(hwnd)
            continue
        try {
            if WinGetMinMax(hwnd) != -1
                WinMinimize(hwnd)
            if WinExist(hwnd) && WinGetMinMax(hwnd) != -1 {
                WW_DebugLog("Expanded-window cycle could not minimize hwnd=" hwnd)
                return false
            }
        }
        catch Error as err {
            if WinExist(hwnd) {
                WW_DebugError("Expanded-window cycle minimize", err)
                return false
            }
        }
    }

    return !target_hwnd || ActivateWindow(target_hwnd)
}
