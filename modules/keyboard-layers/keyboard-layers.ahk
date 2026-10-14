; Secret Keys owns only the enabled prefixes; callbacks remain inside this process.
class LocalKeyboardLayers {
    __New(name := "", statusCallback := 0, layers := unset) {
        global CPL
        this.layers := IsSet(layers) ? layers.Clone() : Map("caps", true, "pause", true)
        CPL_Initialize(this.layers)
        this.bindings := []
        this.session := 0
        this.disposed := false
        this.hooksInstalled := false
        this.prefixes := []
        CPL.observer := InputHook("V L0 I101")
        CPL.observer.KeyOpt("{All}", "N")
        CPL.observer.OnKeyDown := CPL_ObserveKey
        CPL.observer.OnKeyUp := CPL_ObserveRelease
    }

    LayerEnabled(layer) => this.layers.Has(layer) && this.layers[layer]

    OwnsPrefix(key) {
        vk := GetKeyVK(key)
        return (vk = 0x14 && this.LayerEnabled("caps"))
            || ((vk = 0x13 || vk = 3) && this.LayerEnabled("pause"))
    }

    Bind(layer, modifiers, key, label, callback, repeat := false, context := 0) {
        global CPL
        if !this.LayerEnabled(layer)
            throw Error("Cannot register a disabled Secret Keys layer.")
        routeKey := CPL_RouteKey(layer, modifiers, key)
        route := {routeKey: routeKey, layer: layer, modifiers: modifiers, key: key,
            label: label, callback: callback, repeat: repeat, context: context,
            enabled: true, state: "paused"}
        CPL_EnsureRouteVariant(route)
        if !CPL.routes.Has(routeKey)
            CPL.routes[routeKey] := []
        CPL.routes[routeKey].Push(route)
        this.bindings.Push(route)
        return route
    }

    Unbind(route) {
        global CPL
        route.enabled := false
        if CPL.routes.Has(route.routeKey) {
            group := CPL.routes[route.routeKey]
            for index, item in group {
                if item = route {
                    group.RemoveAt(index)
                    break
                }
            }
            if !group.Length
                CPL.routes.Delete(route.routeKey)
        }
        for index, item in this.bindings {
            if item = route {
                this.bindings.RemoveAt(index)
                break
            }
        }
    }

    Start() {
        global CPL
        if this.disposed || this.session
            return
        if !this.hooksInstalled {
            HotIf()
            for key, layer in Map("CapsLock", "caps", "Pause", "pause", "CtrlBreak", "pause") {
                if !this.LayerEnabled(layer)
                    continue
                Hotkey("$*" key, CPL_PrefixDown.Bind(layer, key), "On I100 B0")
                Hotkey("$*" key " Up", CPL_PrefixUp.Bind(layer, key), "On I100 B0")
                this.prefixes.Push(key)
            }
            this.hooksInstalled := true
        } else {
            ; Restore prefix interception only after the suite input gate reopens.
            HotIf()
            for key in this.prefixes {
                Hotkey("$*" key, "On")
                Hotkey("$*" key " Up", "On")
            }
        }
        this.session := 1
        CPL.enabled := true
        CPL_Reset("start")
        for route in this.bindings {
            route.state := "active"
            if GetKeyState(route.key, "P")
                CPL.blockedKeys[route.key] := true
        }
        CPL_UpdateReleaseTimer()
    }

    Stop() {
        global CPL
        this.session := 0
        CPL.enabled := false
        CPL_Reset("pause")
        if this.hooksInstalled {
            ; Turn off the registered prefix handlers so native CapsLock/Pause
            ; input passes through while suspended or a Settings window is open.
            HotIf()
            for key in this.prefixes {
                Hotkey("$*" key, "Off")
                Hotkey("$*" key " Up", "Off")
            }
        }
        for route in this.bindings
            route.state := "paused"
    }

    ServiceMatches() => !this.disposed && this.session != 0

    OwnsInput(key) {
        global CPL
        return CPL.pressed.Has(key) || (CPL.enabled
            && (CPL.selected != "" || (CPL.armed != "" && CPL_Now() < CPL.armedUntil)))
    }

    Dispose() {
        global CPL
        if this.disposed
            return
        this.Stop()
        this.disposed := true
        SetTimer(CPL_CheckReleases, 0)
        SetTimer(CPL_ExpireArm, 0)
        CPL.observer.Stop()
        HotIf()
        for key in this.prefixes {
            Hotkey("$*" key, "Off")
            Hotkey("$*" key " Up", "Off")
        }
        for key, group in CPL.keyGroups {
            HotIf group.predicate
            Hotkey("$*" key, "Off")
            Hotkey("$*" key " Up", "Off")
            for unused, variant in group.variants {
                HotIf variant.predicate
                Hotkey(variant.name, "Off")
            }
        }
        HotIf()
        ToolTip(, , , 2)
        CPL.routes.Clear()
        this.bindings := []
    }
}

CPL_Initialize(layers := unset) {
    global CPL
    CPL := {tapMaxMs: 250, oneShotMs: 1400, releasePollMs: 15,
        showIndicator: true, maxKeyGroups: 256, enabled: false, stopping: false,
        selected: "", armed: "", armedUntil: 0, routes: Map(), keyGroups: Map(),
        pressed: Map(), blockedKeys: Map(), blockedPrefixes: Map(), layers: Map(), observer: 0,
        enabledLayers: IsSet(layers) ? layers.Clone() : Map("caps", true, "pause", true)}
    for name in ["caps", "pause"]
        CPL.layers[name] := {down: false, used: false, started: 0,
            physicalKey: "", cancelTap: false}
}

CPL_SelectRoute(routeKey) {
    global CPL
    if CPL.routes.Has(routeKey)
        for route in CPL.routes[routeKey]
            if CPL_RouteEligible(route)
                return route
    return 0
}

CPL_RouteEligible(route) {
    global CPL
    if !CPL.enabled || CPL.stopping || !route.enabled || CPL.blockedKeys.Has(route.key)
        || !CPL.enabledLayers[route.layer]
        return false
    if HasMethod(route.context, "Call") && !route.context.Call()
        return false
    if CPL.selected = route.layer && CPL.layers[route.layer].down
        return true
    return CPL.selected = "" && CPL.armed = route.layer && CPL_Now() < CPL.armedUntil
}

CPL_SendEvent(press, phase) {
    phases := ["down", "repeat", "up", "cancel"]
    press.route.callback.Call({phase: phases[phase], foregroundHwnd: press.foreground,
        oneShot: press.oneShot})
    return true
}

CPL_Now() => DllCall("GetTickCount64", "uint64")
