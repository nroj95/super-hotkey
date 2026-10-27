#Requires AutoHotkey v2.0

; The suite's single hotkey manager: action catalog, binding grammar, saved
; assignments and native dispatch. Availability and contexts never rewrite
; saved assignments.

class Keybindings {
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
        this.disjointPairs := Map()
        this.migrations := []
        this.loadWarnings := []
        this.observerGroups := Map()
        this.actions := Map()
        ; Maps enumerate by key; the editor lists actions in registration order.
        this.actionOrder := []
        this.configuration := Map()
        this.document := Map()
        this.routes := []
        this.routeMap := Map()
        this.layerKeys := Map()
        this.variants := Map()
        this.groups := Map()
        this.pressed := Map()
        this.blocked := Map()
        this.queue := []
        this.delivered := Map()
        this.nextToken := 0
        this.cancelledThroughToken := 0
        this.dispatching := false
        this.running := false
        this.applying := false
        this.disposed := false
        this.client := 0
        this.externalCapture := false
        this.paused := false
        this.gated := false
        this.observers := []
        this.releaseCallback := ObjBindMethod(this, "_CheckReleases")
        this.drainCallback := ObjBindMethod(this, "_Drain")
        this.editor := KeybindingsEditor(this)
        Keybindings.Current := this
    }

    ; defaults: ["Caps + J", "Ctrl + Alt + F9"]. The editor lists actions in the
    ; order they are added, grouped by category.
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
            defaultEnabled: !!Keybindings.Option(options, "enabled", true),
            available: Keybindings.Option(options, "available", true),
            context: Keybindings.Option(options, "context", 0),
            defaults: this._NormalizeSlots(IsObject(defaults) ? defaults : [])
        }
        this.actionOrder.Push(this.actions[actionId])
        return this
    }

    Start() {
        if this.running
            return this
        if this.disposed
            throw Error("Reload the suite to restart a stopped manager.")
        DirCreate this.root
        this._Load()
        ; The layer client (Secret Layers) owns the CapsLock/Pause prefixes.
        if HasMethod(this.layerFactory, "Call")
            this.client := this.layerFactory.Call(this)
        this.running := true
        ; A rejected configuration leaves the editor usable, with no active inputs.
        this._Commit(this.configuration)
        this._Report("keybindings ready")
        return this
    }

    Stop(*) {
        if this.disposed
            return
        this.running := false
        this.disposed := true
        this.editor.Close()
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

    ; Editor rows in registration order: each module heading is followed by
    ; its own category, then its " / " subcategories.
    static DisplayRows(actions, search := "") {
        search := StrLower(Trim(search))
        grouped := Map()
        sections := Map()
        sectionOrder := []
        for action in actions {
            searchable := action.id " " action.category " " action.label
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
                section := split ? SubStr(action.category, 1, split - 1) : action.category
                if !sections.Has(section) {
                    sections[section] := []
                    sectionOrder.Push(section)
                }
                if split
                    sections[section].Push(action.category)
                else
                    sections[section].InsertAt(1, action.category)
            }
            grouped[action.category].Push({id: action.id, label: action.label, scope: action.scope})
        }
        rows := []
        for section in sectionOrder {
            ; A subcategory-only match still shows its module heading.
            if !grouped.Has(section)
                rows.Push({id: "", label: section})
            for category in sections[section] {
                rows.Push({id: "", label: category})
                for entry in grouped[category]
                    rows.Push(entry)
            }
        }
        return rows
    }

    _ActionInSettingsModule(actionId, moduleId) {
        if moduleId = ""
            return true
        moduleName := SuiteSettings.ModuleNames[moduleId]
        category := this.actions[actionId].category
        return category = moduleName || InStr(category, moduleName " / ") = 1
    }

    ; Enabled, currently available actions in registration order.
    Catalog(configuration := unset, moduleId := "") {
        result := []
        settings := IsSet(configuration) ? configuration : this.configuration
        for action in this.actionOrder {
            setting := settings[action.id]
            if !setting.enabled || !this.IsAvailable(action)
                || !this._ActionInSettingsModule(action.id, moduleId)
                continue
            result.Push({id: action.id, label: action.label, category: action.category,
                scope: action.scope, bindings: setting.bindings.Clone()})
        }
        return result
    }

    Apply(configuration) {
        if !this.running || this.disposed
            throw Error("Start the manager before applying configuration.")
        this._Commit(configuration)
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
        ; 'Caps + Caps' is a deliberate second tap, not a held layer chord.
        if layer = "caps" && StrLower(keyName) = "caps"
            keyName := "CapsLock"
        key := Keybindings._BaseKey(keyName)
        doubleTap := (layer = "caps" && key.vk = 0x14)
            || (layer = "pause" && key.vk = 0x13)
        if layer != "normal" && key.activation && !doubleTap
            throw ValueError("A different layer activation key cannot be its suffix.")
        if doubleTap && mask
            throw ValueError("Layer double-taps cannot include Ctrl, Alt, Shift or Win.")
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
            wheel: key.wheel, doubleTap: doubleTap,
            label: doubleTap ? (layer = "caps" ? "Caps + Caps" : "Pause + Pause") : prefix key.label,
            signature: layer "|" mask "|" StrLower(key.code)}
    }

    ; Bare middle-button and wheel shortcuts are allowed only after a GUI
    ; confirmation. Preserve compatibility with deliberate saved bindings.
    static NeedsMouseConfirmation(binding) {
        return IsObject(binding) && binding.mouse && binding.modifiers = 0
            && (binding.key = "MButton" || binding.wheel)
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

    ; Damaged entries fall back to defaults only after preserving the original.
    ; A failed backup stops recovery so a later save cannot destroy that file.
    _Load() {
        this.loadWarnings := []
        this.configuration := this._DefaultConfiguration()
        this.document := Map()
        if !FileExist(this.path)
            return
        try {
            document := KB_Manifest.Read(this.path)
            if !document.Count
                throw Error("The file is empty.")
            KB_Manifest.Validate(document)
            if KB_Manifest.Get(document, "meta", "id") != this.id
                throw Error("The file belongs to another program.")
            if !document.Has("bindings")
                throw Error("The [bindings] section is missing.")
        }
        catch Error as failure {
            this._KeepDamagedFile("The saved keybindings could not be read: " failure.Message
                . "`nDefault hotkeys are active.")
            return
        }
        this.document := document
        unreadable := []
        for actionId, action in this.actions {
            value := KB_Manifest.Get(document, "bindings", actionId, "")
            if value = ""
                continue
            try {
                fields := StrSplit(value, "`t")
                if fields.Length != 3 || (fields[1] != "0" && fields[1] != "1")
                    throw Error("Unreadable entry.")
                this.configuration[actionId] := {enabled: fields[1] = "1",
                    bindings: this._NormalizeSlots([fields[2], fields[3]])}
            }
            catch
                unreadable.Push(action.label)
        }
        if unreadable.Length {
            list := ""
            for label in unreadable
                list .= "`n- " label
            this._KeepDamagedFile("Some saved hotkeys could not be read and use their defaults:" list)
        }
        meta := document.Has("meta") ? document["meta"] : Map()
        for migration in this.migrations
            if KB_Manifest.Get(document, "meta", migration.key) != migration.value
                migration.callback.Call(this.configuration, meta)
    }

    _KeepDamagedFile(message) {
        copy := KB_Manifest.KeepDamagedFile(this.path)
        message .= "`nThe original file was kept as:`n" copy
        this.loadWarnings.Push(message)
        SuiteState.Log.Write("Keybindings", StrReplace(message, "`n", " "), "ERROR")
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
                        state: "pending", token: 0, foreground: 0, oneShot: false})
            }
        }
        return {configuration: normalized, routes: routes}
    }

    _Commit(configuration) {
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
                    if !Keybindings.CanCoexistScopes(previous.action.scope, route.action.scope, this.disjointPairs)
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
            document := this._MakeDocument(candidate.configuration)
            ; Availability changes reactivate routes without rewriting the file.
            if !FileExist(this.path) || KB_Manifest.Encode(document) != KB_Manifest.Encode(this.document)
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

    _MakeDocument(configuration) {
        document := Map("meta", Map("schema", "1", "id", this.id, "name", this.name), "bindings", Map())
        for migration in this.migrations
            document["meta"][migration.key] := migration.value
        for actionId, setting in configuration
            document["bindings"][actionId] := (setting.enabled ? "1" : "0")
                . "`t" setting.bindings[1] "`t" setting.bindings[2]
        return document
    }

    ; =========================================================================
    ; native dispatch: one hotkey variant per binding signature, a guard per
    ; key for repeats and releases, and a serialized event queue. Layer
    ; suffixes use the same routes; the Secret Layers client owns the prefixes.
    ; =========================================================================

    _CancelPendingInput() {
        ; Reopening a gate or rolling back an edit must not revive queued input.
        this.cancelledThroughToken := this.nextToken
        if IsObject(SuiteState.App) && SuiteState.App.manager = this
            SuiteState.App.CancelInputs()
    }

    _Deactivate() {
        this._CancelPendingInput()
        for route in this.routes {
            route.enabled := false
            if route.token
                this._QueueEvent(route, "cancel", route.foreground, route.oneShot)
        }
        for key, press in this.pressed
            press.finished := true
        if IsObject(this.client)
            this.client.Stop()
        this.routeMap := Map()
        this.layerKeys := Map()
    }

    _Activate() {
        this.externalCapture := IsObject(this.editor.recording)
        this._RefreshGate()
        this.routeMap := Map()
        this.layerKeys := Map()
        ; Scope-specific routes take priority over global fallbacks.
        orderedRoutes := []
        for route in this.routes
            if route.action.scope != ""
                orderedRoutes.Push(route)
        for route in this.routes
            if route.action.scope = ""
                orderedRoutes.Push(route)
        for route in orderedRoutes {
            ; Conflict state is a rejected claim, not merely a disabled native key.
            if InStr(route.state, "unavailable:") = 1
                continue
            route.enabled := true
            route.token := 0
            binding := route.binding
            if !this.routeMap.Has(binding.signature)
                this.routeMap[binding.signature] := []
            this.routeMap[binding.signature].Push(route)
            ; The prefix engine reports double-taps; they have no native suffix.
            if binding.doubleTap {
                route.state := "active"
                continue
            }
            try {
                this._EnsureVariant(binding)
                route.state := "active"
                if binding.layer != "normal"
                    this.layerKeys[binding.key] := true
                if !binding.wheel && GetKeyState(binding.key, "P")
                    this.blocked[binding.key] := true
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
        binding := route.binding
        if this.blocked.Has(binding.key) || Keybindings.ModifierMask() != binding.modifiers
            return false
        ; Ordinary hotkeys stand aside while a layer is held or armed.
        if binding.layer = "normal"
            return !IsObject(this.client) || !this.client.Busy()
        return this.client.Active(binding.layer)
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
            ; A suffix marks a held layer as used, or consumes a one-shot arm.
            oneShot := route.binding.layer != "normal" && this.client.Use(route.binding.layer)
            foreground := DllCall("GetForegroundWindow", "ptr")
            if !route.binding.wheel {
                this.pressed[key] := {route: route, finished: false, oneShot: oneShot}
                this._UpdateReleaseTimer()
            }
            this._QueueEvent(route, "down", foreground, oneShot)
            ; Wheel input has no physical key-up. Each wheel step is a complete
            ; activation, regardless of whether the action allows key repeat.
            if route.binding.wheel
                this._QueueEvent(route, "up", foreground, oneShot)
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
            if press.finished
                return
            if this._PressInvalid(press) {
                press.finished := true
                this._QueueEvent(press.route, "cancel", press.route.foreground, press.oneShot)
            } else if press.route.action.repeat && !press.oneShot {
                this._QueueEvent(press.route, "repeat", press.route.foreground, false)
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
                this._QueueEvent(press.route, "up", press.route.foreground, press.oneShot)
            this.pressed.Delete(key)
            this._UpdateReleaseTimer()
        }
        finally Critical previousCritical
    }

    ; A held press stays valid while its gate, context, modifiers and layer
    ; hold. One-shot layer presses end only on release.
    _PressInvalid(press) {
        route := press.route
        binding := route.binding
        if this.gated || !route.enabled || this.applying || !this.ContextActive(route.action)
            return true
        if press.oneShot
            return false
        if Keybindings.ModifierMask() != binding.modifiers
            return true
        if binding.layer = "normal"
            return IsObject(this.client) && this.client.Busy()
        return !this.client.IsHeld(binding.layer)
    }

    ; Polled only while a key is held or blocked: recovers missed releases.
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
                } else if !press.finished && this._PressInvalid(press) {
                    press.finished := true
                    this._QueueEvent(press.route, "cancel", press.route.foreground, press.oneShot)
                }
            }
            this._UpdateReleaseTimer()
        }
        finally Critical previousCritical
    }

    _UpdateReleaseTimer() {
        SetTimer(this.releaseCallback, this.running && (this.pressed.Count || this.blocked.Count) ? 15 : 0)
    }

    ; The prefix was released first: complete its held chords now. Their keys
    ; stay guarded until released, so key repeat cannot leak into the window.
    _LayerReleased(layer) {
        for key, press in this.pressed
            if press.route.binding.layer = layer && !press.oneShot && !press.finished {
                press.finished := true
                this._QueueEvent(press.route, "up", press.route.foreground, false)
            }
    }

    ; Switching to the other prefix cancels the first layer's held chords.
    _LayerCancelled(layer) {
        for key, press in this.pressed
            if press.route.binding.layer = layer && !press.oneShot && !press.finished {
                press.finished := true
                this._QueueEvent(press.route, "cancel", press.route.foreground, false)
            }
    }

    ; A completed double-tap is one complete, non-repeating press.
    _LayerDoubleTap(layer) {
        if !this.running || this.gated || this.applying
            return
        route := this._SelectedRoute(Keybindings.Parse(layer = "caps" ? "Caps + Caps" : "Pause + Pause").signature)
        if !IsObject(route)
            return
        foreground := DllCall("GetForegroundWindow", "ptr")
        this._QueueEvent(route, "down", foreground, true)
        this._QueueEvent(route, "up", foreground, true)
    }

    ; Keys already down when a layer starts are not part of a layer chord.
    ; Returns how many keys are blocked.
    BlockHeldKeys() {
        for key in this.layerKeys
            if !this.pressed.Has(key) && GetKeyState(key, "P")
                this.blocked[key] := true
        this._UpdateReleaseTimer()
        return this.blocked.Count
    }

    HasLayerRoute(layer, modifiers, keyId) => IsObject(this._SelectedRoute(layer "|" modifiers "|" StrLower(keyId)))

    IsKeyClaimed(keyId) => this.pressed.Has(keyId) || this.blocked.Has(keyId)

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
                    if item.token <= this.cancelledThroughToken
                        || this.gated || this.applying || !item.route.enabled
                        || ((A_TickCount - item.tick) & 0xFFFFFFFF) > 500
                        continue
                    this.delivered[item.token] := item
                } else {
                    if !this.delivered.Has(item.token)
                        continue
                    ; Release held output without firing a cancelled release action.
                    if item.token <= this.cancelledThroughToken
                        item.event.phase := phase := "cancel"
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
        gated := this.paused || this.externalCapture || !this.running
        if gated = this.gated
            return
        this.gated := gated
        if gated {
            this._CancelPendingInput()
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
                if !route.binding.wheel && !route.binding.doubleTap
                    && GetKeyState(route.binding.key, "P")
                    this.blocked[route.binding.key] := true
            this._UpdateReleaseTimer()
            if IsObject(this.client)
                this.client.Start()
        }
    }

    ; The editor window lives in KeybindingsEditor; these are its hooks.
    ShowSettings(moduleId := "") => this.editor.Show(moduleId)

    LayerEnabled(layer) => IsObject(this.client) && this.client.LayerEnabled(layer)

    ; While the editor records a hotkey, every route stays gated.
    SetCapture(active) {
        this.externalCapture := !!active
        this._RefreshGate()
    }

    IsAvailable(action) {
        return HasMethod(action.available, "Call") ? !!action.available.Call() : !!action.available
    }

    ContextActive(action) {
        if !this.IsAvailable(action)
            return false
        if action.scope != "" {
            inverse := SubStr(action.scope, 1, 1) = "!"
            name := inverse ? SubStr(action.scope, 2) : action.scope
            active := !!this.scopes[name].Call()
            if active = inverse
                return false
        }
        return !HasMethod(action.context, "Call") || !!action.context.Call()
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

    RegisterScope(name, predicate) {
        if this.running || !HasMethod(predicate, "Call") || this.scopes.Has(name)
            throw Error("Define each input scope once before starting Keybindings.")
        Keybindings.Id(name)
        this.scopes[name] := predicate
    }

    ; A migration runs once for an existing settings file whose meta[key] is not
    ; value: callback(configuration, meta) adjusts the loaded assignments. Every
    ; save records value, so new installations never run it.
    AddMigration(key, value, callback) {
        if this.running || !HasMethod(callback, "Call")
            throw Error("Register keybinding migrations before Start().")
        this.migrations.Push({key: key, value: value, callback: callback})
    }

    ; For migrations: replace a stock binding only while it is unchanged and no
    ; other action uses the new hotkey. Editor-scoped actions may share it.
    static MigrateDefault(configuration, actionId, slot, previous, replacement) {
        if !configuration.Has(actionId)
            return false
        expected := previous = "" ? "" : Keybindings.Parse(previous).signature
        if configuration[actionId].bindings[slot] != expected
            return false
        target := replacement = "" ? "" : Keybindings.Parse(replacement).signature
        actions := IsObject(Keybindings.Current) ? Keybindings.Current.actions : Map()
        if target != ""
            for otherId, setting in configuration
                for otherSlot, binding in setting.bindings
                    if binding = target && (otherId != actionId || otherSlot != slot)
                        && !(actions.Has(otherId) && actions[otherId].scope != "")
                        return false
        configuration[actionId].bindings[slot] := target
        return true
    }

    RegisterDisjointScopes(first, second) {
        if this.running || first = second || !this.scopes.Has(first) || !this.scopes.Has(second)
            throw ValueError("Declare distinct registered scopes before starting Keybindings.")
        this.disjointPairs[first "|" second] := true
        this.disjointPairs[second "|" first] := true
    }

    static DisjointScopes(first, second, pairs := 0) {
        ; A context callback alone is not proof that two actions cannot overlap.
        return first != "" && second != "" && ((first = "!" second || second = "!" first)
            || (IsObject(pairs) && pairs.Has(first "|" second)))
    }

    static CanCoexistScopes(first, second, pairs := 0) {
        if Keybindings.DisjointScopes(first, second, pairs)
            return true
        ; Narrow positive scopes override a global shortcut while active.
        ; A broad inverse scope (!paper-pad, etc.) cannot override global routes.
        if first = ""
            return second != "" && SubStr(second, 1, 1) != "!"
        if second = ""
            return SubStr(first, 1, 1) != "!"
        return false
    }

    BindingUnavailable(binding) {
        if binding.layer != "normal"
            return !IsObject(this.client) || !this.client.LayerEnabled(binding.layer)
                ? "unavailable: " binding.layer " layer is disabled" : ""
        return binding.activationKey && IsObject(this.client) && this.client.OwnsPrefix(binding.key)
            ? "unavailable: this key is owned by Secret Layers" : ""
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
        ; ~*Key and *Key are variants of one native hotkey, and only the first
        ; created whose criterion holds runs. A pass-through observer created
        ; earlier must not hide one that claims the input, such as a focus-tab click.
        if SubStr(key, 1, 1) = "~" && this._ObserverEligible(SubStr(key, 2))
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

    static KeepDamagedFile(path) {
        base := path ".damaged-" FormatTime(, "yyyyMMdd-HHmmss")
        copy := base
        suffix := 0
        while FileExist(copy)
            copy := base "-" (++suffix)
        ; Never replace a prior recovery copy, even if another writer races us.
        ; Let failure propagate before defaults can be written over the source.
        FileCopy(path, copy, false)
        return copy
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
