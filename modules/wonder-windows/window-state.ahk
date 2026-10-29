; Wonder Windows maximize, minimize and restore.

; =============================================================================
; target selection
; =============================================================================

WW_GetWindowControlTarget(restore_minimized := true)
{
    global WW_last_minimized_hwnd

    if WW_last_minimized_hwnd {
        hwnd := WW_last_minimized_hwnd
        WW_last_minimized_hwnd := 0

        if WinExist("ahk_id " hwnd) {
            if !restore_minimized
                return hwnd

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    WinRestore("ahk_id " hwnd)

                WinActivate("ahk_id " hwnd)
                return hwnd
            }
        }
    }

    hwnd := WinExist("A")
    if !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        return 0
    try return IsShellSurfaceClass(WinGetClass(hwnd)) ? 0 : hwnd
    catch
        return 0
}


WW_ForgetLastMinimizedWindow()
{
    global WW_last_minimized_hwnd
    WW_last_minimized_hwnd := 0
}

; =============================================================================
; maximize / minimize / restore
; =============================================================================

WW_MaximizeWindowTarget()
{
    hwnd := WW_GetWindowControlTarget(false)
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

WW_MinimizeActiveWindow()
{
    Critical "On"

    global WW_last_minimized_hwnd

    hwnd := WinExist("A")

    ; When focus has fallen back to the shell/desktop, use Win+Backspace as a
    ; toggle for the most recent window minimized with this shortcut. Never
    ; minimize Explorer, the taskbar, StartAllBack, or another shell surface.
    if !hwnd || !IsSwitchableWindow(hwnd) {
        if WW_last_minimized_hwnd
            && WinExist("ahk_id " WW_last_minimized_hwnd)
        {
            restore_hwnd := WW_last_minimized_hwnd
            WW_last_minimized_hwnd := 0

            try {
                if WinGetMinMax(restore_hwnd) = -1
                    WinRestore(restore_hwnd)

                WW_EndFocusNavigationSession()
                WinActivate(restore_hwnd)
            }
            catch Error as err {
                WW_DebugError("Restore last minimized window", err)
            }
        } else {
            WW_last_minimized_hwnd := 0
            WW_EndFocusNavigationSession()
        }

        return
    }

    try {
        WinMinimize(hwnd)
        WW_last_minimized_hwnd := hwnd

        ; Move focus forward without clearing the just-minimized restore target.
        WW_FocusAfterMinimize(hwnd)
    }
    catch Error as err {
        WW_DebugError("Minimize active window", err)
    }
}

; Win + Down: a placed, maximized or fullscreen window returns to its normal
; rectangle; a window already there is minimized; the next press restores it.
WW_RestoreOrMinimizeWindow()
{
    global WW_last_minimized_hwnd, WW_normal_window_placements
    Critical "On"
    if WW_last_minimized_hwnd && WinExist("ahk_id " WW_last_minimized_hwnd) {
        WW_EndFocusNavigationSession()
        WW_GetWindowControlTarget() ; restores and activates the minimized window
        return
    }
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

    SuiteWindowOwnership.Claim(hwnd)
    try {
        if !WW_RestoreNormalWindowPlacement(hwnd) {
            WinRestore(hwnd)
            if WinGetMinMax(hwnd) = 1
                WinRestore(hwnd)
        }
        WW_ForgetStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WinActivate(hwnd)
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
