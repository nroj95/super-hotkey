#Requires AutoHotkey v2.0
#SingleInstance Off
#Include "%A_ScriptDir%\..\power-hotkey.ahk"
#Warn All, StdOut

try {
    PH_PresetCheck.Run()
    FileAppend("PASS: " PH_PresetCheck.Count " optional F-key preset assertions.`n", "*")
    ExitApp 0
}
catch Error as presetCheckError {
    FileAppend("FAIL: " presetCheckError.Message "`n" presetCheckError.Stack "`n", "**")
    ExitApp 1
}

class PH_PresetCheck {
    static Count := 0
    static Assert(value, message) {
        this.Count += 1
        if !value
            throw Error(message)
    }

    static Run() {
        root := A_Temp "\nroj-power-hotkey-preset-check-"
            . DllCall("GetCurrentProcessId", "uint") "-" Random(1, 0x7FFFFFFF)
        manager := 0
        try {
            app := PowerHotkeys({dryRun: true, directory: root})
            manager := app.manager
            defaults := PH_FKeyPreset.ClassicAssignments()
            this.Assert(defaults.Count = 12, "classic layout has twelve actions")
            this.Assert(defaults["keyboard.f13"] = Keybindings.Parse("Caps + Q").signature,
                "F13 uses original Q")
            this.Assert(defaults["keyboard.f24"] = Keybindings.Parse("Caps + V").signature,
                "F24 uses original V")
            for actionId, action in manager.actions
                this.Assert(action.trackEdits = (app.catalog[actionId].moduleId = "function-keys"),
                    "tracking opt-in limited to extra F-keys: " actionId)
            manager.SetPaused(true)
            manager.Start()
            plan := PH_Migration.Plan(manager, Map())
            PH_Migration.Install(manager, plan)
            this.Assert(PH_FKeyPreset.Status(manager) = "eligible", "fresh install eligible")
            this.Assert(PH_FKeyPreset.ShouldOffer(manager, true), "offer possible with layer")
            this.Assert(!PH_FKeyPreset.ShouldOffer(manager, false), "no offer without layer")
            manager.Apply(manager.GetConfiguration())
            this.Assert(PH_FKeyPreset.ShouldOffer(manager, true),
                "programmatic no-op does not count as user configuration")

            ; A competing live owner must block ALL twelve assignments, without
            ; saving an applied marker or claiming any partial shortcuts.
            blockerId := "preset-blocker"
            blockerPath := root "\" blockerId ".ini"
            blocker := Map("meta", Map("schema", "1", "id", blockerId,
                    "name", "Preset blocker", "pid", "0", "hwnd", "0"),
                "claims", Map(defaults["keyboard.f13"], "occupied Caps + Q"),
                "configured", Map(defaults["keyboard.f13"], "occupied Caps + Q"),
                "bindings", Map())
            KB_Manifest.WriteAtomic(blockerPath, blocker)
            blockerMutex := DllCall("CreateMutexW", "ptr", 0, "int", false,
                "str", manager._OwnerMutexName(blockerId), "ptr")
            this.Assert(blockerMutex != 0, "simulated conflicting owner started")
            beforeConflict := FileRead(manager.path, "UTF-8")
            blocked := false
            try PH_FKeyPreset.Apply(manager, false, true)
            catch Error
                blocked := true
            this.Assert(blocked, "active external binding rejects entire preset")
            this.Assert(FileRead(manager.path, "UTF-8") = beforeConflict,
                "failed preset leaves entire saved manifest unchanged")
            this.Assert(PH_FKeyPreset.Status(manager) = "eligible",
                "failed preset did not record false success")
            DllCall("CloseHandle", "ptr", blockerMutex)
            FileDelete blockerPath

            ; The actual twelve-key preset is a single owner transaction.
            this.Assert(PH_FKeyPreset.Apply(manager, false, true),
                "approved fresh preset applies successfully")
            this.Assert(PH_FKeyPreset.Status(manager) = "applied", "applied marker persisted")
            this.Assert(manager.GetStatus().Length = 12, "all twelve preset routes installed")
            current := manager.GetConfiguration()
            for actionId, signature in defaults
                this.Assert(current[actionId].bindings[1] = signature,
                    "preset binding saved: " actionId)
            this.Assert(KB_Manifest.Read(manager.path)["power-hotkey"]["fkey-preset"] = "applied",
                "preset and status committed together")
            this.Assert(!manager.WasExplicitlyEdited("keyboard.f13"),
                "programmatic preset does not fabricate user-edit history")
            ; Return to an eligible, empty configuration to test a no-op clear.
            for actionId, signature in defaults
                current[actionId].bindings := ["", ""]
            manager.Apply(current)
            PH_FKeyPreset.SetStatus(manager, "eligible")
            this.Assert(PH_FKeyPreset.ShouldOffer(manager, true),
                "empty programmatic reset alone does not block an offer")

            ; A user clearing an already-empty slot must block a future offer.
            manager.ApplyEdited(manager.GetConfiguration(), ["keyboard.f13"])
            this.Assert(manager.WasExplicitlyEdited("keyboard.f13"),
                "explicit no-op clear tracked")
            this.Assert(!PH_FKeyPreset.ShouldOffer(manager, true),
                "explicit F-key edit prevents whole automatic offer")
            this.Assert(KB_Manifest.Read(manager.path)["explicit-edits"]["keyboard.f13"] = "1",
                "edit history persisted in the manifest")
            this.Assert(!manager.WasExplicitlyEdited("keyboard.f14"),
                "other F-keys remain untouched")

            PH_FKeyPreset.SetStatus(manager, "declined")
            this.Assert(PH_FKeyPreset.Status(manager) = "declined", "decline remembered")
            this.Assert(KB_Manifest.Read(manager.path)["power-hotkey"]["fkey-preset"] = "declined",
                "decline persisted")
            this.Assert(!PH_FKeyPreset.ShouldOffer(manager, true),
                "declined setup never auto-offered")
            manager.Apply(manager.GetConfiguration())
            this.Assert(PH_FKeyPreset.Status(manager) = "declined",
                "ordinary configuration save retains decline")
            PH_FKeyPreset.SetStatus(manager, "eligible")
            this.Assert(!PH_FKeyPreset.ShouldOffer(manager, true),
                "deliberately cleared F-key still blocks offer after status reset")
            this.Assert(manager.GetStatus().Length = 0,
                "metadata-only and empty-slot edits install no shortcuts")
            ; Explicitly requested manual preset is allowed after a prior edit.
            this.Assert(PH_FKeyPreset.Apply(manager, true, true),
                "manual override works after explicit customization")
            this.Assert(manager.WasExplicitlyEdited("keyboard.f13"),
                "manual preset never deletes the user's edit history")
            this.Assert(manager.GetStatus().Length = 12,
                "manual override applies all twelve bindings")
        }
        finally {
            if IsObject(manager)
                manager.Stop()
            if DirExist(root)
                DirDelete(root, true)
        }
    }
}
