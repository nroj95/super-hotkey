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
        this.disjointPairs := Map()
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
        this.cancelledThroughToken := 0
        this.dispatching := false
        this.running := false
        this.applying := false
        this.disposed := false
        this.settings := 0
        this.settingsDraft := 0
        this.settingsModuleId := ""
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
                scope := HasProp(action, "scope") ? action.scope : ""
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
                entry := {id: action.id, label: action.label, scope: scope,
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
                    if moduleId = "paper-pad"
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
                for category in Keybindings.OrderDisplayCategories(moduleName, modules[moduleName]) {
                    heading := (InStr(category, " / ") || allCategories.Count > 1) ? category : participant.name
                    if participant.id != participants[1].id && !participant.controlReady
                        heading .= " (view only)"
                    rows.Push({id: "", kind: "owner", label: heading,
                        ownerId: participant.id})
                    for entry in Keybindings.OrderDisplayEntries(category, grouped[category])
                        rows.Push(entry)
                }
            }
        }
        return rows
    }
    ; Reorder existing Power-Up Utilities subcategories without adding headings.
    static OrderDisplayCategories(moduleName, categories) {
        if moduleName != "Power-Up Utilities"
            return categories
        preferred := ["Power-Up Utilities",
            "Power-Up Utilities / Extra function keys",
            "Power-Up Utilities / Virtual number pad",
            "Power-Up Utilities / Text and symbols",
            "Power-Up Utilities / Windows Terminal"]
        result := []
        placed := Map()
        for wanted in preferred
            for category in categories
                if category = wanted {
                    result.Push(category)
                    placed[category] := true
                }
        for category in categories
            if !placed.Has(category)
                result.Push(category)
        return result
    }

    ; Visual order only. IDs, registration order, categories and saved bindings
    ; are unchanged. Unknown/new actions follow the listed ones in their category.
    static OrderDisplayEntries(category, entries) {
        static order := Map(
            "Global", [
                "core.keybindings", "window-cascade.copy-log", "window-cascade.reset-log"],
            "Paper Pad", [
                "paper-pad.help", "paper-pad.toggle"],
            "Paper Pad / Inside the editor", [
                "paper-pad.new", "paper-pad.save", "paper-pad.delete",
                "paper-pad.previous", "paper-pad.next", "paper-pad.hide"],
            "Cascade Kingdom", [
                "window-cascade.help",
                "window-cascade.focus-previous", "window-cascade.focus-next",
                "window-cascade.slot-previous", "window-cascade.slot-next",
                "window-cascade.swap-up", "window-cascade.swap-down",
                "window-cascade.rotate-next",
                "window-cascade.adopt", "window-cascade.bring-forward",
                "window-cascade.minimize",
                "window-cascade.gather",
                "window-cascade.close-active", "window-cascade.close-monitor"],
            "Wonder Windows", [
                "win-key-overhaul.help",
                "win-key-overhaul.focus-up", "win-key-overhaul.focus-down",
                "win-key-overhaul.focus-left", "win-key-overhaul.focus-right",
                "win-key-overhaul.cycle-stacked", "win-key-overhaul.cycle-expanded",
                "win-key-overhaul.maximize", "win-key-overhaul.restore", "win-key-overhaul.minimize",
                "win-key-overhaul.move-monitor",
                "win-key-overhaul.layout-left", "win-key-overhaul.layout-right",
                "win-key-overhaul.tile-top-left", "win-key-overhaul.tile-top",
                "win-key-overhaul.tile-top-right", "win-key-overhaul.tile-bottom-left",
                "win-key-overhaul.tile-bottom", "win-key-overhaul.tile-bottom-right",
                "win-key-overhaul.stretch-left", "win-key-overhaul.stretch-right",
                "win-key-overhaul.stretch-height", "win-key-overhaul.stretch-full-cycle",
                "win-key-overhaul.reset-stretch",
                "win-key-overhaul.swap-up", "win-key-overhaul.swap-down",
                "win-key-overhaul.swap-left", "win-key-overhaul.swap-right",
                "win-key-overhaul.isolate", "win-key-overhaul.minimize-all"],
            "Wonder Windows / FancyZones", [
                "win-key-overhaul.zone-up", "win-key-overhaul.zone-down",
                "win-key-overhaul.zone-left", "win-key-overhaul.zone-right"],
            "Power-Up Utilities", [
                "power-up-utilities.interface.open", "power-up-utilities.system.wake-speakers",
                "power-up-utilities.system.sleep"],
            "Power-Up Utilities / Extra function keys", [
                "power-up-utilities.keyboard.f13", "power-up-utilities.keyboard.f14",
                "power-up-utilities.keyboard.f15", "power-up-utilities.keyboard.f16",
                "power-up-utilities.keyboard.f17", "power-up-utilities.keyboard.f18",
                "power-up-utilities.keyboard.f19", "power-up-utilities.keyboard.f20",
                "power-up-utilities.keyboard.f21", "power-up-utilities.keyboard.f22",
                "power-up-utilities.keyboard.f23", "power-up-utilities.keyboard.f24"],
            "Power-Up Utilities / Virtual number pad", [
                "power-up-utilities.keyboard.numpad0", "power-up-utilities.keyboard.numpad1",
                "power-up-utilities.keyboard.numpad2", "power-up-utilities.keyboard.numpad3",
                "power-up-utilities.keyboard.numpad4", "power-up-utilities.keyboard.numpad5",
                "power-up-utilities.keyboard.numpad6", "power-up-utilities.keyboard.numpad7",
                "power-up-utilities.keyboard.numpad8", "power-up-utilities.keyboard.numpad9"],
            "Power-Up Utilities / Text and symbols", [
                "power-up-utilities.text.apostrophe", "power-up-utilities.text.en-dash",
                "power-up-utilities.text.nbsp", "power-up-utilities.text.sharp-s",
                "power-up-utilities.text.timestamp"],
            "Power-Up Utilities / Windows Terminal", [
                "power-up-utilities.terminal.copy", "power-up-utilities.terminal.clear"],
            "Secret Layers", [
                "keyboard-layers.help", "power-up-utilities.keyboard.toggle-caps"])
        if !order.Has(category)
            return entries
        byId := Map()
        for entry in entries
            byId[entry.id] := entry
        result := []
        placed := Map()
        for actionId in order[category] {
            if byId.Has(actionId) {
                result.Push(byId[actionId])
                placed[actionId] := true
            }
        }
        for entry in entries
            if !placed.Has(entry.id)
                result.Push(entry)
        return result
    }

    _ActionInSettingsModule(actionId, moduleId) {
        if moduleId = ""
            return true
        moduleName := SuiteSettings.ModuleNames[moduleId]
        category := this.actions[actionId].category
        return category = moduleName || InStr(category, moduleName " / ") = 1
    }

    _LocalCatalogSnapshot(configuration := unset, moduleId := "") {
        result := []
        settings := IsSet(configuration) ? configuration : this.configuration
        for actionId, action in this.actions {
            setting := settings[actionId]
            if !setting.enabled || !this.IsAvailable(action)
                || !this._ActionInSettingsModule(actionId, moduleId)
                continue
            result.Push({id: actionId, label: action.label,
                category: action.category, scope: action.scope, enabled: true, help: action.help,
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
        if this.document.Count && !this.document.Has("bindings")
            throw Error("Existing keybindings settings are missing [bindings]; nothing was overwritten.")
        for actionId, action in this.actions {
            value := KB_Manifest.Get(this.document, "bindings", actionId, "")
            if value = ""
                continue
            fields := StrSplit(value, "`t")
            if fields.Length != 3 || (fields[1] != "0" && fields[1] != "1")
                throw Error("Invalid saved settings for " actionId "; nothing was overwritten.")
            this.configuration[actionId] := {enabled: fields[1] = "1",
                bindings: this._NormalizeSlots([fields[2], fields[3]])}
        }
        if this.document.Count {
            WW_MigrateKeybindingDefaults(this.configuration)
            ; Run this migration once so future manual Caps + F5/F6 choices remain saved.
            if KB_Manifest.Get(this.document, "meta", "debugDefaults") != "2"
                CascadeMigrateDebugKeybindingDefaults(this.configuration)
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
        document := Map("meta", Map("schema", "1", "id", this.id, "name", this.name,
            "debugDefaults", "2"), "bindings", Map())
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
        ; Scope-specific routes take priority over global fallbacks in both
        ; the normal dispatcher and the Secret Layers layer dispatcher.
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
                if route.binding.layer = "normal" && !route.binding.wheel
                    && GetKeyState(route.binding.key, "P")
                    this.blocked[route.binding.key] := true
            this._UpdateReleaseTimer()
            if IsObject(this.client)
                this.client.Start()
        }
    }





    ; =========================================================================
    ; category-based, staged keybinding screen
    ; =========================================================================

    _SettingsTitle() {
        if this.settingsModuleId != ""
            return SuiteSettings.ModuleNames[this.settingsModuleId] " - Keybindings"
        if IsObject(SuiteState.App) && !SuiteState.App.ModuleActive("keyboard-layers")
            return "Keybindings — Secret Layers disabled"

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

    ShowSettings(moduleId := "") {
        if !this.running
            throw Error("Start the keybinding manager first.")
        if moduleId != "" && !SuiteSettings.ModuleNames.Has(moduleId)
            throw ValueError("Unknown Keybindings module: " moduleId)
        if IsObject(this.settings) {
            if this.settingsModuleId = moduleId {
                this.settings.Show()
                return
            }
            ; Switching views discards that view's unapplied edits.
            this._CloseSettings()
        }

        this.settingsModuleId := moduleId
        this.settingsDraft := this.GetConfiguration()
        this.participants := this.DiscoverParticipants()
        if moduleId != ""
            this.participants[1].name := SuiteSettings.ModuleNames[moduleId]
        this.settingsWindowWidth := 1060
        this.settingsWindowHeight := Min(860, Max(560, A_ScreenHeight - 125))

        ; Buffer child-window painting while the editor updates many row controls.
        window := SuiteGui("+Resize +MinSize820x520 +0x02000000 +E0x02000000", this._SettingsTitle())
        this.settings := window
        window.BackColor := "FAF7F2"
        SuiteFullscreen.Enable(window)
        this._SetSettingsIcons(window)
        this._RefreshGate()
        ; Use the same regular weight as the rest of the suite.
        window.SetFont("s10 w400", "Cascadia Mono")
        this.settingsSearch := window.AddEdit("x210 y13 w400 vsearch")
        DllCall("SendMessageW", "ptr", this.settingsSearch.Hwnd, "uint", 0x1501,
            "uptr", 1, "str", "Search… (LMB to record, RMB to type)", "ptr")
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
        this.settingsApply := window.AddButton("x438 y320 w120 h31", "Apply")
        this.settingsDrawButtons[this.settingsApply.Hwnd] := "done"
        this.settingsApply.OnEvent("Click", ObjBindMethod(this, "_ApplyStaged"))
        this.settingsDone := window.AddButton("x572 y320 w110 h31", moduleId = "" ? "Cancel" : "Back")
        this.settingsDrawButtons[this.settingsDone.Hwnd] := "done"
        if moduleId = ""
            this.settingsDone.OnEvent("Click", ObjBindMethod(this, "_RequestCloseSettings"))
        else
            this.settingsDone.OnEvent("Click", ObjBindMethod(this, "_BackToHelp"))
        window.OnEvent("Size", ObjBindMethod(this, "_ResizeSettings"))
        window.OnEvent("ContextMenu", ObjBindMethod(this, "_EditBindingText"))
        window.OnEvent("Close", ObjBindMethod(this, "_RequestCloseSettings"))
        window.OnEvent("Escape", ObjBindMethod(this, "_RequestCloseSettings"))
        this.scrollPosition := 0
        this.settingsResizing := false
        this.settingsRenderedWidth := 0
        this.settingsRenderedHeight := 0
        SuiteShowCentered(window, this.settingsWindowWidth, this.settingsWindowHeight,
            ObjBindMethod(this, "_ResizeSettings"), true)
        OnMessage(0x020A, this.wheelCallback)
        this.wheelHookActive := true
        OnMessage(0x0115, this.verticalScrollCallback)
        this.verticalScrollHookActive := true
    }

    ; Small, explanatory context tags, only for positive application scopes.
    ; Inverse scopes are exclusion rules, not single-application shortcuts.
    static ContextTagText(scope) {
        switch scope {
            case "paper-pad": return "editor only"
            case "windows-terminal": return "terminal only"
            default: return ""
        }
    }

    ; Anchor context tags before the first binding box, not after the
    ; variable-length description. Ellipsize labels that run into the tag.
    static ContextRowLayout(label, tag, primaryX) {
        available := Max(80, primaryX - 33) ; x22 to 11px before binding
        if tag = ""
            return {titleWidth: available, tagX: 22, tagWidth: 0}
        tagWidth := Ceil(StrLen(tag) * 6.0) + 6 ; 7.25pt text, 3px horizontal padding
        tagX := primaryX - tagWidth - 12 ; 12px before the first binding box
        titleWidth := Max(1, Min(StrLen(label) * 8, tagX - 22 - 8))
        return {titleWidth: titleWidth, tagX: tagX, tagWidth: tagWidth}
    }

    ; Avoid dispatching redundant WM_SETTEXT, ShowWindow and EnableWindow updates.
    static _SetSettingsText(control, value) {
        if control.Text != value
            control.Text := value
    }

    static _SetSettingsVisible(control, visible) {
        if control.Visible != visible
            control.Visible := visible
    }

    static _SetSettingsEnabled(control, enabled) {
        if control.Enabled != enabled
            control.Enabled := enabled
    }

    static _MoveSettingsHeading(control, x, width := unset) {
        control.GetPos(&currentX, , &currentWidth)
        if IsSet(width) {
            if currentX != x || currentWidth != width
                control.Move(x, , width)
        } else if currentX != x
            control.Move(x)
    }

    _AddSettingsRow() {
        index := this.settingsRowPool.Length + 1
        window := this.settings
        title := window.AddText("Hidden x22 y48 w290 h25 +0x4000", "") ; SS_ENDELLIPSIS
        categoryTitle := window.AddText("Hidden x22 y48 w752 h25 Center", "")
        contextTag := window.AddText("Hidden x22 y48 w80 h16 Border Center c777777", "")
        contextTag.SetFont("s7.25 c777777", "Cascadia Mono")
        primary := window.AddButton("Hidden x358 y48 w167 h29", "Unbound")
        secondary := window.AddButton("Hidden x535 y48 w153 h29", "Unbound")
        reset := window.AddButton("Hidden x698 y48 w76 h29", "Reset")
        this.settingsDrawButtons[primary.Hwnd] := "binding"
        this.settingsDrawButtons[secondary.Hwnd] := "binding"
        this.settingsDrawButtons[reset.Hwnd] := "reset"
        primary.OnEvent("Click", ObjBindMethod(this, "_BeginRecording", index, 1))
        secondary.OnEvent("Click", ObjBindMethod(this, "_BeginRecording", index, 2))
        reset.OnEvent("Click", ObjBindMethod(this, "_ResetAction", index))
        this.settingsRowPool.Push({title: title, categoryTitle: categoryTitle,
            contextTag: contextTag, primary: primary, secondary: secondary,
            reset: reset, actionId: ""})
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
                        row.contextTag.Visible := false
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
                    tag := row.contextTag.Visible ? row.contextTag.Text : ""
                    layout := Keybindings.ContextRowLayout(row.title.Text, tag, primaryX)
                    positions.Push({control: row.title,
                        x: 22, y: y + 6, w: layout.titleWidth, h: 25})
                    positions.Push({control: row.contextTag,
                        x: layout.tagX, y: y + 6, w: layout.tagWidth, h: 16})
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
                footerX := width - 484 ; 438px button group, 46px right margin
                positions.Push({control: this.settingsResetAll,
                    x: footerX, y: height - 49, w: 180, h: 31})
                positions.Push({control: this.settingsApply,
                    x: footerX + 194, y: height - 49, w: 120, h: 31})
                positions.Push({control: this.settingsDone,
                    x: footerX + 328, y: height - 49, w: 110, h: 31})
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
        newTitle := this._SettingsTitle()
        if this.settings.Title != newTitle
            this.settings.Title := newTitle
        this.warningButtons := Map()
        search := this.settings["search"].Value
        this.participants[1].actions := this._LocalCatalogSnapshot(this.settingsDraft, this.settingsModuleId)
        this.rows := Keybindings.DisplayRows(this.participants, search)
        this.settingsApply.Enabled := this._HasPendingSettings()
        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        this.scrollPosition := Min(Max(this.scrollPosition, 0), maximum)
        Keybindings._SetSettingsVisible(this.settingsScroll, maximum > 0)
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
        this.settings.GetClientPos(, , &clientWidth)
        for index, row in this.visibleRows {
            position := this.scrollPosition + index
            visible := position <= this.rows.Length
            entry := visible ? this.rows[position] : 0
            isAction := visible && entry.id != ""
            isLocal := isAction && entry.ownerId = this.id
            editable := isAction && entry.editable
            row.actionId := editable ? entry.id : ""
            row.ownerId := isAction ? entry.ownerId : ""
            Keybindings._SetSettingsVisible(row.title, isAction)
            Keybindings._SetSettingsVisible(row.categoryTitle, visible && !isAction)
            if !isAction
                Keybindings._SetSettingsVisible(row.contextTag, false)
            Keybindings._SetSettingsVisible(row.primary, isAction)
            Keybindings._SetSettingsVisible(row.secondary, isAction)
            Keybindings._SetSettingsVisible(row.reset, isLocal)
            if !visible
                continue
            if !isAction {
                heading := entry.label = "Global" ? "★ Global ★" : entry.label
                Keybindings._SetSettingsText(row.categoryTitle, heading)
                Keybindings._MoveSettingsHeading(row.categoryTitle, 22, clientWidth - 68)
                continue
            }
            Keybindings._SetSettingsText(row.title, entry.label)
            tag := Keybindings.ContextTagText(entry.scope)
            Keybindings._SetSettingsText(row.contextTag, tag)
            row.primary.GetPos(&primaryX)
            layout := Keybindings.ContextRowLayout(entry.label, tag, primaryX)
            Keybindings._MoveSettingsHeading(row.title, 22, layout.titleWidth)
            if tag != ""
                Keybindings._MoveSettingsHeading(row.contextTag, layout.tagX, layout.tagWidth)
            Keybindings._SetSettingsVisible(row.contextTag, tag != "")
            Keybindings._SetSettingsEnabled(row.primary, editable)
            Keybindings._SetSettingsEnabled(row.secondary, editable)
            setting := isLocal ? this.settingsDraft[entry.id] : entry.setting
            for slot, control in [row.primary, row.secondary] {
                parsed := Keybindings.Parse(setting.bindings[slot])
                if !IsObject(parsed) {
                    Keybindings._SetSettingsText(control, "+ Add")
                    continue
                }
                inactiveLayer := parsed.layer != "normal" && this.BindingUnavailable(parsed) != ""
                if inactiveLayer
                    this.warningButtons[control.Hwnd] := true
                Keybindings._SetSettingsText(control, (inactiveLayer ? "⚠ " : "") parsed.label)
            }
            if isLocal {
                defaults := this.actions[entry.id].defaults
                Keybindings._SetSettingsEnabled(row.reset,
                    setting.bindings[1] != defaults[1] || setting.bindings[2] != defaults[2])
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
            if enabled {
                fillColor := pressed ? 0xDEDEDE : hovered ? 0xEEEEEE : 0xFFFFFF
                frameColor := 0x909090
                textColor := 0x303030
            } else {
                fillColor := 0xF5F5F5
                frameColor := 0xCDCDCD
                textColor := 0xB0B0B0
            }
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
        configuration := this._CloneConfiguration(this.settingsDraft)
        configuration[actionId].bindings := this.actions[actionId].defaults.Clone()
        this._StageConfiguration(configuration)
    }

    _ResetAll(*) {
        subject := this.settingsModuleId = "" ? "all actions, including disabled modules"
            : SuiteSettings.ModuleNames[this.settingsModuleId]
        if MsgBox("Restore default hotkey assignments for " subject "?"
            . "`n`nChanges stay pending until Apply. Other preferences and notes are untouched.",
            this.name, "YesNo Default2 Icon?") != "Yes"
            return
        this._StageDefaults()
    }

    _StageDefaults() {
        configuration := this._CloneConfiguration(this.settingsDraft)
        for actionId, action in this.actions
            if this._ActionInSettingsModule(actionId, this.settingsModuleId)
                configuration[actionId].bindings := action.defaults.Clone()
        this._StageConfiguration(configuration)
    }

    _HasPendingSettings() {
        if !IsObject(this.settingsDraft)
            return false
        for actionId, setting in this.settingsDraft {
            current := this.configuration[actionId]
            if setting.enabled != current.enabled || setting.bindings[1] != current.bindings[1]
                || setting.bindings[2] != current.bindings[2]
                return true
        }
        return false
    }

    ; Editing is purely in-memory. Conflicts are checked against all modules
    ; by Apply(), before the manifest is written and the active hotkeys are updated.
    _StageConfiguration(configuration) {
        if !IsObject(this.settings)
            return false
        this.settingsDraft := this._CloneConfiguration(configuration)
        this._RenderSettings()
        return true
    }

    _ApplyStaged(*) {
        if !IsObject(this.settings) || !this._HasPendingSettings()
            return false
        if IsObject(this.recording) {
            this._EndRecording()
            return false
        }
        try {
            this.Apply(this.settingsDraft)
            this._Report("keybinding changes saved")
            this._CloseSettings()
            return true
        }
        catch Error as failure {
            SuiteState.Log.Error("Keybindings", failure)
            MsgBox(failure.Message, this.name " - binding rejected", "Icon!")
            return false
        }
    }

    _BackToHelp(*) {
        if IsObject(this.recording) {
            this._EndRecording()
            return
        }
        moduleId := this.settingsModuleId
        this._CloseSettings()
        if moduleId != "" && IsObject(SuiteState.App) && IsObject(SuiteState.App.ui)
            SuiteState.App.ui.ShowHelp(moduleId)
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
            SuiteFullscreen.Forget(this.settings)
            SuiteSizeGrip.Detach(this.settings)
            this.settings.Destroy()
        }
        for iconHandle in this.settingsIcons
            DllCall("DestroyIcon", "ptr", iconHandle)
        this.settingsIcons := []
        this.settings := 0
        this.settingsDraft := 0
        this.settingsModuleId := ""
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
            prefixDown: "", prefixDownAt: 0, prefixUsed: false,
            prefixCancel: false, armedLayer: "", armedAt: 0,
            finish: ObjBindMethod(this, "_FinishRecordedKey"),
            timeout: ObjBindMethod(this, "_RecordingTimedOut")}
        this.recording := record
        try {
            this.externalCapture := true
            this._RefreshGate()
            record.button := slot = 1 ? this.visibleRows[index].primary : this.visibleRows[index].secondary
            record.button.Text := "Press keys..."
            hook := InputHook("L0 I101")
            hook.KeyOpt("{All}", "SN")
            hook.OnKeyDown := ObjBindMethod(this, "_RecordKey")
            hook.OnKeyUp := ObjBindMethod(this, "_RecordKeyUp")
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

    ; The recorder is active while Secret Layers is gated, so it must track
    ; prefix taps itself instead of relying on the running layer dispatcher.
    _RecordingPrefixLayer(vk) {
        if !IsObject(this.client)
            return ""
        if vk = 0x14 && this.client.LayerEnabled("caps")
            return "caps"
        if (vk = 0x13 || vk = 3) && this.client.LayerEnabled("pause")
            return "pause"
        return ""
    }

    ; These two transition helpers are deterministic so timing and tap-then-hold
    ; behavior can be regression tested without injecting real keyboard input.
    static RecordingPrefixDown(record, layer, now, oneShotMs := 1400) {
        if record.prefixDown != ""
            return false
        elapsed := now - record.armedAt
        record.prefixCancel := record.armedLayer = layer
            && elapsed >= 0 && elapsed < oneShotMs
        record.prefixDown := layer
        record.prefixDownAt := now
        record.prefixUsed := false
        record.armedLayer := ""
        return true
    }

    static RecordingPrefixUp(record, layer, now, modifiers, tapMaxMs := 250) {
        if record.prefixDown != layer
            return ""
        elapsed := now - record.prefixDownAt
        quick := !record.prefixUsed && modifiers = 0
            && elapsed >= 0 && elapsed <= tapMaxMs
        doubleTap := quick && record.prefixCancel
        cancelled := record.prefixCancel
        record.prefixDown := ""
        record.prefixCancel := false
        record.prefixUsed := false
        if doubleTap
            return "double"
        if quick && !cancelled {
            record.armedLayer := layer
            record.armedAt := now
            return "armed"
        }
        return ""
    }

    static RecordingOneShotLayer(record, now, oneShotMs := 1400) {
        elapsed := now - record.armedAt
        if record.armedLayer != "" && elapsed >= 0 && elapsed < oneShotMs
            return record.armedLayer
        return ""
    }

    static RecordingBareKey(record, physicalLayer, now, modifiers) {
        ; Escape cancels and Backspace clears only without a held or one-shot prefix.
        return physicalLayer = "normal" && record.prefixDown = ""
            && Keybindings.RecordingOneShotLayer(record, now) = "" && modifiers = 0
    }

    _RecordPrefixRelease(layer) {
        if !IsObject(this.recording) || this.recording.pending != ""
            return
        record := this.recording
        result := Keybindings.RecordingPrefixUp(record, layer, A_TickCount,
            Keybindings.ModifierMask())
        if result = "double" {
            ; No prefix is physically held on release. The normal finish watcher
            ; will stage this complete, non-repeating double-tap assignment.
            key := layer = "caps" ? "CapsLock" : "vk13"
            this._StageRecordedBinding(layer, 0, key, "")
        } else if result = "armed"
            record.button.Text := "Press next key..."
        else
            record.button.Text := "Press keys..."
    }

    _RecordKeyUp(hook, vk, sc) {
        if !IsObject(this.recording)
            return
        layer := this._RecordingPrefixLayer(vk)
        if layer != "" && this.recording.prefixDown = layer
            this._RecordPrefixRelease(layer)
    }

    _RecordKey(hook, vk, sc) {
        if !IsObject(this.recording)
            return
        if !WinActive("ahk_id " this.settings.Hwnd) {
            this._EndRecording()
            return
        }
        record := this.recording
        layer := this._CaptureLayer()
        bare := Keybindings.RecordingBareKey(record, layer, A_TickCount,
            Keybindings.ModifierMask())
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
            this.recording.button.Text := "Unbound ..."
            return
        }
        if vk = 0x10 || vk = 0x11 || vk = 0x12 || (vk >= 0xA0 && vk <= 0xA5)
            || vk = 0x5B || vk = 0x5C
            return
        prefix := this._RecordingPrefixLayer(vk)
        if prefix != "" {
            if record.pending = "" && Keybindings.RecordingPrefixDown(record,
                prefix, A_TickCount)
                record.button.Text := "Press next key..."
            return
        }
        if record.pending != ""
            return
        ; A held prefix records a normal chord. A released, quickly tapped
        ; prefix supplies the one-shot layer for the next key (up to 1400 ms).
        if record.prefixDown != "" {
            layer := record.prefixDown
            record.prefixUsed := true
        } else {
            oneShotLayer := Keybindings.RecordingOneShotLayer(record, A_TickCount)
            if oneShotLayer != ""
                layer := oneShotLayer
        }
        record.armedLayer := ""
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
        ; Pause may not generate a conventional key-up on every keyboard.
        ; Poll physical state as a fallback; normal InputHook key-up is preferred.
        if record.pending = "" && record.prefixDown != "" {
            released := record.prefixDown = "caps" ? !GetKeyState("CapsLock", "P")
                : !GetKeyState("Pause", "P") && !GetKeyState("CtrlBreak", "P")
            if released && A_TickCount - record.prefixDownAt >= 20
                this._RecordPrefixRelease(record.prefixDown)
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
        configuration := this._CloneConfiguration(this.settingsDraft)
        configuration[actionId].bindings[slot] := value
        this._StageConfiguration(configuration)
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
                configuration := this._CloneConfiguration(this.settingsDraft)
                old := Keybindings.Parse(configuration[row.actionId].bindings[slot])
                input := InputBox("Type a hotkey, for example CapsLock, Escape, or Ctrl + Alt + J."
                    . "`n`nLeave empty to clear.",
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
                configuration[row.actionId].bindings[slot] := IsObject(parsed) ? parsed.signature : ""
                this._StageConfiguration(configuration)
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
