; =============================================================================
; LocalKeyboardLayers - in-process adapter for the preserved layer state machine.
; Held chords, one-shot taps and release guards are retained; no IPC or leases.
; =============================================================================
class LocalKeyboardLayers {
    __New(name := "", statusCallback := 0) {
        global CPL
        CPL_Initialize()
        this.bindings := []
        this.session := 0
        this.disposed := false
        this.hooksInstalled := false
        CPL.observer := InputHook("V L0 I101")
        CPL.observer.KeyOpt("{All}", "N")
        CPL.observer.OnKeyDown := CPL_ObserveKey
        CPL.observer.OnKeyUp := CPL_ObserveRelease
    }

    Bind(layer, modifiers, key, label, callback, repeat := false, context := 0) {
        global CPL
        routeKey := CPL_RouteKey(layer, modifiers, key)
        if CPL.routes.Has(routeKey)
            throw Error("Duplicate local layer route: " label)
        route := {routeKey: routeKey, layer: layer, modifiers: modifiers, key: key,
            label: label, callback: callback, repeat: repeat, context: context,
            enabled: true, state: "paused"}
        CPL_EnsureRouteVariant(route)
        CPL.routes[routeKey] := route
        this.bindings.Push(route)
        return route
    }

    Unbind(route) {
        global CPL
        route.enabled := false
        if CPL.routes.Has(route.routeKey)
            CPL.routes.Delete(route.routeKey)
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
                Hotkey("$*" key, CPL_PrefixDown.Bind(layer, key), "On I100 B0")
                Hotkey("$*" key " Up", CPL_PrefixUp.Bind(layer, key), "On I100 B0")
            }
            this.hooksInstalled := true
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
        if this.hooksInstalled {
            for key in ["CapsLock", "Pause", "CtrlBreak"] {
                Hotkey("$*" key, "Off")
                Hotkey("$*" key " Up", "Off")
            }
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

CPL_Initialize() {
    global CPL
    CPL := {tapMaxMs: 250, oneShotMs: 1400, releasePollMs: 15,
        showIndicator: true, maxKeyGroups: 256, enabled: false, stopping: false,
        selected: "", armed: "", armedUntil: 0, routes: Map(), keyGroups: Map(),
        pressed: Map(), blockedKeys: Map(), blockedPrefixes: Map(), layers: Map(), observer: 0}
    for name in ["caps", "pause"]
        CPL.layers[name] := {down: false, used: false, started: 0,
            physicalKey: "", cancelTap: false}
}

CPL_RouteEligible(route) {
    global CPL
    if !CPL.enabled || CPL.stopping || !route.enabled || CPL.blockedKeys.Has(route.key)
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
