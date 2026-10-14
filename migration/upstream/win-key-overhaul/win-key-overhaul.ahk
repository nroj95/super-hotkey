#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; Keep a short settling delay instead of the default 100 ms per window command.
SetWinDelay 10

; =============================================================================
; Win Key Overhaul
; =============================================================================
; - Replace selected Windows-key shortcuts with predictable window management.
; - Use quarter/half widths: 2:6 = 25%, 4:4 = 50%.
; - Cycle edge, near-center, and centered layouts; place top/bottom tiles.
; - Stretch to neighboring visible window edges, or the monitor work-area edge.
; - Swap clockwise/counter-clockwise and navigate focus directly.
; - Cycle maximized, fullscreen, and borderless windows without changing geometry.
; - Offer Windows Snap setup and ScreenGrid; retain optional FancyZones support.
; =============================================================================

A_IconTip := "Win Key Overhaul"
try TraySetIcon(A_ScriptDir "\icons\win-key-overhaul.ico")

#Include "%A_ScriptDir%\win-key-overhaul\settings.ahk"

; =============================================================================
; initialization
; =============================================================================

EnsurePreviousLaunchersAreStopped()
InitializeDebugLogging()
OnExit HandleWinKeyOverhaulExit

; =============================================================================
; tray menu and deferred startup guidance
; =============================================================================

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ToggleWinKeyOverhaulHelp)
A_TrayMenu.Add()
A_TrayMenu.Add("Recommended setup", ShowRecommendedSetup)
A_TrayMenu.Add("ScreenGrid on GitHub", OpenScreenGridReleases)
A_TrayMenu.Add()
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add("Debug logging", ToggleDebugLogging)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

UpdateStartupMenu()
UpdateDebugMenu()
SetTimer(InitializeDesktopIntegration, -500)

HandleWinKeyOverhaulExit(exit_reason, exit_code)
{
    try EndFocusNavigationSession()
    try ClearFocusHighlight(true)
    try RunWindowCommand(RestoreAllVerticalStretches)
    try RunWindowCommand(RestoreAllHorizontalStretches)
    try RunWindowCommand(RestoreAllBorderlessWindows, exit_reason, exit_code)
}

; =============================================================================
; internal modules
; =============================================================================
; Settings execute before startup; the remaining modules define functions and
; hotkeys. Do not launch these modules as independent window-management scripts.

#Include "%A_ScriptDir%\win-key-overhaul\controls.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\window-state.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\layout-geometry.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\layouts.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\swapping.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\focus.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\window-switcher.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\borderless.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\fancyzones.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\windows.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\interface.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\startup.ahk"
#Include "%A_ScriptDir%\win-key-overhaul\debug.ahk"
