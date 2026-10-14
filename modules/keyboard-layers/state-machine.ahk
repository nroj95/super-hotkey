; Preserved held/one-shot state machine; lifecycle and dispatch are in keyboard-layers.ahk.

CPL_PrefixDown(layerName, physicalKey, *) {
    global CPL
    Critical
    if !CPL.enabled || CPL.stopping || !CPL.enabledLayers[layerName] || CPL.blockedPrefixes.Has(physicalKey)
        return
    layer := CPL.layers[layerName]
    if layer.down
        return

    cancelTap := CPL.armed = layerName
    CPL_Disarm()
    ; Switching prefixes cancels previous holds rather than ambiguously stacking.
    if CPL.selected != "" && CPL.selected != layerName {
        CPL.layers[CPL.selected].used := true
        CPL_CancelLayerPresses(CPL.selected)
    }
    ; Do not reinterpret an already-held typing key as a new layer chord.
    for keyId, group in CPL.keyGroups
        if GetKeyState(keyId, "P") && !CPL.pressed.Has(keyId)
            CPL.blockedKeys[keyId] := true
    layer.down := true
    layer.used := CPL.blockedKeys.Count > 0
    layer.started := CPL_Now()
    layer.physicalKey := physicalKey
    layer.cancelTap := cancelTap
    CPL.selected := layerName
    CPL_StartObserver()
    CPL_UpdateReleaseTimer()
    CPL_Indicator()
}

CPL_PrefixUp(layerName, physicalKey, *) {
    global CPL
    Critical
    if CPL.blockedPrefixes.Has(physicalKey)
        CPL.blockedPrefixes.Delete(physicalKey)
    layer := CPL.layers[layerName]
    if !layer.down || layer.physicalKey != physicalKey
        return
    CPL_FinishPrefix(layerName, true)
}

CPL_FinishPrefix(layerName, allowTap) {
    global CPL
    layer := CPL.layers[layerName]
    selected := CPL.selected = layerName
    shouldArm := allowTap && selected && !layer.used && !layer.cancelTap
        && CPL_Now() - layer.started <= CPL.tapMaxMs
        && CPL_ModifierMask() = 0 && CPL.enabled

    layer.down := false
    layer.physicalKey := ""
    if selected
        CPL.selected := ""
    CPL_CancelLayerPresses(layerName)
    if shouldArm {
        CPL.armed := layerName
        CPL.armedUntil := CPL_Now() + CPL.oneShotMs
        SetTimer(CPL_ExpireArm, -CPL.oneShotMs)
    }
    CPL_UpdateObserver()
    CPL_UpdateReleaseTimer()
    CPL_Indicator()
}

CPL_Disarm() {
    global CPL
    CPL.armed := ""
    CPL.armedUntil := 0
    SetTimer(CPL_ExpireArm, 0)
    CPL_UpdateObserver()
    CPL_Indicator()
}

CPL_ExpireArm() {
    global CPL
    Critical
    if CPL.armed = ""
        return
    remaining := CPL.armedUntil - CPL_Now()
    if remaining > 0 {
        SetTimer(CPL_ExpireArm, -remaining)
        return
    }
    CPL_Disarm()
}

CPL_StartObserver() {
    global CPL
    if !CPL.observer.InProgress
        CPL.observer.Start()
}

CPL_UpdateObserver() {
    global CPL
    if !IsObject(CPL.observer)
        return
    if CPL.enabled && (CPL.selected != "" || CPL.armed != "" || CPL.blockedKeys.Count)
        CPL_StartObserver()
    else if CPL.observer.InProgress
        CPL.observer.Stop()
}

CPL_ObserveKey(input, vk, sc) {
    global CPL
    Critical
    ; Modifiers can be added after a tap. Prefixes have their own handlers.
    if (vk = 0x14 && CPL.enabledLayers["caps"])
        || ((vk = 0x13 || vk = 0x03) && CPL.enabledLayers["pause"])
        || vk = 0x10 || vk = 0x11 || vk = 0x12
        || (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C
        return
    if !input.InProgress
        return
    if CPL.selected != ""
        CPL.layers[CPL.selected].used := true
    if CPL.armed = ""
        return
    keyId := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
    ; Hook hotkeys can run before this observer; never interfere with a claimed key.
    if CPL.pressed.Has(keyId) || CPL.blockedKeys.Has(keyId)
        return
    routeKey := CPL_RouteKey(CPL.armed, CPL_ModifierMask(), keyId)
    if !IsObject(CPL_SelectRoute(routeKey))
        CPL_Disarm()
}

CPL_ObserveRelease(input, vk, sc) {
    global CPL
    Critical
    keyId := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
    if CPL.blockedKeys.Has(keyId)
        CPL.blockedKeys.Delete(keyId)
    CPL_UpdateObserver()
}

CPL_ModifierMask() {
    return (GetKeyState("Ctrl", "P") ? 1 : 0)
        | (GetKeyState("Alt", "P") ? 2 : 0)
        | (GetKeyState("Shift", "P") ? 4 : 0)
        | ((GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) ? 8 : 0)
}

CPL_ModifierSymbols(mask) {
    return ((mask & 1) ? "^" : "") . ((mask & 2) ? "!" : "")
        . ((mask & 4) ? "+" : "") . ((mask & 8) ? "#" : "")
}

CPL_RouteKey(layerName, modifiers, keyId) => layerName "|" modifiers "|" keyId

CPL_RoutePredicate(routeKey, *) => IsObject(CPL_SelectRoute(routeKey))

CPL_GuardPredicate(keyId, *) {
    global CPL
    return CPL.pressed.Has(keyId)
}

CPL_EnsureKeyGroup(keyId) {
    global CPL
    if CPL.keyGroups.Has(keyId)
        return
    if CPL.keyGroups.Count >= CPL.maxKeyGroups
        throw Error("Physical-key group limit reached.")

    guardPredicate := CPL_GuardPredicate.Bind(keyId)
    group := {predicate: guardPredicate, variants: Map()}
    ; Keep callback objects stable; HotIf stores them for the process lifetime.
    HotIf guardPredicate
    try {
        Hotkey("$*" keyId, CPL_KeyGuardDown.Bind(keyId), "On I100 B0")
        Hotkey("$*" keyId " Up", CPL_KeyUp.Bind(keyId), "On I100 B0")
    }
    finally HotIf()
    CPL.keyGroups[keyId] := group
}

CPL_EnsureRouteVariant(route) {
    global CPL
    CPL_EnsureKeyGroup(route.key)
    group := CPL.keyGroups[route.key]
    if group.variants.Has(route.routeKey)
        return
    predicate := CPL_RoutePredicate.Bind(route.routeKey)
    hotkeyName := "$" CPL_ModifierSymbols(route.modifiers) route.key
    HotIf predicate
    try Hotkey(hotkeyName, CPL_KeyDown.Bind(route.routeKey), "On I100 B0")
    finally HotIf()
    group.variants[route.routeKey] := {predicate: predicate, name: hotkeyName}
}

CPL_KeyDown(routeKey, *) {
    global CPL
    Critical
    if !CPL.routes.Has(routeKey)
        return
    route := CPL_SelectRoute(routeKey)
    if !IsObject(route)
        return
    if CPL.pressed.Has(route.key) {
        CPL_KeyGuardDown(route.key)
        return
    }
    if !CPL_RouteEligible(route)
        return

    oneShot := CPL.selected = ""
    if oneShot
        CPL_Disarm()
    else
        CPL.layers[route.layer].used := true

    press := {route: route, oneShot: oneShot, finished: false,
        foreground: DllCall("GetForegroundWindow", "ptr"),
        started: CPL_Now()}
    ; Publish the guard before delivering an event or touching cosmetic UI.
    CPL.pressed[route.key] := press
    CPL_UpdateReleaseTimer()
    if !CPL_SendEvent(press, 1)
        press.finished := true
}

CPL_KeyGuardDown(keyId, *) {
    global CPL
    Critical
    if !CPL.pressed.Has(keyId)
        return
    press := CPL.pressed[keyId]
    if press.finished || press.oneShot || !press.route.repeat
        return
    if !CPL_RouteEligible(press.route)
        || CPL_ModifierMask() != press.route.modifiers {
        CPL_FinishPress(press, 4)
        return
    }
    if !CPL_SendEvent(press, 2)
        press.finished := true
}

CPL_KeyUp(keyId, *) {
    global CPL
    Critical
    if !CPL.pressed.Has(keyId)
        return
    press := CPL.pressed[keyId]
    CPL_FinishPress(press, 3)
    CPL.pressed.Delete(keyId)
    CPL_UpdateReleaseTimer()
}

CPL_FinishPress(press, phase) {
    if press.finished
        return
    press.finished := true
    CPL_SendEvent(press, phase)
}

CPL_CancelLayerPresses(layerName) {
    global CPL
    for keyId, press in CPL.pressed
        if press.route.layer = layerName && !press.oneShot
            CPL_FinishPress(press, 4)
}

CPL_UpdateReleaseTimer() {
    global CPL
    watch := CPL.pressed.Count > 0 || CPL.blockedKeys.Count > 0 || CPL.blockedPrefixes.Count > 0
    for layerName, layer in CPL.layers
        watch := watch || layer.down
    SetTimer(CPL_CheckReleases, watch ? CPL.releasePollMs : 0)
}

CPL_CheckReleases() {
    global CPL
    Critical
    ; Poll only during held input. This recovers a missed release without
    ; leaving a permanent high-frequency timer running while the layer is idle.
    for keyId, unused in CPL.blockedKeys.Clone()
        if !GetKeyState(keyId, "P")
            CPL.blockedKeys.Delete(keyId)
    for keyName, unused in CPL.blockedPrefixes.Clone()
        if !GetKeyState(keyName, "P")
            CPL.blockedPrefixes.Delete(keyName)
    CPL_UpdateObserver()
    for layerName, layer in CPL.layers {
        if layer.down && !GetKeyState(layer.physicalKey, "P")
            CPL_FinishPrefix(layerName, true)
    }
    for keyId, press in CPL.pressed.Clone() {
        if !GetKeyState(keyId, "P") {
            CPL_KeyUp(keyId)
            continue
        }
        if !press.finished && (!CPL.enabled || !press.route.enabled
            || (HasMethod(press.route.context, "Call") && !press.route.context.Call())
            || (!press.oneShot && (CPL.selected != press.route.layer
                || CPL_ModifierMask() != press.route.modifiers)))
            CPL_FinishPress(press, 4)
    }
    CPL_UpdateReleaseTimer()
}

CPL_Reset(reason := "manual") {
    global CPL
    Critical
    CPL_Disarm()
    CPL.selected := ""
    CPL.blockedPrefixes.Clear()
    for keyName in ["CapsLock", "Pause", "CtrlBreak"]
        if GetKeyState(keyName, "P")
            CPL.blockedPrefixes[keyName] := true
    for layerName, layer in CPL.layers {
        layer.down := false
        layer.used := true
        layer.cancelTap := true
        layer.physicalKey := ""
    }
    for keyId, press in CPL.pressed
        CPL_FinishPress(press, 4)
    ; Keep guards for keys which are still physically held. Stopping/restarting
    ; a layer should not leak the remaining repeat stream into the foreground.
    for keyId, press in CPL.pressed.Clone()
        if !GetKeyState(keyId, "P")
            CPL.pressed.Delete(keyId)
    CPL_UpdateObserver()
    CPL_UpdateReleaseTimer()
    CPL_Indicator()
}

CPL_Indicator() {
    global CPL
    if !CPL.showIndicator || (CPL.selected = "" && CPL.armed = "")
        || CPL_ForegroundHidesIndicator() {
        ToolTip(, , , 2)
        return
    }
    text := CPL.selected != "" ? CPL.selected " held" : CPL.armed " - next key"
    try {
        CoordMode "Mouse", "Screen"
        CoordMode "ToolTip", "Screen"
        MouseGetPos &mouseX, &mouseY
        ToolTip(text, mouseX + 14, mouseY + 18, 2)
    }
}

CPL_ForegroundHidesIndicator() {
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if !hwnd
        return false
    previousDpiContext := 0
    try {
        if DllCall("IsZoomed", "ptr", hwnd, "int")
            return true
        previousDpiContext := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        windowRect := Buffer(16, 0)
        monitorInfo := Buffer(40, 0)
        NumPut("uint", 40, monitorInfo)
        monitor := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", windowRect, "int")
            || !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", monitorInfo, "int")
            return false
        loop 4
            if Abs(NumGet(windowRect, (A_Index - 1) * 4, "int")
                - NumGet(monitorInfo, A_Index * 4, "int")) > 2
                return false
        return true
    }
    catch
        return false
    finally {
        if previousDpiContext
            DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpiContext, "ptr")
    }
}
