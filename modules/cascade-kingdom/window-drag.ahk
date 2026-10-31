; Cascade Kingdom window drags: move-loop tracking and one release-time
; snap, adopt or detach decision.
;
; Drop contract:
; - preserve the original membership/slot throughout a native mouse drag;
; - resolve the visible top-left corner, top-right when mirrored, only after
;   the move loop and mouse-up;
; - snap to the nearest eligible slot, or release an existing member;
; - a real drop can adopt an existing window; ordinary clicks/resizes cannot.

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
    ; Track windows positioned by hand too: a drop on a guide adopts them.
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

CompleteCascadeWindowDrop(drag)
{
    if !IsCascadeEnabled()
        return

    hwnd := drag.hwnd
    if drag.cancelled
        return

    WinGetPosPixels(&x, &y, &width, &height, hwnd)
    if x = drag.x && y = drag.y && width = drag.width && height = drag.height
        return

    ; Edge resizes are not drop-to-join. DPI changes and restoring a maximized
    ; title-bar drag may change size without being an edge resize.
    resized := CascadeDragIsResize(drag, width, height)
    if resized || !IsCascadeWindow(hwnd, true) {
        if drag.source_monitor && !IsWindowInCascadeLayout(hwnd)
            ReleaseCascadeWindow(hwnd)
        return
    }

    if !GetVisibleWindowBounds(hwnd, &frame_x, &frame_y, &frame_width, &frame_height)
        return
    if !(target := CascadeDropTarget(frame_x, frame_y, frame_width))
        return
    monitor_index := target.monitor
    geometry := target.geometry
    slot_index := FindNearestCascadeSlot(target.x, frame_y, geometry.slots, CascadeState.slotTolerance)

    if slot_index && CascadeDisplayAllowed(monitor_index) {
        ; A drop on a guide adopts a window positioned by hand, as Caps + Insert
        ; does. Dropped anywhere else, it stays positioned by hand.
        was_manual := SuiteWindowOwnership.IsManual(hwnd)
        if was_manual && !SuiteWindowOwnership.Release(hwnd) {
            DebugLog("Cascade drop kept a window positioned by hand. | hwnd=" hwnd)
            return
        }
        if PlaceCascadeWindowOnMonitor(hwnd, monitor_index, geometry.slots[slot_index]) {
            RemoveWindowFromMinimizeState(hwnd)
            if drag.source_monitor
                QueueCascadeCompaction(drag.source_monitor)
            else
                RememberCascadeJoinPosition(hwnd, {pid: drag.pid, x: drag.x, y: drag.y,
                    width: drag.width, height: drag.height, placement: drag.placement}, was_manual)
            ; Keep the dropped window in its slot while others fill gaps. The
            ; cascade stays gap-free, so a drop past its end lands at its end.
            QueueCascadeCompaction(monitor_index, hwnd)
            DebugLog("Cascade drop snapped. | hwnd=" hwnd
                " | monitor=" monitor_index " | slot=" slot_index)
            return
        }
        if was_manual
            SuiteWindowOwnership.Claim(hwnd)
        ; A scale change that interrupts the move is not an intentional detach.
        if IsCascadeDisplayTransition()
            return
        ; Do not keep a failed snap half-adopted or silently choose another slot.
        DebugLog("Cascade drop snap failed. | hwnd=" hwnd)
    }

    ReleaseCascadeWindow(hwnd)
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
