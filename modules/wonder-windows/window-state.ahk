; Wonder Windows maximize, minimize and restore.

; =============================================================================
; target selection
; =============================================================================

; Every Wonder Windows key acts on the active window.
WW_GetWindowControlTarget()
{
    hwnd := WinExist("A")
    if !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        return 0
    try return IsShellSurfaceClass(WinGetClass(hwnd)) ? 0 : hwnd
    catch
        return 0
}


; =============================================================================
; maximize / minimize / restore
; =============================================================================

WW_MaximizeWindowTarget()
{
    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    window := "ahk_id " hwnd
    try {
        was_fullscreen := WW_IsNativeFullscreen(hwnd)
        if !WW_SetNativeFullscreen(hwnd, false)
            return

        work_area := WW_GetLayoutWorkArea(hwnd)
        layouts := [WW_BuildRatioLayout(work_area, [0, 1, 0], "top"),
            WW_BuildRatioLayout(work_area, [0, 1, 0], "bottom")]

        maximized := WinGetMinMax(window) = 1
        tile_index := !maximized && !was_fullscreen
            ? WW_FindCurrentLayoutIndex(hwnd, "vertical-half", work_area, layouts)
            : 0
        next_index := WW_NextMaximizeCycleIndex(was_fullscreen, maximized, tile_index)

        if next_index = 0 {
            SuiteWindowOwnership.Claim(hwnd)
            WW_ForgetStretch(hwnd)
            WW_ForgetWindowLayoutCycle(hwnd)
            WinMaximize(window)
        } else {
            WW_PrepareWindowForPlacement(hwnd)
            WW_ApplyTrackedLayout(hwnd, "vertical-half", work_area, layouts, next_index)
        }
    }
    catch Error as err
        WW_DebugError("Maximize / vertical half", err)
}

WW_NextMaximizeCycleIndex(was_fullscreen, maximized, tile_index)
{
    if was_fullscreen
        return 0
    if maximized
        return 1
    return tile_index = 1 ? 2 : 0
}

; Win + Backspace minimizes the active window; Win + Shift + Backspace brings
; back the windows it minimized, newest first. Never minimize Explorer, the
; taskbar or another shell surface. Focus stays on the window's display while
; it has windows left.
WW_MinimizeActiveWindow()
{
    Critical "On"

    global WW_minimized_stack

    hwnd := WinExist("A")
    if !hwnd || !IsSwitchableWindow(hwnd)
        return

    try {
        monitor := WindowMonitorIndex(hwnd)
        WinMinimize(hwnd)
        for index, entry in WW_minimized_stack
            if entry.hwnd = hwnd {
                WW_minimized_stack.RemoveAt(index)
                break
            }
        WW_minimized_stack.InsertAt(1, {hwnd: hwnd, pid: WinGetPID(hwnd)})

        WW_FocusAfterMinimize(hwnd, monitor)
    }
    catch Error as err {
        WW_DebugError("Minimize active window", err)
    }
}

; Win + M minimizes every window, as Windows does, and Win + Shift + M brings
; them back with the frontmost on top again. Unlike Windows' own pair, a
; Win + M with nothing left to minimize keeps what Win + Shift + M restores,
; and a later Win + M adds to it. Like Windows, windows without a minimize
; button stay. windows is every window front to back unless the checks pass
; their own.
WW_MinimizeAllWindows(windows?)
{
    Critical "On"

    global WW_minimized_all

    added := []
    for hwnd in IsSet(windows) ? windows : WinGetList() {
        if !IsSwitchableWindow(hwnd)
            continue
        try {
            if !(WinGetStyle("ahk_id " hwnd) & 0x20000) ; WS_MINIMIZEBOX
                continue
            pid := WinGetPID("ahk_id " hwnd)
            WinMinimize("ahk_id " hwnd)
            added.Push({hwnd: hwnd, pid: pid})
        }
        catch Error as err
            WW_DebugError("Minimize all windows", err)
    }
    ; Windows minimized now were in front of those minimized before.
    for entry in WW_minimized_all {
        listed := false
        for newer in added
            listed := listed || newer.hwnd = entry.hwnd
        if !listed
            added.Push(entry)
    }
    WW_minimized_all := added
}

; Restores back to front, so the frontmost ends on top, and focuses it.
; Windows restored or closed another way are skipped.
WW_RestoreAllWindows()
{
    Critical "On"

    global WW_minimized_all

    entries := WW_minimized_all
    WW_minimized_all := []
    front := 0
    Loop entries.Length {
        entry := entries[entries.Length - A_Index + 1]
        try {
            if !WinExist("ahk_id " entry.hwnd) || WinGetPID("ahk_id " entry.hwnd) != entry.pid
                || WinGetMinMax("ahk_id " entry.hwnd) != -1
                continue
            WinRestore("ahk_id " entry.hwnd)
            front := entry.hwnd
        }
        catch Error as err
            WW_DebugError("Restore all windows", err)
    }
    if front
        ActivateWindow(front)
}

; Windows restored or closed another way are skipped as they come up.
WW_RestoreMinimizedWindow()
{
    Critical "On"

    global WW_minimized_stack

    while WW_minimized_stack.Length {
        entry := WW_minimized_stack.RemoveAt(1)
        try {
            if !WinExist("ahk_id " entry.hwnd) || WinGetPID("ahk_id " entry.hwnd) != entry.pid
                || WinGetMinMax("ahk_id " entry.hwnd) != -1
                continue
            WinRestore("ahk_id " entry.hwnd)
            if ActivateWindow(entry.hwnd)
                SuiteFocusBorder.Show(entry.hwnd, "wonder-windows")
            return
        }
        catch Error as err
            WW_DebugError("Restore minimized window", err)
    }
}

; Win + Down steps down: a placed, maximized or fullscreen window returns to
; its normal rectangle; a window already there is minimized. Win + Shift +
; Backspace brings it back.
WW_RestoreOrMinimizeWindow()
{
    global WW_normal_window_placements
    Critical "On"
    hwnd := WinExist("A")
    if !hwnd || !IsSwitchableWindow(hwnd)
        return
    try {
        if WW_IsAtNormalPlacement(WinGetMinMax(hwnd), WW_IsNativeFullscreen(hwnd),
            WW_normal_window_placements.Has(hwnd))
            WW_MinimizeActiveWindow()
        else
            WW_RestoreWindowTarget()
    }
    catch Error as err
        WW_DebugError("Restore or minimize window", err)
}

WW_IsAtNormalPlacement(min_max, native_fullscreen, has_saved_placement)
{
    return min_max = 0 && !native_fullscreen && !has_saved_placement
}

WW_RestoreWindowTarget()
{
    Critical "On"
    hwnd := WW_GetWindowControlTarget()
    if !hwnd || !WW_SetNativeFullscreen(hwnd, false)
        return

    try {
        placed := CaptureWindowShape(hwnd)
        if !WW_RestoreNormalWindowPlacement(hwnd) {
            WinRestore(hwnd)
            if WinGetMinMax(hwnd) = 1
                WinRestore(hwnd)
        }
        WW_ForgetStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WinActivate(hwnd)
        ; Back at its original shape, the window is no longer placed by hand;
        ; a cascade window rejoins its cascade, remembering where it was.
        SuiteWindowOwnership.Return(hwnd, placed)
    }
    catch Error as err
        WW_DebugError("Restore normal window", err)
}

; =============================================================================
; normal rectangle before script-managed placement or stretch
; =============================================================================

WW_RememberNormalWindowPlacement(hwnd)
{
    global WW_normal_window_placements

    process_id := WinGetPID(hwnd)
    work_area := WW_GetLayoutWorkArea(hwnd)

    if WW_normal_window_placements.Has(hwnd) {
        saved := WW_normal_window_placements[hwnd]

        if saved["pid"] = process_id
            && WW_RectanglesMatch(saved["work_area"], work_area, 0)
        {
            return
        }

        WW_normal_window_placements.Delete(hwnd)
    }

    placement := CaptureWindowPlacement(hwnd)

    WW_normal_window_placements[hwnd] := Map("pid", process_id, "work_area", work_area,
        "placement", placement)
}

WW_RestoreNormalWindowPlacement(hwnd)
{
    global WW_normal_window_placements

    if !WW_normal_window_placements.Has(hwnd)
        return false

    saved := WW_normal_window_placements[hwnd]

    if !WW_WindowStateMatchesProcess(hwnd, saved)
        || !WW_RectanglesMatch(saved["work_area"], WW_GetLayoutWorkArea(hwnd), 0)
    {
        ; Do not pull a manually moved window back to an old monitor or restore
        ; stale coordinates after a work-area/resolution change.
        WW_normal_window_placements.Delete(hwnd)
        return false
    }

    WW_ApplyWindowPlacement(hwnd, saved["placement"], 1) ; SW_SHOWNORMAL
    WW_normal_window_placements.Delete(hwnd)
    return true
}
