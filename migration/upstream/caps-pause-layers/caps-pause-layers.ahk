#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn

; =============================================================================
; caps-pause-layers.ahk - independent CapsLock / Pause input service
; version: 0.1.0-preview.1 | protocol: 1 | Windows / AutoHotkey v2
; =============================================================================
; purpose
;   Own the two layer keys, arbitrate registered layer bindings, and deliver
;   input events to cooperating processes. There are NO built-in feature actions.
;
; behavior
;   Hold CapsLock/Pause for chords; a short unused tap arms one key for 1400 ms.
;   A second tap cancels. An unassigned non-modifier cancels one-shot mode and
;   passes through. Only one layer is selected; layers never stack.
;   A consumed key stays suppressed through its physical release, including
;   after the prefix is released. One-shot presses never auto-repeat.
;
; integration
;   Clients register layer + exact Ctrl/Alt/Shift/Win mask + physical key.
;   Registrations are leased, not persisted. Clients own their actions/settings.
;   Control plane: bounded UTF-16 WM_COPYDATA requests, numeric result codes.
;   Input plane: targeted PostMessage events, never broadcast feature commands.
;   See README-caps-pause-layers.md and lib/caps-pause-client.ahk for protocol 1.
;
; safety boundaries
;   This is NOT a compatibility replacement for capslock-layer.ahk. Stop the
;   old CapsLock/Pause scripts and Window Cascade before testing this preview.
;   No fake legacy presence mutex, feature shortcuts, F-key remaps, Shift
;   gesture, startup installation, automatic elevation, or shared config files.
;   Caps Lock's existing toggle state is not deliberately changed.
;   A client which synthesizes held keys MUST release its own outputs when
;   receiving cancel, disconnecting, or exiting. The service cannot do that
;   cleanup on behalf of a dead process whose actions it does not know.
; =============================================================================

; =============================================================================
; layer-specific defaults (not feature bindings)
; =============================================================================

CPL := {
    version: "0.1.0-preview.1",
    endpointTitle: "nroj.CapsPauseLayers.v1",
    mutexName: "Local\nroj.CapsPauseLayers.Service",
    copyDataTag: 0x43504C31,                 ; ASCII CPL1
    tapMaxMs: 250,
    oneShotMs: 1400,
    leaseMs: 12000,
    releasePollMs: 15,
    showIndicator: true,
    maxClients: 32,
    maxBindingsPerClient: 128,
    maxKeyGroups: 256,
    enabled: false,
    stopping: false,
    selected: "",
    armed: "",
    armedUntil: 0,
    clients: Map(),
    routes: Map(),
    keyGroups: Map(),
    pressed: Map(),
    blockedKeys: Map(),
    blockedPrefixes: Map(),
    layers: Map(),
    nextBindingId: Random(1, 0x3FFFFF),
    mutex: 0,
    endpoint: 0,
    observer: 0,
    statusGui: 0,
    sessionNotifications: false
}

if A_Args.Length && A_Args[1] = "--check" {
    try {
        CPL_SelfCheck()
        FileAppend("PASS: service parsed and pure helper checks passed.`n", "*")
        ExitApp 0
    }
    catch Error as failure {
        FileAppend("FAIL: " failure.Message "`n", "**")
        ExitApp 1
    }
}

try CPL_Start()
catch Error as failure {
    MsgBox("Could not start Caps + Pause Layers.`n`n" failure.Message,
        "Caps + Pause Layers", "Iconx")
    ExitApp 1
}

; =============================================================================
; startup, unique endpoint, and lifecycle
; =============================================================================

CPL_Start() {
    global CPL

    ; Unlike #SingleInstance, this also guards differently named downloaded copies.
    CPL.mutex := DllCall("CreateMutexW", "ptr", 0, "int", false,
        "str", CPL.mutexName, "ptr")
    creationError := A_LastError
    if !CPL.mutex
        throw OSError(creationError, "CreateMutexW")
    if creationError = 183 {
        DllCall("CloseHandle", "ptr", CPL.mutex)
        CPL.mutex := 0
        throw Error("Another copy of Caps + Pause Layers is already running.")
    }
    OnExit CPL_Stop
    Persistent true
    Thread "Interrupt", 0
    SetStoreCapsLockMode false
    A_MenuMaskKey := "vkE8"
    A_IconTip := "Caps + Pause Layers - no clients"

    for layerName in ["caps", "pause"]
        CPL.layers[layerName] := {down: false, used: false, started: 0,
            physicalKey: "", cancelTap: false}

    CPL.eventMessage := CPL_RegisterMessage("nroj.CapsPauseLayers.v1.Event")
    CPL.endpoint := Gui("+ToolWindow -Caption", CPL.endpointTitle)
    ; Creating the HWND, not showing a window, makes a discoverable IPC endpoint.
    endpointHwnd := CPL.endpoint.Hwnd
    OnMessage(0x004A, CPL_ReceiveRequest)
    OnMessage(0x0218, CPL_PowerEvent)
    OnMessage(0x02B1, CPL_SessionEvent)
    CPL.sessionNotifications := DllCall(
        "Wtsapi32\WTSRegisterSessionNotification", "ptr", endpointHwnd,
        "uint", 0, "int") != 0

    ; Only these activation keys exist before clients register anything.
    ; Input level 100 prevents cooperating AHK Send output from triggering layers.
    for physicalKey, layerName in Map("CapsLock", "caps", "Pause", "pause",
        "CtrlBreak", "pause") {
        Hotkey("$*" physicalKey, CPL_PrefixDown.Bind(layerName, physicalKey), "On I100")
        Hotkey("$*" physicalKey " Up", CPL_PrefixUp.Bind(layerName, physicalKey), "On I100")
    }
    InstallKeybdHook true

    ; No text is collected. This observer only cancels unused taps / one-shots.
    ; It runs while a layer is selected/armed, not for ordinary idle typing.
    CPL.observer := InputHook("V L0 I101")
    CPL.observer.KeyOpt("{All}", "N")
    CPL.observer.OnKeyDown := CPL_ObserveKey
    CPL.observer.OnKeyUp := CPL_ObserveRelease

    CPL_BuildTray()
    for keyName in ["CapsLock", "Pause", "CtrlBreak"]
        if GetKeyState(keyName, "P")
            CPL.blockedPrefixes[keyName] := true
    CPL.enabled := true
    CPL_UpdateReleaseTimer()
    CPL_UpdateStatus()
}

CPL_Stop(*) {
    global CPL
    CPL.stopping := true
    try CPL_Reset("exit")
    try SetTimer(CPL_MaintainClients, 0)
    if CPL.sessionNotifications && IsObject(CPL.endpoint)
        try DllCall("Wtsapi32\WTSUnRegisterSessionNotification",
            "ptr", CPL.endpoint.Hwnd, "int")
    if IsObject(CPL.endpoint)
        try CPL.endpoint.Destroy()
    if CPL.mutex {
        DllCall("CloseHandle", "ptr", CPL.mutex)
        CPL.mutex := 0
    }
}

CPL_RegisterMessage(name) {
    messageId := DllCall("RegisterWindowMessageW", "str", name, "uint")
    if !messageId
        throw OSError(A_LastError, "RegisterWindowMessageW", name)
    return messageId
}

CPL_Now() => DllCall("GetTickCount64", "uint64")

; =============================================================================
; layer state machine
; =============================================================================

CPL_PrefixDown(layerName, physicalKey, *) {
    global CPL
    Critical
    if !CPL.enabled || CPL.stopping || CPL.blockedPrefixes.Has(physicalKey)
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
    if vk = 0x14 || vk = 0x13 || vk = 0x03
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
    if !CPL.routes.Has(routeKey) || !CPL_RouteEligible(CPL.routes[routeKey])
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

; =============================================================================
; dynamic binding routes and physical-key guards
; =============================================================================

CPL_RouteKey(layerName, modifiers, keyId) => layerName "|" modifiers "|" keyId

CPL_RouteEligible(route) {
    global CPL
    ; Keep HotIf memory-only except the monotonic clock. Never do IPC, file I/O,
    ; window-title queries, or action callbacks in a keyboard-hook predicate.
    if !CPL.enabled || CPL.stopping || !route.enabled || CPL.blockedKeys.Has(route.key)
        return false
    if CPL_Now() - route.client.lastSeen > CPL.leaseMs
        return false
    if CPL.selected = route.layer && CPL.layers[route.layer].down
        return true
    return CPL.selected = "" && CPL.armed = route.layer
        && CPL_Now() < CPL.armedUntil
}

CPL_RoutePredicate(routeKey, *) {
    global CPL
    return CPL.routes.Has(routeKey) && CPL_RouteEligible(CPL.routes[routeKey])
}

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
    route := CPL.routes[routeKey]
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
    ; Publish the guard before posting an event or touching cosmetic UI.
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
    ; leaving a permanent high-frequency timer running while the service is idle.
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
        if !press.finished && (!CPL_ClientAlive(press.route.client)
            || !press.route.enabled
            || (!press.oneShot && (CPL.selected != press.route.layer
                || CPL_ModifierMask() != press.route.modifiers)))
            CPL_FinishPress(press, 4)
    }
    CPL_UpdateReleaseTimer()
}

CPL_SendEvent(press, phase) {
    global CPL
    route := press.route
    if !CPL_ClientWindowMatches(route.client)
        return false
    ; Numbers only: no pointers to local AHK objects cross the process boundary.
    ; Binding IDs are unique within this service run. Phases: 1 down, 2 repeat,
    ; 3 key release, 4 cancel. Bit 3 marks one-shot input. The initial foreground
    ; HWND accompanies every phase; clients do not have to resample active focus.
    delivered := DllCall("PostMessageW", "ptr", route.client.hwnd,
        "uint", CPL.eventMessage, "uptr", (route.id << 4) | (press.oneShot ? 8 : 0) | phase,
        "ptr", press.foreground, "int") != 0
    ; A lost release must not leave a connected consumer holding synthetic input
    ; forever. Expire its session: its next heartbeat forces local cancel cleanup.
    if !delivered
        route.client.lastSeen := CPL_Now() - CPL.leaseMs - 1
    return delivered
}

; =============================================================================
; versioned client control protocol
; =============================================================================
; UTF-16 fields, separated by TAB. No embedded TAB/CR/LF/NUL in a field.
; HELLO  1  client-name                       -> positive session token
; BIND   session  layer  mask  key  repeat  label  global -> positive binding ID
; UNBIND session  binding-ID                  -> 1
; PING   session                             -> 1
; BYE    session                             -> 1
; Negative results: -1 invalid request; -2 invalid binding; -3 occupied route;
; -4 expired/unknown session; -5 resource limit; -6 internal error.
; This private protocol uses application-specific numeric LRESULT replies.
; See the README for limits, discovery, event ownership and restart rules.
; =============================================================================

CPL_ReceiveRequest(senderHwnd, copyDataPointer, messageId, receiverHwnd) {
    global CPL
    Critical
    if !IsObject(CPL.endpoint) || receiverHwnd != CPL.endpoint.Hwnd
        return
    if CPL.stopping || !senderHwnd || !copyDataPointer
        return 0
    try {
        if NumGet(copyDataPointer, 0, "uptr") != CPL.copyDataTag
            return 0
        byteCount := NumGet(copyDataPointer, A_PtrSize, "uint")
        dataPointer := NumGet(copyDataPointer, A_PtrSize * 2, "ptr")
        if byteCount < 2 || byteCount > 4096 || Mod(byteCount, 2) || !dataPointer
            return -1
        if NumGet(dataPointer, byteCount - 2, "ushort") != 0
            return -1
        text := StrGet(dataPointer, byteCount // 2 - 1, "UTF-16")
        if StrLen(text) != byteCount // 2 - 1 || InStr(text, "`r") || InStr(text, "`n")
            return -1
        fields := StrSplit(text, "`t")
        if fields.Length < 2
            return -1
        ownerPid := CPL_WindowPid(senderHwnd)
        if !ownerPid || senderHwnd = CPL.endpoint.Hwnd
            return -1

        if fields[1] = "HELLO" {
            if fields.Length != 3 || fields[2] != "1"
                || fields[3] = "" || StrLen(fields[3]) > 100
                return -1
            if CPL.clients.Has(senderHwnd) {
                ; A fresh HELLO is an explicit reconnect: invalidate old bindings.
                CPL_RemoveClient(senderHwnd)
            }
            if CPL.clients.Count >= CPL.maxClients
                return -5
            client := {hwnd: senderHwnd, pid: ownerPid, token: Random(1, 0x7FFFFFFF),
                name: fields[3], lastSeen: CPL_Now(), bindings: Map()}
            CPL.clients[senderHwnd] := client
            SetTimer(CPL_MaintainClients, 1000)
            CPL_UpdateStatus()
            return client.token
        }

        if !CPL.clients.Has(senderHwnd) || !RegExMatch(fields[2], "^\d{1,10}$")
            return -4
        client := CPL.clients[senderHwnd]
        if client.pid != ownerPid || client.token != Integer(fields[2])
            || CPL_Now() - client.lastSeen > CPL.leaseMs
            return -4
        client.lastSeen := CPL_Now()
        switch fields[1] {
            case "PING":
                return fields.Length = 2 ? 1 : -1
            case "BYE":
                if fields.Length != 2
                    return -1
                CPL_RemoveClient(senderHwnd)
                return 1
            case "BIND":
                return CPL_RegisterBinding(client, fields)
            case "UNBIND":
                if fields.Length != 3 || !RegExMatch(fields[3], "^\d{1,9}$")
                    return -1
                bindingId := Integer(fields[3])
                if !client.bindings.Has(bindingId)
                    return -2
                CPL_RemoveBinding(client, bindingId)
                CPL_UpdateStatus()
                return 1
            default:
                return -1
        }
    }
    catch Error as request_error {
        OutputDebug "CapsPauseLayers request failed: " request_error.Message
        return -6
    }
}

CPL_RegisterBinding(client, fields) {
    global CPL
    if fields.Length != 8
        return -1
    layerName := StrLower(fields[3])
    if !CPL.layers.Has(layerName) || !RegExMatch(fields[4], "^\d{1,2}$")
        || (fields[6] != "0" && fields[6] != "1")
        || fields[7] = "" || StrLen(fields[7]) > 120 || fields[8] != "global"
        return -2
    modifiers := Integer(fields[4])
    if modifiers > 15
        return -2
    try keyId := CPL_NormalizeKey(fields[5])
    catch
        return -2
    routeKey := CPL_RouteKey(layerName, modifiers, keyId)
    if CPL.routes.Has(routeKey) {
        other := CPL.routes[routeKey]
        if !CPL_ClientAlive(other.client)
            CPL_RemoveClient(other.client.hwnd)
        else
            return -3
    }
    if client.bindings.Count >= CPL.maxBindingsPerClient || CPL.nextBindingId >= 0x0FFFFFFF
        return -5
    if !CPL.keyGroups.Has(keyId) && CPL.keyGroups.Count >= CPL.maxKeyGroups
        return -5
    ; Do not acquire a key which was already down when the binding was created.
    ; The client can retry after releasing it; no character is stolen mid-press.
    if GetKeyState(keyId, "P")
        return -2

    bindingId := ++CPL.nextBindingId
    route := {id: bindingId, client: client, layer: layerName, modifiers: modifiers,
        key: keyId, repeat: fields[6] = "1", label: fields[7],
        routeKey: routeKey, enabled: false}
    CPL_EnsureRouteVariant(route)
    CPL.routes[routeKey] := route
    client.bindings[bindingId] := route
    route.enabled := true
    CPL_UpdateStatus()
    return bindingId
}

CPL_NormalizeKey(keyName) {
    ; Base keys resolve to physical scan codes, not output characters. Keep
    ; explicit scans intact, including keys with no friendly name on this layout.
    if keyName = "" || StrLen(keyName) > 32
        || RegExMatch(keyName, "[\s{}&~*$<>!^#+]")
        throw ValueError("Expected a base key name or scNNN, not a whole hotkey.")
    if RegExMatch(keyName, "i)^sc([0-9a-f]{3})$", &scanMatch) {
        sc := Integer("0x" scanMatch[1])
        if sc = 0 || sc > 0x1FF
            throw ValueError("Invalid physical scan code.")
        vk := GetKeyVK(keyName)
    } else {
        normalizedName := GetKeyName(keyName)
        vk := GetKeyVK(normalizedName)
        sc := GetKeySC(normalizedName)
        if !vk && !sc
            throw ValueError("Unknown key.")
    }
    if vk = 0x14 || vk = 0x13 || vk = 0x03
        || vk = 0x10 || vk = 0x11 || vk = 0x12
        || (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C
        || RegExMatch(keyName, "i)^(LButton|RButton|MButton|XButton[12]|Wheel|Joy)")
        throw ValueError("Protocol 1 accepts non-modifier keyboard suffixes only.")
    for reserved in ["CapsLock", "Pause", "CtrlBreak", "LControl", "RControl",
        "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
        if sc && sc = GetKeySC(reserved)
            throw ValueError("This key is reserved for layer or modifier handling.")
    ; Reject virtual mouse aliases even when their textual spelling is vkNN.
    if vk = 1 || vk = 2 || vk = 4 || vk = 5 || vk = 6
        throw ValueError("Mouse suffixes are not part of protocol 1.")
    return sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
}

CPL_RemoveBinding(client, bindingId) {
    global CPL
    if !client.bindings.Has(bindingId)
        return
    route := client.bindings[bindingId]
    route.enabled := false
    for keyId, press in CPL.pressed
        if press.route.id = bindingId
            CPL_FinishPress(press, 4)
    if CPL.routes.Has(route.routeKey) && CPL.routes[route.routeKey].id = bindingId
        CPL.routes.Delete(route.routeKey)
    client.bindings.Delete(bindingId)
    ; Empty native variants remain inert and reusable. Deleting their predicate
    ; objects is not supported by HotIf; reusing them avoids reconnect leaks.
}

CPL_RemoveClient(hwnd) {
    global CPL
    if !CPL.clients.Has(hwnd)
        return
    client := CPL.clients[hwnd]
    for bindingId, route in client.bindings.Clone()
        CPL_RemoveBinding(client, bindingId)
    CPL.clients.Delete(hwnd)
    if !CPL.clients.Count
        SetTimer(CPL_MaintainClients, 0)
    CPL_UpdateStatus()
}

CPL_WindowPid(hwnd) {
    processId := 0
    if !DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &processId, "uint")
        return 0
    return processId
}

CPL_ClientWindowMatches(client) => CPL_WindowPid(client.hwnd) = client.pid

CPL_ClientAlive(client) {
    global CPL
    return CPL_Now() - client.lastSeen <= CPL.leaseMs && CPL_ClientWindowMatches(client)
}

CPL_MaintainClients() {
    global CPL
    Critical
    for hwnd, client in CPL.clients.Clone()
        if !CPL_ClientAlive(client)
            CPL_RemoveClient(hwnd)
}

; =============================================================================
; reset, suspend/resume, and session recovery
; =============================================================================

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

CPL_PowerEvent(eventCode, *) {
    global CPL
    if eventCode = 4 {
        CPL_Reset("suspend")
    } else if eventCode = 0x12 || eventCode = 7 {
        CPL_Reset("resume")
        ; Reinstall in-place: don't destroy client registrations by reloading.
        SetTimer(CPL_RecoverHook, -500)
    }
}

CPL_SessionEvent(eventCode, *) {
    if eventCode = 7 || eventCode = 8 || eventCode = 6
        CPL_Reset("session")
    if eventCode = 8
        SetTimer(CPL_RecoverHook, -500)
}

CPL_RecoverHook(*) {
    global CPL
    Critical
    CPL_Reset("hook reset")
    InstallKeybdHook true, true
    CPL_MaintainClients()
}

; =============================================================================
; service-only tray and status (no feature keybindings)
; =============================================================================

CPL_BuildTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Status and registered bindings", CPL_ShowStatus)
    A_TrayMenu.Add("Show layer indicator", CPL_ToggleIndicator)
    A_TrayMenu.Check("Show layer indicator")
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reset layer state", (*) => CPL_Reset())
    A_TrayMenu.Add("Repair keyboard hook", CPL_RecoverHook)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Status and registered bindings"
}

CPL_ToggleIndicator(*) {
    global CPL
    CPL.showIndicator := !CPL.showIndicator
    A_TrayMenu.ToggleCheck("Show layer indicator")
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

CPL_UpdateStatus() {
    global CPL
    A_IconTip := "Caps + Pause Layers - " CPL.clients.Count " clients, "
        . CPL.routes.Count " bindings"
    if IsObject(CPL.statusGui)
        try CPL.statusGui["details"].Value := CPL_StatusText()
}

CPL_StatusText() {
    global CPL
    text := "Caps + Pause Layers " CPL.version "`r`n"
        . "protocol 1 | no built-in actions | exact modifier matching`r`n`r`n"
        . "hold a layer key for chords; tap for one command within 1.4 s.`r`n"
        . "a second tap cancels. unassigned keyboard keys pass through.`r`n"
        . "this preview does not support the old Cascade integration.`r`n`r`n"
    if !CPL.routes.Count
        return text "no bindings registered. start the separate test client to test routing."
    for routeKey, route in CPL.routes {
        text .= route.client.name " | " route.label "`r`n    " route.layer " + "
            . CPL_ModifierSymbols(route.modifiers) route.key
            . (route.repeat ? " [repeat]" : " [once]") "`r`n"
    }
    return text
}

CPL_ShowStatus(*) {
    global CPL
    if !IsObject(CPL.statusGui) {
        CPL.statusGui := Gui("+Resize +MinSize600x300", "Caps + Pause Layers")
        CPL.statusGui.SetFont("s10", "Consolas")
        CPL.statusGui.AddEdit("vdetails ReadOnly -Wrap w760 h400", CPL_StatusText())
        CPL.statusGui.OnEvent("Close", (*) => CPL.statusGui.Hide())
        CPL.statusGui.OnEvent("Escape", (*) => CPL.statusGui.Hide())
        CPL.statusGui.OnEvent("Size", CPL_ResizeStatus)
    }
    CPL_UpdateStatus()
    CPL.statusGui.Show()
}

CPL_ResizeStatus(guiObject, minMax, width, height) {
    if minMax != -1
        guiObject["details"].Move(, , Max(100, width - 24), Max(100, height - 24))
}

; =============================================================================
; --check: pure helper assertions, without installing hooks or starting a service
; =============================================================================

CPL_SelfCheck() {
    if CPL_NormalizeKey("j") != CPL_NormalizeKey("J")
        throw Error("Key-name case normalization failed.")
    if CPL_NormalizeKey("Esc") != CPL_NormalizeKey("Escape")
        throw Error("Escape alias normalization failed.")
    if CPL_NormalizeKey("sc024") != "sc024"
        throw Error("Explicit scan-code preservation failed.")
    symbolsSeen := Map()
    loop 16 {
        mask := A_Index - 1
        symbols := CPL_ModifierSymbols(mask)
        if symbolsSeen.Has(symbols)
            throw Error("Modifier-mask normalization is ambiguous.")
        symbolsSeen[symbols] := true
    }
    for keyName in ["CapsLock", "Pause", "CtrlBreak", "LShift", "LWin", "^j", "LButton", "sc000"] {
        rejected := false
        try CPL_NormalizeKey(keyName)
        catch
            rejected := true
        if !rejected
            throw Error("Reserved/invalid key was accepted: " keyName)
    }
    for bindingId in [1, 128, 0x0FFFFFFF] {
        loop 4 {
            phase := A_Index
            for oneShotFlag in [0, 8] {
                packed := (bindingId << 4) | oneShotFlag | phase
                if (packed >> 4) != bindingId || (packed & 7) != phase
                    || (packed & 8) != oneShotFlag
                    throw Error("Event encoding round-trip failed.")
            }
        }
    }
    if CPL_RouteKey("caps", 0, "sc024") = CPL_RouteKey("pause", 0, "sc024")
        || CPL_RouteKey("caps", 0, "sc024") = CPL_RouteKey("caps", 2, "sc024")
        throw Error("Layer/modifier route isolation failed.")
}
