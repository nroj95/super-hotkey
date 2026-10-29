; Wonder Windows moving onto, or swapping with, the nearest window in a direction.

; =============================================================================
; moving onto or swapping with the nearest window in a direction
; =============================================================================

; The active window takes its neighbor's logical zone and stacks in front of
; it, so Win + Enter can cycle the two. The neighbor stays where it is.
WW_MoveOntoWindow(direction)
{
    Critical "On"
    if direction != "left" && direction != "right"
        && direction != "up" && direction != "down"
        return

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        WW_PrepareWindowForPlacement(hwnd)
        monitor := WindowMonitor(hwnd)
        WW_PruneLogicalZones()
        target := WW_FindDirectionalTarget(hwnd, monitor, direction)
        if !target
            return
        if !WW_MoveWindowToZone(hwnd, WW_GetLogicalZone(target, monitor))
            return
        WW_ForgetWindowLayoutCycle(hwnd)
        WinActivate("ahk_id " hwnd)
    }
    catch Error as err
        WW_DebugError("Move onto nearest window", err)
}

; The active window and its neighbor trade logical zones.
WW_SwapWindow(direction)
{
    Critical "On"
    if direction != "left" && direction != "right"
        && direction != "up" && direction != "down"
        return

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        WW_PrepareWindowForPlacement(hwnd)
        monitor := WindowMonitor(hwnd)
        WW_PruneLogicalZones()
        target := WW_FindDirectionalTarget(hwnd, monitor, direction)
        if !target
            return

        WW_RememberNormalWindowPlacement(target)
        if !WW_SwapWindowRectangles(hwnd, target)
            return
        WW_ForgetHorizontalStretch(target)
        WW_ForgetVerticalStretch(target)
        WW_ForgetFullStretch(target)
        WW_ForgetWindowLayoutCycle(hwnd)
        WW_ForgetWindowLayoutCycle(target)
        WinActivate("ahk_id " hwnd)
    }
    catch Error as err
        WW_DebugError("Directional window swap", err)
}

WW_FindDirectionalTarget(hwnd, monitor, direction)
{
    source := WW_GetLogicalZone(hwnd, monitor)
    sourceX := source[1] + source[3] / 2
    sourceY := source[2] + source[4] / 2
    bestHwnd := 0
    bestScore := 0

    for candidate in WinGetList() {
        if candidate = hwnd || !WW_IsDirectionalCandidate(candidate, monitor)
            continue
        try {
            zone := WW_GetLogicalZone(candidate, monitor)
            deltaX := zone[1] + zone[3] / 2 - sourceX
            deltaY := zone[2] + zone[4] / 2 - sourceY
            score := WW_DirectionalScore(deltaX, deltaY, direction)
            if score < 0
                continue
            if !bestHwnd || score < bestScore {
                bestHwnd := candidate
                bestScore := score
            }
        }
    }
    return bestHwnd
}

WW_DirectionalScore(deltaX, deltaY, direction)
{
    switch direction {
        case "left":
            return deltaX < 0 ? -deltaX + Abs(deltaY) * 2 : -1
        case "right":
            return deltaX > 0 ? deltaX + Abs(deltaY) * 2 : -1
        case "up":
            return deltaY < 0 ? -deltaY + Abs(deltaX) * 2 : -1
        case "down":
            return deltaY > 0 ? deltaY + Abs(deltaX) * 2 : -1
    }
    return -1
}

WW_IsDirectionalCandidate(hwnd, monitor_handle)
{
    if !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
        return false

    if WW_IsNativeFullscreen(hwnd)
        return false

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        return false

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if root_hwnd != hwnd
        return false

    try {
        if WinGetMinMax("ahk_id " hwnd) != 0
            return false

        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)
        class_name := WinGetClass("ahk_id " hwnd)
    }
    catch {
        return false
    }

    if title = ""
        return false

    if style & 0x40000000 ; WS_CHILD
        return false

    if !(style & 0x00C00000) ; normal caption
        return false

    if !(style & 0x00040000) ; resizable
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if IsShellSurfaceClass(class_name)
        return false

    if IsWindowCloaked(hwnd)
        return false

    candidate_monitor := WindowMonitor(hwnd)

    return candidate_monitor = monitor_handle
}


; Intended positions remain distinct from what minimum-size windows can display.
; Forget an entry when the user or another application moves/resizes that window.
WW_GetLogicalZone(hwnd, monitor := 0)
{
    global WW_logical_zones
    actual := WW_GetWindowLayoutRectangle(hwnd)
    if !WW_logical_zones.Has(hwnd)
        return actual

    saved := WW_logical_zones[hwnd]
    if !WW_IsStretchStateCurrent(hwnd, saved, monitor)
        || !WW_LogicalZoneMarkerMatches(hwnd)
        || !WW_RectanglesMatch(actual, saved["applied"], 2) {
        WW_ForgetLogicalZone(hwnd)
        return actual
    }
    return saved["zone"].Clone()
}

; Window properties disappear with destroyed HWNDs, unlike our in-memory map.
WW_LogicalZoneMarkerMatches(hwnd)
{
    return DllCall("GetPropW", "ptr", hwnd,
        "str", "nroj.SuperHotkey.LogicalZone", "ptr") = A_ScriptHwnd
}

WW_ForgetLogicalZone(hwnd)
{
    global WW_logical_zones
    if !WW_logical_zones.Has(hwnd)
        return
    if WW_LogicalZoneMarkerMatches(hwnd)
        DllCall("RemovePropW", "ptr", hwnd, "str", "nroj.SuperHotkey.LogicalZone", "ptr")
    WW_logical_zones.Delete(hwnd)
}

WW_PruneLogicalZones()
{
    global WW_logical_zones
    for hwnd, saved in WW_logical_zones.Clone()
        if !WW_WindowStateMatchesProcess(hwnd, saved) || !WW_LogicalZoneMarkerMatches(hwnd)
            WW_ForgetLogicalZone(hwnd)
}

WW_ClearLogicalZones()
{
    global WW_logical_zones
    for hwnd in WW_logical_zones.Clone()
        WW_ForgetLogicalZone(hwnd)
}

WW_SaveLogicalZone(hwnd, zone)
{
    global WW_logical_zones
    actual := WW_GetWindowLayoutRectangle(hwnd)
    ; Ordinary exact placements need no bookkeeping.
    if WW_RectanglesMatch(actual, zone, 2) {
        WW_ForgetLogicalZone(hwnd)
        return
    }

    ; Property identity prevents a freshly reopened GUI inheriting a recycled HWND.
    if !DllCall("SetPropW", "ptr", hwnd, "str", "nroj.SuperHotkey.LogicalZone",
        "ptr", A_ScriptHwnd, "int") {
        WW_DebugLog("Could not mark a logical zone. hwnd=" hwnd)
        return
    }
    WW_logical_zones[hwnd] := Map("pid", WinGetPID(hwnd),
        "monitor", WindowMonitor(hwnd),
        "work_area", WW_GetLayoutWorkArea(hwnd), "zone", zone.Clone(), "applied", actual)
}

WW_MoveWindowToZone(hwnd, zone)
{
    WinGetPos(&x, &y, &width, &height, hwnd)
    raw := [x, y, width, height]
    visible := WW_GetWindowLayoutRectangle(hwnd)

    try {
        if WW_MoveWindowToVisibleRectangle(hwnd, zone)
            && WW_WindowMatchesVisibleRectangle(hwnd, zone) {
            WW_SaveLogicalZone(hwnd, zone)
            return true
        }

        ; A size-constrained app may silently clamp WinMove. Keep the size it
        ; accepts, shifted inward only as far as needed to stay on-screen.
        Sleep 30
        accepted := WW_FitAcceptedRectangle(zone, WW_GetWindowLayoutRectangle(hwnd),
            WW_GetLayoutWorkArea(hwnd))
        if IsObject(accepted) && WW_MoveWindowToVisibleRectangle(hwnd, accepted)
            && WW_WindowMatchesVisibleRectangle(hwnd, accepted) {
            ; Record the intended rectangle rather than the larger accepted size.
            WW_SaveLogicalZone(hwnd, zone)
            WW_DebugLog("Used best-effort placement onto a window zone. hwnd=" hwnd)
            return true
        }
        throw Error("Neither exact nor best-effort placement was accepted.")
    }
    catch Error as failure {
        if !WW_RestoreWindowRectangle(hwnd, raw, visible)
            WW_DebugLog("Could not roll back a window zone move. hwnd=" hwnd)
        WW_DebugError("Move window to zone", failure)
        return false
    }
}

WW_RestoreWindowRectangle(hwnd, raw, visible)
{
    try {
        ; Use HWND rectangles here, including invisible resize borders.
        WinMove(raw[1], raw[2], raw[3], raw[4], hwnd)
        return WW_WindowMatchesVisibleRectangle(hwnd, visible)
    }
    catch {
        return false
    }
}

WW_SwapWindowRectangles(first_hwnd, second_hwnd)
{
    WinGetPos(&first_x, &first_y, &first_width, &first_height, first_hwnd)
    WinGetPos(&second_x, &second_y, &second_width, &second_height, second_hwnd)
    first_raw := [first_x, first_y, first_width, first_height]
    second_raw := [second_x, second_y, second_width, second_height]
    first_visible := WW_GetWindowLayoutRectangle(first_hwnd)
    second_visible := WW_GetWindowLayoutRectangle(second_hwnd)
    first_zone := WW_GetLogicalZone(first_hwnd)
    second_zone := WW_GetLogicalZone(second_hwnd)

    try {
        ; Exchange logical zones. For ordinary windows these equal visible frames.
        if WW_MoveWindowToVisibleRectangle(first_hwnd, second_zone)
            && WW_WindowMatchesVisibleRectangle(first_hwnd, second_zone)
            && WW_MoveWindowToVisibleRectangle(second_hwnd, first_zone)
            && WW_WindowMatchesVisibleRectangle(second_hwnd, first_zone)
            && WW_WindowMatchesVisibleRectangle(first_hwnd, second_zone) {
            WW_SaveLogicalZone(first_hwnd, second_zone)
            WW_SaveLogicalZone(second_hwnd, first_zone)
            return true
        }

        ; A size-constrained app may silently clamp WinMove. Start the fallback
        ; from the original positions, never an incomplete partial swap.
        if !WW_RestoreSwapRectangles(first_hwnd, second_hwnd,
            first_raw, second_raw, first_visible, second_visible)
            throw Error("Exact swap was rejected and original geometry could not be restored.")

        work_area := WW_GetLayoutWorkArea(first_hwnd)
        if WW_TryBestEffortSwap(first_hwnd, second_hwnd,
            first_zone, second_zone, work_area) {
            ; Record intended rectangles rather than the larger accepted size.
            WW_SaveLogicalZone(first_hwnd, second_zone)
            WW_SaveLogicalZone(second_hwnd, first_zone)
            WW_DebugLog("Used best-effort window swap. first=" first_hwnd " second=" second_hwnd)
            return true
        }
        throw Error("Neither exact nor best-effort swap was accepted.")
    }
    catch Error as failure {
        if !WW_RestoreSwapRectangles(first_hwnd, second_hwnd,
            first_raw, second_raw, first_visible, second_visible)
            WW_DebugLog("Could not fully roll back swap. first=" first_hwnd " second=" second_hwnd)
        WW_DebugError("Swap window rectangles", failure)
        return false
    }
}

WW_RestoreSwapRectangles(first_hwnd, second_hwnd,
    first_raw, second_raw, first_visible, second_visible)
{
    ; A failed first rollback must not prevent restoring the second window.
    first_restored := WW_RestoreWindowRectangle(first_hwnd, first_raw, first_visible)
    second_restored := WW_RestoreWindowRectangle(second_hwnd, second_raw, second_visible)
    return first_restored && second_restored
}

WW_TryBestEffortSwap(first_hwnd, second_hwnd,
    first_zone, second_zone, work_area)
{
    ; Probe the sizes that each window actually accepts in the incoming zones.
    if !WW_MoveWindowToVisibleRectangle(first_hwnd, second_zone)
        || !WW_MoveWindowToVisibleRectangle(second_hwnd, first_zone)
        return false

    ; Give GUI size handlers a moment to settle before measuring constraints.
    Sleep 30
    first_accepted := WW_GetWindowLayoutRectangle(first_hwnd)
    second_accepted := WW_GetWindowLayoutRectangle(second_hwnd)
    first_target := WW_FitAcceptedRectangle(second_zone, first_accepted, work_area)
    second_target := WW_FitAcceptedRectangle(first_zone, second_accepted, work_area)
    if !IsObject(first_target) || !IsObject(second_target)
        return false

    ; Keep each destination's top-left corner unless accepted dimensions
    ; require shifting it inward to remain entirely on-screen.
    if !WW_MoveWindowToVisibleRectangle(first_hwnd, first_target)
        || !WW_MoveWindowToVisibleRectangle(second_hwnd, second_target)
        return false
    return WW_WindowMatchesVisibleRectangle(first_hwnd, first_target)
        && WW_WindowMatchesVisibleRectangle(second_hwnd, second_target)
        && WW_WindowMatchesVisibleRectangle(first_hwnd, first_target)
}
