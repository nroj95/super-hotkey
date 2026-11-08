; Cascade Kingdom's mouse keys: while one is held, the mouse handles windows
; instead of their contents. Caps and Pause work through their Secret Layers
; layers; Win needs no Secret Layers. None of them does anything else with the
; mouse, so all three always work, without a setting.
;
; Click contract:
; - a left press on an application window focuses it; the app never sees it;
; - a second left press on the same window within the Windows double-click
;   time adds it to its display's cascade, exactly as Caps + Insert does, or
;   takes a member out, back where it was, as Caps + Shift + Insert does;
; - every other press, the wheel included, is swallowed, so a drag does
;   nothing until the key comes up;
; - every claimed press keeps its release, even after the key comes up;
; - the taskbar, the desktop, Start, focus tabs and suite windows keep their
;   clicks;
; - with Caps or Pause, a claimed press uses the layer, so releasing the key
;   is never a tap; with Win, even alongside a layer, only the Win hotkey (#)
;   takes the press, for which AutoHotkey sends the menu mask key as Win comes
;   up, after the key's auto-repeat, so releasing Win never opens Start.

MouseKeyWinHeld() => GetKeyState("LWin", "P") || GetKeyState("RWin", "P")

; The Caps or Pause layer is held.
MouseKeyLayerHeld()
{
    manager := SuiteState.App.manager
    return IsObject(manager) && (manager.LayerHeld("caps") || manager.LayerHeld("pause"))
}

; The application window under the pointer, or 0 over shell surfaces and
; suite windows.
MouseKeyTarget()
{
    MouseGetPosPixels(, , &hover_hwnd)
    hwnd := DllCall("GetAncestor", "ptr", hover_hwnd, "uint", 2, "ptr") ; GA_ROOT
    if !hwnd || IsShellSurfaceWindow(hwnd) || IsIgnoredByCascade(hwnd, true)
        return 0
    try return IsShellHost(WinGetProcessName(hwnd)) ? 0 : hwnd
    return 0
}

; A press is ours while a mouse key is held over an application window.
; button is "" for the wheel, which has no release; win says whether this is
; the Win hotkey, which alone claims presses while Win is held.
CanClaimMouseKeyClick(button, win)
{
    ; A new press means any claimed release of this button already happened.
    if button != "" && CascadeState.mouseKeyButtons.Has(button)
        CascadeState.mouseKeyButtons.Delete(button)
    held := win ? MouseKeyWinHeld() : !MouseKeyWinHeld() && MouseKeyLayerHeld()
    claim := held && IsCascadeEnabled() && MouseKeyTarget()
    ; Own the release from here, not from the press handler: a quick release
    ; is judged before that queued handler runs, and a bare release still
    ; clicks some buttons, such as File Explorer's minimize, maximize and close.
    if claim && button != ""
        CascadeState.mouseKeyButtons[button] := true
    return claim
}

BeginMouseKeyClick(manager, button)
{
    manager.UseLayer("caps"), manager.UseLayer("pause") ; only a held layer counts
    if button != "LButton" || !(hwnd := MouseKeyTarget())
        return
    now := A_TickCount
    last := CascadeState.mouseKeyLast
    double := IsObject(last) && last.hwnd = hwnd
        && ((now - last.tick) & 0xFFFFFFFF) <= DllCall("GetDoubleClickTime", "uint")
    CascadeState.mouseKeyLast := double ? 0 : {hwnd: hwnd, tick: now}
    SuiteState.App.QueueInput(RunMouseKeyClick, hwnd, double)
}

RunMouseKeyClick(hwnd, double)
{
    ; Both commands revalidate the foreground window, so focus comes first.
    if ActivateWindow(hwnd) && double
        QueueCascadeCommand(GetLiveCascadeMonitor(hwnd) ? "release" : "adopt", hwnd)
}

HasMouseKeyClick(button) => CascadeState.mouseKeyButtons.Has(button)

FinishMouseKeyClick(button)
{
    if CascadeState.mouseKeyButtons.Has(button)
        CascadeState.mouseKeyButtons.Delete(button)
}

ObserveMouseKeyClicks(manager)
{
    ; The release has no Win: Win may come up before the button.
    for button in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
        for win in [false, true]
            manager.Observe((win ? "*#" : "*") button, CanClaimMouseKeyClick.Bind(button, win),
                BeginMouseKeyClick.Bind(manager, button))
        manager.Observe("*" button " Up", HasMouseKeyClick.Bind(button), FinishMouseKeyClick.Bind(button), true)
    }
    for wheel in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
        for win in [false, true]
            manager.Observe((win ? "*#" : "*") wheel, CanClaimMouseKeyClick.Bind("", win),
                BeginMouseKeyClick.Bind(manager, ""))
}
