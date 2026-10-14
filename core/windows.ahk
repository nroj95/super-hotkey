; Shared GUI identity and the small hand-off between manual and automatic layouts.
SuiteGui(options := "", title := "") {
    window := Gui(options, title)
    SuiteIcons.Apply(window)
    ; Mark before showing: the window-show hook must never adopt our own dialogs.
    DllCall("SetPropW", "ptr", window.Hwnd, "str", "nroj.WindowCascade.Ignore", "ptr", 1, "int")
    return window
}

class SuiteIcons {
    static handles := []
    static path := A_ScriptDir "\assets\super-hotkey-world.ico"

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
