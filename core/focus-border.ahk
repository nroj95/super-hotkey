; Shared, module-independent focus border. Windows-accent outline identical to
; the former Wonder Windows highlight (12 px, 2 px overlap, 1500 ms), hidden
; early when its window moves. It stays inside its display's work area, so a
; window at an edge shows only the overlap there, and nothing covers another
; display or a taskbar. A maximized or fullscreen window has no side with
; room, so its outline is drawn inside it instead, which tells displays with
; a big window each apart.
class SuiteFocusBorder {
    static guis := []
    static owner := ""
    static timerCallback := 0
    static watchCallback := 0
    static target := 0     ; the outlined window
    static outlined := 0   ; its visible bounds when outlined: [x, y, width, height]
    static durationMs := 1500
    static watchMs := 50
    static thickness := 12
    static overlap := 2

    static Show(hwnd, owner := "") {
        ; Expiry cannot resume halfway through updating a reused outline.
        previousCritical := Critical("On")
        try return this._Show(hwnd, owner)
        finally Critical(previousCritical)
    }

    static _Show(hwnd, owner) {
        if this.timerCallback
            try SetTimer(this.timerCallback, 0)
        if !hwnd || !WinExist("ahk_id " hwnd) {
            this.Hide()
            return false
        }

        if !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
            || width <= this.thickness * 2 || height <= this.thickness * 2 {
            this.Hide()
            return false
        }

        color := SuiteAccentColor()
        inside := this.FillsDisplay(hwnd, x, y, width, height)
        rects := this.Rects(x, y, width, height, inside)

        try {
            ; Reuse these same four non-activating windows for successive outlines.
            if this.guis.Length != 4 {
                this.Hide("", true)
                Loop 4 {
                    borderGui := SuiteGui(
                        "+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000"
                    )
                    this.guis.Push(borderGui)
                }
            }
            ; Keep the outline inside the work area of the window's display: a
            ; window touching a display edge must not paint a strip onto the
            ; neighbouring display, nor onto a taskbar or docked bar. Drawn
            ; inside a fullscreen window, it may cover the window's whole display.
            bounds := inside ? this.DisplayBounds(hwnd) : this.WorkAreaBounds(hwnd)
            for index, rect in rects {
                borderGui := this.guis[index]
                if !(rect := this.Clip(rect, bounds)) {
                    borderGui.Hide()
                    continue
                }
                if borderGui.BackColor != color
                    borderGui.BackColor := color
                borderGui.Show("NA x" rect[1] " y" rect[2] " w" rect[3] " h" rect[4])
            }
        }
        catch Error as err {
            this.Hide("", true)
            if IsObject(SuiteState.Log)
                SuiteState.Log.Error("Core / focus border", err)
            return false
        }

        this.owner := owner
        this.target := hwnd
        this.outlined := [x, y, width, height]
        if !this.timerCallback
            this.timerCallback := ObjBindMethod(this, "Expire")
        if !this.watchCallback
            this.watchCallback := ObjBindMethod(this, "Watch")
        SetTimer(this.timerCallback, -this.durationMs)
        SetTimer(this.watchCallback, this.watchMs)
        return true
    }

    ; The outline marks where a window is. Once it is dragged, moved by a
    ; hotkey, resized, minimized or closed, the outline goes at once.
    static Watch(*) {
        hwnd := this.target
        if !hwnd
            return this.Hide()
        if !WinExist("ahk_id " hwnd) || DllCall("IsIconic", "ptr", hwnd, "int")
            || !GetVisibleWindowBounds(hwnd, &x, &y, &width, &height)
            || this.Moved(this.outlined, [x, y, width, height])
            this.Hide()
    }

    static Moved(outlined, bounds) {
        for index, value in bounds
            if !IsObject(outlined) || outlined[index] != value
                return true
        return false
    }

    ; An owner-specific cleanup may not remove another module's border.
    static Hide(expectedOwner := "", destroy := false) {
        previousCritical := Critical("On")
        try return this._Hide(expectedOwner, destroy)
        finally Critical(previousCritical)
    }

    static _Hide(expectedOwner, destroy) {
        if !this.CanHide(expectedOwner, this.owner)
            return false
        if this.timerCallback
            try SetTimer(this.timerCallback, 0)
        if this.watchCallback
            try SetTimer(this.watchCallback, 0)
        this.target := 0, this.outlined := 0
        for borderGui in this.guis {
            if destroy {
                try borderGui.Destroy()
            } else {
                try borderGui.Hide()
            }
        }
        if destroy
            this.guis := []
        this.owner := ""
        return true
    }

    ; The work area of the window's display, the display without its taskbars
    ; and docked bars, as [left, top, right, bottom] in physical pixels, or 0.
    static WorkAreaBounds(hwnd) {
        try return CallWithDpiContext(-3, MonitorRects, WindowMonitor(hwnd)).work
        catch
            return 0
    }

    ; The window's whole display, taskbars included, the same way, or 0.
    static DisplayBounds(hwnd) {
        try return CallWithDpiContext(-3, MonitorRects, WindowMonitor(hwnd)).monitor
        catch
            return 0
    }

    ; Maximized, or covering its whole display as a fullscreen window does.
    static FillsDisplay(hwnd, x, y, width, height) {
        try {
            if WinGetMinMax(hwnd) = 1
                return true
            display := this.DisplayBounds(hwnd)
            return IsObject(display) && x <= display[1] && y <= display[2]
                && x + width >= display[3] && y + height >= display[4]
        }
        return false
    }

    ; The four sides of an outline around [x, y, width, height]: mostly
    ; outside the window, overlapping its edge, or wholly inside it.
    static Rects(x, y, width, height, inside := false) {
        thickness := this.thickness
        if inside
            return [[x, y, width, thickness], [x, y + height - thickness, width, thickness],
                [x, y + thickness, thickness, height - thickness * 2],
                [x + width - thickness, y + thickness, thickness, height - thickness * 2]]
        outside := thickness - this.overlap
        return [[x - outside, y - outside, width + outside * 2, thickness],
            [x - outside, y + height - this.overlap, width + outside * 2, thickness],
            [x - outside, y, thickness, height],
            [x + width - this.overlap, y, thickness, height]]
    }

    ; The part of [x, y, width, height] inside bounds, or 0 when none remains.
    static Clip(rect, bounds) {
        if !bounds
            return rect
        left := Max(rect[1], bounds[1]), top := Max(rect[2], bounds[2])
        right := Min(rect[1] + rect[3], bounds[3]), bottom := Min(rect[2] + rect[4], bounds[4])
        return right > left && bottom > top ? [left, top, right - left, bottom - top] : 0
    }

    static CanHide(expectedOwner, activeOwner) {
        return expectedOwner = "" || expectedOwner = activeOwner
    }

    static Expire(*) => this.Hide()
}
