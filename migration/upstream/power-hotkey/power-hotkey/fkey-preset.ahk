; =============================================================================
; Optional classic Caps + QWER / ASDF / ZXCV preset for F13-F24.
; Existing installations never receive an automatic offer; migrations set
; fkey-preset=blocked. This module never owns the Caps/Pause service.
; =============================================================================
class PH_FKeyPreset {
    static ClassicAssignments() {
        bindings := Map()
        for index, key in ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"]
            bindings["keyboard.f" (index + 12)] := Keybindings.Parse("Caps + " key).signature
        return bindings
    }

    static LayerAvailable() {
        hwnd := DllCall("FindWindowW", "ptr", 0,
            "str", "nroj.CapsPauseLayers.v1", "ptr")
        if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
            return false
        pid := 0
        DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid, "uint")
        return !!pid
    }

    static Status(manager) {
        if !manager.document.Has("power-hotkey")
            return "missing"
        section := manager.document["power-hotkey"]
        if !section.Has("fkey-preset")
            return "missing"
        status := section["fkey-preset"]
        if status != "eligible" && status != "blocked" && status != "declined"
            && status != "deferred" && status != "applied"
            throw Error("Invalid Power Hotkey F-key preset status.")
        return status
    }

    static ShouldOffer(manager, serviceAvailable) {
        if !manager.running || manager.disposed || !serviceAvailable
            || this.Status(manager) != "eligible"
            return false
        current := manager.GetConfiguration()
        for actionId, signature in this.ClassicAssignments() {
            if !manager.actions.Has(actionId) || !current.Has(actionId)
                return false
            if manager.WasExplicitlyEdited(actionId)
                return false
            setting := current[actionId]
            if !setting.enabled || setting.bindings[1] != "" || setting.bindings[2] != ""
                return false
        }
        return true
    }

    ; Only preset metadata changes here. Serialize through the same lock and
    ; atomic writer as the owner's bindings; no callbacks run under the lock.
    static SetStatus(manager, status) {
        if status != "declined" && status != "deferred"
            && status != "eligible" && status != "applied" && status != "blocked"
            throw ValueError("Unsupported F-key preset status.")
        if !manager.running || manager.disposed || manager.applying
            throw Error("Keybindings manager is not ready to save preset status.")
        nextDocument := manager.document.Clone()
        section := nextDocument.Has("power-hotkey")
            ? nextDocument["power-hotkey"].Clone() : Map()
        section["fkey-preset"] := status
        nextDocument["power-hotkey"] := section
        previousCritical := manager._Lock()
        try {
            KB_Manifest.WriteAtomic(manager.path, nextDocument)
            manager.document := nextDocument
        }
        finally manager._Unlock(previousCritical)
    }

    ; A single, strict owner-mediated configuration transaction handles all
    ; twelve slots. Conflicts fail the entire change. The applied marker shares
    ; the atomic manifest write, and no preset history is mistaken for a GUI edit.
    ; layerAvailability is an explicit test seam (-1 autodetects in production).
    static Apply(manager, manual := false, layerAvailability := -1) {
        if !manager.running || manager.disposed || manager.applying
            throw Error("Keybindings manager is not ready for the preset.")
        layerReady := layerAvailability = -1 ? this.LayerAvailable() : !!layerAvailability
        if !layerReady
            throw Error("Caps + Pause Layers is not available.")
        if !manual && !this.ShouldOffer(manager, layerReady)
            throw Error("F-key preset eligibility changed while confirming.")
        draft := manager.GetConfiguration()
        for actionId, signature in this.ClassicAssignments() {
            if !draft.Has(actionId)
                throw Error("Missing function-key action: " actionId)
            draft[actionId].bindings[1] := signature
        }
        before := manager.document
        manager.document := manager.document.Clone()
        section := manager.document.Has("power-hotkey")
            ? manager.document["power-hotkey"].Clone() : Map()
        section["fkey-preset"] := "applied"
        manager.document["power-hotkey"] := section
        try manager.Apply(draft)
        catch Error as presetInstallError {
            ; The library can report a post-publication failure; inspect disk
            ; before restoring the pre-transaction in-memory metadata.
            persisted := KB_Manifest.Read(manager.path)
            if !persisted.Has("power-hotkey")
                || !persisted["power-hotkey"].Has("fkey-preset")
                || persisted["power-hotkey"]["fkey-preset"] != "applied"
                manager.document := before
            throw presetInstallError
        }
        return true
    }
}
