; Visual hints only. The existing native drag watcher owns their lifetime.
class CascadeDropGuides {
    static windows := []
    static signature := ""
    static alpha := 255 ; Fully opaque, matching active focus tabs.

    static Update(drag) {
        global cascade_window_drag, cascade_mirrored
        if !IsCascadeEnabled() || IsCascadeDisplayTransition() || drag.cancelled
            || drag.native_ended || !GetKeyState("LButton", "P") {
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
                if cascade_window_drag != drag || drag.cancelled || drag.native_ended
                    || !IsCascadeEnabled() || IsCascadeDisplayTransition()
                    || !GetKeyState("LButton", "P") {
                    this.Hide()
                    return
                }
                this.Show(target.geometry.slots, GetCascadeMonitorDpi(target.monitor), SuiteAccentColor(),
                    cascade_mirrored ? target.geometry.width : 0)
            }
            finally Critical(previous_critical)
        }
        catch Error as err {
            this.Hide()
            DebugError("Cascade drop guides", err)
        }
    }

    ; Each guide marks a slot's top-left corner, or with mirror_width the
    ; top-right corner of a window that wide there.
    static Show(slots, dpi, color, mirror_width := 0) {
        size := Max(12, ScaleForDpi(20, dpi))
        thickness := Max(2, ScaleForDpi(2, dpi))
        signature := size ":" thickness ":" color ":" mirror_width
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
                    WinSetTransparent(this.alpha, window.Hwnd)
                }
                window := this.windows[index]
                window.BackColor := color
                ; One L-shaped region avoids doubled opacity where two bars meet.
                x := mirror_width ? position[1] + mirror_width - size : position[1]
                ShowPhysicalGui(window, "Hide x" x " y" position[2] " w" size " h" size)
                inner := size - thickness
                region := mirror_width
                    ? "0-0 " size "-0 " size "-" size " " inner "-" size " " inner "-" thickness " 0-" thickness
                    : "0-0 " size "-0 " size "-" thickness " " thickness "-" thickness
                        . " " thickness "-" size " 0-" size
                WinSetRegion(region, window.Hwnd)
                ShowPhysicalGui(window, "NA")
            }
            loop Max(0, this.windows.Length - slots.Length)
                this.windows[slots.Length + A_Index].Hide()
            this.signature := signature
        }
        finally Critical(previous_critical)
    }

    static Hide() {
        if this.signature = "" && !this.windows.Length
            return
        previous_critical := Critical("On")
        try {
            for window in this.windows
                window.Hide()
            this.signature := ""
        }
        finally Critical(previous_critical)
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
