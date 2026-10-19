; =============================================================================
; keyboard.ahk - F13-F24 and Numpad 0-9 output with owned-release tracking
; =============================================================================
; Keep the old layer's SendLevel-1 / Blind output behavior. Physically held
; Ctrl/Alt/Shift/Win modifiers are preserved; these are remaps, not text macros.
; Reference counts keep primary/secondary bindings from releasing each other's
; shared output. One-shot activations send a pulse rather than holding a key.
; =============================================================================

class PH_Keyboard {
    __New(app) {
        this.app := app
        this.held := Map()
        this.counts := Map()
        this.pollCallback := ObjBindMethod(this, "CheckReleases")
    }

    Event(output, event) {
        token := event.actionId "|" event.slot
        if event.phase = "up" || event.phase = "cancel" {
            this.Release(token)
            return
        }
        if event.phase != "down" || !this.app.CanDispatch(event.actionId)
            return
        if event.oneShot || InStr(event.key, "Wheel") {
            if !this.counts.Has(output) && !GetKeyState(output, "P")
                this.SendOutput(output)
            return
        }
        if this.held.Has(token) || GetKeyState(output, "P")
            return
        this.Acquire(token, output, event)
    }

    Acquire(token, output, event) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if this.held.Has(token)
                return
            count := this.counts.Has(output) ? this.counts[output] : 0
            this.held[token] := {output: output, event: event.Clone()}
            this.counts[output] := count + 1
            ; Arm cleanup before sending; an interrupted send cannot orphan state.
            SetTimer(this.pollCallback, 15)
            if count = 0
                this.SendOutput(output, " down")
        }
        finally Critical previousCritical
    }

    Release(token) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !this.held.Has(token)
                return
            press := this.held[token]
            remaining := this.counts[press.output] - 1
            if remaining = 0 {
                ; Do not release a real key which the user is now holding.
                if !GetKeyState(press.output, "P")
                    this.SendOutput(press.output, " up")
                this.counts.Delete(press.output)
            } else {
                this.counts[press.output] := remaining
            }
            this.held.Delete(token)
            if !this.held.Count
                SetTimer(this.pollCallback, 0)
        }
        finally Critical previousCritical
    }

    CheckReleases(*) {
        for token, press in this.held.Clone() {
            event := press.event
            released := !this.app.CanDispatch(event.actionId)
            if event.layer = "normal" {
                released := released || !GetKeyState(event.key, "P")
                    || Keybindings.ModifierMask() != event.modifiers
            } else {
                ; The local layer owns suppressed inputs. Do not mistake a
                ; missing local physical event for a release; trust its up/cancel.
                client := this.app.manager.client
                released := released || !IsObject(client) || !client.session
                    || !client.ServiceMatches()
            }
            if released
                try this.Release(token)
                catch Error as releaseError
                    this.app.Report("key release failed: " releaseError.Message)
        }
    }

    ReleaseAll() {
        for token in this.held.Clone()
            try this.Release(token)
            catch Error as releaseError
                this.app.Report("key cleanup failed: " releaseError.Message)
        if !this.held.Count
            SetTimer(this.pollCallback, 0)
    }

    SendOutput(output, state := "") {
        if this.app.dryRun {
            this.app.Report("dry run: send " output (state = "" ? " tap" : state))
            return
        }
        previousLevel := SendLevel(1)
        try SendEvent("{Blind}{" output state "}")
        finally SendLevel(previousLevel)
    }
}
