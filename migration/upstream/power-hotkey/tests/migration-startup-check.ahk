#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include "%A_ScriptDir%\..\power-hotkey.ahk"

; Isolated real-write migration exercise. No PowerHotkeys.Start() and no
; user settings. The test manager stays paused throughout the transaction.

migrationTestReportPath := A_Args.Length >= 2 ? A_Args[2]
    : A_Temp "\ph-migration-startup-report.log"
try {
    if A_Args.Length != 2
        throw Error("Expected temporary directory and report path.")
    PH_StartupMigrationCheck.Run(A_Args[1])
    FileAppend("PASS: Synthetic legacy configuration migrated with original backup intact.`n"
        . "PASS: 33 actions available, no shortcuts assigned, and F-key preset blocked.`n"
        . "PASS: Migration marker persisted and repeat installation did nothing.`n",
        migrationTestReportPath, "UTF-8-RAW")
    ExitApp 0
}
catch Error as migrationStartupTestError {
    try FileAppend("FAIL: " migrationStartupTestError.Message "`n"
        . migrationStartupTestError.Stack "`n", migrationTestReportPath, "UTF-8-RAW")
    ExitApp 1
}

class PH_StartupMigrationCheck {
    static Run(root) {
        manager := 0
        try {
            if !InStr(root, "ph-migration-startup-")
                throw Error("Refusing to run outside a temporary test directory.")
            if FileExist(root "\power-hotkey-dry-run.ini")
                throw Error("Temporary test manifest already exists; refusing overwrite.")
            DirCreate(root)

            app := PowerHotkeys({dryRun: true, directory: root})
            manager := app.manager
            ; Model the old layout, including classic preset keys stored while OFF.
            legacy := Map(
                "meta", Map("schema", "1", "id", manager.id, "name", manager.name),
                "bindings", Map(), "claims", Map(), "configured", Map())
            for actionId, action in manager.actions
                legacy["bindings"][actionId] := "0`t`t"
            oldF13 := Keybindings.Parse("Caps + Q").signature
            oldF14 := Keybindings.Parse("Ctrl + Shift + F9").signature
            oldSleep := Keybindings.Parse("Pause + Escape").signature
            legacy["bindings"]["keyboard.f13"] := "0`t" oldF13 "`t"
            legacy["bindings"]["keyboard.f14"] := "0`t" oldF14 "`t"
            legacy["bindings"]["system.sleep"] := "0`t" oldSleep "`t"
            ; One previously enabled *unassigned* action is safe to model at runtime.
            legacy["bindings"]["terminal.copy"] := "1`t`t"

            KB_Manifest.WriteAtomic(manager.path, legacy)
            legacyText := FileRead(manager.path, "UTF-8")
            plan := PH_Migration.Plan(manager, KB_Manifest.Read(manager.path))
            if !plan.existing || plan.autoPresetEligible || plan.dormant.Count != 3
                throw Error("Incorrect legacy plan or automatic-preset eligibility.")
            if plan.dormant["keyboard.f13"][1] != oldF13
                || plan.dormant["keyboard.f14"][1] != oldF14
                || plan.dormant["system.sleep"][1] != oldSleep
                throw Error("Dormant legacy shortcut was not kept in the plan.")

            backup := PH_Migration.BackupLegacy(manager)
            if !FileExist(backup) || FileRead(backup, "UTF-8") != legacyText
                throw Error("Original settings backup was not preserved faithfully.")

            manager.SetPaused(true)
            manager.Start()
            if !manager.paused || manager.GetStatus().Length
                throw Error("Manager unexpectedly activated a shortcut before migration.")
            if !PH_Migration.Install(manager, plan)
                throw Error("Migration did not install the assignment layout.")

            saved := KB_Manifest.Read(manager.path)
            if !PH_Migration.IsAssignmentLayout(saved)
                throw Error("Assignment-layout marker was not published.")
            if saved["power-hotkey"]["fkey-preset"] != "blocked"
                throw Error("Existing installation became F-key preset eligible.")
            for actionId, action in manager.actions {
                if !saved["bindings"].Has(actionId)
                    throw Error("Migrated action missing: " actionId)
                if saved["bindings"][actionId] != "1`t`t"
                    throw Error("Migrated action unexpectedly assigned: " actionId)
            }
            if manager.GetStatus().Length
                throw Error("Migrated settings registered unexpected shortcuts.")
            after := FileRead(manager.path, "UTF-8")
            if PH_Migration.Install(manager, plan)
                throw Error("Migration repeated despite its marker.")
            if FileRead(manager.path, "UTF-8") != after
                throw Error("Idempotent migration changed saved settings.")
            if FileRead(backup, "UTF-8") != legacyText
                throw Error("Migration modified the original backup.")
        }
        finally {
            if IsObject(manager)
                try manager.Stop()
        }
    }
}
