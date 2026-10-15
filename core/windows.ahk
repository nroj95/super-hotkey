; Shared GUI identity and the small hand-off between manual and automatic layouts.
SuiteGui(options := "", title := "") {
    window := Gui(options, title)
    SuiteIcons.Apply(window)
    ; Mark before showing: the window-show hook must never adopt our own dialogs.
    DllCall("SetPropW", "ptr", window.Hwnd, "str", "nroj.WindowCascade.Ignore", "ptr", 1, "int")
    ; Only actual resizable windows need the native sizing grip.
    ; Cascade focus tabs, DPI probes and other overlays are not resizable.
    if DllCall("GetWindowLongPtrW", "ptr", window.Hwnd, "int", -16, "ptr") & 0x00040000 ; WS_THICKFRAME
        SuiteSizeGrip.Attach(window)
    return window
}

SuiteShowCentered(window, width, height, layoutCallback := 0) {
    ; Size while hidden so the user only sees the correctly centered layout.
    window.Show("Hide w" width " h" height)
    window.GetClientPos(, , &clientWidth, &clientHeight)
    if HasMethod(layoutCallback, "Call")
        layoutCallback.Call(window, 0, clientWidth, clientHeight)

    rect := Buffer(16, 0)
    point := Buffer(8, 0)
    if !DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
        || !DllCall("GetCursorPos", "ptr", point, "int")
        throw OSError(A_LastError, "Center Super Hotkey window")
    outerWidth := NumGet(rect, 8, "int") - NumGet(rect, 0, "int")
    outerHeight := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
    cursorX := NumGet(point, 0, "int")
    cursorY := NumGet(point, 4, "int")
    selected := 1
    loop MonitorGetCount() {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if cursorX >= left && cursorX < right && cursorY >= top && cursorY < bottom {
            selected := A_Index
            break
        }
    }
    MonitorGetWorkArea(selected, &left, &top, &right, &bottom)
    x := left + Floor((right - left - outerWidth) / 2)
    y := top + Floor((bottom - top - outerHeight) / 2)
    if !DllCall("SetWindowPos", "ptr", window.Hwnd, "ptr", 0,
        "int", x, "int", y, "int", 0, "int", 0, "uint", 0x15, "int")
        throw OSError(A_LastError, "Position Super Hotkey window")
    SuiteSizeGrip.Move(window)
    window.Show()
}

class SuiteFullscreen {
    static placements := Map()
    static marker := "nroj.SuperHotkey.FullscreenAllowed"

    static Enable(window) {
        if !DllCall("SetPropW", "ptr", window.Hwnd, "str", this.marker, "ptr", 1, "int")
            throw OSError(A_LastError, "Enable Super Hotkey fullscreen")
    }

    static Active(*) {
        ; F11 remains assignable while the Keybindings recorder is active.
        if IsObject(SuiteState.App) && IsObject(SuiteState.App.manager)
            && IsObject(SuiteState.App.manager.recording)
            return false
        hwnd := WinActive("A")
        return hwnd && !!DllCall("GetPropW", "ptr", hwnd, "str", this.marker, "ptr")
    }

    static IsFullscreen(window) => this.placements.Has(window.Hwnd)

    static Forget(window) {
        if this.placements.Has(window.Hwnd)
            this.placements.Delete(window.Hwnd)
    }

    static Toggle(*) {
        if !this.Active()
            return
        hwnd := WinActive("A")
        window := GuiFromHwnd(hwnd)
        if !IsObject(window)
            return
        target := "ahk_id " hwnd

        if this.placements.Has(hwnd) {
            saved := this.placements[hwnd]
            WinSetStyle(saved.style, target)
            WinSetExStyle(saved.exStyle, target)
            if !DllCall("SetWindowPlacement", "ptr", hwnd, "ptr", saved.placement, "int")
                throw OSError(A_LastError, "Restore Super Hotkey window")
            if !DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
                "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37, "int")
                throw OSError(A_LastError, "Restore Super Hotkey frame")
            this.placements.Delete(hwnd)
            SuiteSizeGrip.Move(window, WinGetMinMax(target))
            return
        }

        placement := Buffer(44, 0) ; WINDOWPLACEMENT
        NumPut("uint", placement.Size, placement)
        if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", placement, "int")
            throw OSError(A_LastError, "Save Super Hotkey placement")
        monitor := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        info := Buffer(40, 0) ; MONITORINFO, including full display bounds
        NumPut("uint", info.Size, info)
        if !monitor || !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", info, "int")
            throw OSError(A_LastError, "Find Super Hotkey monitor")

        window.Restore()
        style := WinGetStyle(target)
        exStyle := WinGetExStyle(target)
        this.placements[hwnd] := {placement: placement, style: style, exStyle: exStyle}
        WinSetStyle((style & ~0xC40000) | 0x80000000, target) ; popup, no caption/resize border
        WinSetExStyle(exStyle & ~0x300, target) ; no client/window edge
        left := NumGet(info, 4, "int")
        top := NumGet(info, 8, "int")
        if !DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
            "int", left, "int", top,
            "int", NumGet(info, 12, "int") - left,
            "int", NumGet(info, 16, "int") - top,
            "uint", 0x34, "int") ; FRAMECHANGED | NOACTIVATE | NOZORDER
            throw OSError(A_LastError, "Enter Super Hotkey fullscreen")
        SuiteSizeGrip.Move(window)
    }
}

class SuiteSizeGrip {
    static handles := Map()

    static Attach(window) {
        ; A native scroll-bar sizing grip gives the corner a familiar diagonal
        ; indicator and lets Windows handle dragging the parent window.
        dimension := DllCall("GetSystemMetrics", "int", 2, "int")
        height := DllCall("GetSystemMetrics", "int", 3, "int")
        grip := DllCall("CreateWindowExW", "uint", 0, "str", "SCROLLBAR",
            "ptr", 0, "uint", 0x50000010, ; WS_CHILD | WS_VISIBLE | SBS_SIZEGRIP
            "int", 0, "int", 0, "int", dimension, "int", height,
            "ptr", window.Hwnd, "ptr", 0,
            "ptr", DllCall("GetModuleHandleW", "ptr", 0, "ptr"),
            "ptr", 0, "ptr")
        if !grip
            throw OSError(A_LastError, "Create Super Hotkey sizing grip")
        this.handles[window.Hwnd] := grip
    }

    static Move(window, minMax := 0) {
        if !this.handles.Has(window.Hwnd)
            return
        grip := this.handles[window.Hwnd]
        if !DllCall("IsWindow", "ptr", grip, "int") {
            this.handles.Delete(window.Hwnd)
            return
        }
        if minMax = 1 || SuiteFullscreen.IsFullscreen(window) {
            DllCall("ShowWindow", "ptr", grip, "int", 0, "int")
            return
        }
        rect := Buffer(16, 0)
        if !DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", rect, "int")
            return
        width := DllCall("GetSystemMetrics", "int", 2, "int")
        height := DllCall("GetSystemMetrics", "int", 3, "int")
        DllCall("SetWindowPos", "ptr", grip, "ptr", 0,
            "int", Max(0, NumGet(rect, 8, "int") - width),
            "int", Max(0, NumGet(rect, 12, "int") - height),
            "int", width, "int", height,
            "uint", 0x54, "int") ; NOZORDER | NOACTIVATE | SHOWWINDOW
    }

    static Detach(window) {
        if this.handles.Has(window.Hwnd)
            this.handles.Delete(window.Hwnd)
        ; Parent GUI destruction also destroys its child resizing grip.
    }
}

class SuiteIcons {
    static handles := []
    static path := A_ScriptDir "\assets\super-hotkey.ico"

    static Initialize() {
        if this.handles.Length || !FileExist(this.path)
            return
        for size in [16, 32] {
            handle := DllCall("LoadImageW", "ptr", 0, "str", this.path, "uint", 1,
                "int", size, "int", size, "uint", 0x10, "ptr")
            this.handles.Push(handle)
        }
        ; The same two HICONs live until process exit; individual windows do not own them.
    }

    static Apply(window) {
        this.Initialize()
        for index, handle in this.handles
            if handle
                SendMessage(0x0080, index - 1, handle, , window.Hwnd)
    }
}

class SuiteWindowOwnership {
    static marker := "nroj.SuperHotkeyWorld.ManualLayout"
    static windows := Map()

    static ProcessId(hwnd) {
        processId := 0
        if hwnd
            DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &processId, "uint")
        return processId
    }

    static IsSuiteSurface(hwnd) {
        return hwnd && (this.ProcessId(hwnd) = DllCall("GetCurrentProcessId", "uint")
            || DllCall("GetPropW", "ptr", hwnd, "str", "nroj.Scratchpad.Notepad3Window", "ptr"))
    }

    static IsManual(hwnd) {
        if !this.windows.Has(hwnd)
            return false
        matches := this.ProcessId(hwnd) = this.windows[hwnd]
            && DllCall("GetPropW", "ptr", hwnd, "str", this.marker, "ptr") = A_ScriptHwnd
        if !matches
            this.windows.Delete(hwnd)
        return matches
    }

    static Claim(hwnd) {
        if IsObject(SuiteState.App) && SuiteState.App.stopping
            return
        processId := this.ProcessId(hwnd)
        if !processId
            return
        ; A per-window property prevents a recycled HWND (even in the same process)
        ; from inheriting manual ownership after the original window was destroyed.
        if !DllCall("SetPropW", "ptr", hwnd, "str", this.marker, "ptr", A_ScriptHwnd, "int")
            throw OSError(A_LastError, "Mark manual window layout")
        this.windows[hwnd] := processId
        if !IsObject(SuiteState.App) || !SuiteState.App.cascadeStarted
            return
        global pending_windows, placement_reservations, handled_windows
        monitor := GetManagedCascadeMonitor(hwnd)
        CancelPlacementStabilization(hwnd)
        if pending_windows.Has(hwnd)
            pending_windows.Delete(hwnd)
        if placement_reservations.Has(hwnd)
            placement_reservations.Delete(hwnd)
        RemoveCascadeWindowFromHistory(hwnd)
        RemoveWindowFromMinimizeState(hwnd)
        handled_windows[hwnd] := true
        if monitor
            QueueCascadeCompaction(monitor)
        QueueFocusCornerUpdate()
    }

    static Release(hwnd, forAdoption := true) {
        if !this.IsManual(hwnd)
            return false
        if forAdoption {
            global WW_borderless_windows, WW_horizontal_stretch_windows, WW_vertical_stretch_windows
            global WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements
            ; Restore the native frame before handing geometry to the cascade.
            ; A refused restoration leaves manual ownership and recovery state intact.
            if WW_borderless_windows.Has(hwnd)
                WW_RunWindowCommand(WW_RestoreBorderlessWindow, hwnd, false, true)
            for states in [WW_horizontal_stretch_windows, WW_vertical_stretch_windows,
                WW_layout_cycle_windows, WW_center_tile_next_sides, WW_normal_window_placements]
                if states.Has(hwnd)
                    states.Delete(hwnd)
        }
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
    return hwnd && !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.Scratchpad.Notepad3Window", "ptr")
}

#HotIf SuiteFullscreen.Active()
F11::{
    SuiteFullscreen.Toggle()
    KeyWait "F11" ; ignore key repeat while held
}
#HotIf
