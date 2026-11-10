; Cascade Kingdom window drags: move-loop tracking and one release-time
; move or detach decision for cascade members.
;
; Drop contract:
; - preserve the original membership/slot throughout a native mouse drag;
; - resolve the visible top-left corner, top-right when mirrored, only after
;   the move loop and mouse-up;
; - a member dropped within tolerance of an eligible slot takes it, on any
;   display; dropped anywhere else, it leaves the cascade where it was
;   dropped, at the size or maximized state it had before joining;
; - a member resized by any edge leaves where and as large as the user made it;
; - a drop never adds a window: Caps + Insert and the mouse key's double-click
;   do (see mouse-key.ahk).

; =============================================================================
; native mouse interaction and move-loop tracking
; =============================================================================

CaptureCascadeMousePress(*)
{
    if !IsCascadeEnabled()
        return

    ; Finish the previous released drag before snapshotting a rapid new press.
    if HasCascadeWindowDrag()
        WatchCascadeWindowDrag()
    CascadeState.mousePress := 0
    if HasFocusTabClick()
        return

    MouseGetPosPixels(, , &hover_hwnd)
    hwnd := DllCall("GetAncestor", "ptr", hover_hwnd, "uint", 2, "ptr") ; GA_ROOT
    CascadeState.mousePress := GetCascadeMousePressSnapshot(hwnd)
}

GetCascadeMousePressSnapshot(hwnd)
{
    ; Any window: commands wait while one is dragged, even outside a cascade.
    if !IsPlausibleTopLevelWindow(hwnd, true)
        return 0

    try {
        WinGetPosPixels(&x, &y, &width, &height, hwnd)
        if !GetVisibleWindowBounds(hwnd, &frame_x, &frame_y, &frame_width, &frame_height)
            return 0

        ; Snapshot on down, not at the later event callback: a quick drag may
        ; already have moved by the time EVENT_SYSTEM_MOVESIZESTART is delivered.
        ; A window dropped onto a slot keeps this as its join position.
        minmax := WinGetMinMax(hwnd)
        ; Dragging a window that Windows Snap arranged first gives it back its
        ; earlier size, kept as the normal rectangle; that is no edge resize.
        normal_width := width, normal_height := height
        if minmax = 0 {
            try {
                normal := CallWithDpiContext(-3, CaptureWindowPlacement, hwnd)
                normal_width := NumGet(normal, 36, "int") - NumGet(normal, 28, "int")
                normal_height := NumGet(normal, 40, "int") - NumGet(normal, 32, "int")
            }
        }
        return {
            hwnd: hwnd, pid: WinGetPID(hwnd),
            x: x, y: y, width: width, height: height,
            normal_width: normal_width, normal_height: normal_height,
            frame_x: frame_x, frame_y: frame_y,
            monitor: WindowMonitorIndex(hwnd),
            minmax: minmax,
            placement: minmax = 1 ? CaptureWindowPlacement(hwnd) : 0,
            dpi: GetCascadeWindowMonitorDpi(hwnd),
            resize: !!RegExMatch(A_Cursor, "^Size(NS|WE|NWSE|NESW)$"),
            down_tick: A_TickCount, up_tick: 0, cancelled: false
        }
    }
    catch {
        return 0
    }
}

CaptureCascadeMouseRelease(*)
{
    if !IsCascadeEnabled()
        return

    CascadeDropGuides.Hide()
    if IsObject(CascadeState.mousePress)
        CascadeState.mousePress.up_tick := A_TickCount
    if IsObject(CascadeState.windowDrag)
        CascadeState.windowDrag.up_tick := A_TickCount

    ; Let the native move loop commit its final rectangle before examining it.
    if HasCascadeWindowDrag()
        SetTimer(WatchCascadeWindowDrag, -1)

}

HasCascadeWindowDrag()
{
    return IsObject(CascadeState.windowDrag)
}

IsCascadeWindowBeingDragged(hwnd)
{
    return IsObject(CascadeState.windowDrag) && CascadeState.windowDrag.hwnd = hwnd
}

BeginCascadeWindowDrag(hwnd, event_time)
{
    if !IsCascadeEnabled()
        return

    if HasCascadeWindowDrag() || HasFocusTabClick()
        return
    if !IsObject(CascadeState.mousePress) || CascadeState.mousePress.hwnd != hwnd {
        ; Recover a move-start notification that beat the ordinary down handler.
        ; The native event confirms a move loop; a held button confirms mouse input.
        if !GetKeyState("LButton", "P")
            return
        CascadeState.mousePress := GetCascadeMousePressSnapshot(hwnd)
        if !IsObject(CascadeState.mousePress)
            return
    }

    press := CascadeState.mousePress
    ; Ignore keyboard move loops or a late event belonging to another click.
    if !GetKeyState("LButton", "P") {
        if !press.up_tick
            || ((event_time - press.down_tick) & 0xFFFFFFFF)
                > ((press.up_tick - press.down_tick) & 0xFFFFFFFF)
            return
    }
    if !WinExist(hwnd) || WinGetPID(hwnd) != press.pid
        return

    drag := press.Clone()
    drag.source_monitor := GetManagedCascadeMonitor(hwnd)
    drag.native_ended := false
    drag.native_state_unknown_since := 0
    drag.completing := false
    drag.landing_counts := Map()  ; display -> how many other members it shows
    CascadeState.windowDrag := drag
    CascadeState.dragGeneration += 1

    ; Manual interaction takes priority over old corrections.
    CancelCascadeDisplayPlacement(hwnd)
    RemoveWindowFromCascadeRestore(hwnd)
    CancelPlacementStabilization(hwnd)

    HideFocusCornerOverlay(hwnd)
    QueueFocusCornerUpdate()
    SetTimer(WatchCascadeWindowDrag, 50)
    DebugLog("Cascade drag started. | hwnd=" hwnd " | source-monitor=" drag.source_monitor)
}

EndCascadeWindowDrag(hwnd)
{
    if !IsCascadeWindowBeingDragged(hwnd)
        return

    CascadeDropGuides.Hide()
    CascadeState.windowDrag.native_ended := true
    SetTimer(WatchCascadeWindowDrag, -1)
}

CancelCascadeWindowDrop(*)
{
    CascadeDropGuides.Hide()
    if IsObject(CascadeState.mousePress)
        CascadeState.mousePress.cancelled := true
    if IsObject(CascadeState.windowDrag)
        CascadeState.windowDrag.cancelled := true
}

IsNativeWindowMoveSizeActive(hwnd)
{
    thread_id := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    thread_info := Buffer(24 + 6 * A_PtrSize, 0)
    NumPut("uint", thread_info.Size, thread_info)
    if !thread_id || !DllCall("GetGUIThreadInfo", "uint", thread_id, "ptr", thread_info, "int")
        return -1

    return !!(NumGet(thread_info, 4, "uint") & 0x0002) ; GUI_INMOVESIZE
}

WatchCascadeWindowDrag()
{
    if !IsObject(CascadeState.windowDrag) {
        SetTimer(WatchCascadeWindowDrag, 0)
        return
    }
    drag := CascadeState.windowDrag
    if drag.completing
        return

    try {
        if !WinExist(drag.hwnd) || WinGetPID(drag.hwnd) != drag.pid {
            StopCascadeWindowDrag(drag)
            return
        }

        if IsCascadeDisplayTransition() {
            CascadeDropGuides.Hide()
            SetTimer(WatchCascadeWindowDrag, 50)
            return
        }

        CascadeDropGuides.Update(drag)
        left_button_held := GetKeyState("LButton", "P")
        native_move_state := drag.native_ended
            ? 0
            : IsNativeWindowMoveSizeActive(drag.hwnd)

        if !drag.native_ended {
            if native_move_state = 1 {
                drag.native_state_unknown_since := 0
                SetTimer(WatchCascadeWindowDrag, 50)
                return
            }

            if native_move_state < 0 {
                ; Never infer completion while the user still physically holds the
                ; drag button. Once released, tolerate a short query failure window,
                ; then abandon snapping rather than leaving the drag gate stuck.
                if left_button_held {
                    drag.native_state_unknown_since := 0
                    SetTimer(WatchCascadeWindowDrag, 50)
                    return
                }

                if !drag.native_state_unknown_since {
                    drag.native_state_unknown_since := A_TickCount
                    SetTimer(WatchCascadeWindowDrag, 50)
                    return
                }

                unknown_elapsed_ms :=
                    (A_TickCount - drag.native_state_unknown_since) & 0xFFFFFFFF
                if unknown_elapsed_ms < CascadeState.dragUnknownReleaseTimeoutMs {
                    SetTimer(WatchCascadeWindowDrag, 50)
                    return
                }

                drag.cancelled := true
                DebugLog("Cascade drag abandoned after native state query failure."
                    . " | elapsed-ms=" unknown_elapsed_ms . " | hwnd=" drag.hwnd)
            } else {
                drag.native_state_unknown_since := 0
            }
        }

        ; Mouse-up can precede final native geometry. If the native move loop has
        ; ended or is known inactive, wait only while the physical button remains.
        if !drag.cancelled && !drag.up_tick && left_button_held {
            SetTimer(WatchCascadeWindowDrag, 50)
            return
        }

        if CascadeState.windowDrag != drag
            return
        drag.completing := true
        CompleteCascadeWindowDrop(drag)
    }
    catch Error as err {
        drag.completing := true
        DebugError("CompleteCascadeWindowDrop", err)
    }
    finally {
        if drag.completing
            StopCascadeWindowDrag(drag)
    }
}

StopCascadeWindowDrag(expected_drag := 0)
{
    if IsObject(expected_drag) && CascadeState.windowDrag != expected_drag
        return
    CascadeDropGuides.Hide()
    CascadeState.windowDrag := 0
    CascadeState.dragGeneration += 1
    SetTimer(WatchCascadeWindowDrag, 0)
    SetTimer(ApplyPendingCascadeDisplayLayout, -50)
    QueueFocusCornerUpdate()
    if CascadeState.compactionPending.Count
        ScheduleCascadeCompactionFlush()
}

; =============================================================================
; one release-time snap / adopt / detach decision
; =============================================================================

CascadeDragIsResize(drag, width, height)
{
    return drag.resize || (drag.minmax = 0
        && drag.dpi = GetCascadeWindowMonitorDpi(drag.hwnd)
        && (width != drag.width || height != drag.height)
        && (width != drag.normal_width || height != drag.normal_height))
}

; Where a dropped window's visible frame lands: the display under its top-left
; corner, or its top-right in a mirrored cascade, and the left edge it takes
; once resized to a cascade window with that corner in place. 0 off-screen.
CascadeDropTarget(frame_x, frame_y, frame_width)
{
    corner_x := CascadeState.mirrored ? frame_x + frame_width - 1 : frame_x
    if !(monitor := GetMonitorForPoint(corner_x, frame_y))
        return 0
    geometry := GetCanonicalCascadeGeometry(monitor)
    return {monitor: monitor, geometry: geometry,
        x: CascadeState.mirrored ? frame_x + frame_width - geometry.width : frame_x}
}

; The slots a drop can take on target's display: those the cascade can fill.
; It has no gaps, so with N members, the dragged window included, these are
; its first N slots; on a display Cascade Kingdom leaves alone, none. The
; other members do not move during a drag, so they are counted once per
; display.
CascadeDropSlots(drag, target)
{
    if !CascadeDisplayAllowed(target.monitor)
        return []
    if !drag.landing_counts.Has(target.monitor) {
        others := []
        for hwnd in GetLiveCascadeHistory(target.monitor)
            if hwnd != drag.hwnd
                others.Push(hwnd)
        count := 0
        if others.Length && (order := ReadCascadeSlotOrder(target.monitor, others))
            for stack in order.stacks
                count += stack.Length
        drag.landing_counts[target.monitor] := count
    }
    slots := []
    loop Min(drag.landing_counts[target.monitor] + 1, target.geometry.slots.Length)
        slots.Push(target.geometry.slots[A_Index])
    return slots
}

; The slot a drop takes there, or 0 when the drop takes the window out. Like
; its guide's L, a slot owns the window's corner while the corner sits inside
; its angle: right of and below the slot's corner, or left of and below it
; when mirrored. The lowest such slot wins, so slots meet along straight
; horizontal and vertical lines, never diagonal ones, and past the last guide
; the corner stays with it. A corner inside no angle, above or beside the
; whole staircase, takes the nearest slot. Either way the slot must be within
; reach on both axes. A window already in that slot moves on, as compaction
; keeps the dropped window there, so a window dragged off its slot swaps with
; a near neighbour instead of sliding back into its own gap.
CascadeDropLandingSlot(drag, target, frame_y)
{
    slots := CascadeDropSlots(drag, target)
    reach := CascadeState.dropTolerance
    best := 0
    for index, slot in slots
        if slot[2] <= frame_y && (CascadeState.mirrored ? slot[1] >= target.x : slot[1] <= target.x)
            && (!best || slot[2] > slots[best][2])
            best := index
    if !best
        return FindNearestCascadeSlot(target.x, frame_y, slots, reach)
    return frame_y - slots[best][2] <= reach && Abs(target.x - slots[best][1]) <= reach ? best : 0
}

CompleteCascadeWindowDrop(drag)
{
    if !IsCascadeEnabled()
        return

    hwnd := drag.hwnd
    if drag.cancelled || !drag.source_monitor
        return

    WinGetPosPixels(&x, &y, &width, &height, hwnd)
    if x = drag.x && y = drag.y && width = drag.width && height = drag.height
        return

    ; Edge resizes are not drop-to-join. DPI changes and restoring a maximized
    ; title-bar drag may change size without being an edge resize.
    resized := CascadeDragIsResize(drag, width, height)
    if resized || !IsCascadeWindow(hwnd, true) {
        ; A size the cascade did not choose: the window is the user's now.
        if resized || !IsWindowInCascadeLayout(hwnd)
            ReleaseCascadeWindow(hwnd)
        return
    }

    if GetVisibleWindowBounds(hwnd, &frame_x, &frame_y, &frame_width, &frame_height)
        && (target := CascadeDropTarget(frame_x, frame_y, frame_width)) {
        monitor_index := target.monitor
        geometry := target.geometry
        ; The same choice the lit guide showed during the drag.
        if slot_index := CascadeDropLandingSlot(drag, target, frame_y) {
            if PlaceCascadeWindowOnMonitor(hwnd, monitor_index, geometry.slots[slot_index]) {
                RemoveWindowFromMinimizeState(hwnd)
                QueueCascadeCompaction(drag.source_monitor)
                ; Keep the dropped window in its slot; the window it displaced
                ; fills the gap the dropped window left.
                QueueCascadeCompaction(monitor_index, hwnd)
                DebugLog("Cascade drop snapped. | hwnd=" hwnd
                    " | monitor=" monitor_index " | slot=" slot_index)
                return
            }
            ; A scale change that interrupts the move is not an intentional detach.
            if IsCascadeDisplayTransition()
                return
            ; Do not keep a failed snap half-placed or silently choose another slot.
            DebugLog("Cascade drop snap failed. | hwnd=" hwnd)
        }
    }

    ; Dragged out: it stays where it was dropped, without the cascade's size.
    position := CascadeState.joinPositions.Has(hwnd) ? CascadeState.joinPositions.Delete(hwnd) : 0
    ReleaseCascadeWindow(hwnd)
    RestoreCascadeJoinSize(hwnd, position)
}

ReleaseCascadeWindow(hwnd)
{
    source_monitor := GetManagedCascadeMonitor(hwnd)
    CancelPlacementStabilization(hwnd)
    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)
    DestroyFocusCornerOverlay(hwnd)
    if source_monitor
        QueueCascadeCompaction(source_monitor)
    QueueFocusCornerUpdate()
    DebugLog("Cascade window released. | hwnd=" hwnd " | source-monitor=" source_monitor)
}
