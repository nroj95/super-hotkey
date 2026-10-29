; Shared GUI building blocks: one icon, centered opening, a native size grip,
; F11 fullscreen for suite windows, flat buttons and batched layouts.
SuiteGui(options := "", title := "") {
    window := Gui(options, title)
    SuiteIcons.Apply(window)
    ; Mark before showing: the window-show hook must never adopt our own dialogs.
    DllCall("SetPropW", "ptr", window.Hwnd, "str", "nroj.SuperHotkey.CascadeIgnore", "ptr", 1, "int")
    ; Only actual resizable windows need the native sizing grip.
    ; Cascade focus tabs, DPI probes and other overlays are not resizable.
    if DllCall("GetWindowLongPtrW", "ptr", window.Hwnd, "int", -16, "ptr") & 0x00040000 ; WS_THICKFRAME
        SuiteSizeGrip.Attach(window)
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
    SuiteSizeGrip.Move(window)
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
            && IsObject(SuiteState.App.manager.editor.recording)
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
        bounds := MonitorRects(WindowMonitor(hwnd)).monitor

        window.Restore()
        style := WinGetStyle(target)
        exStyle := WinGetExStyle(target)
        this.placements[hwnd] := {placement: placement, style: style, exStyle: exStyle}
        WinSetStyle((style & ~0xC40000) | 0x80000000, target) ; popup, no caption/resize border
        WinSetExStyle(exStyle & ~0x300, target) ; no client/window edge
        if !DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0,
            "int", bounds[1], "int", bounds[2],
            "int", bounds[3] - bounds[1],
            "int", bounds[4] - bounds[2],
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

; A Click handler that runs action in its own thread once the Click event has
; returned. AutoHotkey 2.0.26 corrupted pages built inside that event, so
; buttons that open or swap windows must not do it there.
SuiteClickAction(action) => (*) => SetTimer(action, -1)

; Flat, square push buttons drawn through NM_CUSTOMDRAW. kind is "warning",
; "reset" or anything else for the normal style. Returns CDRF_SKIPDEFAULT
; when it painted, or "" to let Windows draw this stage.
SuitePaintButton(lParam, kind) {
    if NumGet(lParam, 16, "int") != -12 ; NM_CUSTOMDRAW
        || NumGet(lParam, 24, "uint") != 1 ; CDDS_PREPAINT
        return ""
    hwnd := NumGet(lParam, 0, "ptr")
    hdc := NumGet(lParam, 32, "ptr")
    state := NumGet(lParam, 64, "uint")
    pressed := !!(state & 0x1) ; CDIS_SELECTED
    hovered := !!(state & 0x40) ; CDIS_HOT
    enabled := !!DllCall("IsWindowEnabled", "ptr", hwnd, "int")
    if kind = "warning" {
        fillColor := pressed ? 0xA7D8FF : hovered ? 0xBCE5FF : 0xD9F0FF
        frameColor := 0x2D8EB9
        textColor := 0x234566
    } else if kind = "reset" && !enabled {
        fillColor := 0xF5F5F5
        frameColor := 0xCDCDCD
        textColor := 0xB0B0B0
    } else if kind = "reset" {
        fillColor := pressed ? 0xDEDEDE : hovered ? 0xEEEEEE : 0xFFFFFF
        frameColor := 0x909090
        textColor := 0x303030
    } else {
        fillColor := pressed ? 0xE5E5E5 : hovered ? 0xF5F5F5 : 0xFFFFFF
        frameColor := 0xC9C9C9
        textColor := enabled ? 0x202020 : 0x999999
    }

    fillBrush := DllCall("CreateSolidBrush", "uint", fillColor, "ptr")
    frameBrush := DllCall("CreateSolidBrush", "uint", frameColor, "ptr")
    try {
        if !fillBrush || !frameBrush
            return ""
        bounds := Buffer(16, 0)
        DllCall("RtlMoveMemory", "ptr", bounds, "ptr", lParam + 40, "uptr", 16)
        DllCall("FillRect", "ptr", hdc, "ptr", bounds, "ptr", fillBrush, "int")
        DllCall("FrameRect", "ptr", hdc, "ptr", bounds, "ptr", frameBrush, "int")
        DllCall("InflateRect", "ptr", bounds, "int", -5, "int", -3, "int")
        length := DllCall("GetWindowTextLengthW", "ptr", hwnd, "int")
        label := Buffer((length + 1) * 2, 0)
        DllCall("GetWindowTextW", "ptr", hwnd, "ptr", label, "int", length + 1, "int")
        font := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x31, "uptr", 0, "ptr", 0, "ptr") ; WM_GETFONT
        originalFont := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
        originalMode := DllCall("SetBkMode", "ptr", hdc, "int", 1, "int")
        originalText := DllCall("SetTextColor", "ptr", hdc, "uint", textColor, "uint")
        try DllCall("DrawTextW", "ptr", hdc, "ptr", label, "int", -1,
            "ptr", bounds, "uint", 0x8825, "int") ; centered, single line, no prefix
        finally {
            DllCall("SetTextColor", "ptr", hdc, "uint", originalText)
            DllCall("SetBkMode", "ptr", hdc, "int", originalMode)
            if originalFont
                DllCall("SelectObject", "ptr", hdc, "ptr", originalFont)
        }
        if state & 0x10 ; CDIS_FOCUS
            DllCall("DrawFocusRect", "ptr", hdc, "ptr", bounds, "int")
        return 4 ; CDRF_SKIPDEFAULT
    }
    finally {
        if fillBrush
            DllCall("DeleteObject", "ptr", fillBrush)
        if frameBrush
            DllCall("DeleteObject", "ptr", frameBrush)
    }
}

; Moves controls given in DPI-independent GUI units, as one batch so the
; window never paints a half-moved layout. positions: [{control, x, y, w, h}].
SuiteMoveControls(window, positions, redrawButtons := false) {
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
    ; Batched moves can leave stale fragments on owner-drawn buttons.
    if redrawButtons
        for item in positions
            if item.control.Type = "Button"
                DllCall("RedrawWindow", "ptr", item.control.Hwnd, "ptr", 0,
                    "ptr", 0, "uint", 0x105, "int") ; RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW
}

; Large, click-through notices centered on the working display, so keyboard
; users see them wherever the pointer rests, even over fullscreen windows.
; Each slot shows one message; a newer message replaces it.
class SuiteNotice {
    static order := ["layer", "status"] ; top to bottom when both show
    static notices := Map()

    ; Shows text in slot until Hide, or for durationMs when given.
    static Show(slot, text, durationMs := 0) {
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
        MonitorGetWorkArea(SuiteWorkingMonitor.Get(), &left, &top, &right, &bottom)
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

#HotIf SuiteFullscreen.Active()
F11::{
    SuiteFullscreen.Toggle()
    KeyWait "F11" ; ignore key repeat while held
}
#HotIf
