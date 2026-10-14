class KeybindingPatch {
    RegisterScope(name, predicate) {
        if this.running || !HasMethod(predicate, "Call") || this.scopes.Has(name)
            throw Error("Define each input scope once before starting Keybindings.")
        Keybindings.Id(name)
        this.scopes[name] := predicate
    }

    ContextActive(action) {
        if action.scope != "" {
            inverse := SubStr(action.scope, 1, 1) = "!"
            name := inverse ? SubStr(action.scope, 2) : action.scope
            active := !!this.scopes[name].Call()
            if active = inverse
                return false
        }
        return !HasMethod(action.context, "Call") || !!action.context.Call()
    }

    static DisjointScopes(first, second) {
        ; Only a registered predicate and its exact complement may share a key.
        ; Arbitrary context callbacks are not proof that two actions cannot overlap.
        return first != "" && second != "" && (first = "!" second || second = "!" first)
    }

    BindingUnavailable(binding) {
        if binding.layer != "normal"
            return !IsObject(this.client) || !this.client.LayerEnabled(binding.layer)
                ? "unavailable: " binding.layer " layer is disabled" : ""
        return binding.activationKey && IsObject(this.client) && this.client.OwnsPrefix(binding.key)
            ? "unavailable: this key is owned by Secret Keys" : ""
    }

    _SelectedRoute(signature) {
        if !this.routeMap.Has(signature)
            return 0
        for route in this.routeMap[signature]
            if route.enabled && this.ContextActive(route.action)
                return route
        return 0
    }

    _Commit(configuration, strict := true, acceptSaved := false, explicitEdits := 0) {
        if this.applying
            throw Error("A keybinding update is already in progress.")
        candidate := this._CandidateRoutes(configuration)
        seen := Map()
        for route in candidate.routes {
            unavailable := this.BindingUnavailable(route.binding)
            if unavailable != "" {
                route.state := unavailable
                continue
            }
            signature := route.binding.signature
            if seen.Has(signature) {
                for previous in seen[signature]
                    if !Keybindings.DisjointScopes(previous.action.scope, route.action.scope)
                        throw Error(route.binding.label " conflicts with " previous.action.label
                            . " and " route.action.label ". No shortcuts were changed.")
            } else
                seen[signature] := []
            seen[signature].Push(route)
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

    _Eligible(signature, *) {
        if !this.running || this.gated || this.applying
            return false
        route := this._SelectedRoute(signature)
        if !IsObject(route)
            return false
        if IsObject(this.client) && this.client.OwnsInput(route.binding.key)
            return false
        return !this.blocked.Has(route.binding.key)
            && Keybindings.ModifierMask() = route.binding.modifiers
    }

    _SetSettingsIcons(window) {
        SuiteIcons.Apply(window)
    }

    Observe(key, context, callback, releaseGuard := false) {
        if !HasMethod(context, "Call") || !HasMethod(callback, "Call")
            throw TypeError("Input observers require callable predicates and callbacks.")
        ; AHK chooses one matching variant, not every variant. Fan out identical
        ; passive observations so one module cannot hide another module's click.
        if !this.observerGroups.Has(key) {
            group := {key: key, callbacks: [], predicate: ObjBindMethod(this, "_ObserverEligible", key)}
            this.observerGroups[key] := group
            HotIf group.predicate
            try Hotkey(key, ObjBindMethod(this, "_DispatchObserver", key), "On I100 B0")
            finally HotIf()
            this.observers.Push(group)
        }
        this.observerGroups[key].callbacks.Push({context: context, callback: callback, releaseGuard: releaseGuard})
    }

    _ObserverEligible(key, *) {
        if !this.running || !this.observerGroups.Has(key)
            return false
        for item in this.observerGroups[key].callbacks
            if (item.releaseGuard || !this.gated) && item.context.Call()
                return true
        return false
    }

    _DispatchObserver(key, *) {
        if !this.running || !this.observerGroups.Has(key)
            return
        for item in this.observerGroups[key].callbacks {
            if (item.releaseGuard || !this.gated) && item.context.Call() {
                try item.callback.Call()
                catch Error as failure
                    SuiteState.Log.Error("Core / input observer", failure)
            }
        }
    }

    _CaptureLayer() {
        if IsObject(this.client) {
            if this.client.LayerEnabled("caps") && GetKeyState("CapsLock", "P")
                return "caps"
            if this.client.LayerEnabled("pause") && (GetKeyState("Pause", "P") || GetKeyState("CtrlBreak", "P"))
                return "pause"
        }
        return "normal"
    }

    _RecordKey(hook, vk, sc) {
        if !IsObject(this.recording)
            return
        if !WinActive("ahk_id " this.settings.Hwnd) {
            this._EndRecording()
            return
        }
        layer := this._CaptureLayer()
        bare := layer = "normal" && Keybindings.ModifierMask() = 0
        if vk = 0x1B && bare {
            this._EndRecording()
            return
        }
        key := vk = 0x13 || vk = 3 ? Format("vk{:02X}", vk)
            : sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        if (vk = 0x08 || vk = 0x2E) && bare {
            this.recording.pending := "CLEAR"
            this.recording.pendingKey := key
            this.recording.clearing := true
            this.recording.button.Text := "unbound ..."
            return
        }
        if vk = 0x10 || vk = 0x11 || vk = 0x12 || (vk >= 0xA0 && vk <= 0xA5)
            || vk = 0x5B || vk = 0x5C
            return
        if IsObject(this.client) && this.client.OwnsPrefix(key)
            return
        if this.recording.pending = ""
            this._StageRecordedBinding(layer, Keybindings.ModifierMask(), key, key)
    }
}
