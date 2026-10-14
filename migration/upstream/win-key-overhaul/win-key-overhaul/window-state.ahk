; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; minimize / restore window groups
; =============================================================================

ToggleOtherWindows()
{
    global isolation_minimized_windows, isolation_active_hwnd

    ToggleMinimizedWindowGroup(
        &isolation_minimized_windows,
        &isolation_active_hwnd,
        true
    )
}

ToggleAllWindows()
{
    global all_minimized_windows, all_active_hwnd

    ToggleMinimizedWindowGroup(&all_minimized_windows, &all_active_hwnd)
}

ToggleMinimizedWindowGroup(
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

        if !IsWindowToggleCandidate(hwnd)
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

GetWindowControlTarget(restore_minimized := true)
{
    global last_minimized_hwnd

    if last_minimized_hwnd {
        hwnd := last_minimized_hwnd
        last_minimized_hwnd := 0

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

    return WinExist("A")
}

ForgetLastMinimizedWindow()
{
    global last_minimized_hwnd
    last_minimized_hwnd := 0
}

; =============================================================================
; maximize / minimize / restore
; =============================================================================

MaximizeWindowTarget()
{
    global borderless_windows

    ; Leave a just-minimized window minimized until this command decides its
    ; next state. WinMaximize can promote it directly to maximized.
    hwnd := GetWindowControlTarget(false)

    if !hwnd
        return

    ForgetHorizontalStretch(hwnd)
    ForgetVerticalStretch(hwnd)

    window := "ahk_id " hwnd

    try {
        if borderless_windows.Has(hwnd) {
            RestoreBorderlessWindow(hwnd, true)
            WinActivate(window)
            return
        }

        if WinGetMinMax(window) = 1 {
            EnterBorderlessFullscreen(hwnd)
            return
        }

        WinMaximize(window)
    }
}

MinimizeActiveWindow()
{
    Critical "On"

    global last_minimized_hwnd
    global borderless_windows

    hwnd := WinExist("A")

    ; When focus has fallen back to the shell/desktop, use Win+Backspace as a
    ; toggle for the most recent window minimized with this shortcut. Never
    ; minimize Explorer, the taskbar, StartAllBack, or another shell surface.
    if !hwnd || !IsWindowToggleCandidate(hwnd) {
        if last_minimized_hwnd
            && WinExist("ahk_id " last_minimized_hwnd)
        {
            restore_hwnd := last_minimized_hwnd
            last_minimized_hwnd := 0

            try {
                if WinGetMinMax(restore_hwnd) = -1
                    WinRestore(restore_hwnd)

                EndFocusNavigationSession()
                WinActivate(restore_hwnd)
            }
            catch Error as err {
                DebugError("Restore last minimized window", err)
            }
        } else {
            last_minimized_hwnd := 0
            EndFocusNavigationSession()
        }

        return
    }

    try {
        if borderless_windows.Has(hwnd)
            RestoreBorderlessWindow(hwnd, false, true)

        WinMinimize(hwnd)
        last_minimized_hwnd := hwnd

        ; Move focus forward without clearing the just-minimized restore target.
        FocusAfterMinimize(hwnd)
    }
    catch Error as err {
        DebugError("Minimize active window", err)
    }
}

RestoreWindowTarget()
{
    Critical "On"

    global borderless_windows

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    try {
        if borderless_windows.Has(hwnd)
            RestoreBorderlessWindow(hwnd, false, true)

        if !RestoreNormalWindowPlacement(hwnd) {
            WinRestore(hwnd)

            ; A minimized maximized window may first restore maximized.
            if WinGetMinMax(hwnd) = 1
                WinRestore(hwnd)
        }

        ForgetHorizontalStretch(hwnd)
        ForgetVerticalStretch(hwnd)
        ForgetWindowLayoutCycle(hwnd)
        WinActivate(hwnd)
    }
    catch Error as err {
        DebugError("Restore normal window", err)
    }
}

; =============================================================================
; normal rectangle before script-managed placement or stretch
; =============================================================================

RememberNormalWindowPlacement(hwnd)
{
    global normal_window_placements, borderless_windows

    process_id := WinGetPID(hwnd)
    work_area := GetLayoutWorkArea(hwnd)

    if normal_window_placements.Has(hwnd) {
        saved := normal_window_placements[hwnd]

        if saved["pid"] = process_id
            && RectanglesMatch(saved["work_area"], work_area, 0)
        {
            return
        }

        normal_window_placements.Delete(hwnd)
    }

    ; A borderless window's live rectangle is fullscreen, not its normal one.
    placement := borderless_windows.Has(hwnd)
        ? borderless_windows[hwnd]["placement"]
        : CaptureWindowPlacement(hwnd)

    normal_window_placements[hwnd] := Map(
        "pid", process_id,
        "work_area", work_area,
        "placement", placement
    )
}

RestoreNormalWindowPlacement(hwnd)
{
    global normal_window_placements

    if !normal_window_placements.Has(hwnd)
        return false

    saved := normal_window_placements[hwnd]

    if !WindowStateMatchesProcess(hwnd, saved)
        || !RectanglesMatch(saved["work_area"], GetLayoutWorkArea(hwnd), 0)
    {
        ; Do not pull a manually moved window back to an old monitor or restore
        ; stale coordinates after a work-area/resolution change.
        normal_window_placements.Delete(hwnd)
        return false
    }

    ApplyWindowPlacement(hwnd, saved["placement"], 1) ; SW_SHOWNORMAL
    normal_window_placements.Delete(hwnd)
    return true
}
