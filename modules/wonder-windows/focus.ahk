; Wonder Windows focus cycling, the focus highlight and focus after minimizing.

; =============================================================================
; focus cycling
; =============================================================================

; Down steps to the next visible window in reading order, up to the previous
; one, wrapping at both ends: displays left to right, then columns left to
; right, then top before bottom. A stack of overlapping windows counts once,
; as its front window; Win + Enter reaches the windows behind it.
WW_CycleWindowFocus(direction)
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    active_hwnd := WinExist("A")
    if !active_hwnd
        return

    ; The first press outlines the current window instead of leaving it. A
    ; manual focus change also starts a new session from that window.
    if !WW_focus_navigation_active || active_hwnd != WW_focus_navigation_hwnd {
        WW_ForgetLastMinimizedWindow()
        WW_focus_navigation_active := true
        WW_focus_navigation_hwnd := active_hwnd
        WW_HighlightFocusedWindow(active_hwnd)
        return
    }

    windows := []
    for entry in WW_SortFocusEntries(WW_FrontFocusEntries(WW_GetFocusEntries(), active_hwnd))
        windows.Push(entry.hwnd)
    if !windows.Length
        return
    index := WW_GetNextCycleIndex(WW_FindWindowIndex(windows, active_hwnd), windows.Length,
        direction = "up")
    if windows[index] = active_hwnd
        return

    WW_ForgetLastMinimizedWindow()
    if ActivateWindow(windows[index]) {
        WW_focus_navigation_hwnd := windows[index]
        WW_HighlightFocusedWindow(windows[index])
    }
}

WW_GetFocusEntries()
{
    entries := []
    for hwnd in WinGetList() {
        if !IsSwitchableWindow(hwnd)
            continue
        if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height) {
            try WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
            catch
                continue
        }
        monitor_left := 0
        if monitor := WindowMonitorIndex(hwnd)
            MonitorGetPixels(monitor, &monitor_left)
        entries.Push({hwnd: hwnd, monitor: monitor_left, x: x, y: y, rect: [x, y, width, height]})
    }
    return entries
}

; Drops windows stacked behind another, keeping keep_hwnd so a session can
; continue from it. Entries come front to back.
WW_FrontFocusEntries(entries, keep_hwnd)
{
    front := []
    for index, entry in entries {
        hidden := false
        if entry.hwnd != keep_hwnd {
            Loop index - 1
                if WW_WindowsStack(entries[A_Index].rect, entry.rect) {
                    hidden := true
                    break
                }
        }
        if !hidden
            front.Push(entry)
    }
    return front
}

; Reading order. Edges within a few pixels count as one column or row.
WW_FocusEntryBefore(first, second, tolerance := 8)
{
    if first.monitor != second.monitor
        return first.monitor < second.monitor
    if Abs(first.x - second.x) > tolerance
        return first.x < second.x
    if Abs(first.y - second.y) > tolerance
        return first.y < second.y
    return first.hwnd < second.hwnd
}

WW_SortFocusEntries(entries)
{
    sorted := []
    for entry in entries {
        position := sorted.Length + 1
        while position > 1 && WW_FocusEntryBefore(entry, sorted[position - 1])
            position -= 1
        sorted.InsertAt(position, entry)
    }
    return sorted
}

; =============================================================================
; focus after minimize
; =============================================================================

WW_FocusAfterMinimize(minimized_hwnd)
{
    ; Prefer the foreground window Windows naturally selects after minimization.
    ; Wait briefly because shell focus transitions are not always immediate.
    Loop 8 {
        if A_Index > 1
            Sleep 25

        foreground_hwnd := DllCall("GetForegroundWindow", "ptr")

        if foreground_hwnd != minimized_hwnd
            && IsSwitchableWindow(foreground_hwnd)
        {
            WW_BeginSpatialFocus(foreground_hwnd)
            return
        }
    }

    ; If Windows left focus on the shell, activate the topmost eligible window
    ; on the current desktop. Cloaked/minimized/shell windows are filtered out.
    for hwnd in WinGetList() {
        if hwnd = minimized_hwnd
            continue

        if !IsSwitchableWindow(hwnd)
            continue

        if ActivateWindow(hwnd) {
            WW_BeginSpatialFocus(hwnd)
            return
        }
    }

    ; With no other eligible window, leave focus to the Windows shell/desktop.
    WW_EndFocusNavigationSession()
}

WW_BeginSpatialFocus(hwnd)
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    if !hwnd || !WinExist("ahk_id " hwnd) {
        WW_EndFocusNavigationSession()
        return false
    }

    WW_focus_navigation_active := true
    WW_focus_navigation_hwnd := hwnd
    WW_HighlightFocusedWindow(hwnd)
    return true
}

; =============================================================================
; focus highlight and session lifetime
; =============================================================================

WW_HighlightFocusedWindow(hwnd)
{
    ; The border belongs to core. Wonder Windows owns only its navigation session.
    if SuiteFocusBorder.Show(hwnd, "wonder-windows")
        SetTimer WW_EndFocusNavigationSession, -SuiteFocusBorder.durationMs
    else
        WW_EndFocusNavigationSession()
}

WW_EndFocusNavigationSession()
{
    global WW_focus_navigation_active, WW_focus_navigation_hwnd

    previous_critical := A_IsCritical
    Critical "On"
    try {
        SetTimer WW_EndFocusNavigationSession, 0
        WW_focus_navigation_active := false
        WW_focus_navigation_hwnd := 0
        ; A late Wonder Windows timer cannot erase a newer Cascade Kingdom border.
        SuiteFocusBorder.Hide("wonder-windows")
    }
    finally {
        Critical previous_critical
    }
}
