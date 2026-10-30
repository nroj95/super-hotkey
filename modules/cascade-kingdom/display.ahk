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
    global cascade_displays, cascade_display_signature, cascade_display_refreshing
    cascade_display_refreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        cascade_displays := snapshot.displays
        cascade_display_signature := snapshot.signature
        DebugLog("Display geometry initialized. | signature=" snapshot.signature)
    }
    finally {
        cascade_display_refreshing := false
    }
    OnMessage(0x007E, HandleCascadeDisplayMessage) ; WM_DISPLAYCHANGE
    OnMessage(0x001A, HandleCascadeDisplayMessage) ; WM_SETTINGCHANGE / work area
    OnMessage(0x02E0, HandleCascadeDisplayMessage) ; WM_DPICHANGED, focus tabs only
    OnMessage(0x0218, HandleCascadeDisplayMessage) ; WM_POWERBROADCAST / resume
}

HandleCascadeDisplayMessage(wparam, lparam, message, hwnd)
{
    global cascade_display_refreshing
    global focus_corner_targets, focus_corner_overlays

    ; A scale change reaches the script window as WM_DISPLAYCHANGE and
    ; WM_SETTINGCHANGE; WM_DPICHANGED only re-anchors a tab that moved.
    if message = 0x02E0 {
        if !focus_corner_targets.Has(hwnd)
            return
        target := focus_corner_targets[hwnd]
        if focus_corner_overlays.Has(target)
            focus_corner_overlays[target].dpi := 0
        ; A tab moving between monitors is not a display-topology change.
        ; Re-anchor to its target instead of using the suggested free-floating RECT.
        QueueFocusCornerUpdate()
        return 0
    }
    if hwnd != A_ScriptHwnd || cascade_display_refreshing
        return
    if message = 0x0218 && wparam != 7 && wparam != 18
        return
    QueueCascadeDisplayRefresh()
}

QueueCascadeDisplayRefresh()
{
    CascadeDropGuides.Hide()
    global cascade_display_change_pending, cascade_display_generation
    global cascade_display_refresh_delay_ms, cascade_membership_generation
    if !cascade_display_change_pending {
        cascade_display_change_pending := true
        cascade_display_generation += 1
        cascade_membership_generation += 1
    }
    SetTimer(RefreshCascadeDisplays, -cascade_display_refresh_delay_ms)
}

IsCascadeDisplayTransition()
{
    global cascade_display_change_pending, cascade_display_refreshing
    return cascade_display_change_pending || cascade_display_refreshing
}

PollCascadeDisplayEnvironment()
{
    global cascade_display_signature, cascade_display_refreshing
    if IsCascadeDisplayTransition()
        return
    cascade_display_refreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        if snapshot.signature != cascade_display_signature
            QueueCascadeDisplayRefresh()
    }
    catch Error as err {
        DebugError("Read display environment", err)
        QueueCascadeDisplayRefresh()
    }
    finally {
        cascade_display_refreshing := false
    }
    ApplyPendingCascadeDisplayLayout()
}

RefreshCascadeDisplays()
{
    global cascade_displays, cascade_display_signature, cascade_display_change_pending
    global cascade_display_refreshing, cascade_display_generation, cascade_membership_generation
    global cascade_history, cascade_window_slots, cascade_display_reflow, cascade_home_devices
    global cascade_minimized_windows, cascade_restore_batches, cascade_close_batches
    global cascade_compaction_pending

    if cascade_display_refreshing
        return
    cascade_display_refreshing := true
    try {
        snapshot := ReadCascadeDisplays()
        if snapshot.signature = cascade_display_signature {
            cascade_display_change_pending := false
            return
        }
        ; Geometry queries above stay interruptible. Publish slots, membership and
        ; cancellation together so a hotkey cannot observe a half-remapped monitor.
        previous_critical := Critical("On")
        try {
            old_displays := cascade_displays
            new_displays := snapshot.displays
            remapped_history := Map()
            remapped_compactions := Map()
            topology_changed := old_displays.Count != new_displays.Count

            ; Preserve each known member's last intended slot before Windows' own DPI
            ; resize makes its current top-left look like an intentional drag away.
            fallback := MonitorGetPrimary()
            if !new_displays.Has(fallback)
                fallback := 1
            for old_monitor, history in cascade_history.Clone() {
                device := old_displays.Has(old_monitor) ? old_displays[old_monitor].device : ""
                for hwnd in history.Clone() {
                    if !DllCall("IsWindow", "ptr", hwnd, "int")
                        continue
                    destination := CascadeMemberDestination(device, cascade_home_devices.Get(hwnd, ""),
                        new_displays, fallback, &home)
                    if home != ""
                        cascade_home_devices[hwnd] := home
                    else if cascade_home_devices.Has(hwnd)
                        cascade_home_devices.Delete(hwnd)
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
                    if !cascade_window_slots.Has(hwnd)
                        RememberCascadeSlot(hwnd, old_monitor)
                    if !cascade_window_slots.Has(hwnd)
                        continue
                    slot := cascade_window_slots[hwnd]
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
                    cascade_window_slots[hwnd] := slot
                    ; An active native drag owns its final destination, even during scaling.
                    if !IsCascadeWindowBeingDragged(hwnd)
                        cascade_display_reflow[hwnd] := slot
                }
                if cascade_compaction_pending.Has(old_monitor) {
                    destination := FindCascadeMonitorDevice(device, new_displays) || fallback
                    remapped_compactions[destination] := cascade_compaction_pending[old_monitor]
                }
            }

            cascade_displays := new_displays
            cascade_display_signature := snapshot.signature
            cascade_display_generation += 1
            cascade_membership_generation += 1
            ; A DPI-only change leaves the original history map/arrays in place.
            if topology_changed {
                cascade_history := remapped_history
                cascade_compaction_pending := remapped_compactions
                ; Old monitor-index gates are no longer meaningful. Their delayed
                ; callbacks already check identity; saved minimized windows are retained.
                cascade_restore_batches.Clear()
                cascade_close_batches.Clear()
            }
            for hwnd in cascade_display_reflow {
                CancelPlacementStabilization(hwnd)
            }
            for target in cascade_minimized_windows {
                if cascade_window_slots.Has(target.hwnd)
                    target.monitor := cascade_window_slots[target.hwnd].monitor
            }
            ; Merged, returned or rescaled cascades close up once their windows
            ; have moved, so windows share a slot only when every slot is taken.
            for monitor in cascade_history
                QueueCascadeCompaction(monitor)
            cascade_display_change_pending := false
            DebugLog("Display geometry refreshed without reload. | displays=" new_displays.Count
                " | pending-members=" cascade_display_reflow.Count " | signature=" snapshot.signature)
        }
        finally {
            Critical(previous_critical)
        }
    }
    catch Error as err {
        DebugError("Refresh display geometry", err)
        ; Keep membership protected while Windows is between valid configurations.
        cascade_display_change_pending := true
        SetTimer(RefreshCascadeDisplays, -1000)
    }
    finally {
        cascade_display_refreshing := false
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
    global cascade_window_slots, cascade_displays
    try {
        if !cascade_displays.Has(monitor_index)
            return
        if !IsSet(x) || !IsSet(y) {
            if !TryGetCascadeLayoutOrigin(hwnd, &observed_monitor, &x, &y)
                return
        }
        display := cascade_displays[monitor_index]
        slot_index := FindNearestCascadeSlot(x, y, display.geometry.slots, 0x7FFFFFFF)
        if slot_index
            cascade_window_slots[hwnd] := {
                pid: WinGetPID(hwnd), monitor: monitor_index,
                device: display.device, slot: slot_index
            }
    }
}

ForgetCascadeSlot(hwnd)
{
    global cascade_window_slots, cascade_display_reflow, cascade_home_devices
    if cascade_window_slots.Has(hwnd)
        cascade_window_slots.Delete(hwnd)
    if cascade_home_devices.Has(hwnd)
        cascade_home_devices.Delete(hwnd)
    if cascade_display_reflow.Has(hwnd)
        cascade_display_reflow.Delete(hwnd)
}

CancelCascadeDisplayPlacement(hwnd, expected_slot := 0)
{
    global cascade_display_reflow
    if !cascade_display_reflow.Has(hwnd)
        return
    if IsObject(expected_slot) && cascade_display_reflow[hwnd] != expected_slot
        return
    cascade_display_reflow.Delete(hwnd)
}

HasPendingCascadeDisplayLayout(monitor_index)
{
    global cascade_display_reflow
    for hwnd, slot in cascade_display_reflow {
        if slot.monitor = monitor_index && DllCall("IsWindow", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
            && DllCall("IsWindowVisible", "ptr", hwnd, "int") && !IsWindowCloaked(hwnd)
            return true
    }
    return false
}

ApplyPendingCascadeDisplayLayout()
{
    global cascade_display_reflow, cascade_displays, placement_reservations
    global cascade_display_generation
    static running := false

    if running || !IsCascadeEnabled() || IsCascadeDisplayTransition()
        || HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return
    running := true
    generation := cascade_display_generation
    try {
        for hwnd, slot in cascade_display_reflow.Clone() {
            if !IsCascadeEnabled() || IsCascadeDisplayTransition()
                || generation != cascade_display_generation
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
                geometry := cascade_displays[slot.monitor].geometry
                position := geometry.slots[slot.slot]
                raw := VisibleToRawRect(hwnd, position[1], position[2], geometry.width, geometry.height)
                if !cascade_display_reflow.Has(hwnd) || cascade_display_reflow[hwnd] != slot
                    || generation != cascade_display_generation || IsCascadeDisplayTransition()
                    continue
                previous_critical := Critical("On")
                try {
                    if !IsCascadeEnabled() || IsCascadeDisplayTransition()
                        || generation != cascade_display_generation
                        || !cascade_display_reflow.Has(hwnd) || cascade_display_reflow[hwnd] != slot
                        || IsCascadeWindowBeingDragged(hwnd) || WinGetPID(hwnd) != slot.pid
                        continue
                    placement_reservations[hwnd] := Map("monitor", slot.monitor, "x", position[1], "y", position[2])
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
