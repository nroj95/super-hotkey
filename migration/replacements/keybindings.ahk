; Replacement methods for the one-time Keybindings migration; not included at runtime.
class KeybindingsMigration {
    __New(ownerId, displayName, options := {}) {
        Keybindings.Id(ownerId)
        Keybindings.Text(displayName, 100)
        if IsObject(Keybindings.Current)
            throw Error("Only one Keybindings manager is allowed in the suite.")
        this.id := ownerId
        this.name := displayName
        this.root := RTrim(Keybindings.Option(options, "directory", ""), "\/")
        if !RegExMatch(this.root, "i)^(?:[a-z]:\\|\\\\)")
            throw ValueError("Use an absolute Windows settings directory.")
        this.path := this.root "\" ownerId ".ini"
        this.layerFactory := Keybindings.Option(options, "layerFactory", 0)
        this.statusCallback := Keybindings.Option(options, "statusCallback", 0)
        this.actions := Map()
        this.configuration := Map()
        this.document := Map()
        this.routes := []
        this.routeMap := Map()
        this.variants := Map()
        this.groups := Map()
        this.pressed := Map()
        this.blocked := Map()
        this.queue := []
        this.delivered := Map()
        this.nextToken := 0
        this.dispatching := false
        this.running := false
        this.applying := false
        this.disposed := false
        this.settings := 0
        this.settingsIcons := []
        this.client := 0
        this.recording := 0
        this.externalCapture := false
        this.paused := false
        this.gated := false
        this.rows := []
        this.visibleRows := []
        this.scrollPosition := 0
        this.wheelRemainder := 0
        this.wheelCallback := ObjBindMethod(this, "_WheelSettings")
        this.wheelHookActive := false
        this.verticalScrollCallback := ObjBindMethod(this, "_VerticalScrollSettings")
        this.verticalScrollHookActive := false
        this.captureMouse := Map()
        this.observers := []
        this.firstRun := false
        this.releaseCallback := ObjBindMethod(this, "_CheckReleases")
        this.drainCallback := ObjBindMethod(this, "_Drain")
        Keybindings.Current := this
    }

    AddAction(actionId, label, callback, defaults := 0, options := {}) {
        if this.running || this.disposed
            throw Error("Define actions before Start().")
        Keybindings.Id(actionId)
        Keybindings.Text(label, 120)
        if this.actions.Has(actionId) || this.actions.Count >= 128
            throw ValueError("Duplicate action ID or too many actions.")
        if !HasMethod(callback, "Call")
            throw TypeError("An action callback must be callable.")
        category := Keybindings.Option(options, "category", "General")
        Keybindings.Text(category, 80)
        this.actions[actionId] := {
            id: actionId, label: label, callback: callback, category: category,
            repeat: !!Keybindings.Option(options, "repeat", false),
            defaultEnabled: !!Keybindings.Option(options, "enabled", true),
            trackEdits: false,
            available: Keybindings.Option(options, "available", true),
            context: Keybindings.Option(options, "context", 0),
            defaults: this._NormalizeSlots(IsObject(defaults) ? defaults : [])
        }
        return this
    }

    Start() {
        if this.running
            return this
        if this.disposed
            throw Error("Reload the suite to restart a stopped manager.")
        DirCreate this.root
        this._Load()
        if HasMethod(this.layerFactory, "Call")
            this.client := this.layerFactory.Call(this.name, this.statusCallback)
        this.running := true
        ; A rejected configuration leaves the editor usable, with no active inputs.
        this._Commit(this.configuration, true, false)
        this._Report("keybindings ready")
        return this
    }

    Stop(*) {
        if this.disposed
            return
        this.running := false
        this.disposed := true
        this._EndRecording()
        this._CloseSettings()
        SetTimer(this.releaseCallback, 0)
        SetTimer(this.drainCallback, 0)
        this._Deactivate()
        for token, item in this.delivered.Clone() {
            this.delivered.Delete(token)
            event := item.event.Clone()
            event.phase := "cancel"
            this._Invoke(item.route, event)
        }
        this.queue := []
        this.pressed.Clear()
        this.blocked.Clear()
        for observer in this.observers {
            HotIf observer.predicate
            try Hotkey(observer.key, "Off")
            finally HotIf()
        }
        this.observers := []
        if IsObject(this.client)
            this.client.Dispose()
        Keybindings.Current := 0
    }

    IsAvailable(action) {
        return HasMethod(action.available, "Call") ? !!action.available.Call() : !!action.available
    }

    ContextActive(action) {
        return !HasMethod(action.context, "Call") || !!action.context.Call()
    }

    DiscoverParticipants() {
        return [{id: this.id, name: this.name, alive: true, controlReady: true,
            actions: this._LocalCatalogSnapshot()}]
    }

    _LocalCatalogSnapshot() {
        result := []
        for actionId, action in this.actions {
            setting := this.configuration[actionId]
            inactive := !setting.enabled || !this.IsAvailable(action)
            result.Push({id: actionId, label: action.label,
                category: action.category (inactive ? " (disabled)" : ""),
                enabled: true, bindings: setting.bindings.Clone()})
        }
        return result
    }

    _CandidateRoutes(configuration) {
        normalized := Map()
        routes := []
        for actionId, action in this.actions {
            if !configuration.Has(actionId)
                throw ValueError("Missing action settings: " actionId)
            setting := configuration[actionId]
            slots := this._NormalizeSlots(setting.bindings)
            normalized[actionId] := {enabled: !!setting.enabled, bindings: slots}
            if !setting.enabled || !this.IsAvailable(action)
                continue
            for slot, text in slots {
                binding := Keybindings.Parse(text)
                if IsObject(binding)
                    routes.Push({action: action, slot: slot, binding: binding, enabled: false,
                        state: "pending", specification: 0, token: 0, foreground: 0, oneShot: false})
            }
        }
        return {configuration: normalized, routes: routes}
    }

    _Commit(configuration, strict := true, acceptSaved := false, explicitEdits := 0) {
        if this.applying
            throw Error("A keybinding update is already in progress.")
        candidate := this._CandidateRoutes(configuration)
        seen := Map()
        ; Validate every effective binding before touching the existing runtime.
        for route in candidate.routes {
            if route.binding.layer != "normal" && !IsObject(this.client) {
                route.state := "unavailable: keyboard layers are disabled"
                continue
            }
            if route.binding.activationKey && IsObject(this.client) {
                route.state := "unavailable: this key is owned by keyboard layers"
                continue
            }
            signature := route.binding.signature
            if seen.Has(signature)
                throw Error(route.binding.label " conflicts with " seen[signature]
                    . " and " route.action.label ". No shortcuts were changed.")
            seen[signature] := route.action.label
        }
        oldRoutes := this.routes
        oldConfiguration := this.configuration
        oldDocument := this.document
        published := false
        this.applying := true
        try {
            this._Deactivate()
            document := this._MakeDocument(candidate.configuration, candidate.routes)
            KB_Manifest.WriteAtomic(this.path, document)
            published := true
            this.configuration := candidate.configuration
            this.document := document
            this.routes := candidate.routes
            this._Activate()
        }
        catch Error as failure {
            if !published {
                this.routes := oldRoutes
                this.configuration := oldConfiguration
                this.document := oldDocument
                this._Activate()
            }
            throw failure
        }
        finally this.applying := false
    }

    _MakeDocument(configuration, routes, explicitEdits := 0) {
        document := Map("meta", Map("schema", "1", "id", this.id, "name", this.name),
            "bindings", Map())
        for actionId, setting in configuration
            document["bindings"][actionId] := (setting.enabled ? "1" : "0")
                . "`t" setting.bindings[1] "`t" setting.bindings[2]
        return document
    }

    static ConflictingSignature(binding, index) {
        ; Normal routes are gated while a local layer is active: they do not overlap.
        return index.Has(binding.signature) ? binding.signature : ""
    }

    static _BaseKey(name) {
        if name = "" || StrLen(name) > 32 || RegExMatch(name, "[\s{}&~*$<>!^#+|]")
            throw ValueError("Use a base key name or scNNN.")
        mouseNames := Map("lbutton", "LButton", "rbutton", "RButton", "mbutton", "MButton",
            "xbutton1", "XButton1", "xbutton2", "XButton2", "wheelup", "WheelUp",
            "wheeldown", "WheelDown", "wheelleft", "WheelLeft", "wheelright", "WheelRight")
        if mouseNames.Has(StrLower(name)) {
            code := mouseNames[StrLower(name)]
            return {code: code, label: code, vk: 0, mouse: true,
                wheel: InStr(code, "Wheel") = 1, activation: false}
        }
        if RegExMatch(name, "i)^sc([0-9a-f]{3})$", &match) {
            scan := Integer("0x" match[1])
            if scan = 0 || scan > 0x1FF
                throw ValueError("Invalid scan code.")
            vk := GetKeyVK(name)
        } else {
            normalized := GetKeyName(name)
            vk := GetKeyVK(normalized)
            scan := GetKeySC(normalized)
            if !vk && !scan
                throw ValueError("Unknown key: " name)
        }
        if vk = 1 || vk = 2 || vk = 4 || vk = 5 || vk = 6
            throw ValueError("Use a named mouse button.")
        if vk = 0x10 || vk = 0x11 || vk = 0x12 || (vk >= 0xA0 && vk <= 0xA5)
            || vk = 0x5B || vk = 0x5C || RegExMatch(name, "i)^Joy")
            throw ValueError("A modifier cannot be the base key.")
        activation := vk = 0x14 || vk = 0x13 || vk = 3
        ; Pause/Break have unusual scan sequences; keep their native VK identities.
        code := vk = 0x13 || vk = 3 ? Format("vk{:02X}", vk)
            : scan ? Format("sc{:03X}", scan) : Format("vk{:02X}", vk)
        friendly := GetKeyName(code)
        if friendly = ""
            friendly := code
        if StrLen(friendly) = 1
            friendly := StrUpper(friendly)
        return {code: code, label: friendly, vk: vk, mouse: false, wheel: false,
            activation: activation}
    }

    _Eligible(signature, *) {
        if !this.running || this.gated || this.applying || !this.routeMap.Has(signature)
            return false
        route := this.routeMap[signature]
        if IsObject(this.client) && this.client.OwnsInput(route.binding.key)
            return false
        return route.enabled && !this.blocked.Has(route.binding.key)
            && Keybindings.ModifierMask() = route.binding.modifiers && this.ContextActive(route.action)
    }

    _LayerEvent(route, event) {
        if (event.phase = "down" || event.phase = "repeat")
            && (!this.running || this.gated || this.applying || !route.enabled
                || !this.ContextActive(route.action))
            return
        this._QueueEvent(route, event.phase, event.foregroundHwnd, event.oneShot)
    }

    _Invoke(route, event) {
        try route.action.callback.Call(event)
        catch Error as failure
            SuiteState.Log.Error(route.action.category, failure)
    }

    Observe(key, context, callback, releaseGuard := false) {
        predicate := (*) => this.running && (releaseGuard || !this.gated) && context.Call()
        HotIf predicate
        try Hotkey(key, callback, "On I100 B0")
        finally HotIf()
        this.observers.Push({key: key, predicate: predicate})
    }

    _ResetAll(*) {
        if MsgBox("Restore the original assignments for every action, including disabled modules?"
            . "`n`nModule settings and Scratchpad notes will not change.",
            this.name, "YesNo Default2 Icon?") != "Yes"
            return
        configuration := this.GetConfiguration()
        for actionId, action in this.actions
            configuration[actionId].bindings := action.defaults.Clone()
        this._SaveConfiguration(configuration)
    }

    _SaveConfiguration(configuration, editedActions := 0) {
        try {
            this.Apply(configuration)
            this._Report("keybinding changes saved")
            this._RenderSettings()
            return true
        }
        catch Error as failure {
            SuiteState.Log.Error("Keybindings", failure)
            MsgBox(failure.Message, this.name " - binding rejected", "Icon!")
            return false
        }
    }

    _BeginRecording(index, slot, *) {
        if IsObject(this.recording) || !IsObject(this.settings)
            return
        actionId := this.visibleRows[index].actionId
        if actionId = ""
            return
        record := {hook: 0, pending: "", pendingKey: "", clearing: false,
            actionId: actionId, slot: slot,
            finish: ObjBindMethod(this, "_FinishRecordedKey"),
            timeout: ObjBindMethod(this, "_RecordingTimedOut")}
        this.recording := record
        try {
            this.externalCapture := true
            this._RefreshGate()
            record.button := slot = 1 ? this.visibleRows[index].primary : this.visibleRows[index].secondary
            record.button.Text := "press keys..."
            hook := InputHook("L0 I101")
            hook.KeyOpt("{All}", "SN")
            hook.OnKeyDown := ObjBindMethod(this, "_RecordKey")
            record.hook := hook
            hook.Start()
            HotIf()
            for mouseName in ["LButton", "RButton", "MButton", "XButton1", "XButton2",
                "WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
                hotkeyName := "$*" mouseName
                Hotkey(hotkeyName, ObjBindMethod(this, "_RecordMouse", mouseName), "On I100 B0")
                this.captureMouse[hotkeyName] := true
            }
            SetTimer(record.finish, 25)
            SetTimer(record.timeout, -10000)
        }
        catch Error as failure {
            this._EndRecording()
            SuiteState.Log.Error("Keybindings", failure)
            MsgBox(failure.Message, this.name " - could not record", "Icon!")
        }
    }

    _FinishRecordedKey(*) {
        if !IsObject(this.recording)
            return
        record := this.recording
        if !IsObject(this.settings) || !WinActive("ahk_id " this.settings.Hwnd) {
            this._EndRecording()
            return
        }
        if record.pending = "" || (record.pendingKey != "" && GetKeyState(record.pendingKey, "P"))
            return
        if Keybindings.ModifierMask() || GetKeyState("CapsLock", "P")
            || GetKeyState("Pause", "P") || GetKeyState("CtrlBreak", "P")
            return
        value := record.clearing ? "" : record.pending
        actionId := record.actionId
        slot := record.slot
        this._EndRecording()
        if Keybindings.NeedsMouseConfirmation(Keybindings.Parse(value))
            && MsgBox("This shortcut intercepts ordinary middle-click or mouse-wheel input. Assign it?",
                this.name, "YesNo Default2 Icon!") != "Yes"
            return
        configuration := this.GetConfiguration()
        configuration[actionId].bindings[slot] := value
        this._SaveConfiguration(configuration)
    }

    _EndRecording(*) {
        if !IsObject(this.recording)
            return
        record := this.recording
        this.recording := 0
        SetTimer(record.finish, 0)
        SetTimer(record.timeout, 0)
        if IsObject(record.hook)
            record.hook.Stop()
        HotIf()
        for hotkeyName in this.captureMouse
            Hotkey(hotkeyName, "Off")
        this.captureMouse.Clear()
        this.externalCapture := false
        this._RefreshGate()
        this._RenderSettings()
    }

    _EditBindingText(window, control, *) {
        if !IsObject(control) || IsObject(this.recording)
            return
        for row in this.visibleRows {
            if row.actionId = ""
                continue
            for slot, button in [row.primary, row.secondary] {
                if button.Hwnd != control.Hwnd
                    continue
                configuration := this.GetConfiguration()
                old := Keybindings.Parse(configuration[row.actionId].bindings[slot])
                input := InputBox("Type a shortcut, for example CapsLock, Escape, or Ctrl + Alt + J."
                    . "`nLeave empty to clear. Layer shortcuts remain editable when layers are disabled.",
                    "Edit shortcut", "w550 h170", IsObject(old) ? old.label : "")
                if input.Result != "OK"
                    return
                try parsed := Keybindings.Parse(input.Value)
                catch Error as failure {
                    MsgBox(failure.Message, this.name, "Icon!")
                    return
                }
                if Keybindings.NeedsMouseConfirmation(parsed)
                    && MsgBox("Intercept ordinary middle-click or mouse-wheel input?", this.name,
                        "YesNo Default2 Icon!") != "Yes"
                    return
                configuration[row.actionId].bindings[slot] := input.Value
                this._SaveConfiguration(configuration)
                return
            }
        }
    }
}
