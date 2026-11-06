; Cascade Kingdom Caps clicks: while the Caps layer is held, the mouse handles
; windows instead of their contents. With Use Win ticked in Settings, a held
; Win key does this instead, and the Caps layer leaves the mouse alone; it needs
; no Secret Layers.
;
; Click contract:
; - a left press on an application window focuses it; the app never sees it;
; - a second left press on the same window within the Windows double-click
;   time adds it to its display's cascade, exactly as Caps + Insert does;
; - a left press that moves past the Windows drag distance drags the window
;   live, restoring a maximized one first; Windows' own move loop needs the
;   button down, which the app would see as a click, so this small loop moves
;   it instead and hands the drop to window-drag.ahk: guides, snapping,
;   releasing from a slot and Escape work as in a title-bar drag;
; - right, middle and side buttons and the wheel are swallowed;
; - every claimed press keeps its release, even after Caps comes up;
; - the taskbar, the desktop, Start, focus tabs and suite windows keep their
;   clicks;
; - a claimed press uses the layer, so releasing Caps is never a tap; with
;   Win, the press goes to a Win hotkey (#), for which AutoHotkey sends the
;   menu mask key as Win comes up, after the key's auto-repeat, so releasing
;   Win never opens Start.

; The chosen key is held: Win when Settings says so, otherwise the Caps layer.
CapsClickKeyHeld(manager)
{
    if CascadeState.useWin
        return GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    return manager.LayerHeld("caps")
}

; The application window under the pointer, or 0 over shell surfaces and
; suite windows.
CapsClickTarget()
{
    MouseGetPosPixels(, , &hover_hwnd)
    hwnd := DllCall("GetAncestor", "ptr", hover_hwnd, "uint", 2, "ptr") ; GA_ROOT
    if !hwnd || IsShellSurfaceWindow(hwnd) || IsIgnoredByCascade(hwnd, true)
        return 0
    try return IsShellHost(WinGetProcessName(hwnd)) ? 0 : hwnd
    return 0
}

; A press is ours while the chosen key is held over an application window.
; button is "" for the wheel, which has no release; win says whether this is
; the Win hotkey, which alone claims presses while Win is chosen.
CanClaimCapsClick(manager, button, win)
{
    ; A new press means any claimed release of this button already happened.
    if button != "" && CascadeState.capsClickButtons.Has(button)
        CascadeState.capsClickButtons.Delete(button)
    return win = CascadeState.useWin && IsCascadeEnabled() && CapsClickKeyHeld(manager) && CapsClickTarget()
}

BeginCapsClick(manager, button)
{
    if !CascadeState.useWin
        manager.UseLayer("caps")
    if button = ""
        return
    CascadeState.capsClickButtons[button] := true
    if button != "LButton" || !(hwnd := CapsClickTarget())
        return
    now := A_TickCount
    last := CascadeState.capsClickLast
    double := IsObject(last) && last.hwnd = hwnd
        && ((now - last.tick) & 0xFFFFFFFF) <= DllCall("GetDoubleClickTime", "uint")
    CascadeState.capsClickLast := double ? 0 : {hwnd: hwnd, tick: now}
    SuiteState.App.QueueInput(RunCapsClick, hwnd, double)

    ; Snapshot on press, as title-bar drags do; a press near an edge still
    ; moves the window rather than resizing it.
    StopCapsDrag()
    MouseGetPosPixels(&x, &y)
    press := GetCascadeMousePressSnapshot(hwnd)
    if IsObject(press)
        press.resize := false
    CascadeState.capsDrag := {hwnd: hwnd, x: x, y: y, press: press, moving: false, cancelled: false}
    SetTimer(CapsDragTick, CascadeState.capsDragMs)
}

RunCapsClick(hwnd, double)
{
    ; Adoption revalidates the foreground window, so focus comes first.
    if ActivateWindow(hwnd) && double
        QueueCascadeCommand("adopt", hwnd)
}

HasCapsClick(button) => CascadeState.capsClickButtons.Has(button)

FinishCapsClick(button)
{
    if CascadeState.capsClickButtons.Has(button)
        CascadeState.capsClickButtons.Delete(button)
    if button = "LButton"
        FinishCapsDrag()
}

; =============================================================================
; dragging
; =============================================================================

; Runs only while a claimed left press is held: AutoHotkey has no pointer-move
; event, and the move loop it replaces follows the pointer the same way.
CapsDragTick()
{
    drag := CascadeState.capsDrag
    if !IsObject(drag) || !GetKeyState("LButton", "P") {
        FinishCapsDrag() ; recovers a missed release
        return
    }
    if drag.cancelled
        return
    MouseGetPosPixels(&x, &y)
    if !drag.moving {
        if Abs(x - drag.x) <= SysGet(68) && Abs(y - drag.y) <= SysGet(69) ; SM_CXDRAG, SM_CYDRAG
            return
        if !StartCapsDrag(drag, x, y) {
            StopCapsDrag()
            return
        }
    }
    try {
        ; Escape cancels a cascade drag; like Windows, put the window back.
        if IsObject(drag.press) && drag.press.cancelled {
            drag.cancelled := true
            if drag.press.minmax = 1
                WinMaximize(drag.hwnd)
            else
                PhysicalDllCall("SetWindowPos", "ptr", drag.hwnd, "ptr", 0, "int", drag.start_x,
                    "int", drag.start_y, "int", 0, "int", 0, "uint", 0x15)
            return
        }
        ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
        PhysicalDllCall("SetWindowPos", "ptr", drag.hwnd, "ptr", 0, "int", drag.window_x + x - drag.x,
            "int", drag.window_y + y - drag.y, "int", 0, "int", 0, "uint", 0x15)
    }
    catch
        StopCapsDrag()
}

StartCapsDrag(drag, x, y)
{
    ; A drag is no first click of a double-click.
    CascadeState.capsClickLast := 0
    try {
        WinGetPosPixels(&window_x, &window_y, &width, , drag.hwnd)
        drag.start_x := window_x, drag.start_y := window_y
        if WinGetMinMax(drag.hwnd) = 1 {
            ; Restored under the pointer, at the same share of its width, as
            ; Windows does for a maximized title-bar drag.
            share := (x - window_x) / width, offset_y := y - window_y
            WinRestore(drag.hwnd)
            WinGetPosPixels(, , &width, &height, drag.hwnd)
            window_x := Round(x - share * width), window_y := y - Min(offset_y, height // 2)
            drag.x := x, drag.y := y
        }
        drag.window_x := window_x, drag.window_y := window_y
    }
    catch
        return false
    drag.moving := true
    ; Windows that cascades can take get guides, snapping and releasing.
    if IsObject(drag.press) {
        CascadeState.mousePress := drag.press
        BeginCascadeWindowDrag(drag.hwnd, A_TickCount)
    }
    return true
}

; The button came up: a moved window drops as at the end of a title-bar drag.
FinishCapsDrag()
{
    drag := CascadeState.capsDrag
    StopCapsDrag()
    if IsObject(drag) && drag.moving
        CaptureCascadeMouseRelease()
}

StopCapsDrag()
{
    SetTimer(CapsDragTick, 0)
    CascadeState.capsDrag := 0
}

ObserveCapsClicks(manager)
{
    ; The release has no Win: Win may come up before the button.
    for button in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
        for win in [false, true]
            manager.Observe((win ? "*#" : "*") button, CanClaimCapsClick.Bind(manager, button, win),
                BeginCapsClick.Bind(manager, button))
        manager.Observe("*" button " Up", HasCapsClick.Bind(button), FinishCapsClick.Bind(button), true)
    }
    for wheel in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
        for win in [false, true]
            manager.Observe((win ? "*#" : "*") wheel, CanClaimCapsClick.Bind(manager, "", win),
                BeginCapsClick.Bind(manager, ""))
}
