; Physical, non-blocking modifier double-taps for the Secret Layers CapsLock layer.
class CapsLockModifierToggle {
    __New(modifier) {
        SuiteSettings.ValidateCapsToggleModifier(modifier)
        this.modifier := modifier
        this.hook := InputHook("V L0 I101")
        this.hook.KeyOpt("{All}", "N")
        this.hook.OnKeyDown := ObjBindMethod(this, "KeyDown")
        this.hook.OnKeyUp := ObjBindMethod(this, "KeyUp")
        this.Reset()
    }

    Start() {
        if this.modifier != "Disabled" && !this.hook.InProgress {
            this.Reset()
            this.hook.Start()
        }
    }

    Stop() {
        if this.hook.InProgress
            this.hook.Stop()
        this.Reset()
    }

    Reset() {
        this.heldKey := ""
        this.pressValid := false
        this.pressStarted := 0
        this.lastKey := ""
        this.lastReleased := 0
    }

    Eligible() {
        app := SuiteState.App
        return IsObject(app) && !app.dryRun && !app.stopping && !app.suspended
            && !app.systemSuspended && app.ModuleActive("keyboard-layers")
            && app.activeLayers["caps"] && IsObject(app.manager)
            && app.manager.running && !app.manager.gated && !app.manager.applying
    }

    OtherModifiersHeld() {
        return (this.modifier != "Shift" && GetKeyState("Shift", "P"))
            || (this.modifier != "Ctrl" && GetKeyState("Ctrl", "P"))
            || (this.modifier != "Alt" && GetKeyState("Alt", "P"))
            || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
            || GetKeyState("CapsLock", "P") || GetKeyState("Pause", "P")
    }

    IsSelected(vk) {
        switch this.modifier {
            case "Shift": return vk = 0x10 || vk = 0xA0 || vk = 0xA1
            case "Ctrl": return vk = 0x11 || vk = 0xA2 || vk = 0xA3
            case "Alt": return vk = 0x12 || vk = 0xA4 || vk = 0xA5
        }
        return false
    }

    KeyDown(input, vk, sc) {
        if !this.Eligible() {
            this.Reset()
            return
        }
        this.HandleDown(vk, sc, A_TickCount, this.OtherModifiersHeld())
    }

    KeyUp(input, vk, sc) {
        if !this.Eligible() {
            this.Reset()
            return
        }
        if this.HandleUp(vk, sc, A_TickCount, this.OtherModifiersHeld())
            SuiteState.App.ToggleCapsLock()
    }

    HandleDown(vk, sc, tick, otherHeld) {
        if !this.IsSelected(vk) {
            this.lastKey := ""
            this.pressValid := false
            return
        }
        key := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        if this.heldKey != "" {
            if key != this.heldKey {
                this.lastKey := ""
                this.pressValid := false
            }
            return
        }
        this.heldKey := key
        this.pressStarted := tick
        this.pressValid := !otherHeld
    }

    HandleUp(vk, sc, tick, otherHeld) {
        if !this.IsSelected(vk) {
            this.lastKey := ""
            this.pressValid := false
            return false
        }
        key := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        if key != this.heldKey
            return false
        valid := this.pressValid && !otherHeld
            && ((tick - this.pressStarted) & 0xFFFFFFFF) <= 250
        this.heldKey := ""
        this.pressValid := false
        if !valid {
            this.lastKey := ""
            return false
        }
        if this.lastKey = key && ((tick - this.lastReleased) & 0xFFFFFFFF) <= 300 {
            this.lastKey := ""
            return true
        }
        this.lastKey := key
        this.lastReleased := tick
        return false
    }
}
