; =============================================================================
; speakers.ahk - keeping awake speakers that fall asleep in silence
; =============================================================================
; Some speakers switch to standby after minutes without sound and wake a few
; seconds late, so notifications and the starts of videos go missing;
; speaker-standby.md keeps what is known and measured about them. While keep
; speakers awake is on, a nudge plays every Minutes, 8 by default, below the
; shortest standby makers state, and as soon as the user is back, so the
; speakers are awake before anything plays. The nudge is a 25 Hz tone, too
; low for small speakers to reproduce, made louder in the file as Windows'
; volume goes down so the same level reaches the jack; past LoudestDb in the
; file, Windows' volume is raised for it instead. For speakers that ignore
; the tone, Chime plays the Windows Balloon chime with a 16 % volume floor.
; A raised volume goes back once the nudge has played, and only if it is
; still the level set. Nudges play only while the user is at the unlocked
; computer with its displays on and Super Hotkey running, so away from it the
; speakers may sleep, and a muted device gets none. The action switches it on
; and off; settings.ini [Speakers] keeps that, Minutes and Chime. A dry run
; plays nothing and reports each nudge.
; =============================================================================

class PU_Speakers {
    static MinutesDefault := 8
    static MinutesLimit := 60
    static CheckMs := 30000
    static NoticeMs := 1400
    static ToneHz := 25
    static ToneDb := -36    ; at the jack: 6 dB above where the measured speakers woke
    static LoudestDb := -6  ; in the file; past it Windows' volume is raised instead
    static ToneMs := 1500
    static Rate := 8000
    static ChimeVolume := 0.16
    static ChimeMs := 2500
    ; GUID_CONSOLE_DISPLAY_STATE: the displays went off, on or dimmed.
    static DisplayState := "{6FE69556-704A-47A0-8F24-C28D936FDA47}"

    __New(module, path) {
        this.module := module
        this.path := path
        this.on := IniRead(path, "Speakers", "KeepAwake", 0) = "1"
        this.minutes := PU_Speakers.CleanMinutes(IniRead(path, "Speakers", "Minutes", PU_Speakers.MinutesDefault))
        this.chime := IniRead(path, "Speakers", "Chime", 0) = "1"
        this.chimePath := A_WinDir "\Media\Windows Balloon.wav"
        this.displayOff := false
        this.wasPresent := false  ; at the last check
        this.nudged := 0       ; A_TickCount of the last nudge
        this.playing := false
        this.tone := 0         ; the tone's WAV, kept until it has played
        this.restore := 0      ; {endpoint, original, raised} while Windows' volume is raised
        this.notification := 0
        this.checkCallback := ObjBindMethod(this, "Check")
        this.soonCallback := ObjBindMethod(this, "Check")
        this.doneCallback := ObjBindMethod(this, "Silence")
        this.powerCallback := ObjBindMethod(this, "PowerSetting")
    }

    static CleanMinutes(value) => IsInteger(value) && value >= 1 && value <= PU_Speakers.MinutesLimit
        ? Integer(value) : PU_Speakers.MinutesDefault

    Start() {
        guid := Buffer(16, 0)
        DllCall("Ole32\CLSIDFromString", "wstr", PU_Speakers.DisplayState, "ptr", guid)
        OnMessage(0x0218, this.powerCallback) ; WM_POWERBROADCAST
        this.notification := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd,
            "ptr", guid, "uint", 0, "ptr")
        SetTimer(this.checkCallback, PU_Speakers.CheckMs)
        this.Check()
    }

    Stop() {
        SetTimer(this.checkCallback, 0)
        SetTimer(this.soonCallback, 0)
        OnMessage(0x0218, this.powerCallback, 0)
        if this.notification
            DllCall("UnregisterPowerSettingNotification", "ptr", this.notification)
        this.notification := 0
        this.Silence()
    }

    ; PBT_POWERSETTINGCHANGE for the display state: 0 off, 1 on, 2 dimmed.
    ; Displays coming on mean the user is back: check at once.
    PowerSetting(wParam, lParam, *) {
        if wParam != 0x8013
            return
        guid := Buffer(78, 0)
        DllCall("Ole32\StringFromGUID2", "ptr", lParam, "ptr", guid, "int", 39)
        if StrGet(guid, "UTF-16") != PU_Speakers.DisplayState
            return
        this.displayOff := NumGet(lParam, 20, "uint") = 0
        if !this.displayOff
            SetTimer(this.soonCallback, -1)
    }

    ; The action: on or off, kept across restarts. Switched on, it nudges at
    ; once, waking speakers that already sleep.
    Toggle() {
        this.on := !this.on
        this.module.app.Settings.WritePreferences(this.module.id,
            Map("Speakers", Map("KeepAwake", this.on ? 1 : 0)))
        SuiteNotice.Show("status", this.on ? "Keeping speakers awake" : "Letting speakers sleep", PU_Speakers.NoticeMs)
        this.module.Report(this.on ? "keeping speakers awake" : "letting speakers sleep")
        this.wasPresent := false
        if this.on
            this.Check()
        else
            this.Silence()
    }

    Present() {
        app := this.module.app
        return this.on && app.ModuleActive(this.module.id) && !this.module.stopping && !app.suspended
            && !app.systemSuspended && !app.sessionLocked && !this.displayOff
    }

    ; Every half minute, and as the user comes back: a nudge when the user has
    ; just returned or the interval has passed.
    Check(*) {
        present := this.Present()
        back := present && !this.wasPresent
        this.wasPresent := present
        if !present || !back && ((A_TickCount - this.nudged) & 0xFFFFFFFF) < this.minutes * 60000
            return
        try this.Nudge()
        catch Error as failure
            SuiteState.Log.Error("Power-Up Utilities / speakers", failure)
    }

    Nudge() {
        this.nudged := A_TickCount
        if this.module.dryRun {
            this.module.Report("dry run: speakers nudged")
            return
        }
        this.Silence()
        pointer := SoundGetInterface("{5CDF2C82-841E-4546-9722-0CF74078229A}")
        if !pointer
            throw Error("The playback device does not expose endpoint volume control.")
        endpoint := ComValue(13, pointer) ; owned IAudioEndpointVolume
        ComCall(15, endpoint, "int*", &muted := 0) ; GetMute
        if muted
            return
        if this.chime {
            if !FileExist(this.chimePath)
                throw Error("The speaker chime was not found:`n" this.chimePath)
            ComCall(9, endpoint, "float*", &volume := 0) ; GetMasterVolumeLevelScalar
            if volume < PU_Speakers.ChimeVolume
                this.Raise(endpoint, 7, PU_Speakers.ChimeVolume) ; SetMasterVolumeLevelScalar
            this.Play(this.chimePath, 0x20003, PU_Speakers.ChimeMs) ; SND_FILENAME | SND_NODEFAULT | SND_ASYNC
            return
        }
        ComCall(8, endpoint, "float*", &volumeDb := 0) ; GetMasterVolumeLevel
        plan := PU_Speakers.TonePlan(volumeDb)
        if plan.raiseTo != ""
            this.Raise(endpoint, 6, plan.raiseTo) ; SetMasterVolumeLevel
        this.tone := PU_Speakers.Tone(plan.fileDb)
        this.Play(this.tone, 0x7, PU_Speakers.ToneMs) ; SND_MEMORY | SND_NODEFAULT | SND_ASYNC
    }

    ; The tone's level in the file for Windows' volume in dB, so ToneDb reaches
    ; the jack, and the volume in dB to raise Windows' to when the file alone
    ; would pass LoudestDb.
    static TonePlan(volumeDb) {
        fileDb := PU_Speakers.ToneDb - volumeDb
        if fileDb <= PU_Speakers.LoudestDb
            return {fileDb: fileDb, raiseTo: ""}
        return {fileDb: PU_Speakers.LoudestDb, raiseTo: PU_Speakers.ToneDb - PU_Speakers.LoudestDb}
    }

    ; A 16-bit mono WAV of the tone at fileDb, faded in and out over 0.2 s.
    static Tone(fileDb) {
        rate := PU_Speakers.Rate
        count := rate * PU_Speakers.ToneMs // 1000
        fade := rate // 5
        bytes := count * 2
        wav := Buffer(44 + bytes, 0)
        NumPut("uint", 0x46464952, "uint", 36 + bytes, "uint", 0x45564157, "uint", 0x20746D66, ; RIFF, WAVE, fmt
            "uint", 16, "ushort", 1, "ushort", 1, "uint", rate, "uint", rate * 2, "ushort", 2, "ushort", 16,
            "uint", 0x61746164, "uint", bytes, wav) ; data
        amplitude := 32767 * 10 ** (fileDb / 20)
        step := 2 * 3.141592653589793 * PU_Speakers.ToneHz / rate
        loop count {
            i := A_Index - 1
            NumPut("short", Round(amplitude * Min(1, i / fade, (count - 1 - i) / fade) * Sin(step * i)), wav, 44 + i * 2)
        }
        return wav
    }

    ; Raises Windows' volume through the endpoint method at index, keeping
    ; what to restore; interruptions never see half a record.
    Raise(endpoint, index, value) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            ComCall(9, endpoint, "float*", &original := 0)
            this.restore := {endpoint: endpoint, original: original, raised: original}
            ComCall(index, endpoint, "float", value, "ptr", 0)
            ComCall(9, endpoint, "float*", &raised := 0)
            this.restore.raised := raised
        }
        finally Critical previousCritical
        Sleep(100)
    }

    Play(sound, flags, durationMs) {
        this.playing := true
        DllCall("winmm\PlaySoundW", Type(sound) = "Buffer" ? "ptr" : "str", sound, "ptr", 0, "uint", flags)
        SetTimer(this.doneCallback, -(durationMs + 500))
    }

    ; Ends a nudge: stops its sound and puts Windows' volume back, unless it
    ; was changed since it was raised. A record kept after a COM failure lets
    ; exit try again.
    Silence(*) {
        SetTimer(this.doneCallback, 0)
        if this.playing
            DllCall("winmm\PlaySoundW", "ptr", 0, "ptr", 0, "uint", 0)
        this.playing := false
        this.tone := 0
        restoration := this.restore
        if !IsObject(restoration)
            return
        ComCall(9, restoration.endpoint, "float*", &current := 0)
        if Abs(current - restoration.raised) < 0.0001
            ComCall(7, restoration.endpoint, "float", restoration.original, "ptr", 0)
        this.restore := 0
    }
}
