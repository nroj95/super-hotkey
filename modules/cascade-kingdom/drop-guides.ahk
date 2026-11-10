; Visual hints only, for cascade members, the only windows a drop can place.
; The existing native drag watcher owns their lifetime. Guides mark only the
; slots a drop can take, those the cascade can fill, so every guide shown is
; a target and the empty slots past its end show none. Like the focus tabs,
; the slot a drop would take shows in the accent color, opaque, and the
; others in the inactive tab color at its opacity; with none lit, releasing
; takes the window out. The lit guide is also twice as long and at least
; twice as thick, so it stands out among guides only a few pixels apart. Arms
; grow with the cascade window, so guides scale with the display and the
; chosen window size, and strokes are an eighth of their arm, faint ones at
; most a third of a slot step so their gaps stay clear. Long arms never
; cross: slots step diagonally, so each corner's arms run parallel to its
; neighbours'. Focus tabs hide while guides show, since a full-side tab
; lies where the guides of neighbouring slots do, and return after the drop.
class CascadeDropGuides {
    static windows := []
    static signature := ""

    static Update(drag) {
        if !IsCascadeEnabled() || IsCascadeDisplayTransition() || drag.cancelled
            || drag.native_ended || !GetKeyState("LButton", "P") || !drag.source_monitor {
            this.Hide()
            return
        }
        try {
            WinGetPosPixels(&x, &y, &width, &height, drag.hwnd)
            if (x = drag.x && y = drag.y) || CascadeDragIsResize(drag, width, height)
                || !IsCascadeWindow(drag.hwnd, true)
                || !GetVisibleWindowBounds(drag.hwnd, &frame_x, &frame_y, &frame_width, &frame_height) {
                this.Hide()
                return
            }
            ; Canonical slots are valid before the first window joins the cascade.
            target := CascadeDropTarget(frame_x, frame_y, frame_width)
            if !target || !CascadeDisplayAllowed(target.monitor) {
                this.Hide()
                return
            }
            previous_critical := Critical("On")
            try {
                ; Queries may yield to suspension, a new drag or display changes.
                if CascadeState.windowDrag != drag || drag.cancelled || drag.native_ended
                    || !IsCascadeEnabled() || IsCascadeDisplayTransition()
                    || !GetKeyState("LButton", "P") {
                    this.Hide()
                    return
                }
                this.Show(CascadeDropSlots(drag, target), GetCascadeMonitorDpi(target.monitor),
                    CascadeDropLandingSlot(drag, target, frame_y),
                    CascadeState.mirrored ? target.geometry.width : 0, target.geometry.height)
            }
            finally Critical(previous_critical)
        }
        catch Error as err {
            this.Hide()
            DebugError("Cascade drop guides", err)
        }
    }

    ; Each guide marks a slot's top-left corner, or with mirror_width the
    ; top-right corner of a window that wide there. highlight is the slot a
    ; drop would take, or 0. A faint arm is a sixteenth of window_height, the
    ; cascade window's height, and never shorter than 20 px at 96 DPI.
    static Show(slots, dpi, highlight, mirror_width := 0, window_height := 0) {
        size := Max(12, ScaleForDpi(20, dpi), Round(window_height / 16))
        ; An eighth of the arm, capped so parallel faint arms keep clear gaps.
        thickness := Max(3, ScaleForDpi(3, dpi), Min(Round(size / 8), CascadeState.stepY // 3))
        lit_size := size * 2, lit_thickness := Max(thickness * 2, Round(lit_size / 8))
        active := SuiteAccentColor()
        inactive := CascadeState.focusCornerInactiveSlotColor
        signature := size ":" thickness ":" active ":" inactive ":" highlight ":" mirror_width
        for position in slots
            signature .= "|" position[1] "," position[2]
        if signature = this.signature
            return
        previous_critical := Critical("On")
        try {
            for index, position in slots {
                if index > this.windows.Length {
                    window := CreatePhysicalGui(
                        "-Caption -Border -DPIScale +ToolWindow +AlwaysOnTop +E0x08000020",
                        "Cascade Kingdom drop guide")
                    this.windows.Push(window)
                }
                window := this.windows[index]
                lit := index = highlight
                window.BackColor := lit ? active : inactive
                WinSetTransparent(lit ? CascadeState.focusCornerActiveSlotAlpha
                    : CascadeState.focusCornerInactiveSlotAlpha, window.Hwnd)
                arm := lit ? lit_size : size, bar := lit ? lit_thickness : thickness
                ; One L-shaped region avoids doubled opacity where two bars meet.
                x := mirror_width ? position[1] + mirror_width - arm : position[1]
                ShowPhysicalGui(window, "Hide x" x " y" position[2] " w" arm " h" arm)
                inner := arm - bar
                region := mirror_width
                    ? "0-0 " arm "-0 " arm "-" arm " " inner "-" arm " " inner "-" bar " 0-" bar
                    : "0-0 " arm "-0 " arm "-" bar " " bar "-" bar " " bar "-" arm " 0-" arm
                WinSetRegion(region, window.Hwnd)
                ShowPhysicalGui(window, "NA")
            }
            ; The bigger lit guide reaches under its neighbours; keep it on top.
            if highlight && highlight <= slots.Length
                try WinMoveTop("ahk_id " this.windows[highlight].Hwnd)
            loop Max(0, this.windows.Length - slots.Length)
                this.windows[slots.Length + A_Index].Hide()
            this.signature := signature
            for hwnd in CascadeState.focusCornerOverlays
                HideFocusCornerOverlay(hwnd)
        }
        finally Critical(previous_critical)
    }

    static Shown() => this.signature != ""

    static Hide() {
        if this.signature = "" && !this.windows.Length
            return
        shown := this.Shown()
        previous_critical := Critical("On")
        try {
            for window in this.windows
                window.Hide()
            this.signature := ""
        }
        finally Critical(previous_critical)
        if shown
            QueueFocusCornerUpdate()
    }

    static Destroy() {
        previous_critical := Critical("On")
        try {
            for window in this.windows
                window.Destroy()
            this.windows := []
            this.signature := ""
        }
        finally Critical(previous_critical)
    }
}
