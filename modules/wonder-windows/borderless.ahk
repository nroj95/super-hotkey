; Wonder Windows implementation. Launch the suite, not this file.
; Included into the same script; functions share the existing global state.

; =============================================================================
; borderless fullscreen
; =============================================================================

WW_MarkBorderlessWindow(hwnd)
{
    static marker := "nroj.WinKeyOverhaul.Borderless"

    if !DllCall(
        "SetPropW",
        "ptr", hwnd,
        "str", marker,
        "ptr", 1,
        "int"
    ) {
        throw OSError(
            A_LastError,
            "SetPropW",
            "Could not mark the borderless window."
        )
    }
}

WW_ClearBorderlessWindowMarker(hwnd)
{
    static marker := "nroj.WinKeyOverhaul.Borderless"

    if hwnd && DllCall("IsWindow", "ptr", hwnd, "int")
        DllCall("RemovePropW", "ptr", hwnd, "str", marker, "ptr")
}

WW_EnterBorderlessFullscreen(hwnd)
{
    SuiteWindowOwnership.Claim(hwnd)
    global WW_borderless_windows

    if WW_borderless_windows.Has(hwnd)
        return

    window := "ahk_id " hwnd

    placement := WW_CaptureWindowPlacement(hwnd)
    original_style := WinGetStyle(window)
    was_topmost := !!(WinGetExStyle(window) & 0x8)

    WW_borderless_windows[hwnd] := Map(
        "pid", WinGetPID(hwnd),
        "style", original_style,
        "placement", placement,
        "was_topmost", was_topmost
    )

    try {
        WW_GetWindowMonitorBounds(
            hwnd,
            &left,
            &top,
            &right,
            &bottom
        )

        ; Borderless mode itself is an ordinary window whose frame has been
        ; removed and whose rectangle fills the physical monitor.
        if WinGetMinMax(window) != 0
            WinRestore(window)

        WinSetStyle("-0xC40000", window)
        WW_RefreshWindowFrame(hwnd)

        WinMove(
            left,
            top,
            right - left,
            bottom - top,
            window
        )

        WinSetAlwaysOnTop 1, window
        WW_MarkBorderlessWindow(hwnd)
        WinActivate(window)
    }
    catch {
        try WW_RestoreBorderlessWindow(hwnd, false)

        throw
    }
}

WW_RestoreBorderlessWindow(
    hwnd,
    restore_maximized := true,
    force_normal := false
)
{
    global WW_borderless_windows

    if !WW_borderless_windows.Has(hwnd)
        return

    saved := WW_borderless_windows[hwnd]
    window := "ahk_id " hwnd

    if !WW_WindowStateMatchesProcess(hwnd, saved) {
        WW_borderless_windows.Delete(hwnd)
        return
    }

    restore_succeeded := false

    try {
        if !saved["was_topmost"]
            WinSetAlwaysOnTop 0, window

        WinSetStyle(saved["style"], window)
        WW_RefreshWindowFrame(hwnd)

        if force_normal {
            WW_ApplyWindowPlacement(
                hwnd,
                saved["placement"],
                1 ; SW_SHOWNORMAL
            )
        } else {
            WW_ApplyWindowPlacement(
                hwnd,
                saved["placement"]
            )

            if restore_maximized
                WinMaximize(window)
        }

        if saved["was_topmost"]
            WinSetAlwaysOnTop 1, window

        WW_ClearBorderlessWindowMarker(hwnd)
        restore_succeeded := true
    }
    finally {
        if restore_succeeded
            WW_borderless_windows.Delete(hwnd)
    }
}

; =============================================================================
; switcher Z-order coordination
; =============================================================================

WW_PromoteBorderlessSwitcherTarget(hwnd)
{
    global WW_borderless_windows, WW_switcher_demoted_borderless_windows

    if !hwnd || !WW_borderless_windows.Has(hwnd)
        return false
    if !WW_WindowStateMatchesProcess(hwnd, WW_borderless_windows[hwnd]) {
        WW_borderless_windows.Delete(hwnd)
        WW_switcher_demoted_borderless_windows.Delete(hwnd)
        return false
    }

    promoted := false

    try {
        if !(WinGetExStyle("ahk_id " hwnd) & 0x8) { ; WS_EX_TOPMOST
            WinSetAlwaysOnTop 1, "ahk_id " hwnd
            promoted := true
        }

        if WW_switcher_demoted_borderless_windows.Has(hwnd)
            WW_switcher_demoted_borderless_windows.Delete(hwnd)

        if !WW_switcher_demoted_borderless_windows.Count
            SetTimer(WW_WatchDemotedBorderlessSwitcherWindows, 0)

        return promoted
    }
    catch Error as err {
        WW_DebugError("Promote borderless switcher target", err)
        return false
    }
}

WW_DemoteBorderlessSwitcherSource(hwnd)
{
    global WW_borderless_windows, WW_switcher_demoted_borderless_windows

    if !hwnd || !WW_borderless_windows.Has(hwnd)
        return
    if !WW_WindowStateMatchesProcess(hwnd, WW_borderless_windows[hwnd]) {
        WW_borderless_windows.Delete(hwnd)
        WW_switcher_demoted_borderless_windows.Delete(hwnd)
        return
    }

    try {
        if WinGetExStyle("ahk_id " hwnd) & 0x8 ; WS_EX_TOPMOST
            WinSetAlwaysOnTop 0, "ahk_id " hwnd

        WW_switcher_demoted_borderless_windows[hwnd] :=
            WW_borderless_windows[hwnd]["pid"]

        SetTimer(WW_WatchDemotedBorderlessSwitcherWindows, 75)
    }
    catch Error as err {
        WW_DebugError("Demote borderless switcher source", err)
    }
}

WW_WatchDemotedBorderlessSwitcherWindows(*)
{
    global WW_borderless_windows, WW_switcher_demoted_borderless_windows

    if !WW_switcher_demoted_borderless_windows.Count {
        SetTimer(WW_WatchDemotedBorderlessSwitcherWindows, 0)
        return
    }

    foreground_hwnd := DllCall("GetForegroundWindow", "ptr")
    stale_hwnds := []

    for hwnd, process_id in WW_switcher_demoted_borderless_windows {
        if !WW_borderless_windows.Has(hwnd)
            || !WW_WindowStateMatchesProcess(hwnd, WW_borderless_windows[hwnd])
            || WW_GetWindowProcessId(hwnd) != process_id
        {
            stale_hwnds.Push(hwnd)
            continue
        }

        if foreground_hwnd != hwnd
            continue

        try {
            WinSetAlwaysOnTop 1, "ahk_id " hwnd
            stale_hwnds.Push(hwnd)

            WW_DebugLog(
                "Restored borderless topmost state after switcher demotion."
                . " | " WW_DebugDescribeWindow(hwnd)
            )
        }
        catch Error as err {
            stale_hwnds.Push(hwnd)
            WW_DebugError("Restore switcher-demoted borderless window", err)
        }
    }

    for hwnd in stale_hwnds {
        if WW_switcher_demoted_borderless_windows.Has(hwnd)
            WW_switcher_demoted_borderless_windows.Delete(hwnd)
    }

    if !WW_switcher_demoted_borderless_windows.Count
        SetTimer(WW_WatchDemotedBorderlessSwitcherWindows, 0)
}

; =============================================================================
; script exit and reload cleanup
; =============================================================================

WW_RestoreAllBorderlessWindows(exit_reason, exit_code)
{
    global WW_borderless_windows

    windows := []

    for hwnd in WW_borderless_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !WW_WindowStateMatchesProcess(hwnd, WW_borderless_windows[hwnd]) {
            WW_borderless_windows.Delete(hwnd)
            continue
        }

        was_iconic := DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

        WW_DebugLog(
            "Borderless exit cleanup begin."
            . " | iconic=" was_iconic
            . " | target=" WW_DebugDescribeWindow(hwnd)
        )

        try {
            if was_iconic {
                saved := WW_borderless_windows[hwnd]
                window := "ahk_id " hwnd

                if !saved["was_topmost"]
                    WinSetAlwaysOnTop 0, window

                ; Restore the frame while the window is still minimized.
                WinSetStyle(saved["style"], window)
                WW_RefreshWindowFrame(hwnd)

                placement := saved["placement"]

                original_flags := NumGet(
                    placement,
                    4,
                    "uint"
                )

                try {
                    ; Reload is a clean restart. A window that was maximized
                    ; before entering borderless should restore as an ordinary
                    ; window after the script restart, not back to maximized.
                    NumPut(
                        "uint",
                        original_flags & ~0x0002,
                        placement,
                        4
                    )

                    WW_ApplyWindowPlacement(
                        hwnd,
                        placement,
                        7 ; SW_SHOWMINNOACTIVE
                    )
                }
                finally {
                    NumPut(
                        "uint",
                        original_flags,
                        placement,
                        4
                    )
                }

                if saved["was_topmost"]
                    WinSetAlwaysOnTop 1, window

                WW_ClearBorderlessWindowMarker(hwnd)
                WW_borderless_windows.Delete(hwnd)
            } else {
                WW_RestoreBorderlessWindow(hwnd, true)
            }

            WW_DebugLog(
                "Borderless exit cleanup complete."
                . " | target=" WW_DebugDescribeWindow(hwnd)
            )
        }
        catch Error as err {
            WW_DebugError(
                "RestoreAllBorderlessWindows hwnd=" hwnd,
                err
            )
        }
    }
}

WW_PruneBorderlessWindows()
{
    global WW_borderless_windows
    stale_hwnds := []
    for hwnd, saved in WW_borderless_windows {
        if !WW_WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }
    for hwnd in stale_hwnds
        WW_borderless_windows.Delete(hwnd)
}
