#Requires AutoHotkey v2.0
#SingleInstance Off
#Include "%A_ScriptDir%\..\power-hotkey.ahk"
#Warn All, StdOut

; Pure migration tests: no hotkeys, audio, sleep, GUI or settings writes.
try {
    PH_MigrationCheck.Run()
    ExitApp 0
} catch Error as migrationCheckError {
    FileAppend("FAIL: " migrationCheckError.Message "`n" migrationCheckError.Stack "`n", "**")
    ExitApp 1
}

class PH_MigrationCheck {
    static count := 0

    static Assert(value, name) {
        this.count += 1
        if !value
            throw Error(name)
    }

    static Run() {
        app := PowerHotkeys({dryRun: true,
        directory: A_Temp "\PowerHotkeys-migration-check-" DllCall("GetCurrentProcessId", "uint")})
    manager := app.manager
    fresh := PH_Migration.Plan(manager, Map())
    this.Assert(fresh.autoPresetEligible && !fresh.existing, "new install is initially preset eligible")
    this.Assert(fresh.configuration.Count = 33, "all 33 actions are available")
    for actionId, setting in fresh.configuration {
        this.Assert(setting.enabled && setting.bindings[1] = "" && setting.bindings[2] = "",
            "new action starts enabled but unassigned: " actionId)
    }
    this.Assert(fresh.dormant.Count = 0, "no archive needed on new install")

    oldDefaults := manager._DefaultConfiguration()
    previous := Map("meta", Map("schema", "1", "id", manager.id, "name", manager.name),
        "bindings", Map())
    for actionId, setting in oldDefaults
        previous["bindings"][actionId] := "0`t" setting.bindings[1] "`t" setting.bindings[2]
    ; Explicitly enabled assignment is preserved, even when customized.
    active := Keybindings.Parse("Ctrl + Alt + F9").signature
    previous["bindings"]["keyboard.f13"] := "1`t" active "`t"
    ; A disabled customized assignment is archived, never activated.
    dormantKey := Keybindings.Parse("Ctrl + Shift + F9").signature
    previous["bindings"]["keyboard.f14"] := "0`t" dormantKey "`t"
    migration := PH_Migration.Plan(manager, previous)
    this.Assert(!migration.autoPresetEligible && migration.existing,
        "existing installation never receives an automatic preset")
    this.Assert(migration.configuration["keyboard.f13"].enabled
        && migration.configuration["keyboard.f13"].bindings[1] = active,
        "previously enabled customized shortcut survives")
    this.Assert(migration.configuration["keyboard.f14"].enabled
        && migration.configuration["keyboard.f14"].bindings[1] = "",
        "disabled shortcut does not activate")
    this.Assert(migration.dormant["keyboard.f14"][1] = dormantKey,
        "disabled customized shortcut is recoverable from archive")
    this.Assert(migration.configuration["system.sleep"].bindings[1] = "",
        "previously disabled sleep shortcut remains unassigned")
    this.Assert(previous["bindings"]["keyboard.f14"] = "0`t" dormantKey "`t",
        "planning never mutates the legacy document")

    ; Explicit clearing does not make an existing installation eligible.
    previous["bindings"]["keyboard.f13"] := "0`t`t"
    cleared := PH_Migration.Plan(manager, previous)
    this.Assert(!cleared.autoPresetEligible, "historical clearing cannot re-enable preset")
    this.Assert(!FileExist(manager.path), "pure tests created no settings files")
    this.Assert(!PH_Migration.IsAssignmentLayout(Map()),
        "fresh settings have no migration marker")
    this.Assert(PH_Migration.IsAssignmentLayout(
        Map("power-hotkey", Map("layout", "assignments-v1"))),
        "converted settings have a stable migration marker")
        FileAppend("PASS: " this.count " Power Hotkey migration assertions.`n", "*")
    }
}
