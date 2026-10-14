#Requires AutoHotkey v2.0

; Shared in-process manager. Parser, recorder, GUI and data codec retain upstream behavior.
; Runtime availability and explicit contexts do not overwrite saved assignments.

class Keybindings {
    static Version := "suite-preview.1"
    static Current := 0

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
        this.scopes := Map()
        this.observerGroups := Map()
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
        this.settingsButtonDrawCallback := ObjBindMethod(this, "_DrawSettingsButton")
        this.settingsDrawButtons := Map()
        this.warningButtons := Map()
        this.warningPaintCount := 0
        this.normalPaintCount := 0
        this.resetPaintCount := 0

        this.captureMouse := Map()
        this.observers := []
        this.firstRun := false
        this.releaseCallback := ObjBindMethod(this, "_CheckReleases")
        this.drainCallback := ObjBindMethod(this, "_Drain")
        Keybindings.Current := this
    }

    ; defaults: ["Caps + J", "Ctrl + Alt + F9"]
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
        scope := Keybindings.Option(options, "scope", "")
        scopeName := SubStr(scope, 1, 1) = "!" ? SubStr(scope, 2) : scope
        if scope != "" && !this.scopes.Has(scopeName)
            throw ValueError("Unknown input scope: " scope)
        this.actions[actionId] := {scope: scope,
            id: actionId, label: label, callback: callback, category: category,
            repeat: !!Keybindings.Option(options, "repeat", false),
            help: !!Keybindings.Option(options, "help", false),
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
        this.observerGroups.Clear()
        if IsObject(this.client)
            this.client.Dispose()
        Keybindings.Current := 0
    }

    ; Returns a defensive copy of the single saved configuration.
    GetConfiguration() => this._CloneConfiguration(this.configuration)

    ; Programmatic Apply() does not record user intent. Stored with the bindings.


    ; Read-only discovery for the future multi-script configuration window.
    ; The owning process remains authoritative for changes.
    static DisplayRows(participants, search := "") {
        rows := []
        search := StrLower(Trim(search))
        for participant in participants {
            grouped := Map()
            modules := Map()
            moduleOrder := []
            allCategories := Map()
            for action in participant.actions {
                if !action.enabled
                    continue
                allCategories[action.category] := true
                searchable := participant.name " " action.id " " action.category " " action.label
                for encoded in action.bindings {
                    parsed := Keybindings.Parse(encoded)
                    if IsObject(parsed)
                        searchable .= " " parsed.label
                }
                if search != "" && !InStr(StrLower(searchable), search)
                    continue
                if !grouped.Has(action.category) {
                    grouped[action.category] := []
                    split := InStr(action.category, " / ")
                    moduleName := split ? SubStr(action.category, 1, split - 1) : action.category
                    if !modules.Has(moduleName) {
                        modules[moduleName] := []
                        moduleOrder.Push(moduleName)
                    }
                    if split
                        modules[moduleName].Push(action.category)
                    else
                        modules[moduleName].InsertAt(1, action.category)
                }
                entry := {id: action.id, label: action.label,
                    ownerId: participant.id, setting: action,
                    editable: (participant.id = participants[1].id || participant.controlReady)}
                if HasProp(action, "help") && action.help
                    grouped[action.category].InsertAt(1, entry)
                else
                    grouped[action.category].Push(entry)
            }
            ; Put the compact Paper Pad section just below Global.
            ; Keep the remaining module order and all subcategories intact.
            orderedModules := []
            placed := Map()
            if participant.id = participants[1].id {
                for category in ["Global", "Paper Pad"] {
                    if modules.Has(category) {
                        orderedModules.Push(category)
                        placed[category] := true
                    }
                }
                for moduleId in SuiteSettings.ModuleOrder {
                    if moduleId = "scratchpad"
                        continue
                    moduleName := SuiteSettings.ModuleNames[moduleId]
                    if modules.Has(moduleName) && !placed.Has(moduleName) {
                        orderedModules.Push(moduleName)
                        placed[moduleName] := true
                    }
                }
            }
            for moduleName in moduleOrder {
                if !placed.Has(moduleName)
                    orderedModules.Push(moduleName)
            }
            for moduleName in orderedModules {
                ; An extension-only module still gets its main heading.
                if !grouped.Has(moduleName)
                    rows.Push({id: "", kind: "owner", label: moduleName, ownerId: participant.id})
                for category in modules[moduleName] {
                    heading := (InStr(category, " / ") || allCategories.Count > 1) ? category : participant.name
                    if participant.id != participants[1].id && !participant.controlReady
                        heading .= " (view only)"
                    rows.Push({id: "", kind: "owner", label: heading,
                        ownerId: participant.id})
                    for entry in grouped[category]
                        rows.Push(entry)
                }
            }
        }
        return rows
    }
    _LocalCatalogSnapshot() {
        result := []
        for actionId, action in this.actions {
            setting := this.configuration[actionId]
            if !setting.enabled || !this.IsAvailable(action)
                continue
            result.Push({id: actionId, label: action.label,
                category: action.category, enabled: true, help: action.help,
                bindings: setting.bindings.Clone()})
        }
        return result
    }



    Apply(configuration, acceptSavedConflicts := false) {
        if !this.running || this.disposed
            throw Error("Start the manager before applying configuration.")
        this._Commit(configuration, true, acceptSavedConflicts)
    }

    ; history in the SAME atomic manifest write as the shortcut configuration.
    ; Non-interactive Apply() intentionally never marks explicit user intent.
    ApplyEdited(configuration, actionIds, acceptSavedConflicts := false) {
        if !(actionIds is Array)
            throw TypeError("Edited action IDs must be an array.")
        for actionId in actionIds {
            Keybindings.Id(actionId)
            if !this.actions.Has(actionId)
                throw ValueError("Unknown keybinding action: " actionId)
        }
        if !this.running || this.disposed
            throw Error("Start the manager before applying configuration.")
        this._Commit(configuration, true, acceptSavedConflicts, actionIds)
    }

    ; Consumers can pause inputs for a module selector or power transition
    ; without erasing enabled flags, releasing registry ownership or restarting.
    SetPaused(paused := true) {
        if this.disposed
            return
        this.paused := !!paused
        if this.running
            this._RefreshGate()
    }

    GetStatus() {
        result := []
        for route in this.routes {
            state := route.state
            if IsObject(route.specification)
                state := route.specification.state
            result.Push({actionId: route.action.id, label: route.action.label,
                slot: route.slot, binding: route.binding.label, state: state})
        }
        return result
    }

    ; =========================================================================
    ; binding grammar and normalization (no hotkeys or file I/O)
    ; =========================================================================

    static Parse(text) {
        if Type(text) != "String"
            throw TypeError("A keybinding must be text.")
        text := Trim(text)
        if text = ""
            return 0
        if StrLen(text) > 140 || RegExMatch(text, "[\t\r\n]")
            throw ValueError("Invalid keybinding text.")
        layer := "normal"
        mask := 0
        keyName := ""
        if RegExMatch(text, "i)^(normal|caps|pause)\|([0-9]{1,2})\|([a-z0-9]+)$", &stored) {
            layer := StrLower(stored[1])
            mask := Integer(stored[2])
            keyName := stored[3]
            if mask > 15
                throw ValueError("Invalid saved modifier mask.")
        } else if RegExMatch(text, "^([\^!+#]+)([^\s+]+)$", &native) {
            for symbol in StrSplit(native[1]) {
                bit := InStr("^!+#", symbol)
                value := 1 << (bit - 1)
                if mask & value
                    throw ValueError("Repeated modifier.")
                mask |= value
            }
            keyName := native[2]
        } else {
            parts := StrSplit(text, "+")
            for index, part in parts {
                part := Trim(part)
                if part = ""
                    throw ValueError("Use a key name/scan code, not a literal + character.")
                lower := StrLower(part)
                if index = parts.Length {
                    keyName := part
                    break
                }
                if lower = "caps" || lower = "capslock" || lower = "pause" {
                    if layer != "normal"
                        throw ValueError("Only one CapsLock/Pause layer can be selected.")
                    layer := lower = "pause" ? "pause" : "caps"
                } else {
                    modifiers := Map("ctrl", 1, "control", 1, "alt", 2, "shift", 4, "win", 8)
                    if !modifiers.Has(lower) || mask & modifiers[lower]
                        throw ValueError("Use Ctrl, Alt, Shift or Win once before the base key.")
                    mask |= modifiers[lower]
                }
            }
        }
        key := Keybindings._BaseKey(keyName)
        if layer != "normal" && key.activation
            throw ValueError("A layer activation key cannot also be its suffix.")
        ; An accidental global click binding could make Windows unusable.
        if key.mouse && (key.code = "LButton" || key.code = "RButton")
            throw ValueError("Left and right mouse buttons cannot be assigned as hotkeys.")
        if layer != "normal" && key.mouse
            throw ValueError("Layer protocol 1 supports keyboard suffixes only. Use an ordinary mouse binding.")
        if (mask = 3 && key.vk = 0x2E) || ((mask & 8) && key.vk = 0x4C)
            throw ValueError("Ctrl + Alt + Delete and Win + L are reserved by Windows.")
        prefix := layer = "caps" ? "Caps + " : layer = "pause" ? "Pause + " : ""
        for bit, name in Map(1, "Ctrl", 2, "Alt", 4, "Shift", 8, "Win")
            if mask & bit
                prefix .= name " + "
        return {layer: layer, modifiers: mask, key: key.code, mouse: key.mouse, activationKey: key.activation,
            wheel: key.wheel, label: prefix key.label,
            signature: layer "|" mask "|" StrLower(key.code)}
    }

    ; Bare middle-button and wheel shortcuts are allowed only after a GUI
    ; confirmation. Preserve compatibility with deliberate saved bindings.
    static NeedsMouseConfirmation(binding) {
        return IsObject(binding) && binding.mouse && binding.modifiers = 0
            && (binding.key = "MButton" || binding.wheel)
    }

    static _MouseCaptureCancels(mouseName) => mouseName = "LButton" || mouseName = "RButton"

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

    static ConflictingSignature(binding, index) {
        ; Normal routes are gated while a local layer is active: they do not overlap.
        return index.Has(binding.signature) ? binding.signature : ""
    }

    static ModifierMask() {
        return (GetKeyState("Ctrl", "P") ? 1 : 0)
            | (GetKeyState("Alt", "P") ? 2 : 0)
            | (GetKeyState("Shift", "P") ? 4 : 0)
            | ((GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) ? 8 : 0)
    }

    static Symbols(mask) {
        result := ""
        for bit, symbol in Map(1, "^", 2, "!", 4, "+", 8, "#")
            if mask & bit
                result .= symbol
        return result
    }

    static Option(options, name, fallback) => HasProp(options, name) ? options.%name% : fallback

    static Id(text) {
        if Type(text) != "String" || !RegExMatch(text, "^[a-z0-9][a-z0-9_.-]{0,63}$")
            throw ValueError("IDs must use lowercase ASCII letters, numbers, dots, hyphens or underscores.")
        if RegExMatch(text, "i)^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)")
            throw ValueError("This ID is a reserved Windows filename.")
    }

    static Text(text, limit) {
        if Type(text) != "String" || text = "" || StrLen(text) > limit
            || RegExMatch(text, "[\t\r\n]")
            throw ValueError("Invalid label text.")
    }

    static Hash(text) {
        value := 2166136261
        loop parse text
            value := ((value ^ Ord(A_LoopField)) * 16777619) & 0xFFFFFFFF
        return value
    }

    _NormalizeSlots(bindings) {
        if !(bindings is Array) || bindings.Length > 2
            throw ValueError("This preview supports two binding slots per action.")
        result := ["", ""]
        for index, text in bindings {
            binding := Keybindings.Parse(text)
            result[index] := IsObject(binding) ? binding.signature : ""
        }
        return result
    }

    _CloneConfiguration(source) {
        result := Map()
        for actionId, setting in source
            result[actionId] := {enabled: setting.enabled, bindings: setting.bindings.Clone()}
        return result
    }

    _DefaultConfiguration() {
        result := Map()
        for actionId, action in this.actions
            result[actionId] := {enabled: action.defaultEnabled, bindings: action.defaults.Clone()}
        return result
    }

    ; =========================================================================
    ; data-only manifests and cooperative conflict arbitration
    ; =========================================================================

    _Load() {
        this.firstRun := !FileExist(this.path)
        this.document := KB_Manifest.Read(this.path)
        if !this.firstRun && !this.document.Count
            throw Error("The existing settings file is empty or damaged; it was not overwritten.")
        if this.document.Count {
            KB_Manifest.Validate(this.document)
            if KB_Manifest.Get(this.document, "meta", "id") != this.id
                throw Error("Settings owner mismatch; the file was not modified.")
        }
        this.configuration := this._DefaultConfiguration()
        ; Migrate the previously selected profile. Never guess which of the two
        ; legacy profiles mattered, and never overwrite a damaged saved value.
        section := "bindings"
        if !this.document.Has(section) {
            legacyProfile := KB_Manifest.Get(this.document, "meta", "profile", "standalone")
            section := "profile:" legacyProfile
        }
        for actionId, action in this.actions {
            value := KB_Manifest.Get(this.document, section, actionId, "")
            if value = ""
                continue
            fields := StrSplit(value, "`t")
            if fields.Length != 3 || (fields[1] != "0" && fields[1] != "1")
                throw Error("Invalid saved settings for " actionId "; nothing was overwritten.")
            this.configuration[actionId] := {enabled: fields[1] = "1",
                bindings: this._NormalizeSlots([fields[2], fields[3]])}
        }
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
                            . " and " route.action.label ". No hotkeys were changed.")
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

    _MakeDocument(configuration, routes, explicitEdits := 0) {
        document := Map("meta", Map("schema", "1", "id", this.id, "name", this.name),
            "bindings", Map())
        for actionId, setting in configuration
            document["bindings"][actionId] := (setting.enabled ? "1" : "0")
                . "`t" setting.bindings[1] "`t" setting.bindings[2]
        return document
    }

    static Join(items, separator) {
        result := ""
        for index, item in items
            result .= (index = 1 ? "" : separator) item
        return result
    }

    ; =========================================================================
    ; ordinary hotkeys, guarded releases and optional layer adapter
    ; =========================================================================

    _Deactivate() {
        for route in this.routes {
            route.enabled := false
            if route.token
                this._QueueEvent(route, "cancel", route.foreground, route.oneShot)
        }
        for key, press in this.pressed
            press.finished := true
        if IsObject(this.client) {
            this.client.Stop()
            for specification in this.client.bindings.Clone()
                this.client.Unbind(specification)
        }
        this.routeMap := Map()
    }

    _Activate() {
        this.externalCapture := IsObject(this.recording)
        this._RefreshGate()
        this.routeMap := Map()
        for route in this.routes {
            ; Conflict state is a rejected claim, not merely a disabled native key.
            if InStr(route.state, "unavailable:") = 1
                continue
            route.enabled := true
            route.specification := 0
            route.token := 0
            binding := route.binding
            if !this.routeMap.Has(binding.signature)
                this.routeMap[binding.signature] := []
            this.routeMap[binding.signature].Push(route)
            try {
                if binding.layer = "normal" {
                    this._EnsureVariant(binding)
                    route.state := "active"
                    if !binding.wheel && GetKeyState(binding.key, "P")
                        this.blocked[binding.key] := true
                } else if IsObject(this.client) {
                    route.specification := this.client.Bind(binding.layer, binding.modifiers,
                        binding.key, route.action.label, ObjBindMethod(this, "_LayerEvent", route),
                        route.action.repeat, ObjBindMethod(this, "ContextActive", route.action))
                    route.state := "offline"
                } else {
                    route.state := "unavailable: no layer adapter"
                }
            }
            catch Error as registrationError {
                route.enabled := false
                route.state := "error: " registrationError.Message
                this._Report(route.action.label ": " registrationError.Message)
            }
        }
        this._UpdateReleaseTimer()
        this._RefreshGate()
        if IsObject(this.client) && !this.gated && this.running
            this.client.Start()
    }

    _EnsureVariant(binding) {
        key := binding.key
        if !binding.wheel && !this.groups.Has(key) {
            predicate := ObjBindMethod(this, "_GuardEligible", key)
            HotIf predicate
            try {
                Hotkey("$*" key, ObjBindMethod(this, "_GuardDown", key), "On I100 B0")
                Hotkey("$*" key " Up", ObjBindMethod(this, "_KeyUp", key), "On I100 B0")
            }
            finally HotIf()
            this.groups[key] := predicate
        }
        signature := binding.signature
        if this.variants.Has(signature)
            return
        if this.variants.Count >= 4096
            throw Error("Too many distinct native hotkey variants; reload the script.")
        predicate := ObjBindMethod(this, "_Eligible", signature)
        HotIf predicate
        try Hotkey("$" Keybindings.Symbols(binding.modifiers) key,
            ObjBindMethod(this, "_KeyDown", signature), "On I100 B0")
        finally HotIf()
        ; HotIf owns predicate references for the process lifetime. Reuse them on
        ; every edit instead of leaking another variant for the same shortcut.
        this.variants[signature] := predicate
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

    _GuardEligible(key, *) => this.running && this.pressed.Has(key)

    _KeyDown(signature, *) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !this._Eligible(signature)
                return
            route := this._SelectedRoute(signature)
            if !IsObject(route)
                return
            key := route.binding.key
            if this.pressed.Has(key) {
                this._GuardDown(key)
                return
            }
            foreground := DllCall("GetForegroundWindow", "ptr")
            if !route.binding.wheel {
                this.pressed[key] := {route: route, finished: false}
                this._UpdateReleaseTimer()
            }
            this._QueueEvent(route, "down", foreground, false)
            ; Wheel input has no physical key-up. Each wheel step is a complete
            ; activation, regardless of whether the action allows key repeat.
            if route.binding.wheel
                this._QueueEvent(route, "up", foreground, false)
        }
        finally Critical previousCritical
    }

    _GuardDown(key, *) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !this.pressed.Has(key)
                return
            press := this.pressed[key]
            route := press.route
            if press.finished
                return
            if this.gated || !route.enabled || this.applying
                || Keybindings.ModifierMask() != route.binding.modifiers
                || !this.ContextActive(route.action)
                || (IsObject(this.client) && this.client.OwnsInput(key)) {
                press.finished := true
                this._QueueEvent(route, "cancel", route.foreground, false)
            } else if route.action.repeat {
                this._QueueEvent(route, "repeat", route.foreground, false)
            }
        }
        finally Critical previousCritical
    }

    _KeyUp(key, *) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if !this.pressed.Has(key)
                return
            press := this.pressed[key]
            if !press.finished
                this._QueueEvent(press.route, "up", press.route.foreground, false)
            this.pressed.Delete(key)
            this._UpdateReleaseTimer()
        }
        finally Critical previousCritical
    }

    _CheckReleases() {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            for key in this.blocked.Clone()
                if !GetKeyState(key, "P")
                    this.blocked.Delete(key)
            for key, press in this.pressed.Clone() {
                if !GetKeyState(key, "P") {
                    this._KeyUp(key)
                } else if !press.finished && (this.gated || !press.route.enabled
                    || this.applying || Keybindings.ModifierMask() != press.route.binding.modifiers
                    || !this.ContextActive(press.route.action)
                    || (IsObject(this.client) && this.client.OwnsInput(key))) {
                    press.finished := true
                    this._QueueEvent(press.route, "cancel", press.route.foreground, false)
                }
            }
            this._UpdateReleaseTimer()
        }
        finally Critical previousCritical
    }

    _UpdateReleaseTimer() {
        SetTimer(this.releaseCallback, this.running && (this.pressed.Count || this.blocked.Count) ? 15 : 0)
    }

    _LayerEvent(route, event) {
        if (event.phase = "down" || event.phase = "repeat")
            && (!this.running || this.gated || this.applying || !route.enabled
                || !this.ContextActive(route.action))
            return
        this._QueueEvent(route, event.phase, event.foregroundHwnd, event.oneShot)
    }

    _QueueEvent(route, phase, foreground, oneShot) {
        previousCritical := A_IsCritical
        Critical "On"
        try {
            if phase = "down" {
                if route.token || this.queue.Length >= 256
                    return
                route.token := ++this.nextToken
                route.foreground := foreground
                route.oneShot := oneShot
            } else if !route.token {
                return
            }
            token := route.token
            if phase = "up" || phase = "cancel"
                route.token := 0
            if phase = "repeat" && this.queue.Length >= 128
                return
            event := {phase: phase, actionId: route.action.id, label: route.action.label,
                slot: route.slot, binding: route.binding.label, layer: route.binding.layer,
                key: route.binding.key, modifiers: route.binding.modifiers,
                foregroundHwnd: foreground, oneShot: oneShot}
            this.queue.Push({route: route, event: event, token: token, tick: A_TickCount})
            if this.running && !this.dispatching
                SetTimer(this.drainCallback, -1)
        }
        finally Critical previousCritical
    }

    _Drain() {
        if this.dispatching || !this.running
            return
        this.dispatching := true
        try {
            loop 32 {
                if !this.queue.Length || !this.running
                    break
                item := this.queue.RemoveAt(1)
                phase := item.event.phase
                if phase = "down" {
                    if this.gated || this.applying || !item.route.enabled
                        || ((A_TickCount - item.tick) & 0xFFFFFFFF) > 500
                        continue
                    this.delivered[item.token] := item
                } else {
                    if !this.delivered.Has(item.token)
                        continue
                    if phase = "up" || phase = "cancel"
                        this.delivered.Delete(item.token)
                }
                this._Invoke(item.route, item.event)
            }
        }
        finally {
            this.dispatching := false
            if this.queue.Length && this.running
                SetTimer(this.drainCallback, -1)
        }
    }

    _Invoke(route, event) {
        try route.action.callback.Call(event)
        catch Error as failure
            SuiteState.Log.Error(route.action.category, failure)
    }

    _Report(text) {
        OutputDebug "Keybindings [" this.id "]: " text
        if HasMethod(this.statusCallback, "Call")
            try this.statusCallback.Call(text)
    }

    _RefreshGate() {
        gated := this.paused || IsObject(this.settings) || this.externalCapture || !this.running
        if gated = this.gated
            return
        this.gated := gated
        if gated {
            for route in this.routes
                if route.token
                    this._QueueEvent(route, "cancel", route.foreground, route.oneShot)
            for key, press in this.pressed
                press.finished := true
            if IsObject(this.client)
                this.client.Stop()
        } else {
            ; Never activate a new shortcut halfway through a key which was
            ; already held while capture/settings temporarily disabled input.
            for route in this.routes
                if route.binding.layer = "normal" && !route.binding.wheel
                    && GetKeyState(route.binding.key, "P")
                    this.blocked[route.binding.key] := true
            this._UpdateReleaseTimer()
            if IsObject(this.client)
                this.client.Start()
        }
    }





    ; =========================================================================
    ; category-based, immediately saved keybinding screen
    ; =========================================================================

    _SettingsTitle() {
        if IsObject(SuiteState.App) && !SuiteState.App.ModuleActive("keyboard-layers")
            return "Keybindings — Secret Keys disabled"

        capsActive := IsObject(this.client) && this.client.LayerEnabled("caps")
        pauseActive := IsObject(this.client) && this.client.LayerEnabled("pause")
        if !capsActive && !pauseActive
            return "Keybindings — CapsLock and Pause layers disabled"
        if !capsActive
            return "Keybindings — CapsLock layer disabled"
        if !pauseActive
            return "Keybindings — Pause layer disabled"
        return "Keybindings"
    }

    ShowSettings(*) {
        if !this.running
            throw Error("Start the keybinding manager first.")
        if IsObject(this.settings) {
            this.settings.Show()
            return
        }

        this.participants := this.DiscoverParticipants()
        this.settingsWindowWidth := 820
        this.settingsWindowHeight := Min(860, Max(560, A_ScreenHeight - 125))

        window := SuiteGui("+Resize +MinSize820x520 +0x02000000", this._SettingsTitle())
        this.settings := window
        this._SetSettingsIcons(window)
        this._RefreshGate()
        ; Use the same regular weight as the rest of the suite.
        window.SetFont("s10 w400", "Cascadia Mono")
        this.settingsSearch := window.AddEdit("x210 y13 w400 vsearch")
        DllCall("SendMessageW", "ptr", this.settingsSearch.Hwnd, "uint", 0x1501,
            "uptr", 1, "str", "search... (right-click a binding to type a hotkey)", "ptr")
        this.settingsSearch.OnEvent("Change", ObjBindMethod(this, "_SearchChanged"))
        this.settingsRowPool := []
        this.visibleRows := []
        this.settingsDrawButtons := Map()
        this.warningButtons := Map()
        OnMessage(0x004E, this.settingsButtonDrawCallback) ; WM_NOTIFY / NM_CUSTOMDRAW
        this.settingsScroll := window.AddCustom("ClassScrollBar x778 y48 w24 h140 +0x1")
        this.settingsDivider := window.AddText("x22 y300 w752 h2 +0x10", "")
        this.settingsResetAll := window.AddButton("x244 y320 w180 h31", "Restore defaults")
        this.settingsDrawButtons[this.settingsResetAll.Hwnd] := "reset"
        this.settingsResetAll.OnEvent("Click", ObjBindMethod(this, "_ResetAll"))
        this.settingsDone := window.AddButton("x438 y320 w130 h31", "done")
        this.settingsDrawButtons[this.settingsDone.Hwnd] := "done"
        this.settingsDone.OnEvent("Click", ObjBindMethod(this, "_RequestCloseSettings"))
        window.OnEvent("Size", ObjBindMethod(this, "_ResizeSettings"))
        window.OnEvent("ContextMenu", ObjBindMethod(this, "_EditBindingText"))
        window.OnEvent("Close", ObjBindMethod(this, "_RequestCloseSettings"))
        window.OnEvent("Escape", ObjBindMethod(this, "_RequestCloseSettings"))
        this.scrollPosition := 0
        this.settingsResizing := false
        this.settingsRenderedWidth := 0
        this.settingsRenderedHeight := 0
        SuiteShowCentered(window, this.settingsWindowWidth, this.settingsWindowHeight,
            ObjBindMethod(this, "_ResizeSettings"))
        OnMessage(0x020A, this.wheelCallback)
        this.wheelHookActive := true
        OnMessage(0x0115, this.verticalScrollCallback)
        this.verticalScrollHookActive := true
    }

    _AddSettingsRow() {
        index := this.settingsRowPool.Length + 1
        window := this.settings
        title := window.AddText("Hidden x22 y48 w290 h25", "")
        categoryTitle := window.AddText("Hidden x22 y48 w752 h25 Center", "")
        primary := window.AddButton("Hidden x358 y48 w167 h29", "unbound")
        secondary := window.AddButton("Hidden x535 y48 w153 h29", "unbound")
        reset := window.AddButton("Hidden x698 y48 w76 h29", "reset")
        this.settingsDrawButtons[primary.Hwnd] := "binding"
        this.settingsDrawButtons[secondary.Hwnd] := "binding"
        this.settingsDrawButtons[reset.Hwnd] := "reset"
        primary.OnEvent("Click", ObjBindMethod(this, "_BeginRecording", index, 1))
        secondary.OnEvent("Click", ObjBindMethod(this, "_BeginRecording", index, 2))
        reset.OnEvent("Click", ObjBindMethod(this, "_ResetAction", index))
        this.settingsRowPool.Push({title: title, categoryTitle: categoryTitle,
            primary: primary, secondary: secondary, reset: reset, actionId: ""})
    }

    _ResizeSettings(window, minMax, width, height) {
        if !IsObject(this.settings) || this.settings != window || minMax = -1
            return
        SuiteSizeGrip.Move(window, minMax)
        if this.settingsResizing
            return
        width := Max(820, width)
        height := Max(320, height)
        widthChanged := width != this.settingsRenderedWidth
        heightChanged := height != this.settingsRenderedHeight
        rowCount := Min(128, Max(4, Floor((height - 120) / 35)))
        rowsChanged := rowCount != this.visibleRows.Length
        if !widthChanged && !heightChanged && !rowsChanged
            return

        this.settingsResizing := true
        redrawSuspended := false
        try {
            if minMax = 0 {
                this.settingsWindowWidth := width
                this.settingsWindowHeight := height
            }
            positions := []
            if rowsChanged {
                ; Only suspend painting when controls are created or shown/hidden.
                SendMessage(0x000B, 0, 0, , window.Hwnd) ; WM_SETREDRAW
                redrawSuspended := true
                while this.settingsRowPool.Length < rowCount
                    this._AddSettingsRow()
                this.visibleRows := []
                for index, row in this.settingsRowPool {
                    if index > rowCount {
                        row.title.Visible := false
                        row.categoryTitle.Visible := false
                        row.primary.Visible := false
                        row.secondary.Visible := false
                        row.reset.Visible := false
                    } else
                        this.visibleRows.Push(row)
                }
            }

            if widthChanged {
                extraWidth := width - 820
                searchWidth := 400 + Min(200, Floor(extraWidth * 0.5))
                positions.Push({control: this.settingsSearch,
                    x: Floor((width - searchWidth) / 2), y: 13, w: searchWidth, h: 23})
            }

            if widthChanged || rowsChanged {
                extraWidth := width - 820
                originalPrimaryX := 323 + Floor(extraWidth * 0.48)
                originalPrimaryWidth := 185 + Floor(extraWidth * 0.28)
                originalSecondaryWidth := 170 + extraWidth
                    - (originalPrimaryX - 323) - (originalPrimaryWidth - 185)
                primaryWidth := Round(originalPrimaryWidth * 0.9)
                secondaryWidth := Round(originalSecondaryWidth * 0.9)
                resetX := width - 122
                secondaryX := resetX - secondaryWidth - 10
                primaryX := secondaryX - primaryWidth - 10
                for index, row in this.visibleRows {
                    y := 48 + (index - 1) * 35
                    positions.Push({control: row.title,
                        x: 22, y: y + 6, w: primaryX - 33, h: 25})
                    positions.Push({control: row.categoryTitle,
                        x: 22, y: y + 6, w: width - 68, h: 25})
                    positions.Push({control: row.primary,
                        x: primaryX, y: y, w: primaryWidth, h: 29})
                    positions.Push({control: row.secondary,
                        x: secondaryX, y: y, w: secondaryWidth, h: 29})
                    positions.Push({control: row.reset,
                        x: resetX, y: y, w: 76, h: 29})
                }
                positions.Push({control: this.settingsScroll,
                    x: width - 42, y: 48, w: 24, h: rowCount * 35})
            }

            if widthChanged || heightChanged {
                positions.Push({control: this.settingsDivider,
                    x: 22, y: height - 64, w: width - 68, h: 2})
                footerX := Floor(width / 2) - 166
                positions.Push({control: this.settingsResetAll,
                    x: footerX, y: height - 49, w: 180, h: 31})
                positions.Push({control: this.settingsDone,
                    x: footerX + 194, y: height - 49, w: 130, h: 31})
            }
            this._MoveSettingsControls(window, positions, width)
            if rowsChanged
                this._RenderSettings()
            this.settingsRenderedWidth := width
            this.settingsRenderedHeight := height
        }
        finally {
            if redrawSuspended {
                SendMessage(0x000B, 1, 0, , window.Hwnd)
                DllCall("RedrawWindow", "ptr", window.Hwnd, "ptr", 0, "ptr", 0,
                    "uint", 0x185, "int") ; invalidate, erase and refresh child controls once
            }
            this.settingsResizing := false
        }
    }

    _MoveSettingsControls(window, positions, logicalWidth) {
        if !positions.Length
            return
        rect := Buffer(16, 0)
        if !DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", rect, "int")
            throw OSError(A_LastError, "GetClientRect")
        physicalWidth := NumGet(rect, 8, "int")
        window.GetClientPos(, , &currentLogicalWidth)
        scale := physicalWidth / currentLogicalWidth
        if currentLogicalWidth <= 0 || scale <= 0
            throw Error("Invalid Keybindings display scale.")

        try {
            batch := DllCall("BeginDeferWindowPos", "int", positions.Length, "ptr")
            if !batch
                throw OSError(A_LastError, "BeginDeferWindowPos")
            for item in positions {
                batch := DllCall("DeferWindowPos", "ptr", batch, "ptr", item.control.Hwnd,
                    "ptr", 0, "int", Round(item.x * scale), "int", Round(item.y * scale),
                    "int", Round(item.w * scale), "int", Round(item.h * scale),
                    "uint", 0x114, "ptr") ; no Z-order/activation/pixel-copy
                if !batch
                    throw OSError(A_LastError, "DeferWindowPos")
            }
            if !DllCall("EndDeferWindowPos", "ptr", batch, "int")
                throw OSError(A_LastError, "EndDeferWindowPos")
        }
        catch Error as failure {
            SuiteState.Log.Error("Keybindings / resize batch", failure)
            for item in positions
                item.control.Move(item.x, item.y, item.w, item.h)
        }
    }

    _SetSettingsIcons(window) {
        SuiteIcons.Apply(window)
    }

    _SearchChanged(*) {
        this.scrollPosition := 0
        this.wheelRemainder := 0
        this._RenderSettings()
    }

    _WheelSettings(wParam, lParam, messageId, receiverHwnd) {
        if !IsObject(this.settings) || IsObject(this.recording)
            return
        ; Handle only wheel messages for this GUI or its child controls.
        if receiverHwnd != this.settings.Hwnd
            && DllCall("GetAncestor", "ptr", receiverHwnd, "uint", 2, "ptr") != this.settings.Hwnd
            return
        ; Windows can deliver the wheel to the focused control even when the
        ; pointer is elsewhere. Never scroll a window behind the cursor.
        MouseGetPos(, , &hoverWindow)
        if hoverWindow != this.settings.Hwnd
            return

        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        if maximum = 0
            return 0
        ; Wheel delta is a signed 16-bit number in the high word of wParam.
        wheelDelta := (wParam >> 16) & 0xFFFF
        if wheelDelta >= 0x8000
            wheelDelta -= 0x10000
        this.wheelRemainder += wheelDelta
        wheelSteps := Floor(Abs(this.wheelRemainder) / 120)
        if wheelSteps = 0
            return 0
        wheelDirection := this.wheelRemainder > 0 ? -1 : 1
        this.wheelRemainder += wheelDirection * wheelSteps * 120
        this.scrollPosition := Min(Max(this.scrollPosition + wheelDirection * wheelSteps * 3,
            0), maximum)
        this._RenderSettings()
        return 0
    }

    _VerticalScrollSettings(wParam, lParam, messageId, receiverHwnd) {
        if !IsObject(this.settings) || receiverHwnd != this.settings.Hwnd
            || lParam != this.settingsScroll.Hwnd
            return
        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        scrollCommand := wParam & 0xFFFF
        nextPosition := this.scrollPosition
        switch scrollCommand {
            case 0: nextPosition -= 1             ; SB_LINEUP
            case 1: nextPosition += 1             ; SB_LINEDOWN
            case 2: nextPosition -= this.visibleRows.Length ; SB_PAGEUP
            case 3: nextPosition += this.visibleRows.Length ; SB_PAGEDOWN
            case 4, 5:                           ; SB_THUMBPOSITION / SB_THUMBTRACK
                scrollInfo := Buffer(28, 0)
                NumPut("uint", 28, scrollInfo, 0)
                NumPut("uint", 0x10, scrollInfo, 4) ; SIF_TRACKPOS
                if DllCall("GetScrollInfo", "ptr", lParam, "int", 2,
                    "ptr", scrollInfo, "int")
                    nextPosition := NumGet(scrollInfo, 24, "int")
            case 6: nextPosition := 0             ; SB_TOP
            case 7: nextPosition := maximum       ; SB_BOTTOM
            default: return 0                    ; SB_ENDSCROLL / unknown
        }
        nextPosition := Min(Max(nextPosition, 0), maximum)
        if nextPosition = this.scrollPosition
            return 0
        this.scrollPosition := nextPosition
        this._RenderSettings()
        return 0
    }

    _RenderSettings(*) {
        if !IsObject(this.settings)
            return
        this.settings.Title := this._SettingsTitle()
        this.warningButtons := Map()
        search := this.settings["search"].Value
        this.participants[1].actions := this._LocalCatalogSnapshot()
        this.rows := Keybindings.DisplayRows(this.participants, search)
        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        this.scrollPosition := Min(Max(this.scrollPosition, 0), maximum)
        this.settingsScroll.Visible := maximum > 0
        ; SCROLLINFO controls both the actual offset and the proportional thumb.
        ; nMax is the final row index, and nPage is the visible row count.
        scrollInfo := Buffer(28, 0)
        NumPut("uint", 28, scrollInfo, 0)
        NumPut("uint", 0x7, scrollInfo, 4) ; SIF_RANGE | SIF_PAGE | SIF_POS
        NumPut("int", 0, scrollInfo, 8)
        NumPut("int", Max(0, this.rows.Length - 1), scrollInfo, 12)
        NumPut("uint", this.visibleRows.Length, scrollInfo, 16)
        NumPut("int", this.scrollPosition, scrollInfo, 20)
        DllCall("SetScrollInfo", "ptr", this.settingsScroll.Hwnd, "int", 2,
            "ptr", scrollInfo, "int", true, "int")
        for index, row in this.visibleRows {
            position := this.scrollPosition + index
            visible := position <= this.rows.Length
            entry := visible ? this.rows[position] : 0
            isAction := visible && entry.id != ""
            isLocal := isAction && entry.ownerId = this.id
            editable := isAction && entry.editable
            row.actionId := editable ? entry.id : ""
            row.ownerId := isAction ? entry.ownerId : ""
            row.title.Visible := isAction
            row.categoryTitle.Visible := visible && !isAction
            row.primary.Visible := isAction
            row.secondary.Visible := isAction
            row.reset.Visible := isLocal
            if !visible
                continue
            if !isAction {
                row.categoryTitle.Text := entry.label = "Global" ? "★ Global ★" : entry.label
                continue
            }
            row.title.Text := entry.label
            row.primary.Enabled := editable
            row.secondary.Enabled := editable
            setting := isLocal ? this.configuration[entry.id] : entry.setting
            for slot, control in [row.primary, row.secondary] {
                parsed := Keybindings.Parse(setting.bindings[slot])
                if !IsObject(parsed) {
                    control.Text := "+ add"
                    continue
                }
                inactiveLayer := parsed.layer != "normal" && this.BindingUnavailable(parsed) != ""
                if inactiveLayer
                    this.warningButtons[control.Hwnd] := true
                control.Text := (inactiveLayer ? "⚠ " : "") parsed.label
            }
            if isLocal {
                defaults := this.actions[entry.id].defaults
                row.reset.Enabled := setting.bindings[1] != defaults[1]
                    || setting.bindings[2] != defaults[2]
            }
        }
    }

    _DrawSettingsButton(wParam, lParam, messageId, receiverHwnd) {
        if !IsObject(this.settings) || receiverHwnd != this.settings.Hwnd
            || !this.settingsDrawButtons.Has(NumGet(lParam, 0, "ptr"))
            || NumGet(lParam, 16, "int") != -12 ; NM_CUSTOMDRAW
            || NumGet(lParam, 24, "uint") != 1 ; CDDS_PREPAINT
            return

        hwnd := NumGet(lParam, 0, "ptr")
        hdc := NumGet(lParam, 32, "ptr")
        state := NumGet(lParam, 64, "uint")
        bounds := Buffer(16, 0)
        DllCall("RtlMoveMemory", "ptr", bounds, "ptr", lParam + 40, "uptr", 16)
        pressed := !!(state & 0x1) ; CDIS_SELECTED
        hovered := !!(state & 0x40) ; CDIS_HOT
        enabled := !!DllCall("IsWindowEnabled", "ptr", hwnd, "int")
        kind := this.warningButtons.Has(hwnd) ? "warning" : this.settingsDrawButtons[hwnd]

        ; Shortcut, reset and Done controls use the same crisp, square frame.
        ; Only unavailable layer assignments receive the amber palette.
        if kind = "warning" {
            fillColor := pressed ? 0xA7D8FF : hovered ? 0xBCE5FF : 0xD9F0FF
            frameColor := 0x2D8EB9
            textColor := 0x234566
        } else if kind = "reset" {
            fillColor := pressed ? 0xDBDBDB : hovered ? 0xE9E9E9 : 0xF5F5F5
            frameColor := 0xCDCDCD
            textColor := enabled ? 0x666666 : 0xB0B0B0
        } else {
            fillColor := pressed ? 0xE5E5E5 : hovered ? 0xF5F5F5 : 0xFFFFFF
            frameColor := 0xC9C9C9
            textColor := enabled ? 0x202020 : 0x999999
        }

        fillBrush := DllCall("CreateSolidBrush", "uint", fillColor, "ptr")
        frameBrush := DllCall("CreateSolidBrush", "uint", frameColor, "ptr")
        if !fillBrush || !frameBrush {
            if fillBrush
                DllCall("DeleteObject", "ptr", fillBrush)
            if frameBrush
                DllCall("DeleteObject", "ptr", frameBrush)
            return
        }
        try {
            DllCall("FillRect", "ptr", hdc, "ptr", bounds, "ptr", fillBrush, "int")
            DllCall("FrameRect", "ptr", hdc, "ptr", bounds, "ptr", frameBrush, "int")
            inner := Buffer(16, 0)
            DllCall("RtlMoveMemory", "ptr", inner, "ptr", bounds, "uptr", 16)
            DllCall("InflateRect", "ptr", inner, "int", -5, "int", -3, "int")
            length := DllCall("GetWindowTextLengthW", "ptr", hwnd, "int")
            label := Buffer((length + 1) * 2, 0)
            DllCall("GetWindowTextW", "ptr", hwnd, "ptr", label,
                "int", length + 1, "int")
            font := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x31,
                "uptr", 0, "ptr", 0, "ptr") ; WM_GETFONT
            originalFont := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
            originalMode := DllCall("SetBkMode", "ptr", hdc, "int", 1, "int")
            originalText := DllCall("SetTextColor", "ptr", hdc, "uint", textColor, "uint")
            try DllCall("DrawTextW", "ptr", hdc, "ptr", label, "int", -1,
                "ptr", inner, "uint", 0x8825, "int") ; centered, no accelerator
            finally {
                DllCall("SetTextColor", "ptr", hdc, "uint", originalText)
                DllCall("SetBkMode", "ptr", hdc, "int", originalMode)
                if originalFont
                    DllCall("SelectObject", "ptr", hdc, "ptr", originalFont)
            }
            if state & 0x10 ; CDIS_FOCUS
                DllCall("DrawFocusRect", "ptr", hdc, "ptr", inner, "int")
            if kind = "warning"
                this.warningPaintCount += 1
            else if kind = "reset"
                this.resetPaintCount += 1
            else
                this.normalPaintCount += 1
        }
        finally {
            DllCall("DeleteObject", "ptr", fillBrush)
            DllCall("DeleteObject", "ptr", frameBrush)
        }
        return 4 ; CDRF_SKIPDEFAULT
    }

    _ResetAction(index, *) {
        if index > this.visibleRows.Length
            return
        actionId := this.visibleRows[index].actionId
        if actionId = ""
            return
        configuration := this.GetConfiguration()
        configuration[actionId].bindings := this.actions[actionId].defaults.Clone()
        this._SaveConfiguration(configuration, [actionId])
    }

    _ResetAll(*) {
        if MsgBox("Restore default hotkey assignments for all actions, including disabled modules?"
            . "`n`nModule settings and Paper Pad notes will not change.",
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

    _RequestCloseSettings(*) {
        if IsObject(this.recording) {
            this._EndRecording()
            return
        }
        this._CloseSettings()
    }

    _CloseSettings(*) {
        this._EndRecording()
        OnMessage(0x004E, this.settingsButtonDrawCallback, 0)
        this.settingsDrawButtons := Map()
        this.warningButtons := Map()
        if this.wheelHookActive {
            OnMessage(0x020A, this.wheelCallback, 0)
            this.wheelHookActive := false
        }
        if this.verticalScrollHookActive {
            OnMessage(0x0115, this.verticalScrollCallback, 0)
            this.verticalScrollHookActive := false
        }
        this.wheelRemainder := 0
        if IsObject(this.settings) {
            SuiteSizeGrip.Detach(this.settings)
            this.settings.Destroy()
        }
        for iconHandle in this.settingsIcons
            DllCall("DestroyIcon", "ptr", iconHandle)
        this.settingsIcons := []
        this.settings := 0
        this.participants := []
        this._RefreshGate()
    }

    ; =========================================================================
    ; direct keyboard and mouse capture (no second editor window)
    ; =========================================================================

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

    _RecordMouse(mouseName, *) {
        if !IsObject(this.recording)
            return
        ; Either primary mouse button is a safe, no-save cancel gesture.
        ; Handle it before the focus check so clicking outside also cancels.
        if Keybindings._MouseCaptureCancels(mouseName) {
            this._EndRecording()
            return
        }
        if !WinActive("ahk_id " this.settings.Hwnd) {
            this._EndRecording()
            return
        }
        if this.recording.pending != ""
            return
        this._StageRecordedBinding(this._CaptureLayer(), Keybindings.ModifierMask(), mouseName, "")
    }

    _StageRecordedBinding(layer, modifiers, key, waitKey) {
        try {
            binding := Keybindings.Parse(layer "|" modifiers "|" key)
            this.recording.pending := binding.signature
            this.recording.pendingKey := waitKey
            this.recording.button.Text := binding.label " ..."
            ; The periodic release watcher also handles wheel-only input.
        }
        catch Error as captureError {
            this._EndRecording()
            MsgBox(captureError.Message, this.name " - unsupported binding", "Icon!")
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
            && MsgBox("This hotkey intercepts ordinary middle-click or mouse-wheel input. Assign it?",
                this.name, "YesNo Default2 Icon!") != "Yes"
            return
        configuration := this.GetConfiguration()
        configuration[actionId].bindings[slot] := value
        this._SaveConfiguration(configuration)
    }

    _RecordingTimedOut(*) => this._EndRecording()

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



    IsAvailable(action) {
        return HasMethod(action.available, "Call") ? !!action.available.Call() : !!action.available
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

    DiscoverParticipants() {
        return [{id: this.id, name: this.name, alive: true, controlReady: true,
            actions: this._LocalCatalogSnapshot()}]
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
                input := InputBox("Type a hotkey, for example CapsLock, Escape, or Ctrl + Alt + J."
                    . "`nLeave empty to clear. Layer hotkeys remain editable when their layers are disabled.",
                    "Edit hotkey", "w550 h170", IsObject(old) ? old.label : "")
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

    RegisterScope(name, predicate) {
        if this.running || !HasMethod(predicate, "Call") || this.scopes.Has(name)
            throw Error("Define each input scope once before starting Keybindings.")
        Keybindings.Id(name)
        this.scopes[name] := predicate
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
}

class KB_SavedConflict extends Error {
}

; =============================================================================
; private data codec - UTF-8 INI-style text, parsed here (no executable settings)
; =============================================================================

class KB_Manifest {
    static Get(document, section, key, fallback := "") {
        return document.Has(section) && document[section].Has(key)
            ? document[section][key] : fallback
    }

    static Read(path) {
        if !FileExist(path)
            return Map()
        if FileGetSize(path) > 2 * 1024 * 1024
            throw Error("Keybinding manifest exceeds the size limit: " path)
        return this.Decode(FileRead(path, "UTF-8"))
    }

    static Decode(text) {
        result := Map()
        section := ""
        text := LTrim(text, Chr(0xFEFF))
        loop parse text, "`n", "`r" {
            line := A_LoopField
            if line = "" || SubStr(line, 1, 1) = ";"
                continue
            if RegExMatch(line, "^\[([^\[\]\t\r\n]+)\]$", &match) {
                section := match[1]
                if result.Has(section)
                    throw Error("Duplicate manifest section: " section)
                result[section] := Map()
                continue
            }
            equal := InStr(line, "=")
            if section = "" || equal <= 1
                throw Error("Malformed keybinding manifest; it was not overwritten.")
            key := SubStr(line, 1, equal - 1)
            if result[section].Has(key)
                throw Error("Duplicate manifest key: " key)
            result[section][key] := SubStr(line, equal + 1)
        }
        return result
    }

    static Validate(document) {
        if this.Get(document, "meta", "schema") != "1"
            throw Error("Unknown or damaged keybinding registry schema; no bindings were claimed.")
        Keybindings.Id(this.Get(document, "meta", "id"))
        Keybindings.Text(this.Get(document, "meta", "name"), 100)
    }

    static Encode(document) {
        text := "; keybindings schema 1 - UTF-8; edit through the configuration window`n"
        for section, rows in document {
            if RegExMatch(section, "[\[\]\t\r\n]")
                throw ValueError("Invalid manifest section.")
            text .= "`n[" section "]`n"
            for key, value in rows {
                if key = "" || RegExMatch(key, "[=\t\r\n]") || RegExMatch(value, "[\r\n]")
                    throw ValueError("Invalid manifest field.")
                text .= key "=" value "`n"
            }
        }
        return text
    }

    static WriteAtomic(path, document) {
        temporary := path ".tmp-" DllCall("GetCurrentProcessId", "uint") "-" Random(1, 0x7FFFFFFF)
        stream := 0
        try {
            stream := FileOpen(temporary, "w", "UTF-8")
            if !IsObject(stream)
                throw OSError(A_LastError, "FileOpen")
            content := this.Encode(document)
            if stream.Write(content) != StrPut(content, "UTF-8") - 1
                throw Error("The settings write was incomplete; the previous file was retained.")
            ; Accessing Handle flushes AHK's buffer before the Windows flush.
            if !DllCall("FlushFileBuffers", "ptr", stream.Handle, "int")
                throw OSError(A_LastError, "FlushFileBuffers")
            stream.Close()
            stream := 0
            ; Same-directory replacement: readers see the old or complete new
            ; snapshot, never half of an IniWrite sequence. Do not delete first.
            if !DllCall("MoveFileExW", "str", temporary, "str", path, "uint", 0x9, "int")
                throw OSError(A_LastError, "MoveFileExW")
        }
        finally {
            if IsObject(stream)
                stream.Close()
            if FileExist(temporary)
                try FileDelete temporary
        }
    }
}
