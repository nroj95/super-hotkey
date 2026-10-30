; Shared GUI building blocks: one icon, centered opening, batched layouts and
; on-screen notices.
SuiteGui(options := "", title := "") {
    window := Gui(options, title)
    SuiteIcons.Apply(window)
    ; Mark before showing: the window-show hook must never adopt our own dialogs.
    DllCall("SetPropW", "ptr", window.Hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr", 1, "int")
    return window
}

SuiteShowCentered(window, width, height, layoutCallback := 0, fitWorkArea := false) {
    SuiteFocusReturn.Remember()
    ; Size while hidden so the user only sees the correctly centered layout.
    window.Show("Hide w" width " h" height)

    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
        throw OSError(A_LastError, "Center Super Hotkey window")
    outerWidth := NumGet(rect, 8, "int") - NumGet(rect, 0, "int")
    outerHeight := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
    MonitorGetWorkArea(SuiteWorkingMonitor.Get(window.Hwnd), &left, &top, &right, &bottom)
    if fitWorkArea {
        fitted := SuiteFitClientSize(window, width, height, right - left, bottom - top)
        window.Show("Hide w" fitted.width " h" fitted.height)
        if !DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
            throw OSError(A_LastError, "Measure Super Hotkey window")
        outerWidth := NumGet(rect, 8, "int") - NumGet(rect, 0, "int")
        outerHeight := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
    }
    window.GetClientPos(, , &clientWidth, &clientHeight)
    if HasMethod(layoutCallback, "Call")
        layoutCallback.Call(window, 0, clientWidth, clientHeight)
    x := left + Floor((right - left - outerWidth) / 2)
    y := top + Floor((bottom - top - outerHeight) / 2)
    if !DllCall("SetWindowPos", "ptr", window.Hwnd, "ptr", 0,
        "int", x, "int", y, "int", 0, "int", 0, "uint", 0x15, "int")
        throw OSError(A_LastError, "Position Super Hotkey window")
    window.Show()
}

SuiteFitClientSize(window, width, height, workWidth, workHeight) {
    window.GetClientPos(, , &logicalWidth, &logicalHeight)
    client := Buffer(16, 0)
    outer := Buffer(16, 0)
    if !logicalWidth || !logicalHeight
        || !DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", client, "int")
        || !DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", outer, "int")
        throw OSError(A_LastError, "Measure Super Hotkey client area")
    physicalWidth := NumGet(client, 8, "int")
    physicalHeight := NumGet(client, 12, "int")
    borderWidth := NumGet(outer, 8, "int") - NumGet(outer, 0, "int") - physicalWidth
    borderHeight := NumGet(outer, 12, "int") - NumGet(outer, 4, "int") - physicalHeight
    ; Gui dimensions are DPI-scaled; the work area and native frame are not.
    return {width: Max(1, Min(width, Floor((workWidth - borderWidth) * logicalWidth / physicalWidth))),
        height: Max(1, Min(height, Floor((workHeight - borderHeight) * logicalHeight / physicalHeight)))}
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

; The Windows accent color as RRGGBB, read live so theme changes apply at once.
SuiteAccentColor() {
    colorization := 0
    blend := 0
    result := DllCall(
        "dwmapi\DwmGetColorizationColor",
        "uint*", &colorization,
        "int*", &blend,
        "int"
    )
    if result != 0
        return "0078D4"
    return Format("{:02X}{:02X}{:02X}",
        (colorization >> 16) & 0xFF,
        (colorization >> 8) & 0xFF,
        colorization & 0xFF)
}

; A Click handler that runs action in its own thread once the Click event has
; returned. AutoHotkey 2.0.26 corrupted pages built inside that event, so
; buttons that open or swap windows must not do it there.
SuiteClickAction(action) => (*) => SetTimer(action, -1)

; Moves controls given in DPI-independent GUI units, as one batch so the
; window never paints a half-moved layout. positions: [{control, x, y, w, h}].
SuiteMoveControls(window, positions) {
    if !positions.Length
        return
    rect := Buffer(16, 0)
    window.GetClientPos(, , &logicalWidth)
    if !logicalWidth || !DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", rect, "int")
        throw OSError(A_LastError, "Measure Super Hotkey window")
    scale := NumGet(rect, 8, "int") / logicalWidth
    try {
        batch := DllCall("BeginDeferWindowPos", "int", positions.Length, "ptr")
        if !batch
            throw OSError(A_LastError, "BeginDeferWindowPos")
        for item in positions {
            batch := DllCall("DeferWindowPos", "ptr", batch, "ptr", item.control.Hwnd,
                "ptr", 0, "int", Round(item.x * scale), "int", Round(item.y * scale),
                "int", Round(item.w * scale), "int", Round(item.h * scale),
                "uint", 0x114, "ptr") ; SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOCOPYBITS
            if !batch
                throw OSError(A_LastError, "DeferWindowPos")
        }
        if !DllCall("EndDeferWindowPos", "ptr", batch, "int")
            throw OSError(A_LastError, "EndDeferWindowPos")
    }
    catch Error as failure {
        SuiteState.Log.Error("Core / layout", failure)
        for item in positions
            item.control.Move(item.x, item.y, item.w, item.h)
    }
}

; Large, click-through notices centered on the working display, so keyboard
; users see them wherever the pointer rests, even over fullscreen windows.
; Each slot shows one message; a newer message replaces it.
class SuiteNotice {
    static order := ["layer", "status"] ; top to bottom when both show
    static notices := Map()

    ; Shows text in slot until Hide, or for durationMs when given. A monitor
    ; index centers it there instead of on the working display.
    static Show(slot, text, durationMs := 0, monitor := 0) {
        if !this.notices.Has(slot)
            this.notices[slot] := {window: 0, text: "", timer: ObjBindMethod(this, "Hide", slot)}
        notice := this.notices[slot]
        SetTimer(notice.timer, 0)
        if notice.text != text || !notice.window {
            if notice.window
                notice.window.Destroy()
            notice.window := this._Build(text)
            notice.text := text
        }
        notice.window.GetPos(, , &width, &height)
        MonitorGetWorkArea(monitor || SuiteWorkingMonitor.Get(), &left, &top, &right, &bottom)
        ; Centered unless an earlier notice is showing; then directly below it.
        offset := 0
        for name in this.order {
            if name = slot
                break
            if this.notices.Has(name) && (earlier := this.notices[name].window)
                && DllCall("IsWindowVisible", "ptr", earlier.Hwnd, "int") {
                earlier.GetPos(, , , &earlierHeight)
                offset += earlierHeight + 12
            }
        }
        x := left + (right - left - width) // 2
        y := top + (bottom - top - height) // 2 + offset
        ; HWND_TOPMOST raises it above other topmost windows such as fullscreen video.
        DllCall("SetWindowPos", "ptr", notice.window.Hwnd, "ptr", -1, "int", x, "int", y,
            "int", 0, "int", 0, "uint", 0x51, "int") ; SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
        if durationMs
            SetTimer(notice.timer, -durationMs)
    }

    static Hide(slot, *) {
        if !this.notices.Has(slot)
            return
        notice := this.notices[slot]
        SetTimer(notice.timer, 0)
        if notice.window
            notice.window.Hide()
    }

    static Destroy() {
        for slot, notice in this.notices {
            SetTimer(notice.timer, 0)
            if notice.window
                try notice.window.Destroy()
        }
        this.notices := Map()
    }

    static _Build(text) {
        ; WS_EX_LAYERED and WS_EX_TRANSPARENT pass clicks through; never activate.
        window := SuiteGui("+AlwaysOnTop -Caption +ToolWindow +E0x80020 +E0x08000000")
        window.BackColor := "202020"
        window.MarginX := 24
        window.MarginY := 12
        window.SetFont("s16 cFFFFFF", "Segoe UI Semibold")
        window.AddText("Center", text)
        DllCall("SetLayeredWindowAttributes", "ptr", window.Hwnd, "uint", 0, "uchar", 235, "uint", 2)
        ; Windows 11 rounds the corners; older versions ignore the request.
        corners := Buffer(4, 0)
        NumPut("int", 2, corners) ; DWMWCP_ROUND
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd, "uint", 33, ; DWMWA_WINDOW_CORNER_PREFERENCE
            "ptr", corners, "uint", 4)
        window.Show("Hide AutoSize")
        return window
    }
}
