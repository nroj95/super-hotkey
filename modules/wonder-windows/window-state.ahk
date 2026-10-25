; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; minimize / restore window groups
; =============================================================================

WW_ToggleOtherWindows()
{
    global WW_isolation_minimized_windows, WW_isolation_active_hwnd

    isolating := !WW_isolation_minimized_windows.Length
    WW_ToggleMinimizedWindowGroup(&WW_isolation_minimized_windows, &WW_isolation_active_hwnd, true)
    ; Briefly outline the window left on screen, unless it already fills it.
    hwnd := WW_isolation_active_hwnd
    if isolating && hwnd && WinExist("ahk_id " hwnd)
        && WinGetMinMax("ahk_id " hwnd) = 0 && !WW_IsNativeFullscreen(hwnd)
        SuiteFocusBorder.Show(hwnd, "wonder-windows")
}

WW_ToggleAllWindows()
{
    global WW_all_minimized_windows, WW_all_active_hwnd

    WW_ToggleMinimizedWindowGroup(&WW_all_minimized_windows, &WW_all_active_hwnd)
}

WW_ToggleMinimizedWindowGroup(&minimized_windows, &saved_active_hwnd, keep_active_window := false)
{
    ; Each toggle restores only its own saved group. Windows already minimized
    ; before that toggle stay untouched.
    if minimized_windows.Length {
        windows_to_restore := minimized_windows
        restore_focus_hwnd := saved_active_hwnd

        minimized_windows := []
        saved_active_hwnd := 0

        ; Preserve the existing order: isolation restores front-to-back;
        ; Win+M restores back-to-front before returning focus.
        Loop windows_to_restore.Length {
            index := (keep_active_window ? A_Index : windows_to_restore.Length - A_Index + 1)
            hwnd := windows_to_restore[index]

            if !WinExist("ahk_id " hwnd)
                continue

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    WinRestore("ahk_id " hwnd)
            }
        }

        if restore_focus_hwnd
            && WinExist("ahk_id " restore_focus_hwnd)
        {
            try WinActivate("ahk_id " restore_focus_hwnd)
        }

        return
    }

    active_hwnd := WinExist("A")

    if keep_active_window && !active_hwnd
        return

    saved_active_hwnd := active_hwnd
    windows_to_minimize := []

    ; Snapshot before minimizing anything, because minimization changes focus
    ; and window order.
    for hwnd in WinGetList() {
        if keep_active_window && hwnd = active_hwnd
            continue

        if !IsSwitchableWindow(hwnd)
            continue

        windows_to_minimize.Push(hwnd)
    }

    for hwnd in windows_to_minimize {
        try {
            WinMinimize("ahk_id " hwnd)
            minimized_windows.Push(hwnd)
        }
    }
}

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
            WW_ForgetHorizontalStretch(hwnd)
            WW_ForgetVerticalStretch(hwnd)
            WW_ForgetFullStretch(hwnd)
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
        WW_ForgetHorizontalStretch(hwnd)
        WW_ForgetVerticalStretch(hwnd)
        WW_ForgetFullStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WinActivate(hwnd)
    }
    catch Error as err
        WW_DebugError("Restore normal window", err)
}

; =============================================================================
; close the active window
; =============================================================================

; The command runs only while its hotkey's foreground window is still active.
WW_CloseActiveWindow()
{
    hwnd := DllCall("GetForegroundWindow", "ptr")
    WW_CloseWindow(hwnd, WindowProcessId(hwnd))
}

; Closing asks the app to close, then lets Windows pick foreground.
; Some apps leave the taskbar or desktop active instead. Capture the eligible
; Z-order BEFORE closing so the fallback works across all monitors.
WW_CaptureCloseFocusTargets(closing_hwnd)
{
    targets := []
    for hwnd in WinGetList() {
        if hwnd = closing_hwnd || !IsSwitchableWindow(hwnd)
            continue
        try targets.Push({hwnd: hwnd, pid: WinGetPID("ahk_id " hwnd)})
    }
    return targets
}

; Preserve ordinary focus handoffs, including modal save/confirmation dialogs.
; Unlike the fallback candidate test, a real foreground dialog may be owned.
WW_HasUsableCloseForeground(hwnd, closing_hwnd, closing_pid)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    if hwnd = closing_hwnd {
        try {
            if WinGetPID("ahk_id " hwnd) = closing_pid
                return false
        }
        catch
            return false
    }
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("IsIconic", "ptr", hwnd, "int")
        || IsWindowCloaked(hwnd) || IsShellSurfaceWindow(hwnd)
        || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        return false
    try return !(WinGetExStyle("ahk_id " hwnd) & 0x08000000) ; WS_EX_NOACTIVATE
    catch
        return false
}

WW_CloseOriginStillVisible(hwnd, pid)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    try return WinGetPID("ahk_id " hwnd) = pid
        && DllCall("IsWindowVisible", "ptr", hwnd, "int")
        && !DllCall("IsIconic", "ptr", hwnd, "int")
        && !IsWindowCloaked(hwnd)
    catch
        return false
}

WW_CloseFocusDecision(other_focused, origin_visible)
{
    return other_focused ? "preserve" : (origin_visible ? "wait" : "recover")
}

; The accent border belongs to a completed close, never to a pending save dialog.
WW_ShouldHighlightCloseFocus(outcome, origin_visible)
{
    return outcome = "preserve" && !origin_visible
}

WW_CloseWindow(hwnd, pid)
{
    global WW_close_focus_request
    if !hwnd || !pid || DllCall("GetForegroundWindow", "ptr") != hwnd
        return
    try {
        if WinGetPID("ahk_id " hwnd) != pid
            return
        targets := WW_CaptureCloseFocusTargets(hwnd)
        ; Invalidate an earlier close request even if this was the last window.
        WW_close_focus_request := 0
        WinClose("ahk_id " hwnd)
        ; Watch even with no fallback targets: Windows may still focus a valid
        ; window that became available during the close.
        request := {hwnd: hwnd, pid: pid, targets: targets, started: A_TickCount}
        WW_close_focus_request := request
        SetTimer(WW_WatchCloseFocus.Bind(request), -130)
    }
    catch Error as err
        WW_DebugError("Close active window", err)
}

WW_WatchCloseFocus(request)
{
    global WW_close_focus_request
    if WW_close_focus_request != request
        return

    foreground := DllCall("GetForegroundWindow", "ptr")
    origin_visible := WW_CloseOriginStillVisible(request.hwnd, request.pid)
    outcome := WW_CloseFocusDecision(
        WW_HasUsableCloseForeground(foreground, request.hwnd, request.pid),
        origin_visible)
    elapsed := (A_TickCount - request.started) & 0xFFFFFFFF

    if outcome = "preserve" {
        if !WW_ShouldHighlightCloseFocus(outcome, origin_visible) {
            ; Keep native focus untouched, including save dialogs. If the close
            ; completes shortly afterward, the next poll highlights its result.
            if elapsed < 3500
                SetTimer(WW_WatchCloseFocus.Bind(request), -140)
            else
                WW_close_focus_request := 0
            return
        }
        WW_close_focus_request := 0
        ; Focus may have changed while the timer ran: highlight only the real
        ; current foreground, never an earlier snapshot.
        foreground := DllCall("GetForegroundWindow", "ptr")
        if WW_HasUsableCloseForeground(foreground, request.hwnd, request.pid) {
            SuiteFocusBorder.Show(foreground, "wonder-windows-close")
            WW_DebugLog("Close native focus highlighted. | target="
                . DescribeWindow(foreground))
        }
        return
    }

    if outcome = "wait" {
        ; WinClose can be asynchronous. Do not steal focus from an application
        ; that is still visible, or while it is waiting for a save prompt.
        if elapsed < 3500
            SetTimer(WW_WatchCloseFocus.Bind(request), -140)
        else
            WW_close_focus_request := 0
        return
    }

    ; Don't race a manual mouse/keyboard action during the shell handoff.
    for key in ["LButton", "RButton", "MButton", "LWin", "RWin", "Alt", "Ctrl"] {
        if GetKeyState(key, "P") {
            if elapsed < 3500
                SetTimer(WW_WatchCloseFocus.Bind(request), -140)
            else
                WW_close_focus_request := 0
            return
        }
    }

    WW_close_focus_request := 0
    for target in request.targets {
        try {
            if !WinExist("ahk_id " target.hwnd)
                || WinGetPID("ahk_id " target.hwnd) != target.pid
                || !IsSwitchableWindow(target.hwnd)
                continue
            ; Never override a real foreground switch while evaluating choices.
            foreground := DllCall("GetForegroundWindow", "ptr")
            if WW_HasUsableCloseForeground(foreground, request.hwnd, request.pid)
                return
            if ActivateWindow(target.hwnd) {
                ; Match Win+Backspace: show the accent border on the window
                ; actually focused by the fallback, including other monitors.
                if DllCall("GetForegroundWindow", "ptr") = target.hwnd
                    SuiteFocusBorder.Show(target.hwnd, "wonder-windows-close")
                WW_DebugLog("Close focus fallback. | target="
                    . DescribeWindow(target.hwnd))
                return
            }
        }
        catch Error as err
            WW_DebugError("Close focus fallback", err)
    }
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
