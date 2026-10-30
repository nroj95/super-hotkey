; Keybindings: layers, double-taps, dispatch, recording, scopes, observers and staged edits.
; Disposable preferences, dry-run inputs and test-owned windows only.
class KeybindingsChecks {
    static Run() {
        this.IndependentLayers()
        this.CapsLockDoubleTap()
        this.LayerDoubleTapGestures()
        this.LayerChordReleaseOrder()
        this.LayerDispatch()
        this.WhilePausedRoutes()
        this.LayerRecordingGestures()
        this.LayerIndicatorDelay()
        this.ScopesAndObservers()
        this.ActiveShortcutVisibility()
        this.StagedKeybindings()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static scopeActive := false

    static terminalScopeActive := false

    static observerCalls := 0

    static Route(manager, actionId, slot := 1) {
        for route in manager.routes
            if route.action.id = actionId && route.slot = slot
                return route
        throw Error("Missing test route: " actionId)
    }

    ; A manager whose routes and prefix engine exist without native hotkeys,
    ; prefix hooks or key injection. Tests call the real dispatch methods.
    static LayerFixture(name) {
        manager := Keybindings("layer-" name, "Layer fixture",
            {directory: SuiteChecks.directory "\layer-" name,
                layerFactory: (owner) => KeyboardLayers(owner, Map("caps", true, "pause", true))})
        events := []
        record := (event) => events.Push(event)
        manager.AddAction("fixture.caps", "caps chord", record, ["Caps + C"], {repeat: true})
        manager.AddAction("fixture.pause", "pause chord", record, ["Pause + C"])
        manager.AddAction("fixture.double", "caps double-tap", record, ["Caps + Caps"])
        manager.AddAction("fixture.plain", "plain key", record, ["C"])
        candidate := manager._CandidateRoutes(manager._DefaultConfiguration())
        manager.configuration := candidate.configuration
        manager.routes := candidate.routes
        manager.client := manager.layerFactory.Call(manager)
        manager.client.showIndicator := false
        manager.client.running := true
        manager.running := true
        for route in manager.routes {
            route.enabled := true
            signature := route.binding.signature
            if !manager.routeMap.Has(signature)
                manager.routeMap[signature] := []
            manager.routeMap[signature].Push(route)
            if route.binding.layer != "normal" && !route.binding.doubleTap
                manager.layerKeys[route.binding.key] := true
        }
        return {manager: manager, layers: manager.client, events: events}
    }

    static HoldLayer(layers, layerName) {
        layer := layers.layers[layerName]
        layers.selected := layerName
        layer.down := true
        layer.used := false
        layer.cancelTap := false
        layer.doubleTap := false
        layer.started := KeyboardLayers.Now()
        layer.physicalKey := layerName = "caps" ? "CapsLock" : "Pause"
    }

    static Phases(fixture) {
        phases := ""
        for event in fixture.events
            phases .= (phases = "" ? "" : ",") event.actionId ":" event.phase (event.oneShot ? "*" : "")
        return phases
    }

    static IndependentLayers() {
        for flags in [[false, false], [false, true], [true, false], [true, true]] {
            label := (flags[1] ? "caps" : "no-caps") "-" (flags[2] ? "pause" : "no-pause")
            app := SuiteApplication(true, SuiteChecks.directory "\layers-" label)
            app.activeLayers := Map("caps", flags[1], "pause", flags[2])
            app.InitializeCatalog()
            manager := app.manager
            try {
                manager.SetPaused(true)
                manager.Start()
                this.Assert(IsObject(manager.client) = (flags[1] || flags[2]), "layer client presence: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Caps + Alt + K")) = "") = flags[1],
                    "Caps assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause + T")) = "") = flags[2],
                    "Pause assignment availability: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("CapsLock")) = "") = !flags[1],
                    "native CapsLock ownership: " label)
                this.Assert((manager.BindingUnavailable(Keybindings.Parse("Pause")) = "") = !flags[2],
                    "native Pause ownership: " label)
                this.Assert(this.Route(manager, "core.keybindings", 2).enabled,
                    "ordinary Keybindings shortcut remains available: " label)
                manager.ShowSettings()
                expectedTitle := flags[1] && flags[2] ? "Keybindings"
                    : !flags[1] && !flags[2]
                        ? "Keybindings — CapsLock and Pause layers disabled"
                    : flags[1] ? "Keybindings — Pause layer disabled"
                        : "Keybindings — CapsLock layer disabled"
                this.Assert(manager.editor.window.Title = expectedTitle,
                    "Keybindings title explains the disabled layer state: " label)
                manager.editor.window["search"].Value := "open Keybindings"
                manager.editor.Render()
                this.Assert(manager.editor.rows[2].id = "core.keybindings",
                    "core shortcut remains visible when searching: " label)
                coreButtons := manager.editor.visibleRows[2]
                this.Assert(InStr(coreButtons.primary.Text, "⚠") = 1 ? !flags[1] : flags[1],
                    "Caps binding receives a warning only when inactive: " label)
                this.Assert(coreButtons.secondary.Text = "Ctrl + Alt + K",
                    "ordinary fallback is never warned: " label)
                this.Assert(coreButtons.primary.Enabled,
                    "inactive bindings remain clickable for reassignment: " label)
                manager.editor.window["search"].Value := "show Paper Pad help"
                manager.editor.Render()
                paperButton := manager.editor.visibleRows[2].primary
                this.Assert(InStr(paperButton.Text, "⚠") = 1 ? !flags[2] : flags[2],
                    "Pause binding receives a warning only when inactive: " label)
                this.Assert(paperButton.Enabled,
                    "Paper Pad Help remains reassignable while Pause is unavailable: " label)
                manager.editor.Close()
                if !flags[1] {
                    configuration := manager.GetConfiguration()
                    configuration["paper-pad.toggle"].bindings[1] := "CapsLock"
                    manager.Apply(configuration)
                    this.Assert(this.Route(manager, "paper-pad.toggle").enabled,
                        "disabled Caps prefix may be explicitly reassigned: " label)
                }
                if IsObject(manager.client) {
                    manager.client.Start()
                    this.Assert(manager.client.prefixes.Length = (flags[1] ? 1 : 0) + (flags[2] ? 2 : 0),
                        "only enabled native prefixes are installed: " label)
                    manager.client.Stop()
                }
            }
            finally manager.Stop()
        }
    }

    static CapsLockDoubleTap() {
        for choice in ["Shift", "Ctrl", "Alt"] {
            vk := Map("Shift", 0xA0, "Ctrl", 0xA2, "Alt", 0xA4)[choice]
            sc := Map("Shift", 0x02A, "Ctrl", 0x01D, "Alt", 0x038)[choice]
            detector := CapsLockModifierToggle(choice)
            detector.HandleDown(vk, sc, 100, false)
            this.Assert(!detector.HandleUp(vk, sc, 150, false),
                "first " choice " tap does not toggle Caps Lock")
            detector.HandleDown(vk, sc, 260, false)
            this.Assert(detector.HandleUp(vk, sc, 300, false),
                "second " choice " tap toggles Caps Lock")
            detector.HandleDown(vk, sc, 500, false)
            detector.HandleUp(vk, sc, 550, false)
            detector.HandleDown(0x41, 0x01E, 560, false)
            detector.HandleUp(0x41, 0x01E, 575, false)
            detector.HandleDown(vk, sc, 640, false)
            this.Assert(!detector.HandleUp(vk, sc, 680, false),
                "typing between " choice " taps cancels the sequence")
            detector.Reset()
            detector.HandleDown(vk, sc, 800, true)
            this.Assert(!detector.HandleUp(vk, sc, 840, false),
                "modifier chords do not start a double-tap")
            detector.HandleDown(vk, sc, 1000, false)
            detector.HandleUp(vk, sc, 1060, false)
            detector.HandleDown(vk, sc, 1500, false)
            this.Assert(!detector.HandleUp(vk, sc, 1540, false),
                "slow " choice " double-taps do not toggle")
            detector.Reset()
            detector.HandleDown(vk, sc, 1800, false)
            detector.HandleDown(vk, sc, 1820, false)
            detector.HandleUp(vk, sc, 1850, false)
            detector.HandleDown(vk, sc, 1950, false)
            this.Assert(detector.HandleUp(vk, sc, 1990, false),
                "key repeat does not count as a separate tap")
            detector.Stop()
        }
        SuiteChecks.Rejects((*) => CapsLockModifierToggle("CapsLock"),
            "CapsLock cannot be its own double-tap modifier")
    }

    static LayerDoubleTapGestures() {
        caps := Keybindings.Parse("Caps + Caps")
        pauseBinding := Keybindings.Parse("Pause + Pause")
        this.Assert(caps.doubleTap && caps.layer = "caps" && caps.modifiers = 0
            && caps.label = "Caps + Caps"
            && Keybindings.Parse(caps.signature).signature = caps.signature,
            "Caps + Caps is an explicit, persisted double-tap shortcut")
        this.Assert(pauseBinding.doubleTap && pauseBinding.layer = "pause" && pauseBinding.modifiers = 0
            && pauseBinding.label = "Pause + Pause"
            && Keybindings.Parse(pauseBinding.signature).signature = pauseBinding.signature,
            "Pause + Pause is an explicit, persisted double-tap shortcut")
        this.Assert(!Keybindings.Parse("Caps + F1").doubleTap
            && !Keybindings.Parse("Pause + F1").doubleTap,
            "ordinary layer chords remain normal bindings")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Caps + Pause"),
            "Caps cannot use the opposite activation key as a suffix")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Pause + CapsLock"),
            "Pause cannot use the opposite activation key as a suffix")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Pause + CtrlBreak"),
            "CtrlBreak cannot duplicate the Pause double-tap gesture")
        SuiteChecks.Rejects((*) => Keybindings.Parse("Caps + Ctrl + Caps"),
            "self-prefix double-taps cannot include extra modifiers")

        this.Assert(KeyboardLayers.OneShotMs = 1400
            && KeyboardLayers.DoubleTapCandidate("caps", "caps", 1500, 1499)
            && !KeyboardLayers.DoubleTapCandidate("caps", "caps", 1500, 1500)
            && !KeyboardLayers.DoubleTapCandidate("pause", "caps", 1500, 200)
            && !KeyboardLayers.DoubleTapCandidate("", "caps", 1500, 200),
            "a second tap uses the exact 1400 ms one-shot deadline")
        layer := {started: 100, used: false, doubleTap: true}
        this.Assert(KeyboardLayers.DoubleTapCompleted(layer, true, 340, 0, true)
            && !KeyboardLayers.DoubleTapCompleted(layer, true, 351, 0, true)
            && !KeyboardLayers.DoubleTapCompleted(layer, true, 200, 1, true),
            "the second tap must be released quickly without modifiers")
        layer.used := true
        this.Assert(!KeyboardLayers.DoubleTapCompleted(layer, true, 200, 0, true),
            "using a held layer chord suppresses its double-tap shortcut")
        layer.used := false
        layer.doubleTap := false
        this.Assert(!KeyboardLayers.DoubleTapCompleted(layer, true, 200, 0, true),
            "an ordinary first tap or tap-then-hold never counts as a double-tap")

        app := SuiteApplication(true, SuiteChecks.directory "\layer-self-double-taps")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            config := manager.GetConfiguration()
            config["power-up-utilities.system.wake-speakers"].bindings[1] := ""
            config["paper-pad.toggle"].bindings[1] := "Caps + Caps"
            config["paper-pad.help"].bindings[2] := "Pause + Pause"
            manager.Apply(config)
            this.Assert(manager.GetConfiguration()["paper-pad.toggle"].bindings[1] = caps.signature
                && manager.GetConfiguration()["paper-pad.help"].bindings[2] = pauseBinding.signature,
                "manual self-prefix assignments save through normal Keybindings")
            this.Assert(manager.routeMap.Has(caps.signature) && manager.routeMap.Has(pauseBinding.signature)
                && !manager.variants.Has(caps.signature) && !manager.variants.Has(pauseBinding.signature)
                && !manager.groups.Has(caps.key) && !manager.groups.Has(pauseBinding.key),
                "double-tap shortcuts never register native activation-key suffix hooks")
            conflicting := manager.GetConfiguration()
            conflicting["paper-pad.help"].bindings[1] := "Caps + Caps"
            SuiteChecks.Rejects((*) => manager.Apply(conflicting),
                "two double-tap actions in the same context still conflict")
            this.Assert(manager.GetConfiguration()["paper-pad.toggle"].bindings[1] = caps.signature,
                "rejected double-tap conflict preserves the saved configuration")
        }
        finally manager.Stop()
    }

    static LayerChordReleaseOrder() {
        key := Keybindings.Parse("C").key
        previousCritical := Critical("On")
        try {
            for layerName in ["caps", "pause"] {
                for suffixFirst in [true, false] {
                    fixture := this.LayerFixture("chord-" layerName "-" suffixFirst)
                    try {
                        this.HoldLayer(fixture.layers, layerName)
                        fixture.manager._KeyDown(Keybindings.Parse(
                            (layerName = "caps" ? "Caps" : "Pause") " + C").signature)
                        if suffixFirst {
                            fixture.manager._KeyUp(key)
                            fixture.layers.FinishPrefix(layerName)
                        } else {
                            fixture.layers.FinishPrefix(layerName)
                            fixture.manager._KeyUp(key)
                        }
                        fixture.manager._Drain()
                        this.Assert(this.Phases(fixture) = "fixture." layerName ":down,fixture." layerName ":up",
                            layerName " chord completes once regardless of release order: "
                            (suffixFirst ? "suffix first" : "prefix first"))
                    }
                    finally fixture.manager.Stop()
                }
            }
        }
        finally Critical(previousCritical)
    }

    ; Layer suffixes and ordinary hotkeys share one dispatcher.
    ; Only a whilePaused action answers during a pause that allows it, such as
    ; the suspend toggle while the suite is suspended.
    static WhilePausedRoutes() {
        pauseChord := Keybindings.Parse("Pause + C").signature
        previousCritical := Critical("On")
        try {
            fixture := this.LayerFixture("while-paused")
            manager := fixture.manager
            layers := fixture.layers
            try {
                this.Route(manager, "fixture.pause").action.whilePaused := true
                manager.paused := manager.gated := true
                this.HoldLayer(layers, "pause")
                this.Assert(!manager._Eligible(pauseChord),
                    "a pause that does not allow it silences a whilePaused action")
                manager.whilePausedOpen := true
                this.Assert(manager._Eligible(pauseChord), "a whilePaused action answers while suspended")
                this.Assert(!manager._Eligible(Keybindings.Parse("C").signature),
                    "ordinary actions stay silent while suspended")
                this.HoldLayer(layers, "caps")
                this.Assert(!manager._Eligible(Keybindings.Parse("Caps + C").signature),
                    "other layer actions stay silent while suspended")
                this.HoldLayer(layers, "pause")
                manager.externalCapture := true
                this.Assert(!manager._Eligible(pauseChord), "recording a hotkey silences even a whilePaused action")
            }
            finally manager.Stop()
        }
        finally Critical(previousCritical)
    }

    static LayerDispatch() {
        key := Keybindings.Parse("C").key
        capsChord := Keybindings.Parse("Caps + C").signature
        plain := Keybindings.Parse("C").signature
        previousCritical := Critical("On")
        try {
            fixture := this.LayerFixture("dispatch-hold")
            manager := fixture.manager
            layers := fixture.layers
            try {
                this.Assert(manager._Eligible(plain) && !manager._Eligible(capsChord),
                    "without a layer only the ordinary hotkey is eligible")
                this.HoldLayer(layers, "caps")
                this.Assert(!manager._Eligible(plain) && manager._Eligible(capsChord),
                    "a held layer claims its suffix and ordinary hotkeys stand aside")
                manager._KeyDown(capsChord)
                manager._GuardDown(key)
                manager._KeyUp(key)
                manager._Drain()
                this.Assert(this.Phases(fixture) = "fixture.caps:down,fixture.caps:repeat,fixture.caps:up"
                    && layers.layers["caps"].used,
                    "a held chord repeats, completes and marks its prefix as used")
            }
            finally manager.Stop()

            fixture := this.LayerFixture("dispatch-tap")
            manager := fixture.manager
            layers := fixture.layers
            try {
                this.HoldLayer(layers, "caps")
                layers.FinishPrefix("caps")
                this.Assert(layers.armed = "caps" && !manager._Eligible(plain)
                    && manager._Eligible(capsChord),
                    "a quick tap arms the layer for the next key")
                manager._KeyDown(capsChord)
                manager._GuardDown(key)
                manager._KeyUp(key)
                manager._Drain()
                this.Assert(this.Phases(fixture) = "fixture.caps:down*,fixture.caps:up*"
                    && layers.armed = "" && manager._Eligible(plain),
                    "an armed key is one non-repeating one-shot press that consumes the arm")
            }
            finally manager.Stop()

            fixture := this.LayerFixture("dispatch-switch")
            manager := fixture.manager
            layers := fixture.layers
            try {
                this.HoldLayer(layers, "caps")
                manager._KeyDown(capsChord)
                layers._PrefixDown("pause", "Pause")
                manager._Drain()
                this.Assert(this.Phases(fixture) = "fixture.caps:down,fixture.caps:cancel"
                    && layers.selected = "pause",
                    "switching to the other prefix cancels the first layer's chord")
            }
            finally manager.Stop()

            fixture := this.LayerFixture("dispatch-double")
            manager := fixture.manager
            layers := fixture.layers
            try {
                this.HoldLayer(layers, "caps")
                layers.FinishPrefix("caps")
                layers._PrefixDown("caps", "CapsLock")
                layers.FinishPrefix("caps")
                manager._Drain()
                this.Assert(this.Phases(fixture) = "fixture.double:down*,fixture.double:up*"
                    && layers.armed = "",
                    "a double-tap dispatches one complete press and does not re-arm")
            }
            finally manager.Stop()
        }
        finally Critical(previousCritical)
    }

    static LayerRecordingGestures() {
        ; Verify the recorder's state transitions without actual key injection.
        for prefix in ["caps", "pause"] {
            record := {prefixDown: "", prefixDownAt: 0, prefixUsed: false,
                prefixCancel: false, armedLayer: "", armedAt: 0}
            this.Assert(KeybindingsEditor.RecordingPrefixDown(record, prefix, 100)
                && KeybindingsEditor.RecordingPrefixUp(record, prefix, 180, 0) = "armed"
                && KeybindingsEditor.RecordingOneShotLayer(record, 1579) = prefix
                && KeybindingsEditor.RecordingOneShotLayer(record, 1580) = ""
                && KeybindingsEditor.RecordingOneShotLayer(record, 1581) = "",
                prefix " tap arms one-shot recording for the next key")
            this.Assert(!KeybindingsEditor.RecordingBareKey(record, "normal", 200, 0)
                && KeybindingsEditor.RecordingBareKey(record, "normal", 1581, 0),
                prefix " one-shot Escape/Backspace are recorded, not cancelled or cleared")

            this.Assert(KeybindingsEditor.RecordingPrefixDown(record, prefix, 350)
                && record.prefixCancel
                && KeybindingsEditor.RecordingPrefixUp(record, prefix, 490, 0) = "double",
                prefix " double-tap is recognized only after second quick release")
            this.Assert(record.armedLayer = "" && record.prefixDown = "",
                prefix " double-tap consumes the one-shot state")

            KeybindingsEditor.RecordingPrefixDown(record, prefix, 600)
            KeybindingsEditor.RecordingPrefixUp(record, prefix, 680, 0)
            this.Assert(KeybindingsEditor.RecordingPrefixDown(record, prefix, 2079)
                && record.prefixCancel
                && KeybindingsEditor.RecordingPrefixUp(record, prefix, 2119, 0) = "double",
                prefix " double-tap accepts the full one-shot window")

            KeybindingsEditor.RecordingPrefixDown(record, prefix, 3000)
            KeybindingsEditor.RecordingPrefixUp(record, prefix, 3070, 0)
            this.Assert(KeybindingsEditor.RecordingPrefixDown(record, prefix, 4470)
                && !record.prefixCancel
                && KeybindingsEditor.RecordingPrefixUp(record, prefix, 4540, 0) = "armed",
                prefix " at the expired one-shot deadline a new tap begins")

            KeybindingsEditor.RecordingPrefixDown(record, prefix, 4700)
            this.Assert(record.prefixCancel
                && KeybindingsEditor.RecordingPrefixUp(record, prefix, 5000, 0) = "",
                prefix " tap then hold does not record double-tap")

            KeybindingsEditor.RecordingPrefixDown(record, prefix, 5500)
            record.prefixUsed := true
            this.Assert(KeybindingsEditor.RecordingPrefixUp(record, prefix, 5550, 0) = ""
                && record.armedLayer = "",
                prefix " hold-plus-key does not become one-shot recording")
            KeybindingsEditor.RecordingPrefixDown(record, prefix, 6000)
            this.Assert(KeybindingsEditor.RecordingPrefixUp(record, prefix, 6050, 1) = ""
                && record.armedLayer = "",
                prefix " with modifiers cannot arm a tap")
        }
    }

    static LayerIndicatorDelay() {
        layers := KeyboardLayers({}, Map("caps", true, "pause", true))
        tapMs := KeyboardLayers.TapMaxMs
        this.Assert(!layers.HeldIndicatorReady(), "idle layers have no held indicator")
        layers.selected := "caps"
        caps := layers.layers["caps"]
        caps.down := true
        caps.started := KeyboardLayers.Now()
        this.Assert(!layers.HeldIndicatorReady(), "initial Caps press hides held indicator")
        caps.started := KeyboardLayers.Now() - tapMs + 50
        this.Assert(!layers.HeldIndicatorReady(), "quick Caps tap hides held indicator")
        caps.started := KeyboardLayers.Now() - tapMs - 50
        this.Assert(layers.HeldIndicatorReady(), "held Caps passes tap threshold")
        caps.down := false
        this.Assert(!layers.HeldIndicatorReady(), "Caps release cancels held indicator")
        layers.selected := "pause"
        pauseLayer := layers.layers["pause"]
        pauseLayer.down := true
        pauseLayer.started := KeyboardLayers.Now() - tapMs - 50
        this.Assert(layers.HeldIndicatorReady(), "held Pause passes tap threshold")
        layers.selected := ""
        this.Assert(!layers.HeldIndicatorReady(), "clearing Pause removes held indicator")
    }

    static ScopesAndObservers() {
        for layered in [false, true] {
            suffix := layered ? "layer" : "ordinary"
            options := {directory: SuiteChecks.directory "\scopes-" suffix}
            if layered
                options.layerFactory := (owner) => KeyboardLayers(owner, Map("caps", true, "pause", false))
            manager := Keybindings("scope-check-" suffix, "Scope check", options)
            try {
                manager.RegisterScope("editor", (*) => this.scopeActive)
                manager.RegisterScope("terminal", (*) => this.terminalScopeActive)
                manager.RegisterDisjointScopes("editor", "terminal")
                binding := layered ? "Caps + F8" : "Ctrl + Alt + F8"
                manager.AddAction("inside", "inside editor", (*) => 0, [binding], {scope: "editor"})
                manager.AddAction("outside", "outside editor", (*) => 0, [binding], {scope: "!editor"})
                manager.AddAction("global", "global action", (*) => 0, [])
                alternate := layered ? "Caps + F9" : "Ctrl + Alt + F9"
                manager.AddAction("editor-alt", "editor action", (*) => 0, [alternate],
                    {scope: "editor"})
                manager.AddAction("terminal-alt", "terminal action", (*) => 0, [alternate],
                    {scope: "terminal"})
                SuiteChecks.Rejects((*) => manager.AddAction("unknown", "unknown scope", (*) => 0, [],
                    {scope: "missing"}), "unknown scope names cannot bypass conflicts: " suffix)
                manager.SetPaused(true)
                manager.Start()
                signature := Keybindings.Parse(binding).signature
                this.Assert(manager.routeMap[signature].Length = 2,
                    "explicit complementary scopes may share one physical binding: " suffix)
                alternateSignature := Keybindings.Parse(alternate).signature
                this.Assert(manager.routeMap[alternateSignature].Length = 2,
                    "explicitly disjoint editor and Terminal scopes may share a key: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "terminal-alt",
                    "Terminal-only route selected in Terminal: " suffix)
                this.terminalScopeActive := false
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "editor-alt",
                    "editor-only route selected in the editor: " suffix)
                this.scopeActive := false
                this.Assert(manager._SelectedRoute(signature).action.id = "outside", "outside scope routing: " suffix)
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(signature).action.id = "inside", "inside scope routing: " suffix)
                configuration := manager.GetConfiguration()
                configuration["global"].bindings[1] := binding
                before := FileRead(manager.path)
                SuiteChecks.Rejects((*) => manager.Apply(configuration), "a global collision is still rejected: " suffix)
                this.Assert(FileRead(manager.path) = before, "scope conflict does not overwrite saved bindings: " suffix)
                configuration["global"].bindings[1] := alternate
                manager.Apply(configuration)
                this.Assert(manager.routeMap[alternateSignature].Length = 3,
                    "global fallback shares an explicit scoped shortcut: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := false
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "global",
                    "global fallback works outside scoped windows: " suffix)
                this.scopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "editor-alt",
                    "editor scope overrides the global fallback: " suffix)
                this.scopeActive := false
                this.terminalScopeActive := true
                this.Assert(manager._SelectedRoute(alternateSignature).action.id = "terminal-alt",
                    "Terminal scope overrides the global fallback: " suffix)
                this.terminalScopeActive := false
                overlapping := manager.GetConfiguration()
                overlapping["inside"].bindings[1] := alternate
                before := FileRead(manager.path)
                SuiteChecks.Rejects((*) => manager.Apply(overlapping),
                    "two overlapping editor shortcuts still conflict: " suffix)
                this.Assert(FileRead(manager.path) = before,
                    "overlapping scoped conflict preserves saved assignments: " suffix)
                if layered
                    this.Assert(this.Route(manager, "inside").binding.layer = "caps"
                        && IsObject(manager.client),
                        "layer suffixes share the same scoped routes")
                this.observerCalls := 0
                for unused in [1, 2]
                    manager.Observe("~*F24", (*) => true, (*) => this.observerCalls += 1, true)
                this.Assert(manager.observers.Length = 1, "identical passive observers share one native variant: " suffix)
                manager._DispatchObserver("~*F24")
                this.Assert(this.observerCalls = 2, "both modules receive the passive observation: " suffix)
                ; Pass-through observers are global variants, so the hook never
                ; waits on this thread for them; AutoHotkey ranks a global variant
                ; last, so a claim such as a focus-tab click still wins on a tab.
                claiming := false
                manager.Observe("*F24", (*) => claiming, (*) => 0, true)
                this.Assert(!manager.observerGroups["~*F24"].predicate
                    && IsObject(manager.observerGroups["*F24"].predicate),
                    "only observers that claim input keep a context check: " suffix)
                this.Assert(!manager._ObserverEligible("*F24"),
                    "a claiming observer stays out of ordinary input: " suffix)
                claiming := true
                this.Assert(manager._ObserverEligible("*F24"),
                    "a claiming observer takes the input when its context holds: " suffix)
            }
            finally {
                manager.Stop()
                this.scopeActive := false
                this.terminalScopeActive := false
            }
        }
    }

    static AssertDisplaySequence(rows, actionIds, label) {
        ; Each visible action must follow its predecessor. Missing actions fail
        ; too, so an accidental rename or deletion cannot pass unnoticed.
        positions := Map()
        for index, row in rows
            if row.id != ""
                positions[row.id] := index
        previous := 0
        ordered := true
        for actionId in actionIds {
            if !positions.Has(actionId) || positions[actionId] <= previous {
                ordered := false
                break
            }
            previous := positions[actionId]
        }
        this.Assert(ordered, label)
    }

    static CheckDisplayOrder(rows) {
        this.AssertDisplaySequence(rows, [
            "core.keybindings", "core.close-active", "core.clear-log", "core.copy-log",
            "core.restart", "core.suspend"],
            "Global shortcuts group application first, logs together, then restart")
        this.AssertDisplaySequence(rows, [
            "paper-pad.help", "paper-pad.toggle", "paper-pad.hide",
            "paper-pad.previous", "paper-pad.next", "paper-pad.delete"],
            "Paper Pad shows and hides, then navigates, then deletes")
        this.AssertDisplaySequence(rows, [
            "cascade-kingdom.help", "cascade-kingdom.focus-previous", "cascade-kingdom.focus-next",
            "cascade-kingdom.slot-previous", "cascade-kingdom.slot-next",
            "cascade-kingdom.swap-up", "cascade-kingdom.swap-down",
            "cascade-kingdom.rotate-next",
            "cascade-kingdom.adopt", "cascade-kingdom.release", "cascade-kingdom.bring-forward",
            "cascade-kingdom.minimize", "cascade-kingdom.restore", "cascade-kingdom.gather",
            "cascade-kingdom.close-monitor"],
            "Cascade Kingdom groups navigation, rotation and management")
        this.AssertDisplaySequence(rows, [
            "wonder-windows.help",
            "wonder-windows.zones-from-left", "wonder-windows.zones-from-right",
            "wonder-windows.maximize", "wonder-windows.restore", "wonder-windows.stretch",
            "wonder-windows.move-onto-up", "wonder-windows.move-onto-down",
            "wonder-windows.move-onto-left", "wonder-windows.move-onto-right",
            "wonder-windows.focus-up", "wonder-windows.focus-down",
            "wonder-windows.cycle-stacked",
            "wonder-windows.minimize", "wonder-windows.restore-minimized"],
            "Wonder Windows groups placing, resizing, relocating, switching and minimizing")
        this.AssertDisplaySequence(rows, [
            "power-up-utilities.help", "power-up-utilities.system.wake-speakers",
            "power-up-utilities.system.sleep",
            "power-up-utilities.terminal.copy", "power-up-utilities.terminal.clear"],
            "Power-Up Utilities groups system and Terminal controls")
        this.AssertDisplaySequence(rows, [
            "power-up-utilities.keyboard.f13", "power-up-utilities.keyboard.f18",
            "power-up-utilities.keyboard.f24"],
            "extra function keys follow numeric order")
        this.AssertDisplaySequence(rows, [
            "power-up-utilities.keyboard.numpad0", "power-up-utilities.keyboard.numpad5",
            "power-up-utilities.keyboard.numpad9"],
            "virtual number pad follows numeric order")
        this.AssertDisplaySequence(rows, [
            "power-up-utilities.text.apostrophe", "power-up-utilities.text.en-dash",
            "power-up-utilities.text.nbsp", "power-up-utilities.text.sharp-s",
            "power-up-utilities.text.timestamp"],
            "text utilities keep characters together before timestamp")
        this.AssertDisplaySequence(rows, [
            "secret-layers.help", "secret-layers.toggle-caps"],
            "Secret Layers keeps Help first")
        powerHeadings := []
        for row in rows
            if row.id = "" && InStr(row.label, "Power-Up Utilities") = 1
                powerHeadings.Push(row.label)
        this.Assert(powerHeadings.Length = 4
            && powerHeadings[1] = "Power-Up Utilities"
            && powerHeadings[2] = "Power-Up Utilities / Text and symbols"
            && powerHeadings[3] = "Power-Up Utilities / Extra function keys"
            && powerHeadings[4] = "Power-Up Utilities / Virtual number pad",
            "text actions precede the long runs of virtual keys")
        wonderHeadings := []
        for row in rows
            if row.id = "" && InStr(row.label, "Wonder Windows") = 1
                wonderHeadings.Push(row.label)
        expectedWonder := ["Wonder Windows"]
        wonderOrdered := wonderHeadings.Length = expectedWonder.Length
        for index, heading in expectedWonder
            wonderOrdered := wonderOrdered && wonderHeadings.Has(index) && wonderHeadings[index] = heading
        this.Assert(wonderOrdered, "Wonder Windows keeps its actions under one heading")
    }

    static RouteExists(manager, actionId) {
        for route in manager.routes
            if route.action.id = actionId && route.enabled
                return true
        return false
    }

    static ActiveShortcutVisibility() {
        app := SuiteApplication(true, SuiteChecks.directory "\visibility")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            groups := Map("Power-Up Utilities", 0,
                "Power-Up Utilities / Extra function keys", 0,
                "Power-Up Utilities / Virtual number pad", 0,
                "Power-Up Utilities / Text and symbols", 0)
            for actionId, action in manager.actions {
                if InStr(actionId, "power-up-utilities.") != 1
                    || actionId = "secret-layers.toggle-caps"
                    continue
                this.Assert(groups.Has(action.category),
                    "Power-Up Utilities keeps only useful subcategories: " actionId)
                groups[action.category] += 1
            }
            this.Assert(manager.actions["power-up-utilities.terminal.copy"].category = "Power-Up Utilities"
                && manager.actions["power-up-utilities.terminal.clear"].category = "Power-Up Utilities",
                "Windows Terminal actions share the main category")
            this.Assert(groups["Power-Up Utilities / Extra function keys"] = 12
                && groups["Power-Up Utilities / Virtual number pad"] = 10
                && groups["Power-Up Utilities / Text and symbols"] = 5,
                "large coherent Power-Up Utilities feature sets have their own headings")
            this.Assert(groups["Power-Up Utilities"] > 0,
                "individual utilities remain directly under Power-Up Utilities")
            this.Assert(manager.actions["core.keybindings"].category = "Global"
                && manager.actions["core.copy-log"].category = "Global"
                && manager.actions["core.clear-log"].category = "Global",
                "core and debug actions share one Global display heading")
            rows := Keybindings.DisplayRows(manager.Catalog())
            this.CheckDisplayOrder(rows)
            actionScopes := Map()
            cleanHeadings := true
            for row in rows {
                if row.id = "" {
                    if HasProp(row, "scope")
                        cleanHeadings := false
                } else
                    actionScopes[row.id] := row.scope
            }
            this.Assert(cleanHeadings && actionScopes["paper-pad.delete"] = "paper-pad"
                && actionScopes["power-up-utilities.terminal.copy"] = "windows-terminal",
                "scopes belong to action descriptions rather than category headings")
            this.Assert(actionScopes["core.keybindings"] = ""
                && KeybindingsEditor.ContextTagText("!paper-pad") = ""
                && KeybindingsEditor.ContextTagText("paper-pad") = "editor only"
                && KeybindingsEditor.ContextTagText("windows-terminal") = "terminal only",
                "only application-specific shortcuts receive readable context tags")
            this.Assert(manager.actions["wonder-windows.zones-from-left"].scope = ""
                && manager.actions["paper-pad.previous"].scope = "paper-pad",
                "Wonder Windows is a global fallback for Paper Pad editor shortcuts")
            this.Assert(manager.actions["power-up-utilities.terminal.clear"].scope = "windows-terminal"
                && manager.actions["power-up-utilities.terminal.copy"].scope = "windows-terminal",
                "Terminal shortcuts are gated by the actual foreground application")
            mainHeadings := []
            activeParent := ""
            subcategoriesFollowParent := true
            for row in rows {
                if row.id != ""
                    continue
                separator := InStr(row.label, " / ")
                if separator {
                    if SubStr(row.label, 1, separator - 1) != activeParent
                        subcategoriesFollowParent := false
                } else {
                    activeParent := row.label
                    mainHeadings.Push(row.label)
                }
            }
            expectedOrder := ["Global", "Paper Pad", "Cascade Kingdom",
                "Wonder Windows", "Power-Up Utilities", "Secret Layers"]
            this.Assert(mainHeadings.Length = expectedOrder.Length,
                "Keybindings includes exactly the five assignable sections")
            for index, expectedName in expectedOrder
                this.Assert(mainHeadings[index] = expectedName,
                    "Keybindings section order: " expectedName)
            this.Assert(subcategoriesFollowParent,
                "all Keybindings subcategories stay immediately after their main section")
            paperSection := 0
            for index, row in rows
                if row.id = "" && row.label = "Paper Pad" {
                    paperSection := index
                    break
                }
            this.Assert(paperSection > 0 && rows[paperSection + 1].id = "paper-pad.help"
                && rows[paperSection + 2].id = "paper-pad.toggle"
                && rows[paperSection + 3].id = "paper-pad.hide"
                && rows[paperSection + 6].id = "paper-pad.delete",
                "Paper Pad keeps all actions under one heading")
            expectedHelp := Map("Paper Pad", "paper-pad.help",
                "Cascade Kingdom", "cascade-kingdom.help",
                "Wonder Windows", "wonder-windows.help",
                "Power-Up Utilities", "power-up-utilities.help",
                "Secret Layers", "secret-layers.help")
            for index, row in rows {
                if row.id != "" || !expectedHelp.Has(row.label)
                    continue
                this.Assert(index < rows.Length && rows[index + 1].id = expectedHelp[row.label],
                    row.label " displays its Help shortcut first")
            }
            saved := manager.GetConfiguration()
            this.Assert(saved["core.clear-log"].bindings[1]
                    = Keybindings.Parse("Pause + F1").signature
                && saved["core.copy-log"].bindings[1]
                    = Keybindings.Parse("Pause + F2").signature,
                "debug log hotkeys default to Pause + F1/F2")
            this.Assert(saved["paper-pad.help"].bindings[1]
                = Keybindings.Parse("Pause + F12").signature
                && saved["paper-pad.help"].bindings[2] = "",
                "Paper Pad Help defaults to Pause + F12")
            this.Assert(saved["secret-layers.help"].bindings[1] = ""
                && saved["secret-layers.help"].bindings[2] = "",
                "Secret Layers Help remains unassigned by default")
            this.Assert(manager.actions["secret-layers.toggle-caps"].category = "Secret Layers"
                && saved["secret-layers.toggle-caps"].bindings[1] = "",
                "Caps Lock toggle belongs to Secret Layers and defaults unassigned")
            this.Assert(saved["cascade-kingdom.help"].bindings[1]
                = Keybindings.Parse("Caps + H").signature
                && saved["wonder-windows.help"].bindings[1]
                    = Keybindings.Parse("Ctrl + Alt + H").signature
                && saved["power-up-utilities.help"].bindings[1]
                    = Keybindings.Parse("Pause + H").signature,
                "existing module Help shortcuts retain their original defaults")
            this.Assert(this.RouteExists(manager, "paper-pad.help"),
                "Paper Pad Help registers its default Pause + F12 shortcut")
            this.Assert(!this.RouteExists(manager, "secret-layers.help"),
                "unassigned Secret Layers Help installs no shortcut")
            this.Assert(InStr(app.modules["secret-layers"].HelpText(), "WHY I MADE THIS") = 1
                && !InStr(app.modules["secret-layers"].HelpText(), "CURRENT SAVED SHORTCUTS"),
                "Secret Layers help provides a practical guide without a shortcut inventory")
            filtered := Keybindings.DisplayRows(manager.Catalog(), "paper-pad.")
            this.Assert(filtered.Length = 7 && filtered[1].label = "Paper Pad"
                && filtered[2].id = "paper-pad.help"
                && filtered[7].id = "paper-pad.delete",
                "filtered Paper Pad actions share one heading")
            generalHeading := 0
            functionHeading := 0
            for index, row in rows {
                if row.id = "" && row.label = "Power-Up Utilities"
                    generalHeading := index
                if row.id = "" && row.label = "Power-Up Utilities / Extra function keys"
                    functionHeading := index
            }
            this.Assert(generalHeading > 0 && functionHeading > generalHeading,
                "general Power-Up Utilities shortcuts precede specialized subcategories")
            sample := [
                {id: "alpha.first", category: "Alpha / Shortcuts", label: "first",
                    scope: "", bindings: ["", ""]},
                {id: "beta.one", category: "Beta", label: "other module",
                    scope: "", bindings: ["", ""]},
                {id: "alpha.second", category: "Alpha / Extensions", label: "second",
                    scope: "", bindings: ["", ""]},
                {id: "alpha.general", category: "Alpha", label: "general",
                    scope: "", bindings: ["", ""]}
            ]
            sampleRows := Keybindings.DisplayRows(sample)
            headings := []
            for row in sampleRows
                if row.id = ""
                    headings.Push(row.label)
            this.Assert(headings.Length = 4 && headings[1] = "Alpha"
                && headings[2] = "Alpha / Shortcuts"
                && headings[3] = "Alpha / Extensions" && headings[4] = "Beta",
                "subcategories follow their module immediately without interleaving")
            sampleRows := Keybindings.DisplayRows(sample, "Extensions")
            this.Assert(sampleRows.Length = 3 && sampleRows[1].label = "Alpha"
                && sampleRows[2].label = "Alpha / Extensions",
                "search keeps extension headings directly after their parent")
            this.Assert(!manager.actions.Has("wonder-windows.zone-left")
                && this.RouteExists(manager, "wonder-windows.zones-from-left"),
                "FancyZones forwarding is gone and zone cycling is registered")
            app.activeModules["paper-pad"] := false
            manager.Apply(manager.GetConfiguration())
            rows := Keybindings.DisplayRows(manager.Catalog())
            paperFound := false
            for row in rows
                if InStr(row.id, "paper-pad.") = 1
                    paperFound := true
            this.Assert(!paperFound, "disabled Paper Pad entries disappear completely")
            configuration := manager.GetConfiguration()
            this.Assert(configuration["paper-pad.toggle"].bindings[1] != "",
                "hidden module assignments remain safely stored")

            changed := manager.GetConfiguration()
            changed["power-up-utilities.keyboard.f13"].bindings[1] := "Ctrl + Alt + Left"
            manager.Apply(changed)
            this.Assert(this.RouteExists(manager, "power-up-utilities.keyboard.f13"),
                "the old FancyZones shortcuts are free for other actions")
            this.Assert(!InStr(Keybindings.DisplayRows(manager.Catalog())[1].label, "disabled"),
                "Keybindings headings do not acquire disabled suffixes")
        }
        finally {
            manager.Stop()
        }
    }

    static StagedKeybindings() {
        app := SuiteApplication(true, SuiteChecks.directory "\staged-keybindings")
        app.InitializeCatalog()
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            before := manager.GetConfiguration()["core.keybindings"].bindings[2]
            replacement := Keybindings.Parse("Ctrl + Alt + F11").signature
            this.Assert(before != replacement, "staged regression binding differs from the saved default")
            beforeFile := FileRead(manager.path, "UTF-8")
            manager.ShowSettings()
            candidate := manager._CloneConfiguration(manager.editor.draft)
            candidate["core.keybindings"].bindings[2] := replacement
            manager.editor.Stage(candidate)
            this.Assert(manager.editor.applyButton.Enabled
                && manager.editor.draft["core.keybindings"].bindings[2] = replacement
                && manager.GetConfiguration()["core.keybindings"].bindings[2] = before
                && FileRead(manager.path, "UTF-8") = beforeFile,
                "editing stages hotkeys without changing the live configuration or saved file")
            manager.editor.Close()
            manager.ShowSettings()
            this.Assert(manager.editor.draft["core.keybindings"].bindings[2] = before
                && !manager.editor.applyButton.Enabled,
                "closing Keybindings discards all uncommitted edits")
            manager.editor.Stage(candidate)
            this.Assert(manager.editor.ApplyStaged()
                && manager.GetConfiguration()["core.keybindings"].bindings[2] = replacement
                && KB_Manifest.Get(KB_Manifest.Read(manager.path), "bindings", "core.keybindings") != "",
                "Apply saves staged hotkeys without restarting")
            this.Assert(IsObject(manager.editor.window) && !manager.editor.HasPending()
                && !manager.editor.applyButton.Enabled,
                "Apply keeps Keybindings open and greys out once nothing is pending")
            manager.ShowSettings("cascade-kingdom")
            this.Assert(manager.editor.doneButton.Text = "Back"
                && manager.editor.applyButton.Text = "Apply"
                && manager.editor.moduleId = "cascade-kingdom",
                "module Keybindings provides Back and live Apply")
            unrelated := manager.editor.draft["core.keybindings"].bindings[2]
            moduleCandidate := manager._CloneConfiguration(manager.editor.draft)
            moduleCandidate["cascade-kingdom.help"].bindings[1] := Keybindings.Parse("Caps + F10").signature
            manager.editor.Stage(moduleCandidate)
            manager.editor.StageDefaults()
            this.Assert(manager.editor.draft["cascade-kingdom.help"].bindings[1]
                    = manager.actions["cascade-kingdom.help"].defaults[1]
                && manager.editor.draft["core.keybindings"].bindings[2] = unrelated,
                "module Restore defaults stages only that module's shortcuts")
            manager.editor.Close()
        }
        finally {
            if IsObject(manager.editor.window)
                manager.editor.Close()
            manager.Stop()
        }
    }
}
