; Shared, module-independent focus border. Windows-accent outline identical to
; the former Wonder Windows highlight (12 px, 2 px overlap, 1500 ms).
class SuiteFocusBorder {
    static guis := []
    static owner := ""
    static timerCallback := 0
    static durationMs := 1500
    static thickness := 12
    static overlap := 2

    static Show(hwnd, owner := "") {
        if this.timerCallback
            try SetTimer(this.timerCallback, 0)
        if !hwnd || !WinExist("ahk_id " hwnd) {
            this.Hide()
            return false
        }

        if !this.GetVisibleBounds(hwnd, &x, &y, &width, &height)
            || width <= this.thickness * 2 || height <= this.thickness * 2 {
            this.Hide()
            return false
        }

        thickness := this.thickness
        overlap := this.overlap
        outside := thickness - overlap
        color := this.GetAccentColor()
        rects := [
            [x - outside, y - outside, width + outside * 2, thickness],
            [x - outside, y + height - overlap, width + outside * 2, thickness],
            [x - outside, y, thickness, height],
            [x + width - overlap, y, thickness, height]
        ]

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
            for index, rect in rects {
                borderGui := this.guis[index]
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
        if !this.timerCallback
            this.timerCallback := ObjBindMethod(this, "Expire")
        SetTimer(this.timerCallback, -this.durationMs)
        return true
    }

    ; An owner-specific cleanup may not remove another module's border.
    static Hide(expectedOwner := "", destroy := false) {
        if !this.CanHide(expectedOwner, this.owner)
            return false
        if this.timerCallback
            try SetTimer(this.timerCallback, 0)
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

    static CanHide(expectedOwner, activeOwner) {
        return expectedOwner = "" || expectedOwner = activeOwner
    }

    static Expire(*) => this.Hide()

    static GetVisibleBounds(hwnd, &x, &y, &width, &height) {
        frame := Buffer(16, 0)
        result := DllCall(
            "dwmapi\DwmGetWindowAttribute",
            "ptr", hwnd,
            "uint", 9, ; DWMWA_EXTENDED_FRAME_BOUNDS
            "ptr", frame,
            "uint", frame.Size,
            "int"
        )
        if result != 0
            return false
        x := NumGet(frame, 0, "int")
        y := NumGet(frame, 4, "int")
        width := NumGet(frame, 8, "int") - x
        height := NumGet(frame, 12, "int") - y
        return width > 0 && height > 0
    }

    static GetAccentColor() {
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
}
