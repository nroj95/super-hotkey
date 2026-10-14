; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; minimize / restore window groups
; =============================================================================

WW_ToggleOtherWindows()
{
    global WW_isolation_minimized_windows, WW_isolation_active_hwnd

    WW_ToggleMinimizedWindowGroup(
        &WW_isolation_minimized_windows,
        &WW_isolation_active_hwnd,
        true
    )
}

WW_ToggleAllWindows()
{
    global WW_all_minimized_windows, WW_all_active_hwnd

    WW_ToggleMinimizedWindowGroup(&WW_all_minimized_windows, &WW_all_active_hwnd)
}

WW_ToggleMinimizedWindowGroup(
    &minimized_windows,
    &saved_active_hwnd,
    keep_active_window := false
)
{
    ; Each toggle restores only its own saved group. Windows already minimized
    ; before that toggle stay untouched.
    if minimized_windows.Length {
        windows_to_restore := minimized_windows
        restore_focus_hwnd := saved_active_hwnd

        minimized_windows := []
        saved_active_hwnd := 0

        ; Preserve the existing order: Win+Shift+Home restores front-to-back;
        ; Win+M restores back-to-front before returning focus.
        Loop windows_to_restore.Length {
            index := (
                keep_active_window
                ? A_Index
                : windows_to_restore.Length - A_Index + 1
            )
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

        if !WW_IsWindowToggleCandidate(hwnd)
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
    if !hwnd || SuiteWindowOwnership.IsSuiteSurface(hwnd)
        return 0
    try return WW_IsWinKeyOverhaulShellClass(WinGetClass(hwnd)) ? 0 : hwnd
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
    global WW_borderless_windows

    ; Leave a just-minimized window minimized until this command decides its
    ; next state. WinMaximize can promote it directly to maximized.
    hwnd := WW_GetWindowControlTarget(false)

    if !hwnd
        return
    SuiteWindowOwnership.Claim(hwnd)

    WW_ForgetHorizontalStretch(hwnd)
    WW_ForgetVerticalStretch(hwnd)

    window := "ahk_id " hwnd

    try {
        if WW_borderless_windows.Has(hwnd) {
            WW_RestoreBorderlessWindow(hwnd, true)
            WinActivate(window)
            return
        }

        if WinGetMinMax(window) = 1 {
            WW_EnterBorderlessFullscreen(hwnd)
            return
        }

        WinMaximize(window)
    }
}

WW_MinimizeActiveWindow()
{
    Critical "On"

    global WW_last_minimized_hwnd
    global WW_borderless_windows

    hwnd := WinExist("A")

    ; When focus has fallen back to the shell/desktop, use Win+Backspace as a
    ; toggle for the most recent window minimized with this shortcut. Never
    ; minimize Explorer, the taskbar, StartAllBack, or another shell surface.
    if !hwnd || !WW_IsWindowToggleCandidate(hwnd) {
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
        if WW_borderless_windows.Has(hwnd)
            WW_RestoreBorderlessWindow(hwnd, false, true)

        WinMinimize(hwnd)
        WW_last_minimized_hwnd := hwnd

        ; Move focus forward without clearing the just-minimized restore target.
        WW_FocusAfterMinimize(hwnd)
    }
    catch Error as err {
        WW_DebugError("Minimize active window", err)
    }
}

WW_RestoreWindowTarget()
{
    Critical "On"

    global WW_borderless_windows

    hwnd := WW_GetWindowControlTarget()

    if !hwnd
        return
    SuiteWindowOwnership.Claim(hwnd)

    try {
        if WW_borderless_windows.Has(hwnd)
            WW_RestoreBorderlessWindow(hwnd, false, true)

        if !WW_RestoreNormalWindowPlacement(hwnd) {
            WinRestore(hwnd)

            ; A minimized maximized window may first restore maximized.
            if WinGetMinMax(hwnd) = 1
                WinRestore(hwnd)
        }

        WW_ForgetHorizontalStretch(hwnd)
        WW_ForgetVerticalStretch(hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)
        WinActivate(hwnd)
    }
    catch Error as err {
        WW_DebugError("Restore normal window", err)
    }
}

; =============================================================================
; normal rectangle before script-managed placement or stretch
; =============================================================================

WW_RememberNormalWindowPlacement(hwnd)
{
    global WW_normal_window_placements, WW_borderless_windows

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

    ; A borderless window's live rectangle is fullscreen, not its normal one.
    placement := WW_borderless_windows.Has(hwnd)
        ? WW_borderless_windows[hwnd]["placement"]
        : WW_CaptureWindowPlacement(hwnd)

    WW_normal_window_placements[hwnd] := Map(
        "pid", process_id,
        "work_area", work_area,
        "placement", placement
    )
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
