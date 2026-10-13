#Requires AutoHotkey v2.0

; =============================================================================
; caps-pause-client.ahk - small protocol-1 adapter, not a running service
; =============================================================================
; Include this in a consumer or inline it when building a standalone release.
; Each script still owns its actions, ordinary hotkeys and saved configuration.
; Call Bind() for desired layer shortcuts, then Start(). Stop() disconnects.
;
; Callback signature: callback(event). The event object contains phase,
; foregroundHwnd, label, layer, key, modifiers, and oneShot.
; phase is "down", "repeat", "up", or "cancel". Keep callbacks SHORT: schedule
; slow work yourself. Never put MsgBox, KeyWait or Sleep inside these callbacks.
; Held-output features must clean up on up, cancel, disconnect and their own exit.
;
; This adapter does not implement the future keybinding GUI or global registry.
; It performs no automatic startup installation and never launches the service.
; =============================================================================

class CapsPauseClient {
    __New(clientName, statusCallback := 0) {
        if clientName = "" || StrLen(clientName) > 100
            || RegExMatch(clientName, "[\t\r\n]")
            throw ValueError("Invalid layer client name.")
        this.name := clientName
        this.statusCallback := statusCallback
        this.window := Gui("+ToolWindow -Caption", "CapsPauseLayers client")
        this.hwnd := this.window.Hwnd
        this.endpointTitle := "nroj.CapsPauseLayers.v1"
        this.serviceHwnd := 0
        this.servicePid := 0
        this.session := 0
        this.running := false
        this.bindings := []
        this.remoteBindings := Map()
        this.active := Map()
        this.eventMessage := DllCall("RegisterWindowMessageW", "str",
            "nroj.CapsPauseLayers.v1.Event", "uint")
        if !this.eventMessage
            throw OSError(A_LastError, "RegisterWindowMessageW")
        this.eventHandler := ObjBindMethod(this, "ReceiveEvent")
        this.maintenanceHandler := ObjBindMethod(this, "Maintain")
        this.exitHandler := ObjBindMethod(this, "Stop")
        OnMessage(this.eventMessage, this.eventHandler)
        OnExit(this.exitHandler)
    }

    Bind(layerName, modifiers, keyName, label, callback, allowRepeat := false) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !HasMethod(callback, "Call")
                throw TypeError("A binding callback must be callable.")
            if label = "" || StrLen(label) > 120 || RegExMatch(label, "[\t\r\n]")
                || RegExMatch(keyName, "[\t\r\n]")
                throw ValueError("Invalid binding text.")
            if !IsInteger(modifiers) || modifiers < 0 || modifiers > 15
                throw ValueError("The modifier mask must be an integer from 0 to 15.")
            specification := {layer: StrLower(layerName), modifiers: modifiers,
                key: keyName, label: label, callback: callback, repeat: !!allowRepeat,
                remoteId: 0, state: "offline"}
            this.bindings.Push(specification)
            if this.session
                this.Register(specification)
            return specification
        }
        finally {
            Critical previousCritical
        }
    }

    Start(*) {
        if this.running
            return
        this.running := true
        this.Maintain()
        SetTimer(this.maintenanceHandler, 2000)
    }

    Stop(*) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            this.running := false
            SetTimer(this.maintenanceHandler, 0)
            if this.session && this.ServiceMatches()
                this.Request("BYE`t" this.session)
            this.ForgetConnection("disconnected")
        }
        finally {
            Critical previousCritical
        }
    }

    Reconnect(*) {
        this.Stop()
        this.Start()
    }

    Maintain(*) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !this.running
                return
            if this.session {
                if this.ServiceMatches() && this.Request("PING`t" this.session) = 1
                    return
                this.ForgetConnection("layer service unavailable")
            }
            hwnd := DllCall("FindWindowW", "ptr", 0, "str", this.endpointTitle, "ptr")
            if !hwnd
                return
            this.serviceHwnd := hwnd
            this.servicePid := this.WindowPid(hwnd)
            session := this.Request("HELLO`t1`t" this.name)
            if session <= 0 {
                this.serviceHwnd := 0
                this.servicePid := 0
                return
            }
            this.session := session
            this.Status("connected to Caps + Pause Layers")
            for specification in this.bindings {
                if this.Register(specification) = 0 {
                    this.ForgetConnection("registration timed out; waiting to reconnect")
                    break
                }
            }
        }
        finally {
            Critical previousCritical
        }
    }

    Register(specification) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            result := this.Request("BIND`t" this.session "`t" specification.layer
                . "`t" specification.modifiers "`t" specification.key "`t"
                . (specification.repeat ? "1" : "0") "`t" specification.label "`tglobal")
            if result > 0 {
                specification.remoteId := result
                specification.state := "active"
                this.remoteBindings[result] := specification
                this.Status("registered: " specification.label)
            } else {
                specification.remoteId := 0
                specification.state := result = -3 ? "conflict" : "unavailable"
                this.Status(specification.label ": " this.DescribeError(result))
            }
            return result
        }
        finally {
            Critical previousCritical
        }
    }

    Unbind(specification) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            remoteId := specification.remoteId
            if remoteId && this.session {
                result := this.Request("UNBIND`t" this.session "`t" remoteId)
                ; A timeout has an uncertain outcome; keep the local mapping intact
                ; until disconnect/lease recovery instead of reporting a false success.
                if result != 1
                    return false
            }
            if remoteId && this.active.Has(remoteId) {
                activePress := this.active[remoteId]
                this.active.Delete(remoteId)
                this.Invoke(specification, "cancel", activePress)
            }
            if remoteId && this.remoteBindings.Has(remoteId)
                this.remoteBindings.Delete(remoteId)
            for index, existing in this.bindings {
                if existing = specification {
                    this.bindings.RemoveAt(index)
                    break
                }
            }
            specification.remoteId := 0
            specification.state := "removed"
            return true
        }
        finally {
            Critical previousCritical
        }
    }

    ReceiveEvent(packedEvent, foregroundHwnd, messageId, receiverHwnd) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if receiverHwnd != this.hwnd || !this.session || !this.ServiceMatches()
                return
            packedEvent := packedEvent & 0xFFFFFFFF
            bindingId := packedEvent >> 4
            phaseNumber := packedEvent & 7
            if !this.remoteBindings.Has(bindingId) || phaseNumber < 1 || phaseNumber > 4
                return
            specification := this.remoteBindings[bindingId]
            ; Do not execute a delayed activation after a busy/suspended client resumes.
            ; Releases are never discarded by this age check.
            if phaseNumber <= 2 && A_EventInfo
                && ((A_TickCount - A_EventInfo) & 0xFFFFFFFF) > 500
                return
            if phaseNumber = 1 {
                if this.active.Has(bindingId)
                    return
                activePress := {foreground: foregroundHwnd, oneShot: (packedEvent & 8) != 0}
                this.active[bindingId] := activePress
                this.Invoke(specification, "down", activePress)
            } else if phaseNumber = 2 {
                if this.active.Has(bindingId)
                    this.Invoke(specification, "repeat", this.active[bindingId])
            } else if this.active.Has(bindingId) {
                activePress := this.active[bindingId]
                this.active.Delete(bindingId)
                this.Invoke(specification, phaseNumber = 3 ? "up" : "cancel", activePress)
            }
            return 0
        }
        finally {
            Critical previousCritical
        }
    }

    ForgetConnection(reason) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            oldActive := this.active
            oldBindings := this.remoteBindings
            this.active := Map()
            this.remoteBindings := Map()
            hadSession := this.session != 0
            this.session := 0
            this.serviceHwnd := 0
            this.servicePid := 0
            for bindingId, activePress in oldActive
                if oldBindings.Has(bindingId)
                    this.Invoke(oldBindings[bindingId], "cancel", activePress)
            for specification in this.bindings {
                specification.remoteId := 0
                specification.state := "offline"
            }
            if hadSession
                this.Status(reason)
        }
        finally {
            Critical previousCritical
        }
    }

    Invoke(specification, phase, activePress) {
        event := {phase: phase, foregroundHwnd: activePress.foreground,
            label: specification.label, layer: specification.layer,
            key: specification.key, modifiers: specification.modifiers,
            oneShot: activePress.oneShot}
        try specification.callback.Call(event)
        catch Error as failure {
            OutputDebug "CapsPauseClient callback failed: " failure.Message
            this.Status("callback failed: " specification.label " - " failure.Message)
        }
    }

    Status(text) {
        if HasMethod(this.statusCallback, "Call")
            try this.statusCallback.Call(text)
    }

    ServiceMatches() {
        return this.serviceHwnd && this.WindowPid(this.serviceHwnd) = this.servicePid
            && DllCall("FindWindowW", "ptr", 0, "str", this.endpointTitle, "ptr")
                = this.serviceHwnd
    }

    WindowPid(hwnd) {
        processId := 0
        if !DllCall("GetWindowThreadProcessId", "ptr", hwnd,
            "uint*", &processId, "uint")
            return 0
        return processId
    }

    Request(payload) {
        if !this.serviceHwnd
            return 0
        copyData := Buffer(3 * A_PtrSize, 0)
        NumPut("uptr", 0x43504C31, copyData, 0)
        NumPut("uint", (StrLen(payload) + 1) * 2, copyData, A_PtrSize)
        NumPut("ptr", StrPtr(payload), copyData, 2 * A_PtrSize)
        result := 0
        ; Bounded calls are for registration/heartbeats, never a HotIf predicate.
        ; Do not bypass UIPI: run cooperating scripts at the same integrity level.
        delivered := DllCall("SendMessageTimeoutW", "ptr", this.serviceHwnd,
            "uint", 0x004A, "uptr", this.hwnd, "ptr", copyData,
            "uint", 0x22, "uint", 200, "ptr*", &result, "ptr")
        if !delivered
            return 0
        result := result & 0xFFFFFFFF
        return result >= 0x80000000 ? result - 0x100000000 : result
    }

    DescribeError(code) {
        switch code {
            case 0: return "service did not answer (offline, busy, or elevation mismatch)"
            case -1: return "invalid protocol request"
            case -2: return "unsupported binding, reserved key, or key currently held"
            case -3: return "this layer/key/modifier combination is already registered"
            case -4: return "session expired; reconnect required"
            case -5: return "service resource limit reached"
            case -6: return "service rejected the request due to an internal error"
            default: return "unknown response: " code
        }
    }
}
