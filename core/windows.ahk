; Window ownership shared by the modules. Windows that Wonder Windows
; positioned by hand are left alone by automatic placement until an explicit
; adoption releases them. Modules react through handlers instead of core
; reaching into their state.
class SuiteWindowOwnership {
    static marker := "nroj.SuperHotkeyWorld.ManualLayout"
    static windows := Map()
    static claimHandlers := []    ; handler(hwnd) after a window becomes manual
    static releaseHandlers := []  ; handler(hwnd) before adoption; false keeps it manual

    static OnClaim(handler) => this._AddHandler(this.claimHandlers, handler)
    static OffClaim(handler) => this._RemoveHandler(this.claimHandlers, handler)
    static OnRelease(handler) => this._AddHandler(this.releaseHandlers, handler)

    static _AddHandler(handlers, handler) {
        for existing in handlers
            if existing = handler
                return
        handlers.Push(handler)
    }

    static _RemoveHandler(handlers, handler) {
        for index, existing in handlers
            if existing = handler {
                handlers.RemoveAt(index)
                return
            }
    }

    static IsSuiteSurface(hwnd) {
        return hwnd && (WindowProcessId(hwnd) = DllCall("GetCurrentProcessId", "uint")
            || DllCall("GetPropW", "ptr", hwnd, "str", "nroj.PaperPad.Notepad3Window", "ptr"))
    }

    ; Ordinary suite GUIs and the marked Paper Pad editor may be arranged by
    ; Wonder Windows; overlays, hooks, and private utility windows stay excluded.
    static AllowsWonderWindows(hwnd) {
        if !hwnd
            return false
        if !this.IsSuiteSurface(hwnd)
            return true
        return !!DllCall("GetPropW", "ptr", hwnd, "str", SuiteFullscreen.marker, "ptr")
            || !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.PaperPad.Notepad3Window", "ptr")
    }

    static IsManual(hwnd) {
        if !this.windows.Has(hwnd)
            return false
        matches := WindowProcessId(hwnd) = this.windows[hwnd]
            && DllCall("GetPropW", "ptr", hwnd, "str", this.marker, "ptr") = A_ScriptHwnd
        if !matches
            this.windows.Delete(hwnd)
        return matches
    }

    static Claim(hwnd) {
        if IsObject(SuiteState.App) && SuiteState.App.stopping
            return
        processId := WindowProcessId(hwnd)
        if !processId
            return
        ; A per-window property prevents a recycled HWND (even in the same process)
        ; from inheriting manual ownership after the original window was destroyed.
        if !DllCall("SetPropW", "ptr", hwnd, "str", this.marker, "ptr", A_ScriptHwnd, "int")
            throw OSError(A_LastError, "Mark manual window layout")
        this.windows[hwnd] := processId
        for handler in this.claimHandlers.Clone()
            handler.Call(hwnd)
    }

    static Release(hwnd, forAdoption := true) {
        if !this.IsManual(hwnd)
            return false
        if forAdoption
            for handler in this.releaseHandlers.Clone()
                if !handler.Call(hwnd)
                    return false
        DllCall("RemovePropW", "ptr", hwnd, "str", this.marker, "ptr")
        this.windows.Delete(hwnd)
        return true
    }

    static Prune() {
        for hwnd in this.windows.Clone()
            this.IsManual(hwnd)
    }

    static Clear() {
        for hwnd in this.windows.Clone()
            this.Release(hwnd, false)
    }
}

PaperPadWindowActive(*) {
    hwnd := DllCall("GetForegroundWindow", "ptr")
    return hwnd && !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.PaperPad.Notepad3Window", "ptr")
}

; =============================================================================
; native window queries and DPI boundaries shared by the modules
; =============================================================================

WindowProcessId(hwnd) {
    processId := 0
    if hwnd
        DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &processId, "uint")
    return processId
}

; Cloaked windows (other virtual desktops, suspended apps) are invisible even
; though IsWindowVisible reports them as visible.
IsWindowCloaked(hwnd) {
    cloaked := 0
    result := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd,
        "uint", 14, "uint*", &cloaked, "uint", 4, "int") ; DWMWA_CLOAKED
    return result = 0 && cloaked != 0
}

; The visible DWM frame in physical pixels, without invisible resize borders.
GetVisibleWindowBounds(hwnd, &x, &y, &width, &height) {
    frame := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd,
        "uint", 9, "ptr", frame, "uint", frame.Size, "int") != 0 ; DWMWA_EXTENDED_FRAME_BOUNDS
        return false
    x := NumGet(frame, 0, "int")
    y := NumGet(frame, 4, "int")
    width := NumGet(frame, 8, "int") - x
    height := NumGet(frame, 12, "int") - y
    return width > 0 && height > 0
}

; A window's raw rectangle and visible DWM frame in physical pixels, or 0.
; Without DWM frame bounds the visible frame is the raw rectangle. left, top,
; right and bottom are the invisible resize borders between the two.
GetWindowFrame(hwnd) {
    if !hwnd
        return 0
    try WinGetPosPixels(&rawX, &rawY, &rawWidth, &rawHeight, "ahk_id " hwnd)
    catch
        return 0
    if rawWidth <= 0 || rawHeight <= 0
        return 0
    if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
        x := rawX, y := rawY, width := rawWidth, height := rawHeight
    return {rawX: rawX, rawY: rawY, rawWidth: rawWidth, rawHeight: rawHeight,
        x: x, y: y, width: width, height: height,
        left: x - rawX, top: y - rawY,
        right: rawX + rawWidth - x - width, bottom: rawY + rawHeight - y - height}
}

; The raw rectangle that gives a window this visible frame.
VisibleToRawRect(hwnd, x, y, width, height) {
    if !(frame := GetWindowFrame(hwnd))
        return [x, y, width, height]
    return [x - frame.left, y - frame.top,
        Max(1, width + frame.left + frame.right), Max(1, height + frame.top + frame.bottom)]
}

; Taskbars, the desktop and tray popups are never arranged or focused.
IsShellSurfaceClass(className) {
    return className = "Shell_TrayWnd" || className = "Shell_SecondaryTrayWnd"
        || className = "Progman" || className = "WorkerW"
        || className = "NotifyIconOverflowWindow" || className = "tooltips_class32"
}

IsShellSurfaceWindow(hwnd) {
    try return hwnd && IsShellSurfaceClass(WinGetClass("ahk_id " hwnd))
    return false
}

; A root, activatable, unowned window outside the shell: the common base for
; the windows the modules arrange.
IsTopLevelAppWindow(hwnd, &className := "") {
    if !hwnd || DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != hwnd ; GA_ROOT
        return false
    try {
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)
        className := WinGetClass("ahk_id " hwnd)
    }
    catch
        return false
    ; Reject WS_CHILD, WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE and owned popups.
    return !(style & 0x40000000) && !(exStyle & 0x08000080)
        && !DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") && !IsShellSurfaceClass(className)
}

; The display Windows assigns a window to: the largest intersection, or the
; restored rectangle when it is minimized. 0 when no display matches.
WindowMonitorIndex(hwnd) {
    monitor := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST
    info := Buffer(104, 0) ; MONITORINFOEXW
    NumPut("uint", info.Size, info)
    if !monitor || !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", info, "int")
        return 0
    device := StrGet(info.Ptr + 40, 32, "UTF-16")
    Loop MonitorGetCount() {
        if MonitorGetName(A_Index) = device
            return A_Index
    }
    return 0
}

; Geometry is in physical pixels. Scope the context to one native call:
; AutoHotkey threads share one OS thread, so Sleep, dialogs and modal message
; loops would let another thread run in a borrowed context.
CallWithDpiContext(context, callback, args*) {
    previousContext := DllCall("SetThreadDpiAwarenessContext", "ptr", context, "ptr")
    if !previousContext
        throw OSError(A_LastError, "SetThreadDpiAwarenessContext")
    try return callback(args*)
    finally {
        ; Restoring the context must not replace a native operation's error code.
        lastError := A_LastError
        DllCall("SetThreadDpiAwarenessContext", "ptr", previousContext, "ptr")
        DllCall("SetLastError", "uint", lastError)
    }
}

WinGetPosPixels(args*) => CallWithDpiContext(-3, WinGetPos, args*)
WinMovePixels(args*) => CallWithDpiContext(-3, WinMove, args*)
MonitorGetPixels(args*) => CallWithDpiContext(-3, MonitorGet, args*)
MonitorGetWorkAreaPixels(args*) => CallWithDpiContext(-3, MonitorGetWorkArea, args*)
MouseGetPosPixels(args*) => CallWithDpiContext(-3, MouseGetPos, args*)
PhysicalDllCall(args*) => CallWithDpiContext(-3, DllCall, args*)
