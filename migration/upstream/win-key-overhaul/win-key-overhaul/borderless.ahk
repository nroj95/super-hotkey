; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; borderless fullscreen
; =============================================================================

MarkBorderlessWindow(hwnd)
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

ClearBorderlessWindowMarker(hwnd)
{
    static marker := "nroj.WinKeyOverhaul.Borderless"

    if hwnd && DllCall("IsWindow", "ptr", hwnd, "int")
        DllCall("RemovePropW", "ptr", hwnd, "str", marker, "ptr")
}

EnterBorderlessFullscreen(hwnd)
{
    global borderless_windows

    if borderless_windows.Has(hwnd)
        return

    window := "ahk_id " hwnd

    placement := CaptureWindowPlacement(hwnd)
    original_style := WinGetStyle(window)
    was_topmost := !!(WinGetExStyle(window) & 0x8)

    borderless_windows[hwnd] := Map(
        "pid", WinGetPID(hwnd),
        "style", original_style,
        "placement", placement,
        "was_topmost", was_topmost
    )

    try {
        GetWindowMonitorBounds(
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
        RefreshWindowFrame(hwnd)

        WinMove(
            left,
            top,
            right - left,
            bottom - top,
            window
        )

        WinSetAlwaysOnTop 1, window
        MarkBorderlessWindow(hwnd)
        WinActivate(window)
    }
    catch {
        try RestoreBorderlessWindow(hwnd, false)

        throw
    }
}

RestoreBorderlessWindow(
    hwnd,
    restore_maximized := true,
    force_normal := false
)
{
    global borderless_windows

    if !borderless_windows.Has(hwnd)
        return

    saved := borderless_windows[hwnd]
    window := "ahk_id " hwnd

    if !WindowStateMatchesProcess(hwnd, saved) {
        borderless_windows.Delete(hwnd)
        return
    }

    restore_succeeded := false

    try {
        if !saved["was_topmost"]
            WinSetAlwaysOnTop 0, window

        WinSetStyle(saved["style"], window)
        RefreshWindowFrame(hwnd)

        if force_normal {
            ApplyWindowPlacement(
                hwnd,
                saved["placement"],
                1 ; SW_SHOWNORMAL
            )
        } else {
            ApplyWindowPlacement(
                hwnd,
                saved["placement"]
            )

            if restore_maximized
                WinMaximize(window)
        }

        if saved["was_topmost"]
            WinSetAlwaysOnTop 1, window

        ClearBorderlessWindowMarker(hwnd)
        restore_succeeded := true
    }
    finally {
        if restore_succeeded
            borderless_windows.Delete(hwnd)
    }
}

; =============================================================================
; switcher Z-order coordination
; =============================================================================

PromoteBorderlessSwitcherTarget(hwnd)
{
    global borderless_windows, switcher_demoted_borderless_windows

    if !hwnd || !borderless_windows.Has(hwnd)
        return false
    if !WindowStateMatchesProcess(hwnd, borderless_windows[hwnd]) {
        borderless_windows.Delete(hwnd)
        switcher_demoted_borderless_windows.Delete(hwnd)
        return false
    }

    promoted := false

    try {
        if !(WinGetExStyle("ahk_id " hwnd) & 0x8) { ; WS_EX_TOPMOST
            WinSetAlwaysOnTop 1, "ahk_id " hwnd
            promoted := true
        }

        if switcher_demoted_borderless_windows.Has(hwnd)
            switcher_demoted_borderless_windows.Delete(hwnd)

        if !switcher_demoted_borderless_windows.Count
            SetTimer(WatchDemotedBorderlessSwitcherWindows, 0)

        return promoted
    }
    catch Error as err {
        DebugError("Promote borderless switcher target", err)
        return false
    }
}

DemoteBorderlessSwitcherSource(hwnd)
{
    global borderless_windows, switcher_demoted_borderless_windows

    if !hwnd || !borderless_windows.Has(hwnd)
        return
    if !WindowStateMatchesProcess(hwnd, borderless_windows[hwnd]) {
        borderless_windows.Delete(hwnd)
        switcher_demoted_borderless_windows.Delete(hwnd)
        return
    }

    try {
        if WinGetExStyle("ahk_id " hwnd) & 0x8 ; WS_EX_TOPMOST
            WinSetAlwaysOnTop 0, "ahk_id " hwnd

        switcher_demoted_borderless_windows[hwnd] :=
            borderless_windows[hwnd]["pid"]

        SetTimer(WatchDemotedBorderlessSwitcherWindows, 75)
    }
    catch Error as err {
        DebugError("Demote borderless switcher source", err)
    }
}

WatchDemotedBorderlessSwitcherWindows(*)
{
    global borderless_windows, switcher_demoted_borderless_windows

    if !switcher_demoted_borderless_windows.Count {
        SetTimer(WatchDemotedBorderlessSwitcherWindows, 0)
        return
    }

    foreground_hwnd := DllCall("GetForegroundWindow", "ptr")
    stale_hwnds := []

    for hwnd, process_id in switcher_demoted_borderless_windows {
        if !borderless_windows.Has(hwnd)
            || !WindowStateMatchesProcess(hwnd, borderless_windows[hwnd])
            || GetWindowProcessId(hwnd) != process_id
        {
            stale_hwnds.Push(hwnd)
            continue
        }

        if foreground_hwnd != hwnd
            continue

        try {
            WinSetAlwaysOnTop 1, "ahk_id " hwnd
            stale_hwnds.Push(hwnd)

            DebugLog(
                "Restored borderless topmost state after switcher demotion."
                . " | " DebugDescribeWindow(hwnd)
            )
        }
        catch Error as err {
            stale_hwnds.Push(hwnd)
            DebugError("Restore switcher-demoted borderless window", err)
        }
    }

    for hwnd in stale_hwnds {
        if switcher_demoted_borderless_windows.Has(hwnd)
            switcher_demoted_borderless_windows.Delete(hwnd)
    }

    if !switcher_demoted_borderless_windows.Count
        SetTimer(WatchDemotedBorderlessSwitcherWindows, 0)
}

; =============================================================================
; script exit and reload cleanup
; =============================================================================

RestoreAllBorderlessWindows(exit_reason, exit_code)
{
    global borderless_windows

    windows := []

    for hwnd in borderless_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !WindowStateMatchesProcess(hwnd, borderless_windows[hwnd]) {
            borderless_windows.Delete(hwnd)
            continue
        }

        was_iconic := DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

        DebugLog(
            "Borderless exit cleanup begin."
            . " | iconic=" was_iconic
            . " | target=" DebugDescribeWindow(hwnd)
        )

        try {
            if was_iconic {
                saved := borderless_windows[hwnd]
                window := "ahk_id " hwnd

                if !saved["was_topmost"]
                    WinSetAlwaysOnTop 0, window

                ; Restore the frame while the window is still minimized.
                WinSetStyle(saved["style"], window)
                RefreshWindowFrame(hwnd)

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

                    ApplyWindowPlacement(
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

                ClearBorderlessWindowMarker(hwnd)
                borderless_windows.Delete(hwnd)
            } else {
                RestoreBorderlessWindow(hwnd, true)
            }

            DebugLog(
                "Borderless exit cleanup complete."
                . " | target=" DebugDescribeWindow(hwnd)
            )
        }
        catch Error as err {
            DebugError(
                "RestoreAllBorderlessWindows hwnd=" hwnd,
                err
            )
        }
    }
}

PruneBorderlessWindows()
{
    global borderless_windows
    stale_hwnds := []
    for hwnd, saved in borderless_windows {
        if !WindowStateMatchesProcess(hwnd, saved)
            stale_hwnds.Push(hwnd)
    }
    for hwnd in stale_hwnds
        borderless_windows.Delete(hwnd)
}
