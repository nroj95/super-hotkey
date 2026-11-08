; =============================================================================
; Click to focus: while the chosen key is held, the mouse handles windows
; instead of their contents. The tray's Click to focus menu picks Caps, Pause
; or Win, or turns it off; Caps and Pause work through their Secret Layers
; layers, Win needs no layer. No hold key does anything else with the mouse,
; so the chosen one works whichever modules are on.
;
; Click contract:
; - a left press on an application window focuses it; the app never sees it;
; - a second left press on the same window within the Windows double-click
;   time goes to the OnDoubleClick handlers, such as Cascade Kingdom adding
;   the window to its cascade or taking it out;
; - every other press, the wheel included, is swallowed, so a drag does
;   nothing until the key comes up;
; - every claimed press keeps its release, even after the key comes up;
; - the taskbar, the desktop, Start and suite windows, focus tabs included,
;   keep their clicks;
; - with Caps or Pause, a claimed press uses the layer, so releasing the key
;   is never a tap; with Win, only the Win hotkey (#) takes the press, for
;   which AutoHotkey sends the menu mask key as Win comes up, after the key's
;   auto-repeat, so releasing Win never opens Start.
; =============================================================================
class SuiteClickFocus {
    static Keys := ["caps", "pause", "win", "off"]
    static key := "caps"            ; set from SuiteSettings before Start
    static manager := 0
    static buttons := Map()         ; buttons whose claimed press still owns its release
    static last := 0                ; the last claimed left press, for double-clicks
    static doubleClickHandlers := []

    static Start(manager) {
        this.manager := manager
        ; The release has no Win: Win may come up before the button.
        for button in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
            for win in [false, true]
                manager.Observe((win ? "*#" : "*") button, ObjBindMethod(this, "CanClaim", button, win),
                    ObjBindMethod(this, "Begin", button))
            manager.Observe("*" button " Up", ObjBindMethod(this, "Owns", button),
                ObjBindMethod(this, "Finish", button), true)
        }
        for wheel in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
            for win in [false, true]
                manager.Observe((win ? "*#" : "*") wheel, ObjBindMethod(this, "CanClaim", "", win),
                    ObjBindMethod(this, "Begin", ""))
    }

    ; callback(hwnd) runs after the window has focus, from the input queue.
    static OnDoubleClick(callback) => this.doubleClickHandlers.Push(callback)

    static OffDoubleClick(callback) {
        for index, handler in this.doubleClickHandlers
            if handler = callback {
                this.doubleClickHandlers.RemoveAt(index)
                return
            }
    }

    static Cancel() => this.last := 0

    static WinHeld() => GetKeyState("LWin", "P") || GetKeyState("RWin", "P")

    ; The chosen key is held. win says whether this is the Win hotkey, which
    ; alone sees presses while Win is held.
    static Held(win) {
        if this.key = "win"
            return win && this.WinHeld()
        return !win && !this.WinHeld() && (this.key = "caps" || this.key = "pause")
            && IsObject(this.manager) && this.manager.LayerHeld(this.key)
    }

    ; The application window under the pointer, or 0 over shell surfaces and
    ; suite windows.
    static Target() {
        MouseGetPosPixels(, , &hover_hwnd)
        hwnd := DllCall("GetAncestor", "ptr", hover_hwnd, "uint", 2, "ptr") ; GA_ROOT
        if !hwnd || IsShellSurfaceWindow(hwnd)
            || DllCall("GetPropW", "ptr", hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr")
            return 0
        try return IsShellHost(WinGetProcessName(hwnd)) ? 0 : hwnd
        return 0
    }

    ; button is "" for the wheel, which has no release.
    static CanClaim(button, win, *) {
        ; A new press means any claimed release of this button already happened.
        if button != "" && this.buttons.Has(button)
            this.buttons.Delete(button)
        claim := this.Held(win) && this.Target()
        ; Own the release from here, not from the press handler: a quick release
        ; is judged before that queued handler runs, and a bare release still
        ; clicks some buttons, such as File Explorer's minimize, maximize and close.
        if claim && button != ""
            this.buttons[button] := true
        return claim
    }

    static Begin(button, *) {
        this.manager.UseLayer("caps"), this.manager.UseLayer("pause") ; only a held layer counts
        if button != "LButton" || !(hwnd := this.Target())
            return
        now := A_TickCount
        last := this.last
        double := IsObject(last) && last.hwnd = hwnd
            && ((now - last.tick) & 0xFFFFFFFF) <= DllCall("GetDoubleClickTime", "uint")
        this.last := double ? 0 : {hwnd: hwnd, tick: now}
        SuiteState.App.QueueInput(ObjBindMethod(this, "Run"), hwnd, double)
    }

    static Run(hwnd, double) {
        ; Double-click handlers revalidate the foreground window, so focus comes first.
        if !ActivateWindow(hwnd) || !double
            return
        for handler in this.doubleClickHandlers.Clone() {
            try handler.Call(hwnd)
            catch Error as failure
                SuiteState.Log.Error("Core / click to focus", failure)
        }
    }

    static Owns(button, *) => this.buttons.Has(button)

    static Finish(button, *) {
        if this.buttons.Has(button)
            this.buttons.Delete(button)
    }
}
