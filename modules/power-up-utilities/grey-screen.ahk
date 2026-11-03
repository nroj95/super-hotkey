; =============================================================================
; grey-screen.ahk - drains the color from every display, from 0 (none) to 1
; (fully grey)
; =============================================================================
; The Magnification API's full-screen color effect changes no Windows setting,
; and Windows drops it as soon as this process ends, so not even a crash can
; leave the displays grey. Each source asks for its own level and the greyest
; wins, so two reasons to grey never add up past fully grey. A dry run only
; records the levels.
; =============================================================================

class PU_GreyScreen {
    ; How much of each source channel feeds every output channel when grey.
    static Luminance := [0.3, 0.59, 0.11]

    __New(dryRun) {
        this.dryRun := dryRun
        this.levels := Map()  ; source -> its level
        this.level := 0       ; the level shown
        this.initialized := false
    }

    Set(source, level) {
        level := Max(0, Min(1, level))
        if level
            this.levels[source] := level
        else if this.levels.Has(source)
            this.levels.Delete(source)
        this.Show()
    }

    Clear() {
        this.levels.Clear()
        this.Show()
    }

    Show() {
        greyest := 0
        for , level in this.levels
            greyest := Max(greyest, level)
        if greyest = this.level
            return
        this.level := greyest
        if this.dryRun
            return
        try this._Apply(greyest)
        catch Error as failure
            SuiteState.Log.Error("Power-Up Utilities / grey screen", failure)
    }

    ; Mixes identity and grey by level; level 0 also releases the API.
    _Apply(level) {
        if !this.initialized {
            if !level
                return
            if !DllCall("LoadLibrary", "str", "Magnification.dll", "ptr")
                || !DllCall("Magnification\MagInitialize", "int")
                throw OSError(A_LastError, "MagInitialize")
            this.initialized := true
        }
        matrix := Buffer(100, 0)
        loop 5 {
            row := A_Index
            loop 5 {
                column := A_Index
                grey := row <= 3 && column <= 3 ? PU_GreyScreen.Luminance[row] : row = column
                NumPut("float", (1 - level) * (row = column) + level * grey, matrix, ((row - 1) * 5 + column - 1) * 4)
            }
        }
        if !DllCall("Magnification\MagSetFullscreenColorEffect", "ptr", matrix, "int")
            throw OSError(A_LastError, "MagSetFullscreenColorEffect")
        if !level {
            DllCall("Magnification\MagUninitialize", "int")
            this.initialized := false
        }
    }
}
