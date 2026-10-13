#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include "%A_ScriptDir%\..\lib\keybindings.ahk"

; =============================================================================
; keybindings-check.ahk - helper, persistence and ownership checks
; =============================================================================
; Uses a unique temporary directory and mutex names. No feature shortcuts are
; enabled, no keyboard hooks or recording GUI are installed, and the layer
; service is never contacted. The fake peer publishes claims only.
; This is not a physical-input or multi-process race test.
; =============================================================================

try {
    checkCount := KB_Check.Run()
    FileAppend("PASS: " checkCount " keybinding, persistence and ownership assertions.`n", "*")
    ExitApp 0
}
catch Error as checkFailure {
    FileAppend("FAIL: " checkFailure.Message "`n" checkFailure.Stack "`n", "**")
    ExitApp 1
}

class KB_Check {
    static Count := 0

    static Assert(condition, message) {
        this.Count += 1
        if !condition
            throw Error(message)
    }

    static Throws(callback, message, expectedClass := "") {
        this.Count += 1
        try callback.Call()
        catch Error as expectedError {
            if expectedClass != "" && Type(expectedError) != expectedClass
                throw Error(message " (wrong exception: " Type(expectedError) ")")
            return
        }
        throw Error(message " (expected rejection)")
    }

    static Run() {
        this.Assert(!IsObject(Keybindings.Parse("")), "empty binding clears a slot")
        for pair in [["Ctrl + Alt + J", "^!j"], ["Alt + Ctrl + J", "!^j"],
            ["Esc", "Escape"], ["Caps + J", "CapsLock + J"],
            ["Control + Shift + F9", "^+F9"]] {
            this.Assert(Keybindings.Parse(pair[1]).signature = Keybindings.Parse(pair[2]).signature,
                "equivalent binding spellings: " pair[1])
        }
        for text in ["J", "Caps + J", "Pause + Ctrl + J", "Shift + F24", "Win + XButton1",
            "Ctrl + WheelDown", "Alt + sc024", "Caps + Shift + J"] {
            binding := Keybindings.Parse(text)
            this.Assert(Keybindings.Parse(binding.signature).signature = binding.signature,
                "saved binding round trip: " text)
        }
        this.Assert(Keybindings.Parse("Ctrl + Alt + Shift + Win + F9").modifiers = 15, "all modifiers")
        this.Assert(Keybindings.Parse("Pause + Ctrl + J").layer = "pause", "Pause layer")
        this.Assert(Keybindings.Parse("Caps + Alt + J").modifiers = 2, "adapter Alt mask")
        this.Assert(Keybindings.Parse("Caps + Shift + J").modifiers = 4, "adapter Shift mask")
        this.Assert(Keybindings.Parse("XButton1").mouse, "ordinary mouse button")
        this.Assert(Keybindings.Parse("WheelUp").wheel, "wheel has complete press events")
        ; No primary mouse button can be bound, including canonical saved forms.
        for text in ["LButton", "RButton", "Ctrl + LButton", "Shift + RButton",
            "normal|0|LButton", "normal|0|RButton"]
            this.Throws(() => Keybindings.Parse(text),
                "primary mouse button is reserved: " text)
        this.Assert(Keybindings._MouseCaptureCancels("LButton"), "left click cancels capture")
        this.Assert(Keybindings._MouseCaptureCancels("RButton"), "right click cancels capture")
        this.Assert(!Keybindings._MouseCaptureCancels("MButton"), "middle click is recordable")
        this.Assert(!Keybindings._MouseCaptureCancels("XButton1"), "side button is recordable")
        this.Assert(Keybindings.NeedsMouseConfirmation(Keybindings.Parse("MButton")),
            "bare middle-click requires approval")
        this.Assert(Keybindings.NeedsMouseConfirmation(Keybindings.Parse("WheelUp")),
            "bare wheel-up requires approval")
        this.Assert(Keybindings.NeedsMouseConfirmation(Keybindings.Parse("WheelDown")),
            "bare wheel-down requires approval")
        this.Assert(!Keybindings.NeedsMouseConfirmation(Keybindings.Parse("Ctrl + WheelUp")),
            "modified wheel requires no approval")
        this.Assert(!Keybindings.NeedsMouseConfirmation(Keybindings.Parse("Alt + MButton")),
            "modified middle-click requires no approval")
        this.Assert(!Keybindings.NeedsMouseConfirmation(Keybindings.Parse("XButton1")),
            "side button requires no approval")
        this.Assert(!Keybindings.NeedsMouseConfirmation(Keybindings.Parse("Ctrl + XButton1")),
            "modified side button requires no approval")
        this.Assert(!Keybindings.NeedsMouseConfirmation(Keybindings.Parse("")),
            "clearing a shortcut requires no approval")
        this.Assert(Keybindings.Parse("J").signature != Keybindings.Parse("Caps + J").signature,
            "normal and layered bindings have distinct identifiers")
        normalIndex := Map(Keybindings.Parse("J").signature, "normal J")
        capsIndex := Map(Keybindings.Parse("Caps + J").signature, "Caps J")
        this.Assert(Keybindings.ConflictingSignature(Keybindings.Parse("Caps + J"), normalIndex) != "",
            "global normal binding overlaps a matching layer binding")
        this.Assert(Keybindings.ConflictingSignature(Keybindings.Parse("J"), capsIndex) != "",
            "overlap detection is symmetric")
        this.Assert(Keybindings.ConflictingSignature(Keybindings.Parse("Pause + J"), capsIndex) = "",
            "Caps and Pause do not overlap")
        this.Assert(Keybindings.ConflictingSignature(Keybindings.Parse("Ctrl + J"), normalIndex) = "",
            "exact modifier masks do not overlap")
        for text in ["CapsLock", "Pause", "Ctrl", "LShift", "Caps + Pause + J", "Ctrl + Ctrl + J",
            "*j", "~j", "<^j", "j & k", "Caps + XButton1", "Pause + WheelUp", "Joy1",
            "sc000", "sc200", "normal|99|sc024", "Win + L", "Ctrl + Alt + Delete"]
            this.Throws(() => Keybindings.Parse(text), "unsupported/reserved binding: " text)
        this.Assert(Keybindings.Symbols(15) = "^!+#", "modifier symbol ordering")
        this.Throws(() => Keybindings.Id("../bad"), "invalid owner ID")
        this.Throws(() => Keybindings.Id("CON"), "reserved owner ID")
        this.Throws(() => KB_Manifest.Decode("[a]`nx=1`nx=2`n"), "duplicate manifest key")
        this.Throws(() => KB_Manifest.Decode("[a]`nx=1`n[a]`ny=2`n"), "duplicate manifest section")
        this.Throws(() => KB_Manifest.Validate(Map("meta", Map("schema", "99"))), "unknown schema")

        directory := A_Temp "\nroj-keybindings-check-" DllCall("GetCurrentProcessId", "uint")
            . "-" Random(1, 0x7FFFFFFF)
        manager := 0
        fakeMutex := 0
        try {
            manager := Keybindings("checks", "keybindings checks", {directory: directory})
            manager.AddAction("test.one", "first action", (*) => 0, [],
                {trackEdits: true})
            manager.AddAction("test.two", "second action", (*) => 0)
            legacy := Map("meta", Map("schema", "1", "id", "checks", "name", "keybindings checks",
                    "profile", "layered", "pid", "0", "hwnd", "0"),
                "profile:layered", Map("test.two", "1`t`t"),
                "profile:standalone", Map("test.two", "0`t`t"))
            DirCreate directory
            KB_Manifest.WriteAtomic(manager.path, legacy)
            manager.Start()
            this.Assert(FileExist(manager.path) != "", "settings snapshot created")
            saved := KB_Manifest.Read(manager.path)
            KB_Manifest.Validate(saved)
            this.Assert(saved.Has("bindings"), "single configuration section persisted")
            this.Assert(saved.Has("catalog"), "action catalog published")
            this.Assert(saved["catalog"].Count = 2, "all actions published")
            this.Assert(saved["catalog"]["test.one"] = "general`tfirst action",
                "catalog preserves action category and label")
            this.Assert(manager.GetConfiguration()["test.two"].enabled,
                "the selected legacy layered profile migrated")
            this.Assert(!saved.Has("profile:standalone") && !saved.Has("profile:layered"),
                "legacy profile sections retired after successful migration")
            this.Assert(!saved["meta"].Has("profile"), "no profile selector persisted")
            this.Assert(saved["claims"].Count = 0, "unbound actions claim no keys")

            clone := manager.GetConfiguration()
            clone["test.one"].enabled := false
            this.Assert(manager.GetConfiguration()["test.one"].enabled,
                "configuration is a defensive copy")
            manager.Apply(clone)
            this.Assert(!manager.GetConfiguration()["test.one"].enabled,
                "single configuration applied")
            this.Assert(KB_Manifest.Read(manager.path)["bindings"]["test.one"] = "0`t`t",
                "single configuration saved")
            this.Assert(!manager.WasExplicitlyEdited("test.one"),
                "programmatic Apply does not count as an explicit edit")
            this.Assert(!manager.WasExplicitlyEdited("test.two"),
                "untracked action has no edit marker")
            this.Throws(() => manager.ApplyEdited(manager.GetConfiguration(),
                ["missing.action"]), "unknown edited action rejected")
            binding := Keybindings.Parse("Ctrl + Alt + F9")
            peer := Map("meta", Map("schema", "1", "id", "fake-peer", "name", "Jørn – テスト",
                    "pid", "0", "hwnd", "0"),
                "configured", Map(binding.signature, "another action"),
                "claims", Map(binding.signature, "another action"),
                "catalog", Map(
                    "peer.bound", "Window Cascade`tother action",
                    "peer.empty", "Window Cascade`tno shortcut"),
                "bindings", Map(
                    "peer.bound", "1`t" binding.signature "`t",
                    "peer.empty", "1`t`t"))
            peerPath := directory "\fake-peer.ini"
            KB_Manifest.WriteAtomic(peerPath, peer)
            this.Assert(KB_Manifest.Read(peerPath)["meta"]["name"] = "Jørn – テスト", "UTF-8 round trip")
            fakeMutex := DllCall("CreateMutexW", "ptr", 0, "int", false,
                "str", manager._OwnerMutexName("fake-peer"), "ptr")
            this.Assert(fakeMutex != 0, "fake peer presence signal")
            this.Assert(manager._OwnerAlive("fake-peer"), "running owner is detected")
            this.Assert(manager._OwnerControl(1, 12345, manager.ownerControlMessage,
                A_ScriptHwnd) = (12345 ^ 0x4B425031), "valid owner control probe")
            this.Assert(manager._OwnerControl(2, 12345, manager.ownerControlMessage,
                A_ScriptHwnd) = 0, "unknown owner control operation rejected")
            this.Assert(manager._OwnerControl(1, 0, manager.ownerControlMessage,
                A_ScriptHwnd) = 0, "invalid owner control challenge rejected")
            this.Assert(manager._OwnerControl(1, 12345, manager.ownerControlMessage,
                0) = 0, "wrong receiver window rejected")
            this.Assert(manager._ApplyRemoteSlotCAS("not-an-action", 1, false, "", "") = 4,
                "remote edit rejects unknown action")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 9, false, "", "") = 4,
                "remote edit rejects invalid slot")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false, "", "") = 6,
                "no-op remote clear remains an accepted edit")
            this.Assert(manager.WasExplicitlyEdited("test.one"),
                "even clearing an empty tracked slot records explicit intent")
            this.Assert(KB_Manifest.Read(manager.path)["explicit-edits"]["test.one"] = "1",
                "explicit intent was atomically stored in the owner manifest")
            this.Assert(!manager.WasExplicitlyEdited("test.two"),
                "untracked actions are not marked by an unrelated edit")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, true, "", Keybindings.Parse("Caps + J").signature) = 2,
                "remote edit rejects stale enabled state")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false, "", Keybindings.Parse("Caps + J").signature) = 1,
                "remote edit updates disabled action without installing hotkey")
            this.Assert(manager.GetConfiguration()["test.one"].bindings[1]
                = Keybindings.Parse("Caps + J").signature, "remote edit stored normalized shortcut")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false, "", Keybindings.Parse("Caps + K").signature) = 2,
                "remote edit rejects stale slot")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false,
                Keybindings.Parse("Caps + J").signature, "") = 1,
                "remote edit can clear its own changed shortcut")
            this.Assert(manager.GetConfiguration()["test.one"].bindings[1] = "",
                "remote edit reverted test action")
            this.Assert(manager.WasExplicitlyEdited("test.one"),
                "explicit edit history persists through later shortcut updates")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false, "", "") = 6,
                "remote edit detects unchanged binding")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false,
                "", "invalid!!") = 4, "remote edit rejects invalid replacement")
            this.Assert(manager._ApplyRemoteSlotCAS("test.one", 1, false,
                "Caps + J", "") = 4, "remote edit rejects noncanonical expected binding")
            this.Assert(manager.GetConfiguration()["test.one"].bindings[1] = "",
                "invalid requests leave saved binding unchanged")
            this.Assert(!manager._PeerControlReady({alive: true, hwnd: 0, pid: 0}),
                "peer probe rejects missing identity")
            participants := manager.DiscoverParticipants()
            this.Assert(participants.Length = 2, "local and running peer discovered")
            this.Assert(participants[1].id = "checks", "local owner listed first")
            this.Assert(participants[1].controlReady, "local owner is control-ready")
            this.Assert(participants[1].hwnd = A_ScriptHwnd,
                "local participant publishes its own window")
            this.Assert(participants[1].pid = DllCall("GetCurrentProcessId", "uint"),
                "local participant publishes its own process")
            this.Assert(!participants[2].controlReady, "fake owner without HWND is not control-ready")
            this.Assert(participants[1].actions.Length = 2, "local actions included")
            this.Assert(!participants[1].actions[1].enabled, "local disabled state preserved")
            this.Assert(participants[2].name = "Jørn – テスト", "peer name preserved")
            this.Assert(participants[2].actions.Length = 2, "all peer actions discovered")
            this.Assert(participants[2].actions[1].bindings[1] = binding.signature,
                "peer shortcut preserved")
            this.Assert(participants[2].actions[2].bindings[1] = "",
                "unassigned peer action included")
            this.Assert(manager.RequestRemoteSlotEdit(
                participants[2], "peer.empty", 1, "") = 4,
                "unchanged snapshot cannot bypass owner verification")
            displayed := Keybindings.DisplayRows(participants)
            this.Assert(displayed.Length = 5, "enabled actions grouped by script")
            this.Assert(displayed[1].label = "keybindings checks", "local script header")
            this.Assert(displayed[3].label = "Jørn – テスト (view only)", "remote header is read-only")
            this.Assert(displayed[2].editable, "local action remains editable")
            this.Assert(!displayed[4].editable, "legacy peer is view-only")
            this.Assert(displayed[4].id = "peer.bound", "remote action visible")
            participants[2].controlReady := true
            readyRows := Keybindings.DisplayRows(participants)
            this.Assert(readyRows[3].label = "Jørn – テスト", "ready peer title has no view-only suffix")
            this.Assert(readyRows[4].editable, "ready peer actions are editable")
            participants[2].controlReady := false
            this.Assert(displayed[5].setting.bindings[1] = "", "unassigned action visible")
            searched := Keybindings.DisplayRows(participants, "no shortcut")
            this.Assert(searched.Length = 2 && searched[1].ownerId = "fake-peer",
                "global search finds remote actions")
            ; Category headings are peers of script headings, not nested inside one.
            categorized := [{id: "category-test", name: "Category Test", controlReady: true,
                actions: [
                    {id: "keys.one", label: "first key", category: "Extra keys",
                        enabled: true, bindings: ["", ""]},
                    {id: "tools.one", label: "tool", category: "Utilities",
                        enabled: true, bindings: ["", ""]},
                    {id: "keys.two", label: "second key", category: "Extra keys",
                        enabled: true, bindings: ["", ""]}
                ]}]
            categoryRows := Keybindings.DisplayRows(categorized)
            this.Assert(categoryRows.Length = 5, "each category is a flat heading")
            this.Assert(categoryRows[1].kind = "owner" && categoryRows[1].label = "Extra keys",
                "first category uses the normal heading style")
            this.Assert(categoryRows[2].id = "keys.one" && categoryRows[3].id = "keys.two",
                "interleaved actions stay grouped by category")
            this.Assert(categoryRows[4].kind = "owner" && categoryRows[4].label = "Utilities"
                && categoryRows[5].id = "tools.one", "second category is a normal heading")
            categorySearch := Keybindings.DisplayRows(categorized, "tool")
            this.Assert(categorySearch.Length = 2 && categorySearch[1].label = "Utilities",
                "search preserves the matching category heading")
            categoryNameSearch := Keybindings.DisplayRows(categorized, "Extra keys")
            this.Assert(categoryNameSearch.Length = 3 && categoryNameSearch[2].id = "keys.one",
                "search matches category names")
            this.Assert(categoryRows[1].ownerId = "category-test"
                && categoryRows[4].ownerId = "category-test",
                "flat categories retain their script owner")
            draft := manager.GetConfiguration()
            draft["test.one"].enabled := true
            draft["test.one"].bindings[1] := binding.signature
            before := FileRead(manager.path, "UTF-8")
            this.Throws(() => manager.Apply(draft), "running peer blocks a collision", "Error")
            this.Assert(FileRead(manager.path, "UTF-8") = before, "rejected edit leaves disk unchanged")
            this.Assert(!manager.GetConfiguration()["test.one"].enabled, "rejected edit retains prior settings")
            this.Assert(manager.routes.Length = 0, "rejected edit activates no shortcuts")
            DllCall("CloseHandle", "ptr", fakeMutex)
            fakeMutex := 0
            this.Assert(!manager._OwnerAlive("fake-peer"), "closed owner loses its active claim")
            this.Assert(manager.DiscoverParticipants().Length = 1, "offline peer excluded")
            this.Throws(() => manager.Apply(draft), "inactive peer produces saved warning", "KB_SavedConflict")
            FileDelete peerPath
            draft["test.two"].enabled := true
            draft["test.two"].bindings[1] := binding.signature
            this.Throws(() => manager.Apply(draft), "duplicate bindings within one script", "Error")
            this.Assert(manager.routes.Length = 0, "local conflict registers no shortcuts")

            manager.Stop()
            this.Assert(!manager._OwnerAlive("checks"), "Stop releases owner presence")
            this.Assert(FileExist(manager.path) != "", "configured preferences survive Stop")
            this.Assert(this.Count >= 50, "expected test cases executed")
        }
        finally {
            if IsObject(manager)
                manager.Stop()
            if fakeMutex
                DllCall("CloseHandle", "ptr", fakeMutex)
            if DirExist(directory)
                DirDelete directory, true
        }
        return this.Count
    }
}
