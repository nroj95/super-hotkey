; Cascade Kingdom Caps clicks: while the Caps layer is held, the mouse handles
; windows instead of their contents. With Use Win ticked in Settings, a held
; Win key does this instead, and the Caps layer leaves the mouse alone; it needs
; no Secret Layers.
;
; Click contract:
; - a left press on an application window focuses it; the app never sees it;
; - a second left press on the same window within the Windows double-click
;   time adds it to its display's cascade, exactly as Caps + Insert does;
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
