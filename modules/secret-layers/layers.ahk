; Secret Layers' prefix engine. CapsLock and Pause become layer prefixes:
; hold one while pressing a key, or tap it to arm the next key for 1.4 s; a
; second tap cancels the layer or runs a double-tap action. Keybindings owns
; every suffix hotkey; this class owns only the prefix keys and tells it when
; a layer ends, is cancelled or is double-tapped.
class KeyboardLayers {
    static TapMaxMs := 250
    static PrefixLayers := Map("CapsLock", "caps", "Pause", "pause", "CtrlBreak", "pause")
    static OneShotMs := 1400
    static ReleasePollMs := 15

    ; layers: Map("caps", bool, "pause", bool) of the layers enabled in settings.
    __New(manager, layers) {
        this.manager := manager
        this.enabledLayers := Map("caps", !!layers["caps"], "pause", !!layers["pause"])
        this.layers := Map()
        for name in ["caps", "pause"]
            this.layers[name] := {down: false, used: false, started: 0,
                physicalKey: "", cancelTap: false, doubleTap: false}
        this.selected := ""
        this.armed := ""
        this.armedUntil := 0
        this.running := false
        this.disposed := false
        this.hooksInstalled := false
        this.prefixes := []
        this.blockedPrefixes := Map()
        this.showIndicator := true
        this.pollCallback := ObjBindMethod(this, "_CheckPrefixes")
        this.expireCallback := ObjBindMethod(this, "_ExpireArm")
        this.indicatorCallback := ObjBindMethod(this, "_UpdateIndicator")
        ; Any other key during a hold makes the prefix release a chord, not a tap.
        this.observer := InputHook("V L0 I101")
        this.observer.KeyOpt("{All}", "N")
        this.observer.OnKeyDown := ObjBindMethod(this, "_ObserveKey")
    }

    static Now() => DllCall("GetTickCount64", "uint64")

    LayerEnabled(layer) => this.enabledLayers.Has(layer) && this.enabledLayers[layer]

    OwnsPrefix(key) {
        vk := GetKeyVK(key)
        return (vk = 0x14 && this.LayerEnabled("caps"))
            || ((vk = 0x13 || vk = 3) && this.LayerEnabled("pause"))
    }

    IsHeld(layer) => this.selected = layer && this.layers[layer].down

    ; The layer currently accepts a suffix: held, or armed by a recent tap.
    Active(layer) {
        return this.running && this.LayerEnabled(layer) && (this.IsHeld(layer)
            || (this.selected = "" && this.armed = layer && KeyboardLayers.Now() < this.armedUntil))
    }

    ; While any layer is held or armed, ordinary hotkeys stand aside.
    Busy() => this.running && (this.selected != ""
        || (this.armed != "" && KeyboardLayers.Now() < this.armedUntil))

    ; A suffix of this layer was pressed. Returns true for a one-shot (armed) use.
    Use(layer) {
        if this.IsHeld(layer) {
            this.layers[layer].used := true
            this._UpdateIndicator()
            return false
        }
        this.Disarm()
        return true
    }

    ; only: a Map of the layers to run, such as the one layer a suspend toggle
    ; needs while the suite is suspended; the other prefixes stay native.
    Start(only := 0) {
        if this.disposed || this.running
            return
        HotIf()
        if !this.hooksInstalled {
            for key, layer in KeyboardLayers.PrefixLayers {
                if !this.LayerEnabled(layer)
                    continue
                Hotkey("$*" key, ObjBindMethod(this, "_PrefixDown", layer, key), "On I100 B0")
                Hotkey("$*" key " Up", ObjBindMethod(this, "_PrefixUp", layer, key), "On I100 B0")
                this.prefixes.Push(key)
            }
            this.hooksInstalled := true
        }
        ; Restore prefix interception only after the suite input gate reopens.
        for key in this.prefixes {
            state := !IsObject(only) || only.Has(KeyboardLayers.PrefixLayers[key]) ? "On" : "Off"
            Hotkey("$*" key, state)
            Hotkey("$*" key " Up", state)
        }
        this.running := true
        this.Reset()
    }

    ; Native CapsLock and Pause pass through while the gate is closed.
    Stop() {
        this.running := false
        this.Reset()
        if this.hooksInstalled {
            HotIf()
            for key in this.prefixes {
                Hotkey("$*" key, "Off")
                Hotkey("$*" key " Up", "Off")
            }
        }
    }

    Dispose() {
        if this.disposed
            return
        this.Stop()
        this.disposed := true
        SetTimer(this.pollCallback, 0)
        SetTimer(this.expireCallback, 0)
        SetTimer(this.indicatorCallback, 0)
        this.observer.Stop()
        SuiteNotice.Hide("layer")
    }

    Reset() {
        Critical
        SetTimer(this.indicatorCallback, 0)
        this.Disarm()
        this.selected := ""
        this.blockedPrefixes.Clear()
        for keyName in ["CapsLock", "Pause", "CtrlBreak"]
            if GetKeyState(keyName, "P")
                this.blockedPrefixes[keyName] := true
        for layerName, layer in this.layers {
            layer.down := false
            layer.used := true
            layer.cancelTap := true
            layer.doubleTap := false
            layer.physicalKey := ""
        }
        this._UpdateObserver()
        this._UpdatePoll()
        this._UpdateIndicator()
    }

    _PrefixDown(layerName, physicalKey, *) {
        Critical
        if !this.running || !this.LayerEnabled(layerName) || this.blockedPrefixes.Has(physicalKey)
            return
        layer := this.layers[layerName]
        if layer.down
            return
        ; A second prefix tap uses the same one-shot deadline as another key.
        doubleTap := KeyboardLayers.DoubleTapCandidate(this.armed, layerName,
            this.armedUntil, KeyboardLayers.Now())
        this.Disarm()
        ; Switching prefixes cancels previous holds rather than ambiguously stacking.
        if this.selected != "" && this.selected != layerName {
            this.layers[this.selected].used := true
            this.manager._LayerCancelled(this.selected)
        }
        ; Do not reinterpret an already-held typing key as a new layer chord.
        held := this.manager.BlockHeldKeys()
        layer.down := true
        layer.used := held > 0
        layer.started := KeyboardLayers.Now()
        layer.physicalKey := physicalKey
        layer.cancelTap := doubleTap
        layer.doubleTap := doubleTap
        this.selected := layerName
        this._UpdateObserver()
        this._UpdatePoll()
        this._UpdateIndicator()
        ; A tap must not flash the held state before it becomes a genuine hold.
        SetTimer(this.indicatorCallback, -(KeyboardLayers.TapMaxMs + KeyboardLayers.ReleasePollMs))
    }

    _PrefixUp(layerName, physicalKey, *) {
        Critical
        if this.blockedPrefixes.Has(physicalKey)
            this.blockedPrefixes.Delete(physicalKey)
        layer := this.layers[layerName]
        if !layer.down || layer.physicalKey != physicalKey
            return
        this.FinishPrefix(layerName)
    }

    ; The prefix was released: complete its chords, arm a quick tap, or
    ; deliver a completed double-tap.
    FinishPrefix(layerName) {
        layer := this.layers[layerName]
        selected := this.selected = layerName
        if selected
            SetTimer(this.indicatorCallback, 0)
        now := KeyboardLayers.Now()
        modifiers := Keybindings.ModifierMask()
        shouldArm := selected && !layer.used && !layer.cancelTap
            && now - layer.started <= KeyboardLayers.TapMaxMs
            && modifiers = 0 && this.running
        doubleTap := KeyboardLayers.DoubleTapCompleted(layer, selected, now, modifiers, this.running)

        layer.down := false
        layer.doubleTap := false
        layer.physicalKey := ""
        if selected
            this.selected := ""
        this.manager._LayerReleased(layerName)
        if shouldArm {
            this.armed := layerName
            this.armedUntil := KeyboardLayers.Now() + KeyboardLayers.OneShotMs
            SetTimer(this.expireCallback, -KeyboardLayers.OneShotMs)
        }
        this._UpdateObserver()
        this._UpdatePoll()
        this._UpdateIndicator()
        if doubleTap
            this.manager._LayerDoubleTap(layerName)
    }

    ; The prefix remains a double-tap candidate only while one-shot is armed.
    static DoubleTapCandidate(armed, layerName, armedUntil, now) {
        return armed = layerName && now < armedUntil
    }

    ; The second press must also finish quickly and without any chord or modifiers.
    static DoubleTapCompleted(layer, selected, now, modifiers, running) {
        return selected && !layer.used && layer.doubleTap
            && now >= layer.started && now - layer.started <= KeyboardLayers.TapMaxMs
            && modifiers = 0 && running
    }

    Disarm() {
        this.armed := ""
        this.armedUntil := 0
        SetTimer(this.expireCallback, 0)
        this._UpdateObserver()
        this._UpdateIndicator()
    }

    _ExpireArm() {
        Critical
        if this.armed = ""
            return
        remaining := this.armedUntil - KeyboardLayers.Now()
        if remaining > 0 {
            SetTimer(this.expireCallback, -remaining)
            return
        }
        this.Disarm()
    }

    _UpdateObserver() {
        if this.running && (this.selected != "" || this.armed != "") {
            if !this.observer.InProgress
                this.observer.Start()
        } else if this.observer.InProgress
            this.observer.Stop()
    }

    _ObserveKey(input, vk, sc) {
        Critical
        ; Modifiers can be added after a tap. Prefixes have their own handlers.
        if (vk = 0x14 && this.LayerEnabled("caps"))
            || ((vk = 0x13 || vk = 0x03) && this.LayerEnabled("pause"))
            || vk = 0x10 || vk = 0x11 || vk = 0x12
            || (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C
            return
        if !input.InProgress
            return
        if this.selected != ""
            this.layers[this.selected].used := true
        if this.armed = ""
            return
        keyId := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        ; Hook hotkeys can run before this observer; never interfere with a claimed key.
        if this.manager.IsKeyClaimed(keyId)
            return
        ; An armed layer ends at the first key it has no hotkey for.
        if !this.manager.HasLayerRoute(this.armed, Keybindings.ModifierMask(), keyId)
            this.Disarm()
    }

    ; Poll only while a prefix is down: recovers a missed release without a
    ; permanent high-frequency timer.
    _CheckPrefixes() {
        Critical
        for keyName in this.blockedPrefixes.Clone()
            if !GetKeyState(keyName, "P")
                this.blockedPrefixes.Delete(keyName)
        for layerName, layer in this.layers
            if layer.down && !GetKeyState(layer.physicalKey, "P")
                this.FinishPrefix(layerName)
        this._UpdatePoll()
    }

    _UpdatePoll() {
        watch := this.blockedPrefixes.Count > 0
        for layerName, layer in this.layers
            watch := watch || layer.down
        SetTimer(this.pollCallback, watch ? KeyboardLayers.ReleasePollMs : 0)
    }

    HeldIndicatorReady() {
        if this.selected = ""
            return false
        layer := this.layers[this.selected]
        ; Once a hotkey has answered, the held notice gives way to its notices.
        return layer.down && !layer.used && KeyboardLayers.Now() - layer.started > KeyboardLayers.TapMaxMs
    }

    _UpdateIndicator(*) {
        ready := this.selected != "" ? this.HeldIndicatorReady() : this.armed != ""
        if !this.showIndicator || !ready {
            SuiteNotice.Hide("layer")
            return
        }
        layer := this.selected != "" ? this.selected : this.armed
        text := StrUpper(SubStr(layer, 1, 1)) SubStr(layer, 2) (this.selected != "" ? " held" : " - next key")
        try SuiteNotice.Show("layer", text)
        catch Error as failure
            SuiteState.Log.Error("Secret Layers / indicator", failure)
    }
}
