; Cascade Kingdom display changes: notifications, the display half of the
; slow polling fallback in events.ahk, and logical slots that survive
; transient geometry changes.
; Refresh display geometry in this process; never Reload or reconstruct membership
; from whatever windows happen to be visible after a scale change.

; =============================================================================
; display notifications and polling
; =============================================================================

InitializeCascadeDisplays()
{
    CascadeState.displayRefreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        CascadeState.displays := snapshot.displays
        CascadeState.displaySignature := snapshot.signature
        DebugLog("Display geometry initialized. | signature=" snapshot.signature)
    }
    finally {
        CascadeState.displayRefreshing := false
    }
    OnMessage(0x007E, HandleCascadeDisplayMessage) ; WM_DISPLAYCHANGE
    OnMessage(0x001A, HandleCascadeDisplayMessage) ; WM_SETTINGCHANGE / work area
    OnMessage(0x02E0, HandleCascadeDisplayMessage) ; WM_DPICHANGED, focus tabs only
    OnMessage(0x0218, HandleCascadeDisplayMessage) ; WM_POWERBROADCAST / resume
}

HandleCascadeDisplayMessage(wparam, lparam, message, hwnd)
{
    ; A scale change reaches the script window as WM_DISPLAYCHANGE and
    ; WM_SETTINGCHANGE; WM_DPICHANGED only re-anchors a tab that moved.
    if message = 0x02E0 {
        if !CascadeState.focusCornerTargets.Has(hwnd)
            return
        target := CascadeState.focusCornerTargets[hwnd]
        if CascadeState.focusCornerOverlays.Has(target)
            CascadeState.focusCornerOverlays[target].dpi := 0
        ; A tab moving between monitors is not a display-topology change.
        ; Re-anchor to its target instead of using the suggested free-floating RECT.
        QueueFocusCornerUpdate()
        return 0
    }
    if hwnd != A_ScriptHwnd || CascadeState.displayRefreshing
        return
    if message = 0x0218 && wparam != 7 && wparam != 18
        return
    QueueCascadeDisplayRefresh()
}

QueueCascadeDisplayRefresh()
{
    CascadeDropGuides.Hide()
    if !CascadeState.displayChangePending {
        CascadeState.displayChangePending := true
        CascadeState.displayGeneration += 1
        CascadeState.membershipGeneration += 1
    }
    SetTimer(RefreshCascadeDisplays, -CascadeState.displayRefreshDelayMs)
}

IsCascadeDisplayTransition()
{
    return CascadeState.displayChangePending || CascadeState.displayRefreshing
}

PollCascadeDisplayEnvironment()
{
    if IsCascadeDisplayTransition()
        return
    CascadeState.displayRefreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        if snapshot.signature != CascadeState.displaySignature
            QueueCascadeDisplayRefresh()
    }
    catch Error as err {
        DebugError("Read display environment", err)
        QueueCascadeDisplayRefresh()
    }
    finally {
        CascadeState.displayRefreshing := false
    }
    ApplyPendingCascadeDisplayLayout()
}

RefreshCascadeDisplays()
{
    if CascadeState.displayRefreshing
        return
    CascadeState.displayRefreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        if snapshot.signature = CascadeState.displaySignature {
            CascadeState.displayChangePending := false
            return
        }
        ; Geometry queries above stay interruptible. Publish slots, membership and
        ; cancellation together so a hotkey cannot observe a half-remapped monitor.
        previous_critical := Critical("On")
        try {
            old_displays := CascadeState.displays
            new_displays := snapshot.displays
            remapped_history := Map()
            remapped_compactions := Map()
            topology_changed := old_displays.Count != new_displays.Count

            ; Preserve each known member's last intended slot before Windows' own DPI
            ; resize makes its current top-left look like an intentional drag away.
            fallback := MonitorGetPrimary()
            if !new_displays.Has(fallback)
                fallback := 1
            for old_monitor, history in CascadeState.history.Clone() {
                device := old_displays.Has(old_monitor) ? old_displays[old_monitor].device : ""
                for hwnd in history.Clone() {
                    if !DllCall("IsWindow", "ptr", hwnd, "int")
                        continue
                    destination := CascadeMemberDestination(device, CascadeState.homeDevices.Get(hwnd, ""),
                        new_displays, fallback, &home)
                    if home != ""
                        CascadeState.homeDevices[hwnd] := home
                    else if CascadeState.homeDevices.Has(hwnd)
                        CascadeState.homeDevices.Delete(hwnd)
                    if !CascadeDisplayAllowed(destination, new_displays) {
                        ReleaseCascadeWindow(hwnd)
                        topology_changed := true
                        continue
                    }
                    if destination != old_monitor || !old_displays.Has(old_monitor)
                        topology_changed := true
                    if !remapped_history.Has(destination)
                        remapped_history[destination] := []
                    remapped_history[destination].Push(hwnd)
                    changed := !old_displays.Has(old_monitor)
                        || old_displays[old_monitor].signature != new_displays[destination].signature
                    if !changed && destination = old_monitor
                        continue
                    if !CascadeState.windowSlots.Has(hwnd)
                        RememberCascadeSlot(hwnd, old_monitor)
                    if !CascadeState.windowSlots.Has(hwnd)
                        continue
                    slot := CascadeState.windowSlots[hwnd]
                    try {
                        if WinGetPID(hwnd) != slot.pid
                            continue
                    }
                    catch {
                        continue
                    }
                    slot := slot.Clone()
                    slot.monitor := destination
                    slot.device := new_displays[destination].device
                    slot.slot := Min(slot.slot, new_displays[destination].geometry.slots.Length)
                    CascadeState.windowSlots[hwnd] := slot
                    ; An active native drag owns its final destination, even during scaling.
                    if !IsCascadeWindowBeingDragged(hwnd)
                        CascadeState.displayReflow[hwnd] := slot
                }
                if CascadeState.compactionPending.Has(old_monitor) {
                    destination := FindCascadeMonitorDevice(device, new_displays) || fallback
                    remapped_compactions[destination] := CascadeState.compactionPending[old_monitor]
                }
            }

            CascadeState.displays := new_displays
            CascadeState.displaySignature := snapshot.signature
            CascadeState.displayGeneration += 1
            CascadeState.membershipGeneration += 1
            ; A DPI-only change leaves the original history map/arrays in place.
            if topology_changed {
                CascadeState.history := remapped_history
                CascadeState.compactionPending := remapped_compactions
                ; Old monitor-index gates are no longer meaningful. Their delayed
                ; callbacks already check identity; saved minimized windows are retained.
                CascadeState.restoreBatches.Clear()
                CascadeState.closeBatches.Clear()
            }
            for hwnd in CascadeState.displayReflow {
                CancelPlacementStabilization(hwnd)
            }
            for target in CascadeState.minimizedWindows {
                if CascadeState.windowSlots.Has(target.hwnd)
                    target.monitor := CascadeState.windowSlots[target.hwnd].monitor
            }
            ; Merged, returned or rescaled cascades close up once their windows
            ; have moved, so windows share a slot only when every slot is taken.
            for monitor in CascadeState.history
                QueueCascadeCompaction(monitor)
            CascadeState.displayChangePending := false
            DebugLog("Display geometry refreshed without reload. | displays=" new_displays.Count
                " | pending-members=" CascadeState.displayReflow.Count " | signature=" snapshot.signature)
        }
        finally {
            Critical(previous_critical)
        }
    }
    catch Error as err {
        DebugError("Refresh display geometry", err)
        ; Keep membership protected while Windows is between valid configurations.
        CascadeState.displayChangePending := true
        SetTimer(RefreshCascadeDisplays, -1000)
    }
    finally {
        CascadeState.displayRefreshing := false
        QueueFocusCornerUpdate()
        SetTimer(ApplyPendingCascadeDisplayLayout, -50)
    }
}

; Where a cascade member on device goes after a display change. A window
; whose display went missing moves to fallback and remembers that display as
; its home, returning when it reconnects. new_home is the home to keep, or "".
CascadeMemberDestination(device, home, displays, fallback, &new_home)
{
    if home != "" && (monitor := FindCascadeMonitorDevice(home, displays)) {
        new_home := ""
        return monitor
    }
    if monitor := FindCascadeMonitorDevice(device, displays) {
        new_home := home
        return monitor
    }
    new_home := home != "" ? home : device
    return fallback
}

; =============================================================================
; logical slots preserve intended placement across transient geometry changes
; =============================================================================

RememberCascadeSlot(hwnd, monitor_index, x?, y?)
{
    try {
        if !CascadeState.displays.Has(monitor_index)
            return
        if !IsSet(x) || !IsSet(y) {
            if !TryGetCascadeLayoutOrigin(hwnd, &observed_monitor, &x, &y)
                return
        }
        display := CascadeState.displays[monitor_index]
        slot_index := FindNearestCascadeSlot(x, y, display.geometry.slots, 0x7FFFFFFF)
        if slot_index
            CascadeState.windowSlots[hwnd] := {
                pid: WinGetPID(hwnd), monitor: monitor_index,
                device: display.device, slot: slot_index
            }
    }
}

ForgetCascadeSlot(hwnd)
{
    if CascadeState.windowSlots.Has(hwnd)
        CascadeState.windowSlots.Delete(hwnd)
    if CascadeState.homeDevices.Has(hwnd)
        CascadeState.homeDevices.Delete(hwnd)
    if CascadeState.displayReflow.Has(hwnd)
        CascadeState.displayReflow.Delete(hwnd)
}

CancelCascadeDisplayPlacement(hwnd, expected_slot := 0)
{
    if !CascadeState.displayReflow.Has(hwnd)
        return
    if IsObject(expected_slot) && CascadeState.displayReflow[hwnd] != expected_slot
        return
    CascadeState.displayReflow.Delete(hwnd)
}

HasPendingCascadeDisplayLayout(monitor_index)
{
    for hwnd, slot in CascadeState.displayReflow {
        if slot.monitor = monitor_index && DllCall("IsWindow", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
            && DllCall("IsWindowVisible", "ptr", hwnd, "int") && !IsWindowCloaked(hwnd)
            return true
    }
    return false
}

ApplyPendingCascadeDisplayLayout()
{
    static running := false

    if running || !IsCascadeEnabled() || IsCascadeDisplayTransition()
        || HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return
    running := true
    generation := CascadeState.displayGeneration
    try {
        for hwnd, slot in CascadeState.displayReflow.Clone() {
            if !IsCascadeEnabled() || IsCascadeDisplayTransition()
                || generation != CascadeState.displayGeneration
                || HasCascadeWindowDrag() || HasFocusTabClick()
                break
            try {
                if !DllCall("IsWindow", "ptr", hwnd, "int") || WinGetPID(hwnd) != slot.pid
                    || GetManagedCascadeMonitor(hwnd) != slot.monitor {
                    CancelCascadeDisplayPlacement(hwnd, slot)
                    continue
                }
                state := WinGetMinMax(hwnd)
                ; Do not restore independently minimized windows or expose another
                ; virtual desktop. Keep their destination until they become visible.
                if state = -1 || IsWindowCloaked(hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
                    continue
                if state = 1 {
                    CancelCascadeDisplayPlacement(hwnd, slot)
                    continue
                }
                if IsCascadeCloseBatchActive(slot.monitor)
                    continue
                geometry := CascadeState.displays[slot.monitor].geometry
                position := geometry.slots[slot.slot]
                raw := VisibleToRawRect(hwnd, position[1], position[2], geometry.width, geometry.height)
                if !CascadeState.displayReflow.Has(hwnd) || CascadeState.displayReflow[hwnd] != slot
                    || generation != CascadeState.displayGeneration || IsCascadeDisplayTransition()
                    continue
                previous_critical := Critical("On")
                try {
                    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
                        || generation != CascadeState.displayGeneration
                        || !CascadeState.displayReflow.Has(hwnd) || CascadeState.displayReflow[hwnd] != slot
                        || IsCascadeWindowBeingDragged(hwnd) || WinGetPID(hwnd) != slot.pid
                        continue
                    CascadeState.placementReservations[hwnd] := Map("monitor", slot.monitor, "x", position[1], "y", position[2])
                    ; No activation, Z-order rebuild, restore, close, or membership adoption.
                    moved := PhysicalDllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
                        "int", raw[1], "int", raw[2], "int", raw[3], "int", raw[4],
                        "uint", 0x4014, "int") ; ASYNC | NOACTIVATE | NOZORDER
                    move_error := A_LastError
                    if moved
                        SchedulePlacementStabilization(hwnd, position[1], position[2],
                            geometry.width, geometry.height)
                    else {
                        CancelPlacementStabilization(hwnd)
                        DebugLog("Display reflow refused. | hwnd=" hwnd " | last-error=" move_error)
                    }
                    CancelCascadeDisplayPlacement(hwnd, slot)
                }
                finally {
                    Critical(previous_critical)
                }
            }
            catch Error as err {
                CancelCascadeDisplayPlacement(hwnd, slot)
                DebugError("Refresh managed window geometry", err)
            }
        }
    }
    finally {
        running := false
    }
    QueueFocusCornerUpdate()
}

StopCascadeDisplays()
{
    SetTimer(RefreshCascadeDisplays, 0)
    SetTimer(ApplyPendingCascadeDisplayLayout, 0)
    for message in [0x007E, 0x001A, 0x02E0, 0x0218]
        OnMessage(message, HandleCascadeDisplayMessage, 0)
}
