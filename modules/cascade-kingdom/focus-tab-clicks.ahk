; Cascade Kingdom focus-tab clicks and their release pairing.
;
; Click contract:
; - inactive slot: focus its exposed window on press;
; - active slot: rotate its front window to the back and focus the next layer;
; - consume the matching release without another action, even outside the tab;
; - leave ordinary application clicks/drags and keyboard rotation unchanged.

; =============================================================================
; mouse ownership and press actions
; =============================================================================

HasFocusTabClick()
{
    return IsObject(CascadeState.focusTabPendingPress) || IsObject(CascadeState.focusTabClick)
}

CanStartFocusTabClick()
{
    if !IsCascadeEnabled()
        return false

    if HasFocusTabClick()
        return true
    if IsCascadeDisplayTransition()
        return false

    ; #HotIf can also run for release matching. Never claim an application drag
    ; just because it finishes over a tab.
    if !GetKeyState("LButton", "P")
        return false

    MouseGetPosPixels(, , &overlay_hwnd)
    if !CascadeState.focusCornerTargets.Has(overlay_hwnd)
        return false

    target_hwnd := CascadeState.focusCornerTargets[overlay_hwnd]
    if !CascadeState.focusCornerOverlays.Has(target_hwnd)
        || !CascadeState.focusCornerOverlays[target_hwnd].shown
        return false

    ; Snapshot before the hotkey thread starts or the pointer leaves the tab.
    ; Keep hit-testing cheap: resolve live slot membership in the press handler.
    CascadeState.focusTabPendingPress := {
        target_hwnd: target_hwnd,
        overlay_hwnd: overlay_hwnd,
        active_hwnd: DllCall("GetForegroundWindow", "ptr"),
        release_missing_since: 0
    }
    return true
}

BeginFocusTabClick(*)
{
    if !IsCascadeEnabled()
        return

    if IsObject(CascadeState.focusTabClick) || !IsObject(CascadeState.focusTabPendingPress)
        return

    ; A quick mouse-up must not see a half-initialized press or run it twice.
    previous_critical := A_IsCritical
    Critical "On"
    press := CascadeState.focusTabPendingPress
    CascadeState.focusTabPendingPress := 0
    CascadeState.focusTabClick := press
    CascadeState.focusTabClickGeneration += 1

    try ActivateFocusTabClick(press)
    catch Error as err {
        DebugError("BeginFocusTabClick", err)
    }
    finally {
        ; This only recovers a missed release; it never tracks movement or rotates.
        SetTimer(WatchFocusTabRelease, CascadeState.focusTabReleasePollMs)
        QueueFocusCornerUpdate()
        Critical(previous_critical)
    }
}

ActivateFocusTabClick(press)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return

    target_hwnd := press.target_hwnd
    ; A destroyed tab no longer maps to its target, even if its handle is reused.
    if !CascadeState.focusCornerOverlays.Has(target_hwnd)
        || CascadeState.focusCornerTargets.Get(press.overlay_hwnd, 0) != target_hwnd
        || !CascadeState.focusCornerOverlays[target_hwnd].shown
        || !IsCascadeWindowShown(target_hwnd)
        return

    monitor_index := GetManagedCascadeMonitor(target_hwnd)
    if !monitor_index
        return

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)
    z_ranks := GetCascadeWindowZRanks()

    for stack_info in stacks {
        contains_target := false
        for hwnd in stack_info["windows"] {
            if hwnd = target_hwnd {
                contains_target := true
                break
            }
        }
        if !contains_target
            continue

        ordered_windows := SortCascadeWindowsByZOrder(stack_info["windows"], z_ranks)

        ; Do not reinterpret a stale tab as a different action after focus or
        ; membership changes. A skipped click still owns its matching mouse-up.
        if DllCall("GetForegroundWindow", "ptr") != press.active_hwnd
            || SelectFocusCornerSlotTarget(ordered_windows, press.active_hwnd) != target_hwnd
            return

        HideFocusCornerOverlay(target_hwnd)

        if ordered_windows[1] = press.active_hwnd {
            ; Merely activating the second window would alternate the first two.
            ; Rotate the whole stack so A -> B -> C -> A visits every layer.
            RotateCascadeSlotForWindow(press.active_hwnd, 1, monitor_index, stack_info["slot_index"]
            )
        } else {
            WinActivate(target_hwnd)
        }
        return
    }
}

; =============================================================================
; release pairing and missed-release recovery (no release action)
; =============================================================================

FinishFocusTabClick(*)
{
    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; A very quick release can be dispatched before the queued press handler.
        ; Complete that original press once, then only clear button ownership.
        if !IsObject(CascadeState.focusTabClick)
            BeginFocusTabClick()
    }
    finally {
        StopFocusTabClick()
        Critical(previous_critical)
    }
}

WatchFocusTabRelease()
{
    Critical "On"
    if !IsObject(CascadeState.focusTabClick) {
        SetTimer(WatchFocusTabRelease, 0)
        return
    }

    if GetKeyState("LButton", "P") {
        CascadeState.focusTabClick.release_missing_since := 0
        return
    }

    ; Allow a queued mouse-up handler to finish before recovering a missed one.
    ; Releasing never triggers an additional activation or layer rotation.
    if !CascadeState.focusTabClick.release_missing_since
        CascadeState.focusTabClick.release_missing_since := A_TickCount
    else if ((A_TickCount - CascadeState.focusTabClick.release_missing_since) & 0xFFFFFFFF) >= 100
        StopFocusTabClick()
}

StopFocusTabClick()
{
    CascadeState.focusTabPendingPress := 0
    CascadeState.focusTabClick := 0
    SetTimer(WatchFocusTabRelease, 0)
}
