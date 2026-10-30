; Wonder Windows focus cycling and focus after minimizing. The outline is core's
; SuiteFocusBorder; Caps + Caps shows it on the current window.

; =============================================================================
; focus cycling
; =============================================================================

; Down steps to the next visible window in reading order, up to the previous
; one, wrapping at both ends: displays left to right, then columns left to
; right, then top before bottom. A stack of overlapping windows counts once,
; as its front window; Win + Enter reaches the windows behind it. Every press
; steps and outlines the window it lands on.
WW_CycleWindowFocus(direction)
{
    active_hwnd := WinExist("A")
    if !active_hwnd
        return

    windows := []
    for entry in WW_SortFocusEntries(WW_FrontFocusEntries(WW_GetFocusEntries(), active_hwnd))
        windows.Push(entry.hwnd)
    if !windows.Length
        return
    index := WW_GetNextCycleIndex(WW_FindWindowIndex(windows, active_hwnd), windows.Length,
        direction = "up")
    if windows[index] = active_hwnd
        return

    if ActivateWindow(windows[index])
        SuiteFocusBorder.Show(windows[index], "wonder-windows")
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
            SuiteFocusBorder.Show(foreground_hwnd, "wonder-windows")
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
            SuiteFocusBorder.Show(hwnd, "wonder-windows")
            return
        }
    }
    ; With no other eligible window, focus stays with the Windows shell/desktop.
}
