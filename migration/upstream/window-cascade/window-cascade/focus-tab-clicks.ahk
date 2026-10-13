; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.
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
    global focus_tab_pending_press, focus_tab_click

    return IsObject(focus_tab_pending_press) || IsObject(focus_tab_click)
}

CanStartFocusTabClick()
{
    if !IsCascadeEnabled()
        return false

    global focus_tab_pending_press
    global focus_corner_targets, focus_corner_overlays

    if HasFocusTabClick()
        return true
    if IsCascadeDisplayTransition()
        return false

    ; #HotIf can also run for release matching. Never claim an application drag
    ; just because it finishes over a tab.
    if !GetKeyState("LButton", "P")
        return false

    MouseGetPosPixels(, , &overlay_hwnd)
    if !focus_corner_targets.Has(overlay_hwnd)
        return false

    target_hwnd := focus_corner_targets[overlay_hwnd]
    if !focus_corner_overlays.Has(target_hwnd)
        || !focus_corner_overlays[target_hwnd].shown
        return false

    ; Snapshot before the hotkey thread starts or the pointer leaves the tab.
    ; Keep hit-testing cheap: resolve live slot membership in the press handler.
    focus_tab_pending_press := {
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

    global focus_tab_pending_press, focus_tab_click, focus_tab_click_generation
    global focus_tab_release_poll_ms

    if IsObject(focus_tab_click) || !IsObject(focus_tab_pending_press)
        return

    ; A quick mouse-up must not see a half-initialized press or run it twice.
    previous_critical := A_IsCritical
    Critical "On"
    press := focus_tab_pending_press
    focus_tab_pending_press := 0
    focus_tab_click := press
    focus_tab_click_generation += 1

    try {
        CancelPendingAdoptionUndo()
        CancelNewWindowFocus()
        ActivateFocusTabClick(press)
    }
    catch Error as err {
        DebugError("BeginFocusTabClick", err)
    }
    finally {
        ; This only recovers a missed release; it never tracks movement or rotates.
        SetTimer(WatchFocusTabRelease, focus_tab_release_poll_ms)
        QueueFocusCornerUpdate()
        Critical(previous_critical)
    }
}

ActivateFocusTabClick(press)
{
    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
        return

    global focus_corner_overlays

    target_hwnd := press.target_hwnd
    if !focus_corner_overlays.Has(target_hwnd)
        || focus_corner_overlays[target_hwnd].gui.Hwnd != press.overlay_hwnd
        || !focus_corner_overlays[target_hwnd].shown
        || !DllCall("IsWindowVisible", "ptr", target_hwnd, "int")
        || IsWindowCloaked(target_hwnd)
        || WinGetMinMax(target_hwnd) != 0
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
            RotateCascadeSlotForWindow(
                press.active_hwnd,
                1,
                monitor_index,
                stack_info["slot_index"]
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
    global focus_tab_click

    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; A very quick release can be dispatched before the queued press handler.
        ; Complete that original press once, then only clear button ownership.
        if !IsObject(focus_tab_click)
            BeginFocusTabClick()
    }
    finally {
        StopFocusTabClick()
        Critical(previous_critical)
    }
}

WatchFocusTabRelease()
{
    global focus_tab_click

    Critical "On"
    if !IsObject(focus_tab_click) {
        SetTimer(WatchFocusTabRelease, 0)
        return
    }

    if GetKeyState("LButton", "P") {
        focus_tab_click.release_missing_since := 0
        return
    }

    ; Allow a queued mouse-up handler to finish before recovering a missed one.
    ; Releasing never triggers an additional activation or layer rotation.
    if !focus_tab_click.release_missing_since
        focus_tab_click.release_missing_since := A_TickCount
    else if ((A_TickCount - focus_tab_click.release_missing_since) & 0xFFFFFFFF) >= 100
        StopFocusTabClick()
}

StopFocusTabClick()
{
    global focus_tab_pending_press, focus_tab_click

    focus_tab_pending_press := 0
    focus_tab_click := 0
    SetTimer(WatchFocusTabRelease, 0)
}
