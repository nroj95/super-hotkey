; Cascade Kingdom's tuning constants, saved preferences and runtime state, in
; one object that every Cascade Kingdom file reads and changes as
; CascadeState.name. InitializeCascadeState sets them all, when the module is
; created and in the checks.
class CascadeState {
}

InitializeCascadeState()
{
; =============================================================================
; settings
; =============================================================================

; Cascade windows use a predictable generic size instead of an app's remembered size.
CascadeState.windowWidthRatio := 0.80
CascadeState.windowHeightRatio := 0.80

; First branch moves left/up from center; second branch moves right/down.
; A mirrored cascade swaps left and right.
CascadeState.stepX := 28
CascadeState.stepY := 24

; One tolerance for slot membership and mouse drops (screen-coordinate pixels).
; During a native drag, the original slot is retained. On release, the visible
; top-left, or top-right when mirrored, must be within this distance on both
; axes; the closest slot wins.
CascadeState.slotTolerance := 56

; Restore requests can finish before their native/DWM rectangles settle.
; Poll only during restores; a failed restore must not lock compaction forever.
CascadeState.restorePollMs := 50
CascadeState.restoreSettleMs := 200
CascadeState.restoreTimeoutMs := 5000

; A cancelled/ignored close must not defer this monitor's compaction forever.
; This only expires bookkeeping; it never forces a window to close.
CascadeState.closeTimeoutMs := 5000

; A placed window is checked once; if it is off by more than the tolerance, it
; is moved back once and checked again, then left to its application.
CascadeState.placementStabilizeDelayMs := 500
CascadeState.placementStabilizeVerifyMs := 1000
CascadeState.placementStabilizeTolerance := 6

; If Windows stops reporting native move-loop state after mouse release, abandon
; the snap decision instead of leaving the cascade permanently locked in a drag.
CascadeState.dragUnknownReleaseTimeoutMs := 500

CascadeState.edgeMargin := 12
CascadeState.minimumWidth := 320
CascadeState.minimumHeight := 220

; Focus-tab dimensions are 96-DPI UI units; only these are scaled per monitor.
; Slot spacing, drop tolerance, and cascade rectangles remain physical pixels.
CascadeState.focusCornerSize := 24
CascadeState.focusCornerThickness := 54
CascadeState.focusCornerFullHeightThickness := 36
CascadeState.focusCornerOverlap := 2
; Coalesce event-driven focus-tab updates. The slow timer below is only a
; fallback for Windows events that may occasionally be missed.
CascadeState.focusCornerUpdateMs := 50
CascadeState.focusCornerFallbackMs := 1000

; The active slot, which represents the next layer, uses the Windows accent
; color; inactive tabs, which represent their exposed windows, use a color
; chosen from a small fixed palette.
; Deeper tabs stay hidden, so opacity no longer accumulates with stack depth.
CascadeState.focusTabColorPresets := Map("White", "FFFFFF", "Grey", "808080", "Red", "F44336",
    "Orange", "FF9800", "Yellow", "FBC02D", "Green", "4CAF50", "Cyan", "00BCD4", "Blue", "2196F3",
    "Purple", "9C27B0", "Pink", "E91E63")

; Inactive-slot tabs stay faint while active-slot tabs use stronger opacity.
; Alpha 1 is reserved for the hidden state so overlays remain hit-testable.
CascadeState.focusCornerInactiveSlotAlpha := 128
CascadeState.focusCornerActiveSlotAlpha := 255

; Only watch for a missed mouse-up while a focus-tab click owns the button.
CascadeState.focusTabReleasePollMs := 50

CascadeState.settingsPath := SuiteState.App.Settings.directory "\cascade-kingdom\settings.ini"
; Cascade members, saved on exit and restored on start; see SaveCascades().
CascadeState.statePath := SuiteState.App.Settings.directory "\cascade-kingdom\state.ini"
CascadeState.focusCornerVisible := IniRead(CascadeState.settingsPath, "FocusTabs", "Visible", "1") = "1"

CascadeState.focusCornerInactiveSlotColorName := IniRead(CascadeState.settingsPath, "FocusTabs", "InactiveSlotColor",
    "White")

if !CascadeState.focusTabColorPresets.Has(CascadeState.focusCornerInactiveSlotColorName)
    CascadeState.focusCornerInactiveSlotColorName := "White"

CascadeState.focusCornerInactiveSlotColor :=
    CascadeState.focusTabColorPresets[CascadeState.focusCornerInactiveSlotColorName]

; =============================================================================
; runtime state
; =============================================================================

CascadeState.commandQueue := []
CascadeState.commandDraining := false

CascadeState.placementReservations := Map()
CascadeState.placementStabilizationGenerations := Map()
CascadeState.placementStabilizationGenerationCounter := 0
CascadeState.joinPositions := Map()
CascadeState.lentWindows := Map()  ; members Wonder Windows placed: their slot until they return
CascadeState.pollMs := 1000
CascadeState.history := Map()
; A display snapshot is refreshed by notifications and the slow polling fallback.
; Logical slots survive transient geometry/display changes; restarts keep
; membership only, through SaveCascades().
CascadeState.displays := Map()
CascadeState.displaySignature := ""
CascadeState.displayChangePending := false
CascadeState.displayRefreshing := false
CascadeState.displayGeneration := 0
CascadeState.displayRefreshDelayMs := 250
CascadeState.windowSlots := Map()
CascadeState.homeDevices := Map()  ; members moved off a missing display -> that display's device
CascadeState.displayReflow := Map()
CascadeState.membershipGeneration := 0
CascadeState.minimizedObserved := Map()
CascadeState.mousePress := 0
CascadeState.windowDrag := 0
CascadeState.dragGeneration := 0
CascadeState.compactionPending := Map()
CascadeState.compactionTimerPending := false
CascadeState.restoreBatches := Map()
CascadeState.restoreRequestDepth := 0
CascadeState.closeBatches := Map()
CascadeState.targetDisplay := IniRead(CascadeState.settingsPath, "Controls", "Display", "All")
CascadeState.mirrored := IniRead(CascadeState.settingsPath, "Controls", "Mirrored", "0") = "1"
CascadeState.minimizeInProgress := false
CascadeState.minimizedWindows := []

CascadeState.focusCornerOverlays := Map()
CascadeState.focusCornerTargets := Map()
CascadeState.focusCornerUpdatePending := false
CascadeState.focusTabPendingPress := 0
CascadeState.focusTabClick := 0
CascadeState.focusTabClickGeneration := 0

CascadeState.winEventCallback := 0
CascadeState.winEventHooks := []
}
