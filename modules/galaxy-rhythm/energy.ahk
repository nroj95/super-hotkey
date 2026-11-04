; =============================================================================
; energy.ahk - an energy bar that is a daily budget: it drains while the
; user works, breaks give a little back, and it starts over each morning
; =============================================================================
; A minute with physical keyboard, mouse or XInput game controller input
; costs a minute; Windows does not count controllers as input, so connected
; ones are read ten times a second, and only XInput's real input counts: a
; button, a trigger past its threshold or a stick beyond its dead zone, never
; a thumb resting on a stick. A minute at the unlocked computer with its
; screens on but no input, watching or reading, costs half, down to zero but
; never onto the road; anything programs do on their own is no input. A full
; bar holds FullHours of active minutes.
;
; Only the start of a day fills the bar. At Your day starts at (bedtime's
; wakeTime) it starts over, as a day does in Stardew Valley: full if the
; computer was last used before bedtime's first message, half if still at it
; at bedtime's sleep, sliding between the two in between, and halved again
; after a day that ran dry (MorningShare). Use during lights-out, from the
; sleep to the day start, does not count: bedtime sends the user back to
; bed, so a quick look costs nothing and an early riser is not up late.
;
; Breaks give a little back: one of BreakMinutes or more, the least
; screen-work guidance asks for, refills RefillShare times its length, up to
; RefillLimit and never above a full bar, silently, even out of the grey. A
; break across the start of a day earns nothing; the new day is its reward. A break is the time from the
; moment the computer first saw the user gone, when it locked, turned its
; displays off, slept or was off, until they come back. Idle time before that
; may have been reading or a film: walking off without locking loses the
; minutes until the displays turn off, so the guide suggests Win + L, sleep
; or a short display timeout. Time while the suite is suspended or the bar
; hidden is no break, even locked, and a break starts no earlier than its
; end. A suite closed by Windows signing out or shutting down counts the
; time until the next start as a break from that moment, a crash from its
; last tick, and a suite closed by hand none, even across a reboot.
;
; 10 % left says so. At zero the road to fainting starts with its notice.
; With Faint on, the displays turn grey over FadeMinutes of activity, then
; Lights out shows and the computer sleeps; the user wakes halfway along the
; road, with time to save their work, until a break or a second wind lifts
; them out; the day has run dry either way. The grey never comes without
; the faint, so without it the bar just stays empty. Stay awake never
; touches the bar: it keeps the computer up while the user is away, when the
; bar neither drains nor greys. A night off (the module's Off) pauses the
; drain, its notices, the grey and the faint until the day starts; how late
; the computer was used still counts. The level, when the computer was last
; used and when the day last started survive restarts in energy.ini. The
; bar, outlined so it shows on dark backgrounds, sits in the corner
; Position names, bottom right by default, on the display Display names, the
; primary one by default, or on all; a dry run draws no bar.
; =============================================================================

class GR_Energy {
    static TickMs := 10000
    static ActiveMs := 60000      ; input this recent makes a tick active
    static PassiveShare := 0.5    ; of a tick's cost while the user only watches or reads
    static PadPollMs := 100
    ; XInput's thresholds for real input: XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
    ; XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE and XINPUT_GAMEPAD_TRIGGER_THRESHOLD.
    static LeftStickDeadZone := 7849
    static RightStickDeadZone := 8689
    static TriggerThreshold := 30
    static FadeDefault := 30      ; minutes of activity from zero to the faint
    static LowShare := 0.1
    static WakeShare := 0.5       ; of the road still owed after a faint
    ; A break of BreakMinutes or more refills RefillShare times its length,
    ; up to RefillLimit minutes.
    static BreakMinutes := 5
    static RefillShare := 2
    static RefillLimit := 60
    ; The morning bar after using the computer from bedtime's sleep on, and
    ; the share left of it after a day that ran dry.
    static LateShare := 0.5
    static DryShare := 0.5
    static WindShare := 0.25      ; of a full bar a second wind gives back, once a day
    ; The default words of the notices, which Settings can change.
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
        this.lastSeen := ""      ; A_Now of the last tick
        this.savedMinute := ""
        this.away := false       ; locked, displays off or asleep since awaySince
        this.awaySince := ""     ; A_Now when the computer first saw the user gone
        this.lastUp := ""        ; A_Now of the last tick at the computer
        this.dayStarted := ""    ; A_Now of the day start the bar last started over at
        this.dry := false        ; the bar ran empty since the day started
        this.windDay := ""       ; A_Now of the day start of the day a second wind was taken
        this.displayOff := false
        this.lowShown := false
        this.roadShown := false
        this.fainting := false
        this.padSlots := []       ; XInput slots connected at the last tick
        this.padButtons := Map()  ; slot -> its buttons at the last reading
        this.padUsed := 0         ; A_TickCount when a controller was last used, or 0
        this.padCallback := ObjBindMethod(this, "PollPads")
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

    ; The latest moment at or before now when the clock showed time (HHmm).
    static LastAt(now, time) {
        moment := SubStr(now, 1, 8) time "00"
        return DateDiff(moment, now, "Seconds") > 0 ? DateAdd(moment, -1, "Days") : moment
    }

    ; The share of a full bar a day starting at dayStart begins with, for a
    ; computer last used before lights-out at lastUp, bedtime's first message
    ; at lateTime and its sleep at sleepTime (HHmm): full before lateTime,
    ; LateShare from sleepTime on, sliding between, and DryShare of that
    ; after a dry day.
    static MorningShare(dayStart, lastUp, lateTime, sleepTime, dry) {
        late := GR_Energy.LastAt(dayStart, lateTime)
        span := DateDiff(GR_Energy.LastAt(dayStart, sleepTime), late, "Seconds")
        share := 1
        if lastUp != "" && DateDiff(lastUp, late, "Seconds") > 0
            share := span > 0 ? Max(GR_Energy.LateShare,
                1 - (1 - GR_Energy.LateShare) * DateDiff(lastUp, late, "Seconds") / span) : GR_Energy.LateShare
        return dry ? share * GR_Energy.DryShare : share
    }

    static Whole(text, low, high, fallback) => IsNumber(text) && text >= low && text <= high
        ? Integer(text) : fallback

    ; Started after the suite last ticked: the computer was off meanwhile.
    static Restarted(lastSeen, now, uptimeMs) => lastSeen != ""
        && DateDiff(lastSeen, DateAdd(now, -(uptimeMs // 1000), "Seconds"), "Seconds") < 0

    ; Away since the last run: it ended with the user gone, signed out or shut
    ; down included, or the computer restarted since its last tick.
    static AwayAtStart(awaySince, lastSeen, now, uptimeMs) => awaySince != ""
        || GR_Energy.Restarted(lastSeen, now, uptimeMs)

    LoadSettings() {
        read := (key, fallback) => IniRead(this.settingsPath, "Energy", key, fallback)
        this.show := read("Show", 1) = "1"
        this.fullHours := GR_Energy.Whole(read("FullHours", ""), 4, 24, 10)
        this.faint := read("Faint", 1) = "1"
        this.roadMinutes := GR_Energy.Whole(read("FadeMinutes", ""), 10, 180, GR_Energy.FadeDefault)
        this.lowText := GR_Bedtime.CleanText(read("LowText", ""), GR_Energy.Low)
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
        seen := IniRead(this.statePath, "Energy", "LastSeen", "")
        since := IniRead(this.statePath, "Energy", "AwaySince", "")
        up := IniRead(this.statePath, "Energy", "LastUp", "")
        started := IniRead(this.statePath, "Energy", "DayStarted", "")
        this.lastSeen := IsTime(seen) ? seen : ""
        this.awaySince := IsTime(since) ? since : ""
        this.lastUp := IsTime(up) ? up : ""
        this.dayStarted := IsTime(started) ? started : ""
        this.dry := IniRead(this.statePath, "Energy", "Dry", 0) = "1"
        wind := IniRead(this.statePath, "Energy", "SecondWind", "")
        this.windDay := IsTime(wind) ? wind : ""
    }

    SaveState() {
        if this.module.dryRun
            return
        try {
            SplitPath(this.statePath, , &directory)
            DirCreate(directory)
            IniWrite(Round(this.level, 2), this.statePath, "Energy", "Level")
            IniWrite(this.lastSeen, this.statePath, "Energy", "LastSeen")
            IniWrite(this.away ? this.awaySince : "", this.statePath, "Energy", "AwaySince")
            IniWrite(this.lastUp, this.statePath, "Energy", "LastUp")
            IniWrite(this.dayStarted, this.statePath, "Energy", "DayStarted")
            IniWrite(this.dry ? 1 : 0, this.statePath, "Energy", "Dry")
            IniWrite(this.windDay, this.statePath, "Energy", "SecondWind")
        }
        catch Error as failure
            SuiteState.Log.Error("Galaxy Rhythm / energy state", failure)
    }

    Start() {
        ; Away since the last run: a break from leaving, or from its last tick.
        this.away := GR_Energy.AwayAtStart(this.awaySince, this.lastSeen, A_Now, A_TickCount)
        if this.away && this.awaySince = ""
            this.awaySince := this.lastSeen
        guid := Buffer(16, 0)
        DllCall("Ole32\CLSIDFromString", "wstr", GR_Energy.DisplayState, "ptr", guid)
        OnMessage(0x0218, this.powerCallback) ; WM_POWERBROADCAST
        this.notification := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd,
            "ptr", guid, "uint", 0, "ptr")
        this.bar := GR_EnergyBar()
        SetTimer(this.tickCallback, GR_Energy.TickMs)
        SetTimer(this.drawCallback, 1000)
    }

    ; Closed by Windows signing out or shutting down, the user left now, and
    ; the next start counts the time since as a break. Closed for any other
    ; reason, it is no break, even across a reboot: the user may have kept
    ; working meanwhile.
    Stop(reason := "Exit") {
        SetTimer(this.tickCallback, 0)
        SetTimer(this.drawCallback, 0)
        SetTimer(this.faintCallback, 0)
        SetTimer(this.padCallback, 0)
        OnMessage(0x0218, this.powerCallback, 0)
        if this.notification
            DllCall("UnregisterPowerSettingNotification", "ptr", this.notification)
        this.notification := 0
        if IsObject(this.bar)
            this.bar.Destroy()
        this.bar := 0
        if reason = "Shutdown" || reason = "Logoff"
            this.Left()
        else
            this.lastSeen := "", this.away := false
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
            this.Left()
    }

    ; The user stepped away: locked, the displays went off or the computer
    ; went to sleep. The first sign starts the break.
    Left(now := "") {
        if this.away
            return
        this.away := true
        this.awaySince := now = "" ? A_Now : now
    }

    Present() {
        app := this.module.app
        return app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked && !this.displayOff
    }

    ; One tick: the start of a day, a break on coming back, the drain, then
    ; the notices, the grey and the faint. Takes the time and idle
    ; milliseconds it pretends.
    Tick(now := "", idleMs := "") {
        now := now = "" ? A_Now : now
        idleMs := idleMs = "" ? Min(A_TimeIdlePhysical, this.PadIdleMs()) : idleMs
        app := this.module.app
        this.lastSeen := now
        this.StartDay(now)
        if !this.show || !this.Present() {
            ; A suspended suite or a hidden bar is neither use nor rest, even
            ; locked meanwhile: a break starts no earlier than its end.
            if app.suspended || !this.show
                this.away := false
            else if app.sessionLocked || app.systemSuspended || this.displayOff
                this.Left(now)
            this.Save(now)
            return
        }
        rows := this.module.bedtime.rows
        if !GR_Bedtime.InNight(now, rows[-1].time, this.module.bedtime.wakeTime)
            this.lastUp := now
        if this.away {
            this.away := false
            this.TakeBreak(DateDiff(now, this.awaySince, "Seconds") / 60)
        }
        ; A night off pauses the drain, its notices, the grey and the faint.
        if this.module.Off(now) {
            this.Shade()
            this.Save(now)
            return
        }
        ; Watching or reading costs half, and never onto the road.
        active := idleMs < GR_Energy.ActiveMs
        cost := GR_Energy.TickMs / 60000 * (active ? 1 : GR_Energy.PassiveShare)
        this.level := Max(this.level - cost, Min(this.level, active ? -this.roadMinutes : 0))
        if this.level <= 0
            this.dry := true
        if this.level > this.full * GR_Energy.LowShare
            this.lowShown := false
        else if this.level > 0 && !this.lowShown {
            this.lowShown := true
            this.Notice(this.lowText)
        }
        if this.level > 0
            this.roadShown := false
        else if !this.roadShown {
            this.roadShown := true
            this.Notice(this.roadText)
        }
        this.Shade()
        if this.faint && !this.fainting && this.level <= -this.roadMinutes {
            this.fainting := true
            this.Notice(this.faintText)
            SetTimer(this.faintCallback, -SuiteNotice.NewsMs)
        }
        this.Save(now)
    }

    ; Windows' idle time never sees game controllers, so each tick looks for
    ; XInput ones, and while one is connected PollPads reads it ten times a
    ; second. Milliseconds since a controller was last used.
    PadIdleMs() {
        slots := []
        state := Buffer(16, 0)
        try loop 4
            if !DllCall("xinput1_4\XInputGetState", "uint", A_Index - 1, "ptr", state, "uint")
                slots.Push(A_Index - 1)
        this.padSlots := slots
        SetTimer(this.padCallback, slots.Length ? GR_Energy.PadPollMs : 0)
        return this.padUsed ? A_TickCount - this.padUsed : 0x7FFFFFFF
    }

    PollPads(*) {
        state := Buffer(16, 0) ; XINPUT_STATE
        for slot in this.padSlots
            try if !DllCall("xinput1_4\XInputGetState", "uint", slot, "ptr", state, "uint")
                this.NotePad(slot, NumGet(state, 4, "ushort"), NumGet(state, 6, "uchar"), NumGet(state, 7, "uchar"),
                    NumGet(state, 8, "short"), NumGet(state, 10, "short"),
                    NumGet(state, 12, "short"), NumGet(state, 14, "short"), A_TickCount)
    }

    ; Real input as XInput defines it: a button pressed or released, a trigger
    ; past its threshold or a stick beyond its dead zone, so a thumb resting
    ; on a stick does not count, and a stick held over does.
    NotePad(slot, buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY, tick) {
        if this.padButtons.Has(slot) && this.padButtons[slot] != buttons
            || Max(leftTrigger, rightTrigger) > GR_Energy.TriggerThreshold
            || Sqrt(leftX ** 2 + leftY ** 2) > GR_Energy.LeftStickDeadZone
            || Sqrt(rightX ** 2 + rightY ** 2) > GR_Energy.RightStickDeadZone
            this.padUsed := tick
        this.padButtons[slot] := buttons
    }

    ; At most once a minute, so ticks do not wear the disk.
    Save(now) {
        if SubStr(now, 1, 12) = this.savedMinute
            return
        this.savedMinute := SubStr(now, 1, 12)
        this.SaveState()
    }

    ; At the start of a day the bar starts over, once, whether the user is
    ; there or not: by MorningShare for how late the computer was used before
    ; lights-out and whether the day ran dry. The first run only notes the day.
    StartDay(now) {
        start := GR_Energy.LastAt(now, this.module.bedtime.wakeTime)
        if this.dayStarted != "" && DateDiff(start, this.dayStarted, "Seconds") > 0 {
            rows := this.module.bedtime.rows
            share := GR_Energy.MorningShare(start, this.lastUp, rows[1].time, rows[-1].time, this.dry)
            this.level := this.full * share
            this.dry := false
            this.lowShown := false
            this.roadShown := false
            this.module.Report("day starts at " Round(share * 100) " %")
            this.Shade()
        }
        if this.dayStarted = "" || DateDiff(start, this.dayStarted, "Seconds") > 0
            this.dayStarted := start
    }

    ; A break of BreakMinutes or more refills RefillShare times its length,
    ; up to RefillLimit, silently, even out of the grey. One across the start
    ; of a day earns nothing: the new day is its reward.
    TakeBreak(minutes) {
        if minutes < GR_Energy.BreakMinutes
            || this.dayStarted != "" && DateDiff(this.awaySince, this.dayStarted, "Seconds") < 0
            return
        gained := Min(GR_Energy.RefillLimit, minutes * GR_Energy.RefillShare)
        this.level := Min(this.full, this.level + gained)
        this.module.Report("break of " Round(minutes) " min: +" Round(gained) " min of energy")
    }

    ; Once a day, from one day start to the next, a second wind gives back
    ; WindShare of a full bar, even out of the grey. False if already taken.
    SecondWind(now := "") {
        day := GR_Energy.LastAt(now = "" ? A_Now : now, this.module.bedtime.wakeTime)
        if this.windDay = day
            return false
        this.windDay := day
        this.level := Min(this.full, this.level + this.full * GR_Energy.WindShare)
        if this.level > 0
            this.roadShown := false
        this.Shade()
        this.SaveState()
        this.module.Report("second wind")
        return true
    }

    Notice(text) {
        SuiteNotice.ShowEverywhere("status", text)
        this.module.Report("energy: " text)
    }

    ; Once Lights out has gone: taking the night off meanwhile keeps the
    ; computer up. The faint keeps half the debt, so waking straight away
    ; leaves time to save work, and the grey stays until the day starts over.
    FaintNow(*) {
        app := this.module.app
        if !this.fainting
            return
        if this.module.Off() || this.module.stopping || !app.ModuleActive(this.module.id)
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
        this.roadShown := false
        ; The faint sends the user away, so the nap counts from the tick
        ; that brought it.
        this.Left(this.lastSeen)
        if this.module.dryRun
            this.module.Report("dry run: energy faint")
        else {
            try SuiteSleep.Now()
            catch Error as failure {
                SuiteState.Log.Error("Galaxy Rhythm / faint", failure)
                TrayTip(failure.Message, this.module.Name, 2)
            }
        }
        ; Back from sleep, or Windows would not sleep: half the debt is owed.
        this.level := -this.roadMinutes * GR_Energy.WakeShare
        this.Shade()
    }

    ; The grey of the road, cleared at once by a night off or a suspended
    ; suite; Draw runs it every second, so it never waits for a tick.
    Shade() {
        app := this.module.app
        this.module.grey.Set("energy", this.show && this.faint && this.level < 0 && !this.module.Off()
            && !app.suspended && app.ModuleActive(this.module.id) ? -this.level / this.roadMinutes : 0)
    }

    Draw(*) {
        this.Shade()
        if IsObject(this.bar)
            this.bar.Draw(this.level / this.full, this.show && this.Present(), this.display, this.position)
    }
}

; The bar itself: an upright, see-through and click-through gauge marked E
; that fills from the bottom, outlined in light grey so it shows on dark
; backgrounds too, in a corner of the work area, so just inside the
; taskbar, on the display chosen or on all, and hidden on a display a window
; fills. One window per display.
class GR_EnergyBar {
    static Width := 18
    static Height := 160       ; the gauge, below its E
    static LabelHeight := 20
    static Outline := 2        ; the light frame around the E and the gauge
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

    ; Green when full, yellow at half and red when empty, blended smoothly in
    ; whole percents as in Stardew Valley; an empty red track on the road.
    static Colors(share) {
        blend := Round(Max(0, Min(1, share)), 2)
        low := blend < 0.5
        from := low ? 0xD03030 : 0xE0B000
        to := low ? 0xE0B000 : 0x3CB043
        mix := low ? blend * 2 : blend * 2 - 1
        color := 0
        for shift in [16, 8, 0]
            color |= Round(((from >> shift) & 0xFF) * (1 - mix) + ((to >> shift) & 0xFF) * mix) << shift
        return Format("{:06X}", color) (share > 0 ? " Background303030" : " Background5A1414")
    }

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
        ; The window's own colour shows only as the outline around the controls.
        window.BackColor := "D0D0D0"
        window.SetFont("s9 bold cFFFFFF", "Segoe UI")
        edge := GR_EnergyBar.Outline
        window.AddText("x" edge " y" edge " w" GR_EnergyBar.Width " h" GR_EnergyBar.LabelHeight
            . " Center 0x200 Background202020", "E") ; SS_CENTERIMAGE
        progress := window.AddProgress("x" edge " y" edge + GR_EnergyBar.LabelHeight " w" GR_EnergyBar.Width
            . " h" GR_EnergyBar.Height " -Theme Vertical Range0-1000")
        DllCall("SetLayeredWindowAttributes", "ptr", window.Hwnd, "uint", 0, "uchar", GR_EnergyBar.Opacity, "uint", 2)
        window.Show("Hide w" GR_EnergyBar.Width + 2 * edge " h" GR_EnergyBar.LabelHeight + GR_EnergyBar.Height + 2 * edge)
        return {window: window, progress: progress, colors: "", shown: false}
    }

    Destroy() {
        for monitor, bar in this.bars
            try bar.window.Destroy()
        this.bars := Map()
    }
}
