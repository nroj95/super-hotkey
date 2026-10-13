; =============================================================================
; Power Hotkey legacy configuration planning (pure; no files or input changes).
; =============================================================================
; The old module selector saved default bindings even when modules were OFF.
; Activating all old disabled entries would silently introduce hotkeys.
;
class PH_Migration {
    static Plan(manager, savedDocument) {
        if !(savedDocument is Map)
            throw TypeError("Expected a parsed Keybindings document.")
        existing := savedDocument.Count > 0
        if existing {
            KB_Manifest.Validate(savedDocument)
            if !savedDocument.Has("bindings")
                throw Error("Cannot migrate a legacy profile-only document automatically.")
        }

        target := Map()
        dormant := Map()
        for actionId, action in manager.actions {
            setting := {enabled: true, bindings: ["", ""]}
            if existing && savedDocument["bindings"].Has(actionId) {
                fields := StrSplit(savedDocument["bindings"][actionId], "`t")
                if fields.Length != 3 || (fields[1] != "0" && fields[1] != "1")
                    throw Error("Invalid saved settings for " actionId ".")
                savedSlots := manager._NormalizeSlots([fields[2], fields[3]])
                if fields[1] = "1" {
                    ; Preserve every existing active assignment (including both slots).
                    setting.bindings := savedSlots
                } else if savedSlots[1] != "" || savedSlots[2] != "" {
                    ; Keep formerly disabled assignments in an archive, not active.
                    dormant[actionId] := savedSlots
                }
            }
            target[actionId] := setting
        }

        ; Old manifests do not record whether a key was assigned then cleared.
        ; Treat EVERY existing installation as ineligible for automatic presets.
        return {configuration: target, dormant: dormant,
            existing: existing, autoPresetEligible: !existing}
    }

    static IsAssignmentLayout(document) {
        if !document.Count || !document.Has("power-hotkey")
            return false
        section := document["power-hotkey"]
        if !section.Has("layout")
            return false
        if section["layout"] != "assignments-v1"
            throw Error("Unknown Power Hotkey settings layout; no migration was performed.")
        return true
    }

    static BackupLegacy(manager) {
        ; Save the ORIGINAL manifest before manager.Start() rewrites metadata.
        backupPath := manager.path ".legacy-" FormatTime(, "yyyyMMdd-HHmmss")
            . "-" Random(100000, 999999) ".bak"
        FileCopy(manager.path, backupPath, false)
        if !FileExist(backupPath)
            throw Error("Could not back up the original Power Hotkey settings.")
        return backupPath
    }

    static Install(manager, plan) {
        if !manager.running || manager.disposed || !manager.paused
            throw Error("Power Hotkey migration requires a running, paused manager.")
        if this.IsAssignmentLayout(manager.document)
            return false
        before := manager.document
        manager.document := manager.document.Clone()
        manager.document["power-hotkey"] := Map("layout", "assignments-v1",
            "fkey-preset", plan.autoPresetEligible ? "eligible" : "blocked")
        try manager.Apply(plan.configuration)
        catch Error as migrationInstallError {
            ; Fail closed: don't retain the new marker in memory on rejection.
            if !this.IsAssignmentLayout(KB_Manifest.Read(manager.path))
                manager.document := before
            throw migrationInstallError
        }
        return true
    }
}
