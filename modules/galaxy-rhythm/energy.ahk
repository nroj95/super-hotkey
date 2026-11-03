; =============================================================================
; energy.ahk - an energy bar that drains while the user works and refills
; while they rest away from the computer
; =============================================================================
; A minute with physical keyboard or mouse input costs a minute; idle time and
; anything programs do on their own cost nothing. A full bar holds FullHours
; of active minutes.
;
; Rest is the time since the last input before leaving, counted when the user
; comes back to a computer that was locked, had its displays off, was asleep
; or was off; a suspended or closed suite is not rest. Breaks shorter than
; BreakMinutes do not count. A full night (NightHours) refills the whole bar,
; and breaks pay most in their first half hour (Refill).
;
; 10 % left says so. At zero the road to fainting starts, always from zero and
; with its notice: when the bar first empties, when stay awake ends and when
; the user is back after a faint without a real break. With Faint on, the
; displays turn grey over FadeMinutes of activity, then Lights out shows and
; the computer sleeps; the grey never comes without the faint, so without it
; the bar just stays empty. Stay awake holds the bar at zero quietly: no
; notice at zero, no grey and no faint, since the notice belongs to the grey
; and comes once stay awake ends. The level and the last input survive
; restarts in energy.ini. The bar sits in the corner Position names, bottom
; right by default, on the display Display names, the primary one by default,
; or on all; a dry run draws no bar.
; =============================================================================

class GR_Energy {
    static TickMs := 10000
    static ActiveMs := 60000      ; input this recent makes a tick active
    static FadeDefault := 30      ; minutes of activity from zero to the faint
    static LowShare := 0.1
    ; Breaks pay most at first: up to BonusMinutes of extra rest, most of it
    ; within the first half hour.
    static BonusMinutes := 35
    static BonusDecayMinutes := 15
    ; The notices; Road and Faint are only the default words of settings.
    static Low := "You're running low on energy"
    static Road := "You're running on fumes"
    static Faint := "Lights out"
    ; GUID_CONSOLE_DISPLAY_STATE: the displays went off, on or dimmed.
    static DisplayState := "{6FE69556-704A-47A0-8F24-C28D936FDA47}"
    static HeldKeys := ["Ctrl", "Alt", "Shift", "LWin", "RWin", "CapsLock", "Pause", "CtrlBreak"]

    __New(module, settingsPath, statePath) {
        this.module := module
        this.settingsPath := settingsPath
        this.statePath := statePath
        this.level := 0          ; active minutes left; below zero is the road
        this.lastInput := ""     ; A_Now of the last input while present
        this.lastSeen := ""      ; A_Now of the last tick
        this.savedMinute := ""
        this.away := false       ; locked, displays off or asleep since lastInput
        this.displayOff := false
        this.staying := false    ; stay awake at the previous tick
        this.lowShown := false
        this.roadShown := false
        this.fainting := false
        this.notification := 0
        this.bar := 0
        this.tickCallback := ObjBindMethod(this, "Tick")
        this.drawCallback := ObjBindMethod(this, "Draw")
        this.faintCallback := ObjBindMethod(this, "FaintNow")
        this.powerCallback := ObjBindMethod(this, "PowerSetting")
        this.LoadSettings()
        this.LoadState()
    }

    full => this.fullHours * 60

    ; Energy back, in active minutes, for restMinutes of rest: a full night
    ; fills the bar, and the first half hour of a break counts extra.
    static Refill(restMinutes, fullMinutes, nightMinutes) {
        boosted := restMinutes + GR_Energy.BonusMinutes * (1 - Exp(-restMinutes / GR_Energy.BonusDecayMinutes))
        return boosted * fullMinutes / nightMinutes
    }

    static Whole(text, low, high, fallback) => IsNumber(text) && text >= low && text <= high
        ? Integer(text) : fallback

    ; Started after the suite last ticked: the computer was off meanwhile.
    static Restarted(lastSeen, now, uptimeMs) => lastSeen != ""
        && DateDiff(lastSeen, DateAdd(now, -(uptimeMs // 1000), "Seconds"), "Seconds") < 0

    LoadSettings() {
        read := (key, fallback) => IniRead(this.settingsPath, "Energy", key, fallback)
        this.show := read("Show", 1) = "1"
        this.fullHours := GR_Energy.Whole(read("FullHours", ""), 4, 24, 12)
        this.nightHours := GR_Energy.Whole(read("NightHours", ""), 4, 12, 8)
        this.breakMinutes := GR_Energy.Whole(read("BreakMinutes", ""), 1, 60, 10)
        this.faint := read("Faint", 1) = "1"
        this.roadMinutes := GR_Energy.Whole(read("FadeMinutes", ""), 10, 180, GR_Energy.FadeDefault)
        this.roadText := GR_Bedtime.CleanText(read("RoadText", ""), GR_Energy.Road)
        this.faintText := GR_Bedtime.CleanText(read("FaintText", ""), GR_Energy.Faint)
        position := read("Position", "bottom-right")
        this.position := GR_EnergyBar.IsCorner(position) ? position : "bottom-right"
        display := read("Display", "Primary")
        ; The primary display, every display, or one by its Windows device
        ; name, such as \\.\DISPLAY2.
        this.display := display = "Primary" || display = "All"
            || RegExMatch(display, "i)^\\\\\.\\DISPLAY\d+$") ? display : "Primary"
        this.level := Max(-this.roadMinutes, Min(this.level, this.full))
        this.Shade()
    }

    LoadState() {
        level := IniRead(this.statePath, "Energy", "Level", "")
        this.level := IsNumber(level) ? Max(-this.roadMinutes, Min(Number(level), this.full)) : this.full
        last := IniRead(this.statePath, "Energy", "LastInput", "")
        seen := IniRead(this.statePath, "Energy", "LastSeen", "")
        this.lastInput := IsTime(last) ? last : ""
        this.lastSeen := IsTime(seen) ? seen : ""
    }

    SaveState() {
        if this.module.dryRun
            return
        try {
            SplitPath(this.statePath, , &directory)
            DirCreate(directory)
            IniWrite(Round(this.level, 2), this.statePath, "Energy", "Level")
            IniWrite(this.lastInput, this.statePath, "Energy", "LastInput")
            IniWrite(this.lastSeen, this.statePath, "Energy", "LastSeen")
        }
        catch Error as failure
            SuiteState.Log.Error("Galaxy Rhythm / energy state", failure)
    }

    Start() {
        ; Off or restarted since the last tick: that time was rest.
        this.away := GR_Energy.Restarted(this.lastSeen, A_Now, A_TickCount) && this.lastInput != ""
        if !this.away
            this.lastInput := ""
        guid := Buffer(16, 0)
        DllCall("Ole32\CLSIDFromString", "wstr", GR_Energy.DisplayState, "ptr", guid)
        OnMessage(0x0218, this.powerCallback) ; WM_POWERBROADCAST
        this.notification := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd,
            "ptr", guid, "uint", 0, "ptr")
        this.bar := GR_EnergyBar()
        SetTimer(this.tickCallback, GR_Energy.TickMs)
        SetTimer(this.drawCallback, 1000)
    }

    Stop() {
        SetTimer(this.tickCallback, 0)
        SetTimer(this.drawCallback, 0)
        SetTimer(this.faintCallback, 0)
        OnMessage(0x0218, this.powerCallback, 0)
        if this.notification
            DllCall("UnregisterPowerSettingNotification", "ptr", this.notification)
        this.notification := 0
        if IsObject(this.bar)
            this.bar.Destroy()
        this.bar := 0
        if this.lastSeen != ""
            this.SaveState()
    }

    ; PBT_POWERSETTINGCHANGE for the display state: 0 off, 1 on, 2 dimmed.
    PowerSetting(wParam, lParam, *) {
        if wParam != 0x8013
            return
        guid := Buffer(78, 0)
        DllCall("Ole32\StringFromGUID2", "ptr", lParam, "ptr", guid, "int", 39)
        if StrGet(guid, "UTF-16") != GR_Energy.DisplayState
            return
        this.displayOff := NumGet(lParam, 20, "uint") = 0
        if this.displayOff
            this.away := true
    }

    ; The user stepped away: locked, or the computer went to sleep.
    Left() => this.away := true

    Present() {
        app := this.module.app
        return app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked && !this.displayOff
    }

    ; One tick: rest on coming back, drain while active, then the notices,
    ; the grey and the faint. Takes the time and idle milliseconds it pretends.
    Tick(now := "", idleMs := "") {
        now := now = "" ? A_Now : now
        idleMs := idleMs = "" ? A_TimeIdlePhysical : idleMs
        app := this.module.app
        this.lastSeen := now
        if !this.show || !this.Present() {
            if app.sessionLocked || app.systemSuspended || this.displayOff
                this.away := true
            this.Save(now)
            return
        }
        if this.away {
            this.away := false
            rest := this.lastInput = "" ? 0 : DateDiff(now, this.lastInput, "Seconds") / 60
            if rest >= this.breakMinutes
                this.Rest(rest)
        }
        this.lastInput := DateAdd(now, -(idleMs // 1000), "Seconds")
        staying := SuiteStayAwake.active
        if this.staying && !staying
            this.roadShown := false
        this.staying := staying
        if staying && this.level < 0
            this.level := 0
        if idleMs < GR_Energy.ActiveMs {
            lowest := staying ? 0 : -this.roadMinutes
            this.level := Max(this.level - GR_Energy.TickMs / 60000, Min(this.level, lowest))
        }
        if this.level > this.full * GR_Energy.LowShare
            this.lowShown := false
        else if this.level > 0 && !this.lowShown {
            this.lowShown := true
            this.Notice(GR_Energy.Low)
        }
        ; The notice at zero announces the grey, so stay awake holds it back
        ; until it ends.
        if this.level > 0
            this.roadShown := false
        else if !this.roadShown && !staying {
            this.roadShown := true
            this.Notice(this.roadText)
        }
        this.Shade()
        if this.faint && !staying && !this.fainting && this.level <= -this.roadMinutes {
            this.fainting := true
            this.Notice(this.faintText)
            SetTimer(this.faintCallback, -SuiteNotice.NewsMs)
        }
        this.Save(now)
    }

    ; At most once a minute, so ticks do not wear the disk.
    Save(now) {
        if SubStr(now, 1, 12) = this.savedMinute
            return
        this.savedMinute := SubStr(now, 1, 12)
        this.SaveState()
    }

    ; A break back from the road starts at zero, then adds its refill.
    Rest(minutes) {
        before := Max(this.level, 0)
        this.level := Min(before + GR_Energy.Refill(minutes, this.full, this.nightHours * 60), this.full)
        gained := Round((this.level - before) / this.full * 100)
        this.module.Report("rested " Round(minutes) " min, +" gained " %")
        if gained >= 1
            this.Notice("Rested: +" gained " %")
    }

    Notice(text) {
        SuiteNotice.ShowEverywhere("status", text)
        this.module.Report("energy: " text)
    }

    ; Once Lights out has gone: stay awake switched on meanwhile keeps the
    ; computer up. Back after the faint, the road starts again at zero.
    FaintNow(*) {
        app := this.module.app
        if !this.fainting
            return
        if SuiteStayAwake.active || this.module.stopping || !app.ModuleActive(this.module.id)
            || app.suspended || app.systemSuspended {
            this.fainting := false
            return
        }
        for key in GR_Energy.HeldKeys
            if GetKeyState(key, "P") {
                SetTimer(this.faintCallback, -250)
                return
            }
        this.fainting := false
        this.level := 0
        this.roadShown := false
        if this.module.dryRun {
            this.module.Report("dry run: energy faint")
            this.module.grey.Set("energy", 0)
            return
        }
        try SuiteSleep.Now()
        catch Error as failure {
            SuiteState.Log.Error("Galaxy Rhythm / faint", failure)
            TrayTip(failure.Message, this.module.Name, 2)
        }
        ; Back from sleep, or if Windows accepted it without sleeping.
        SetTimer(() => this.module.grey.Set("energy", 0), -5000)
    }

    ; The grey of the road, cleared at once by stay awake or a suspended
    ; suite; Draw runs it every second, so it never waits for a tick.
    Shade() {
        app := this.module.app
        this.module.grey.Set("energy", this.show && this.faint && this.level < 0 && !SuiteStayAwake.active
            && !app.suspended && app.ModuleActive(this.module.id) ? -this.level / this.roadMinutes : 0)
    }

    Draw(*) {
        this.Shade()
        if IsObject(this.bar)
            this.bar.Draw(this.level / this.full, this.show && this.Present(), this.display, this.position)
    }
}

; The bar itself: an upright, see-through and click-through gauge marked E
; that fills from the bottom, in a corner of the work area, so just inside the
; taskbar, on the display chosen or on all, and hidden on a display a window
; fills. One window per display.
class GR_EnergyBar {
    static Width := 18
    static Height := 160       ; the gauge, below its E
    static LabelHeight := 20
    static MarginX := 12       ; in from the side of its corner
    static MarginY := 16       ; in from the top or bottom
    static Opacity := 140      ; of 255: see-through enough to read what lies behind
    static Corners := [["bottom-right", "Bottom right"], ["bottom-left", "Bottom left"],
        ["top-right", "Top right"], ["top-left", "Top left"]]

    __New() {
        this.bars := Map()  ; monitor index -> {window, progress, colors, shown}
    }

    static IsCorner(text) {
        for corner in GR_EnergyBar.Corners
            if corner[1] = text
                return true
        return false
    }

    ; Green when full, then yellow, orange and red; an empty red track on the road.
    static Colors(share) => (share > 0.5 ? "3CB043" : share > 0.25 ? "E0B000" : share > 0.1 ? "E07000" : "D03030")
        . (share > 0 ? " Background303030" : " Background5A1414")

    ; The displays to show on: the primary display, every display, or the one
    ; named by its Windows device name; the primary while that one is
    ; disconnected.
    static Monitors(display) {
        monitors := []
        if display != "Primary"
            loop MonitorGetCount()
                try if display = "All" || MonitorGetName(A_Index) = display
                    monitors.Push(A_Index)
        if !monitors.Length
            monitors.Push(MonitorGetPrimary())
        return monitors
    }

    ; Where a width x height bar sits in a corner of a work area.
    static Place(corner, left, top, right, bottom, width, height, &x, &y) {
        x := InStr(corner, "left") ? left + GR_EnergyBar.MarginX : right - width - GR_EnergyBar.MarginX
        y := InStr(corner, "top") ? top + GR_EnergyBar.MarginY : bottom - height - GR_EnergyBar.MarginY
    }

    Draw(share, visible, display, corner) {
        wanted := Map()
        if visible
            for monitor in GR_EnergyBar.Monitors(display)
                if !GR_EnergyBar.Fullscreen(monitor)
                    wanted[monitor] := true
        for monitor, bar in this.bars
            if bar.shown && !wanted.Has(monitor) {
                bar.window.Hide()
                bar.shown := false
            }
        colors := GR_EnergyBar.Colors(share)
        for monitor in wanted {
            if !this.bars.Has(monitor)
                this.bars[monitor] := GR_EnergyBar._Build()
            bar := this.bars[monitor]
            if colors != bar.colors {
                bar.progress.Opt("c" colors)
                bar.colors := colors
            }
            bar.progress.Value := Round(Max(0, Min(1, share)) * 1000)
            bar.window.GetPos(, , &width, &height)
            MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
            GR_EnergyBar.Place(corner, left, top, right, bottom, width, height, &x, &y)
            DllCall("SetWindowPos", "ptr", bar.window.Hwnd, "ptr", -1, "int", x, "int", y,
                "int", 0, "int", 0, "uint", 0x51, "int") ; HWND_TOPMOST; SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
            bar.shown := true
        }
    }

    ; The foreground window covers its whole display, as games and videos do.
    static Fullscreen(monitor) {
        hwnd := DllCall("GetForegroundWindow", "ptr")
        if !hwnd || IsShellSurfaceWindow(hwnd) || WindowMonitorIndex(hwnd) != monitor
            return false
        try WinGetPosPixels(&x, &y, &width, &height, "ahk_id " hwnd)
        catch
            return false
        MonitorGetPixels(monitor, &left, &top, &right, &bottom)
        return x <= left && y <= top && x + width >= right && y + height >= bottom
    }

    static _Build() {
        ; WS_EX_LAYERED and WS_EX_TRANSPARENT pass clicks through; never activate.
        window := SuiteGui("+AlwaysOnTop -Caption +ToolWindow +E0x80020 +E0x08000000")
        window.MarginX := window.MarginY := 0
        window.BackColor := "202020"
        window.SetFont("s9 bold cFFFFFF", "Segoe UI")
        window.AddText("x0 y0 w" GR_EnergyBar.Width " h" GR_EnergyBar.LabelHeight " Center 0x200", "E") ; SS_CENTERIMAGE
        progress := window.AddProgress("x0 y" GR_EnergyBar.LabelHeight " w" GR_EnergyBar.Width
            . " h" GR_EnergyBar.Height " -Theme Vertical Range0-1000")
        DllCall("SetLayeredWindowAttributes", "ptr", window.Hwnd, "uint", 0, "uchar", GR_EnergyBar.Opacity, "uint", 2)
        window.Show("Hide AutoSize")
        return {window: window, progress: progress, colors: "", shown: false}
    }

    Destroy() {
        for monitor, bar in this.bars
            try bar.window.Destroy()
        this.bars := Map()
    }
}
