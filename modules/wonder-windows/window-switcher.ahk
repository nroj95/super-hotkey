; Wonder Windows switchers: the windows stacked with the active one, and the
; maximized and fullscreen windows on the working display.

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

    ; A window with an open dialog hands the foreground to that dialog.
    activated := ActivateWindow(target)
        || DllCall("GetAncestor", "ptr", DllCall("GetForegroundWindow", "ptr"), "uint", 3, "ptr") = target
    WW_monitor_cycle_refused_hwnd := activated ? 0 : target
    WW_monitor_cycle_refused_from := activated ? 0 : current
    WW_DebugLog("Stacked window cycle focused a window. | activated=" (activated ? 1 : 0)
        . " | " DescribeWindow(target))
}

; =============================================================================
; maximized and fullscreen cycle
; =============================================================================

; Each press shows the next maximized or fullscreen window on the working
; display and minimizes the others there, so one big window is out at a time.
; Previous steps back. From any other window, the first press brings back the
; big window shown last; Win + Backspace puts it away again. The order stays
; fixed, because activation changes the Z-order. A maximized cascade window
; counts too: its cascade fills the gap while it is minimized. A notice says
; when there is nothing else to show.
WW_CycleMaximizedFullscreenWindows(direction)
{
    Critical "On"
    global WW_maximized_fullscreen_cycle, WW_last_maximized_fullscreen_hwnd

    ; One order for every display, so each display keeps its own while you switch.
    detected := []
    for hwnd in WinGetList()
        if WW_IsMaximizedOrFullscreen(hwnd)
            detected.Push(hwnd)
    WW_maximized_fullscreen_cycle := WW_MergeCycleOrder(WW_maximized_fullscreen_cycle, detected)

    monitor := SuiteWorkingMonitor.Get()
    windows := []
    for hwnd in WW_maximized_fullscreen_cycle
        if WindowMonitorIndex(hwnd) = monitor
            windows.Push(hwnd)
    if !windows.Length {
        SuiteNotice.Show("status", "No maximized or fullscreen windows here", 1400)
        return
    }

    active := SuiteWorkingMonitor.UserWindow()
    target := WW_NextMaximizedFullscreenWindow(windows, active, WW_last_maximized_fullscreen_hwnd,
        direction = "previous")
    ; The only big window here is already out.
    if target = active {
        SuiteNotice.Show("status", "No other maximized or fullscreen windows here", 1400)
        return
    }
    WW_DebugLog("Expanded-window cycle step. | monitor=" monitor " | windows=" windows.Length
        . " | to=" DescribeWindow(target))
    if WW_ShowMaximizedFullscreenWindow(windows, target)
        WW_last_maximized_fullscreen_hwnd := target
}

; The window after the active one, wrapping around. From outside the cycle,
; the last window shown, or else the first (the last going backwards).
WW_NextMaximizedFullscreenWindow(windows, active_hwnd, last_hwnd, backwards := false)
{
    if index := WW_FindWindowIndex(windows, active_hwnd)
        return windows[WW_GetNextCycleIndex(index, windows.Length, backwards)]
    if WW_FindWindowIndex(windows, last_hwnd)
        return last_hwnd
    return windows[backwards ? windows.Length : 1]
}

; Shows the target first, then minimizes the others: minimizing a background
; window never moves focus.
WW_ShowMaximizedFullscreenWindow(windows, target_hwnd)
{
    if !ActivateWindow(target_hwnd) {
        WW_DebugLog("Expanded-window cycle could not activate a window. | " DescribeWindow(target_hwnd))
        return false
    }
    for hwnd in windows {
        if hwnd = target_hwnd || DllCall("IsIconic", "ptr", hwnd, "int")
            continue
        try WinMinimize(hwnd)
        catch Error as err
            WW_DebugError("Expanded-window cycle minimize", err)
    }
    return true
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
