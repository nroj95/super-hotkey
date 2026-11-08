; Window ownership shared by the modules. Windows that Wonder Windows
; positioned by hand are left alone by automatic placement until an explicit
; adoption releases them, or until Wonder Windows returns them to their
; original shape. Modules react through handlers instead of core reaching
; into their state.
class SuiteWindowOwnership {
    static marker := "nroj.SuperHotkey.ManualLayout"
    static windows := Map()
    static claimHandlers := []    ; handler(hwnd) after a window becomes manual
    static releaseHandlers := []  ; handler(hwnd) before adoption; false keeps it manual
    static returnHandlers := []   ; handler(hwnd, shape) after a window is back at its original shape

    static OnClaim(handler) => this._AddHandler(this.claimHandlers, handler)
    static OffClaim(handler) => this._RemoveHandler(this.claimHandlers, handler)
    static OnRelease(handler) => this._AddHandler(this.releaseHandlers, handler)
    static OnReturn(handler) => this._AddHandler(this.returnHandlers, handler)
    static OffReturn(handler) => this._RemoveHandler(this.returnHandlers, handler)

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

    ; Marks an ordinary suite window, such as a settings page, that Wonder
    ; Windows may arrange like any application window.
    static AllowArranging(window) {
        if !DllCall("SetPropW", "ptr", window.Hwnd, "str", "nroj.SuperHotkey.Arrangeable", "ptr", 1, "int")
            throw OSError(A_LastError, "Mark Super Hotkey window")
    }

    ; Ordinary suite GUIs and the marked Paper Pad editor may be arranged by
    ; Wonder Windows; overlays, hooks, and private utility windows stay excluded.
    static AllowsWonderWindows(hwnd) {
        if !hwnd
            return false
        if !this.IsSuiteSurface(hwnd)
            return true
        return !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.SuperHotkey.Arrangeable", "ptr")
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
        if IsObject(SuiteState.Log) && !this.IsManual(hwnd)
            SuiteState.Log.Debug("Core", "Window positioned by hand. | " DescribeWindow(hwnd))
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
        if IsObject(SuiteState.Log)
            SuiteState.Log.Debug("Core", "Window no longer positioned by hand. | adoption=" (forAdoption ? 1 : 0)
                . " | " DescribeWindow(hwnd))
        return true
    }

    ; A window positioned by hand is back at its original shape: it stops being
    ; manual, and a module that lent it, such as Cascade Kingdom, takes it back.
    ; shape is the CaptureWindowShape it had by hand just before, or 0.
    static Return(hwnd, shape := 0) {
        if !this.Release(hwnd, false)
            return false
        for handler in this.returnHandlers.Clone()
            handler.Call(hwnd, shape)
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

; Windows that a module arranges automatically. Cascade Kingdom is the provider,
; so Wonder Windows can respect its windows without calling into it.
class SuiteManagedWindows {
    static provider := 0  ; ManagedMonitor(hwnd)

    ; The display a managed window belongs to, or 0 when no module manages it.
    static Monitor(hwnd) => this.provider ? this.provider.ManagedMonitor(hwnd) : 0
}

; The display the user is working on. Keyboard-only users never aim the
; pointer, so it chooses a display only through a click: the active app window
; decides. Start, search, the taskbar and the desktop are passed through; the
; click that opened one chooses, or else the app window used before it does.
; Hotkeys also ask it for the window the user is in, which looks through
; passing overlays such as a shortcut guide shown while Win is held.
class SuiteWorkingMonitor {
    static recent := []  ; foreground windows, newest first: {hwnd, click}
    static click := 0    ; the last physical mouse press: {tick, x, y} in physical pixels
    static hook := 0
    static callback := 0

    static Start(manager) {
        for key in ["LButton", "RButton", "MButton"]
            manager.Observe("~*" key, (*) => true, ObjBindMethod(this, "_RecordClick"))
        this.callback := CallbackCreate(ObjBindMethod(this, "_RecordForeground"), , 7)
        ; EVENT_SYSTEM_FOREGROUND out of context, including the suite's own windows.
        this.hook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0,
            "ptr", this.callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
        if !this.hook
            SuiteState.Log.Write("Core", "foreground tracking unavailable; using the active window only", "ERROR")
    }

    static Stop() {
        if this.hook
            DllCall("UnhookWinEvent", "ptr", this.hook)
        if this.callback
            CallbackFree(this.callback)
        this.hook := this.callback := 0
        this.recent := []
        this.click := 0
    }

    ; The AutoHotkey index of the working display. ignore skips a window that
    ; just appeared, such as a suite window being centered.
    static Get(ignore := 0) {
        foreground := DllCall("GetForegroundWindow", "ptr")
        if foreground && (!this.recent.Length || this.recent[1].hwnd != foreground)
            this._RecordForeground(0, 3, foreground)
        monitor := this.Choose(this.recent, ignore, &reason, &source)
        if IsObject(SuiteState.Log) && SuiteState.Log.verbose
            SuiteState.Log.Debug("Core", "Working monitor chosen. | monitor=" monitor " | reason=" reason
                . " | source=" DescribeWindow(source) " | foreground=" DescribeWindow(foreground)
                . " | ignored=" ignore " | recent=" this.recent.Length)
        return monitor
    }

    ; The display that foreground entries, newest first, choose. reason and
    ; source report which entry decided, for verbose logs.
    static Choose(entries, ignore := 0, &reason := "", &source := 0) {
        for entry in entries {
            if entry.hwnd = ignore || !DllCall("IsWindow", "ptr", entry.hwnd, "int")
                continue
            source := entry.hwnd
            if this.IsWorkWindow(entry.hwnd) {
                reason := "work window"
                return WindowMonitorIndex(entry.hwnd) || MonitorGetPrimary()
            }
            if entry.click {
                reason := "click at " entry.click.x "," entry.click.y
                return MonitorHandleIndex(PhysicalDllCall("MonitorFromPoint",
                    "int64", (entry.click.y << 32) | (entry.click.x & 0xFFFFFFFF), "uint", 2, "ptr"))
                    || MonitorGetPrimary()
            }
        }
        source := 0
        reason := "primary fallback"
        return MonitorGetPrimary()
    }

    ; An app window the user works in, unlike the shell surfaces passed through.
    static IsWorkWindow(hwnd) {
        if !IsTopLevelAppWindow(hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            || IsWindowCloaked(hwnd)
            return false
        try return !IsShellHost(WinGetProcessName("ahk_id " hwnd))
        return false
    }

    ; The window the user is in: the foreground, or the window a passing
    ; overlay covers. The user never chose the overlay, so it never decides.
    static UserWindow() {
        foreground := DllCall("GetForegroundWindow", "ptr")
        if !IsPassingOverlay(foreground)
            return foreground
        if !this.recent.Length || this.recent[1].hwnd != foreground
            this._RecordForeground(0, 3, foreground)
        for entry in this.recent
            if !IsPassingOverlay(entry.hwnd) && DllCall("IsWindow", "ptr", entry.hwnd, "int")
                return entry.hwnd
        return foreground
    }

    static _RecordClick(*) {
        MouseGetPosPixels(&x, &y)
        foreground := DllCall("GetForegroundWindow", "ptr")
        this.NoteClick({tick: A_TickCount, x: x, y: y}, foreground)
        if IsObject(SuiteState.Log) && SuiteState.Log.verbose
            SuiteState.Log.Debug("Core", "Click recorded. | at=" x "," y
                . " | keyboard-idle=" A_TimeIdleKeyboard " | mouse-idle=" A_TimeIdleMouse
                . " | foreground=" DescribeWindow(foreground))
    }

    ; The desktop is one window across every display, so clicking it on
    ; another display changes no foreground: the front entry takes the newer
    ; click. A click that activates another window gets its own entry anyway.
    static NoteClick(click, foreground) {
        this.click := click
        if this.recent.Length && this.recent[1].hwnd = foreground
            this.recent[1].click := click
    }

    ; A window that takes the foreground after a click newer than any
    ; keystroke was brought there by that click.
    ; Focus handed back by the suite is not a new choice: the window's entry,
    ; including the click that brought it forward, returns to the front.
    static Return(hwnd) {
        for index, entry in this.recent
            if entry.hwnd = hwnd {
                this.recent.RemoveAt(index)
                this.recent.InsertAt(1, entry)
                return
            }
        this._RecordForeground(0, 3, hwnd)
    }

    static _RecordForeground(hook, event, hwnd, *) {
        ; Get() and Return() may already have put this window in front.
        if !hwnd || this.recent.Length && this.recent[1].hwnd = hwnd
            return
        keyboardIdle := A_TimeIdleKeyboard, mouseIdle := A_TimeIdleMouse
        clickAge := this.click ? A_TickCount - this.click.tick : "none"
        press := this.click && clickAge < keyboardIdle ? this.click : 0
        if IsObject(SuiteState.Log) && SuiteState.Log.verbose
            SuiteState.Log.Debug("Core", "Foreground recorded. | by-click=" (press ? 1 : 0)
                . " | click-age=" clickAge " | keyboard-idle=" keyboardIdle " | mouse-idle=" mouseIdle
                . " | work=" this.IsWorkWindow(hwnd) " | " DescribeWindow(hwnd))
        recent := [{hwnd: hwnd, click: press}]
        for entry in this.recent
            if entry.hwnd != hwnd && recent.Length < 16
                recent.Push(entry)
        this.recent := recent
    }
}

PaperPadWindowActive(*) {
    hwnd := SuiteWorkingMonitor.UserWindow()
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

; Start, search and the shell's flyouts run in these hosts.
IsShellHost(processName) {
    return processName = "startmenuexperiencehost.exe" || processName = "searchhost.exe"
        || processName = "searchapp.exe" || processName = "shellexperiencehost.exe"
        || processName = "shellhost.exe"
}

; A floating helper that takes the foreground on its own, such as a shortcut
; guide shown while Win is held: a topmost tool or no-activate window. The
; shell's own surfaces, menus and switchers are things the user opened.
IsPassingOverlay(hwnd) {
    exStyle := hwnd ? DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", -20, "ptr") : 0
    ; WS_EX_TOPMOST with WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE.
    if !(exStyle & 0x8) || !(exStyle & 0x08000080)
        return false
    try {
        processName := WinGetProcessName("ahk_id " hwnd)
        return !IsShellSurfaceClass(WinGetClass("ahk_id " hwnd))
            && processName != "explorer.exe" && !IsShellHost(processName)
    }
    return false
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

; A visible, uncloaked application window the user can switch to. Suite
; overlays stay excluded; minimized windows count only when requested.
IsSwitchableWindow(hwnd, includeMinimized := false) {
    if !SuiteWindowOwnership.AllowsWonderWindows(hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || !IsTopLevelAppWindow(hwnd) || IsWindowCloaked(hwnd)
        return false
    try return (includeMinimized || WinGetMinMax("ahk_id " hwnd) != -1) && WinGetTitle("ahk_id " hwnd) != ""
    return false
}

; Restores and activates a window. Windows can refuse a foreground change,
; so SetForegroundWindow is retried up to six times.
ActivateWindow(hwnd) {
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false
    if WinActive(hwnd) && !DllCall("IsIconic", "ptr", hwnd, "int")
        return true
    SuiteState.Log.Debug("Core", "Window activation begin. | target=" DescribeWindow(hwnd))
    try {
        if WinGetMinMax(hwnd) = -1
            WinRestore(hwnd)
    }
    Loop 6 {
        try WinActivate(hwnd)
        if WinActive(hwnd)
            return true
        result := DllCall("SetForegroundWindow", "ptr", hwnd, "int")
        Sleep 50
        foreground := DllCall("GetForegroundWindow", "ptr")
        SuiteState.Log.Debug("Core", "Window activation attempt. | attempt=" A_Index
            . " | SetForegroundWindow=" result " | requested=" DescribeWindow(hwnd)
            . " | foreground=" DescribeWindow(foreground))
        if foreground = hwnd
            return true
    }
    return false
}

; Closes a window, then makes sure a sensible window has focus. Windows picks
; the next foreground; some apps leave the taskbar or desktop active instead,
; so the eligible Z-order is captured BEFORE closing and used as a fallback
; across all monitors. Save prompts and other genuine handoffs are left alone.
class SuiteCloseWindow {
    static request := 0
    static owner := "close-window"

    ; Closes hwnd only while it is still the foreground window of process pid.
    static Close(hwnd, pid) {
        if !hwnd || !pid || DllCall("GetForegroundWindow", "ptr") != hwnd
            return
        try {
            if WinGetPID("ahk_id " hwnd) != pid
                return
            targets := []
            for candidate in WinGetList()
                if candidate != hwnd && IsSwitchableWindow(candidate)
                    try targets.Push({hwnd: candidate, pid: WinGetPID("ahk_id " candidate)})
            ; Invalidate an earlier close request even if this was the last window.
            this.request := 0
            WinClose("ahk_id " hwnd)
            ; Watch even with no fallback targets: Windows may still focus a valid
            ; window that became available during the close.
            request := {hwnd: hwnd, pid: pid, targets: targets, started: A_TickCount}
            this.request := request
            SetTimer(ObjBindMethod(this, "Watch", request), -130)
        }
        catch Error as err
            SuiteState.Log.Error("Core / close window", err)
    }

    static Cancel() => this.request := 0

    ; Preserve ordinary focus handoffs, including modal save/confirmation dialogs.
    ; Unlike the fallback candidate test, a real foreground dialog may be owned.
    static HasUsableForeground(hwnd, closing_hwnd, closing_pid) {
        if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
            return false
        if hwnd = closing_hwnd {
            try {
                if WinGetPID("ahk_id " hwnd) = closing_pid
                    return false
            }
            catch
                return false
        }
        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            || DllCall("IsIconic", "ptr", hwnd, "int")
            || IsWindowCloaked(hwnd) || IsShellSurfaceWindow(hwnd)
            || !SuiteWindowOwnership.AllowsWonderWindows(hwnd)
            return false
        try return !(WinGetExStyle("ahk_id " hwnd) & 0x08000000) ; WS_EX_NOACTIVATE
        catch
            return false
    }

    static OriginStillVisible(hwnd, pid) {
        if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
            return false
        try return WinGetPID("ahk_id " hwnd) = pid
            && DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
            && !IsWindowCloaked(hwnd)
        catch
            return false
    }

    static Decision(other_focused, origin_visible) {
        return other_focused ? "preserve" : (origin_visible ? "wait" : "recover")
    }

    ; The accent border belongs to a completed close, never to a pending save dialog.
    static ShouldHighlight(outcome, origin_visible) => outcome = "preserve" && !origin_visible

    static Watch(request) {
        if this.request != request
            return
        foreground := DllCall("GetForegroundWindow", "ptr")
        origin_visible := this.OriginStillVisible(request.hwnd, request.pid)
        outcome := this.Decision(this.HasUsableForeground(foreground, request.hwnd, request.pid),
            origin_visible)
        elapsed := (A_TickCount - request.started) & 0xFFFFFFFF
        keepWatching := elapsed < 3500

        if outcome = "preserve" && !this.ShouldHighlight(outcome, origin_visible) {
            ; Keep native focus untouched, including save dialogs. If the close
            ; completes shortly afterward, the next poll highlights its result.
            return this._Again(request, keepWatching)
        }
        if outcome = "preserve" {
            this.request := 0
            ; Focus may have changed while the timer ran: highlight only the real
            ; current foreground, never an earlier snapshot.
            foreground := DllCall("GetForegroundWindow", "ptr")
            if this.HasUsableForeground(foreground, request.hwnd, request.pid) {
                SuiteFocusBorder.Show(foreground, this.owner)
                SuiteState.Log.Debug("Core", "Close native focus highlighted. | target=" DescribeWindow(foreground))
            }
            return
        }
        ; WinClose can be asynchronous. Do not steal focus from an application
        ; that is still visible, or while it is waiting for a save prompt.
        if outcome = "wait"
            return this._Again(request, keepWatching)
        ; Don't race a manual mouse/keyboard action during the shell handoff.
        for key in ["LButton", "RButton", "MButton", "LWin", "RWin", "Alt", "Ctrl"]
            if GetKeyState(key, "P")
                return this._Again(request, keepWatching)

        this.request := 0
        for target in request.targets {
            try {
                if !WinExist("ahk_id " target.hwnd)
                    || WinGetPID("ahk_id " target.hwnd) != target.pid
                    || !IsSwitchableWindow(target.hwnd)
                    continue
                ; Never override a real foreground switch while evaluating choices.
                if this.HasUsableForeground(DllCall("GetForegroundWindow", "ptr"), request.hwnd, request.pid)
                    return
                if ActivateWindow(target.hwnd) {
                    ; Outline the window actually focused, including on other monitors.
                    if DllCall("GetForegroundWindow", "ptr") = target.hwnd
                        SuiteFocusBorder.Show(target.hwnd, this.owner)
                    SuiteState.Log.Debug("Core", "Close focus fallback. | target=" DescribeWindow(target.hwnd))
                    return
                }
            }
            catch Error as err
                SuiteState.Log.Error("Core / close focus fallback", err)
        }
    }

    static _Again(request, keepWatching) {
        if keepWatching
            SetTimer(ObjBindMethod(this, "Watch", request), -140)
        else
            this.request := 0
    }
}

; Closing a suite window returns focus to the window the user was in before
; the suite opened it. Otherwise Windows hands focus to the next app in
; Z-order, which may sit on another display: keystrokes would land there, and
; the next suite window would open there too.
class SuiteFocusReturn {
    static target := 0 ; the last non-suite foreground seen when a suite window opened

    static Remember() {
        hwnd := DllCall("GetForegroundWindow", "ptr")
        if hwnd && !SuiteWindowOwnership.IsSuiteSurface(hwnd)
            this.target := hwnd
    }

    ; Destroys a suite window. When it has focus, focus moves back first, while
    ; the suite still owns the foreground and Windows allows the switch.
    static Destroy(window) {
        hwnd := window.Hwnd
        target := this.target
        if DllCall("GetForegroundWindow", "ptr") = hwnd && target && target != hwnd
            && DllCall("IsWindow", "ptr", target, "int") && DllCall("IsWindowVisible", "ptr", target, "int")
            && !DllCall("IsIconic", "ptr", target, "int") && !IsWindowCloaked(target)
            && DllCall("SetForegroundWindow", "ptr", target, "int")
            && DllCall("GetForegroundWindow", "ptr") = target
            SuiteWorkingMonitor.Return(target)
        window.Destroy()
    }
}

; A WINDOWPLACEMENT snapshot, including a maximized window's restore rectangle.
CaptureWindowPlacement(hwnd) {
    placement := Buffer(44, 0)
    NumPut("uint", placement.Size, placement)
    if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", placement, "int")
        throw OSError()
    return placement
}

; Where a window is, in physical pixels, and a maximized window's placement
; with its normal rectangle, or 0: {pid, x, y, width, height, placement}.
CaptureWindowShape(hwnd) {
    try {
        placement := WinGetMinMax(hwnd) = 1 ? CaptureWindowPlacement(hwnd) : 0
        WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
        return {pid: WinGetPID(hwnd), x: x, y: y, width: width, height: height, placement: placement}
    }
    catch
        return 0
}

; A one-line window description for verbose logs; only the handle otherwise.
DescribeWindow(hwnd) {
    if !SuiteState.Log.verbose || !hwnd
        return "hwnd=" hwnd
    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"
    title := className := processName := processPath := ""
    minMax := style := exStyle := x := y := width := height := "?"
    try title := StrReplace(StrReplace(WinGetTitle(hwnd), "`r", " "), "`n", " ")
    try className := WinGetClass(hwnd)
    try processName := WinGetProcessName(hwnd)
    try processPath := WinGetProcessPath(hwnd)
    try minMax := WinGetMinMax(hwnd)
    try style := WinGetStyle(hwnd)
    try exStyle := WinGetExStyle(hwnd)
    ; A failed WinGetPos unsets its outputs; the window may close meanwhile.
    try WinGetPosPixels(&x, &y, &width, &height, hwnd)
    catch
        x := y := width := height := "?"
    return "hwnd=" hwnd ' exe="' processName '" class="' className '" title="' title '"'
        . " minmax=" minMax " visible=" DllCall("IsWindowVisible", "ptr", hwnd, "int")
        . " iconic=" DllCall("IsIconic", "ptr", hwnd, "int") " cloaked=" IsWindowCloaked(hwnd)
        . " owner=" DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        . " style=" style " exstyle=" exStyle " rect=(" x "," y " " width "x" height ")"
        . ' path="' processPath '"'
}

; The native handle of the display Windows assigns a window to: the largest
; intersection, or the restored rectangle when it is minimized.
WindowMonitor(hwnd) => DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST

; A display's MONITORINFOEXW: rcMonitor at 4, rcWork at 20, device name at 40.
; Rectangles follow the calling thread's DPI context.
ReadMonitorInfo(monitor) {
    info := Buffer(104, 0)
    NumPut("uint", info.Size, info)
    if !monitor || !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", info, "int")
        throw OSError(A_LastError, "GetMonitorInfoW")
    return info
}

; A display's bounds and work area, each as [left, top, right, bottom].
MonitorRects(monitor) {
    info := ReadMonitorInfo(monitor)
    Rect(offset) => [NumGet(info, offset, "int"), NumGet(info, offset + 4, "int"),
        NumGet(info, offset + 8, "int"), NumGet(info, offset + 12, "int")]
    return {monitor: Rect(4), work: Rect(20)}
}

; The AutoHotkey index of the display a window is on, or 0.
WindowMonitorIndex(hwnd) => MonitorHandleIndex(WindowMonitor(hwnd))

; The AutoHotkey index of a native display handle, or 0.
MonitorHandleIndex(monitor) {
    try device := StrGet(ReadMonitorInfo(monitor).Ptr + 40, 32, "UTF-16")
    catch
        return 0
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
