; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk.

; =============================================================================
; direct window-management shortcuts
; =============================================================================

; The $ prefixes keep forwarded FancyZones keystrokes out of our handlers.
$#Up::RunWindowCommand(MaximizeWindowTarget)
$#Down::RunWindowCommand(RestoreWindowTarget)

#HotIf !IsScratchpadWindowActive()
$#Left::RunWindowCommand(CycleWindowSnap, "left")
$#Right::RunWindowCommand(CycleWindowSnap, "right")
#HotIf

$+#Up::RunWindowCommand(StretchWindowVertically)
$+#Down::RunWindowCommand(ResetWindowStretch)
$+#Left::RunWindowCommand(ToggleHorizontalStretch, "left")
$+#Right::RunWindowCommand(ToggleHorizontalStretch, "right")

^#h::ToggleWinKeyOverhaulHelp()
#Backspace::RunWindowCommand(MinimizeActiveWindow)
+#Home::RunWindowCommand(ToggleOtherWindows)
#m::RunWindowCommand(ToggleAllWindows)

#Insert::RunWindowCommand(PlaceCornerTile, "top-left")
#Delete::RunWindowCommand(PlaceCornerTile, "bottom-left")

#HotIf !IsScratchpadWindowActive()
$#PgUp::RunWindowCommand(PlaceCornerTile, "top-right")
$#PgDn::RunWindowCommand(PlaceCornerTile, "bottom-right")
#HotIf

#Home::RunWindowCommand(PlaceCenterTile, "top")
#End::RunWindowCommand(PlaceCenterTile, "bottom")

#Enter::RunWindowCommand(SwapWindow, "clockwise")
+#Enter::RunWindowCommand(SwapWindow, "counter-clockwise")

; Standalone spatial focus and maximized/fullscreen cycling.
$!#Left::RunWindowCommand(FocusNearestWindow, "left")
$!#Right::RunWindowCommand(FocusNearestWindow, "right")
$!#Up::RunWindowCommand(FocusNearestWindow, "up")
$!#Down::RunWindowCommand(FocusNearestWindow, "down")
+#Tab::RunWindowCommand(CycleMaximizedFullscreenWindows)

; =============================================================================
; optional FancyZones navigation
; =============================================================================

; The existing process watcher updates this cache; do not enumerate processes
; while Windows is waiting for a keyboard-hook condition.
#HotIf fancyzones_process_id

$^!Left::MoveWindowThroughFancyZones("Left")
$^!Right::MoveWindowThroughFancyZones("Right")
$^!Up::MoveWindowThroughFancyZones("Up")
$^!Down::MoveWindowThroughFancyZones("Down")

; Ctrl+Alt+PgUp/PgDn are registered by FancyZones itself. Registering them here
; as well would block its zone-window switching. Startup offers to configure it.
#HotIf

; A deliberate click abandons the window last minimized with Win+Backspace.
~LButton::ForgetLastMinimizedWindow()
~RButton::ForgetLastMinimizedWindow()
~MButton::ForgetLastMinimizedWindow()

IsScratchpadWindowActive()
{
    hwnd := WinExist("A")
    return hwnd
        && DllCall(
            "GetPropW",
            "ptr", hwnd,
            "str", "nroj.Scratchpad.Notepad3Window",
            "ptr"
        )
}
