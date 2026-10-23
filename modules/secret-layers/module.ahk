; Secret Layers: CapsLock and Pause hotkey layers, the Caps Lock double-tap
; toggle, settings page and guide. Layer changes take effect after a restart.
class SecretLayersModule extends SuiteModule {
    hasSettings := true

    __New(app) {
        super.__New(app, "secret-layers")
        this.manager := 0
        this.engine := 0
        this.capsToggle := 0
    }

    ; Keybindings creates the prefix engine at start, only for enabled layers.
    LayerFactory() {
        app := this.app
        if !app.ModuleActive(this.id) || !(app.activeLayers["caps"] || app.activeLayers["pause"])
            return 0
        return (manager) => this.engine := KeyboardLayers(manager, app.activeLayers)
    }

    ; A mouse gesture with the prefix held is neither a tap nor a double-tap.
    ConsumeGesture(layer) {
        if IsObject(this.engine)
            this.engine.ConsumeGesture(layer)
    }

    Register(manager) {
        this.manager := manager
        manager.AddAction("secret-layers.help", "show Secret Layers help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), [],
            {category: "Secret Layers", available: ObjBindMethod(this, "Available")})
        ; Retain the old ID so saved shortcuts survive the change of module owner.
        manager.AddAction("power-up-utilities.keyboard.toggle-caps", "toggle Caps Lock",
            ObjBindMethod(this, "ToggleCapsLockEvent"), [],
            {category: "Secret Layers", available: ObjBindMethod(this, "Available")})
        settings := this.app.Settings
        if this.Available() && this.app.activeLayers["caps"] && settings.capsToggleModifier != "Disabled"
            this.capsToggle := CapsLockModifierToggle(settings.capsToggleModifier)
    }

    Available(*) => this.app.ModuleActive(this.id)

    Start() {
        if IsObject(this.capsToggle)
            this.capsToggle.Start()
    }

    Stop(*) {
        if IsObject(this.capsToggle)
            this.capsToggle.Stop()
    }

    CancelWork() {
        if IsObject(this.capsToggle)
            this.capsToggle.Reset()
    }

    static ToggleCapsLock() => SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")

    ToggleCapsLockEvent(event) {
        app := this.app
        if event.phase = "up" && !app.dryRun && !app.stopping && !app.suspended
            && !this.manager.gated && this.Available()
            SecretLayersModule.ToggleCapsLock()
    }

    ShowSettings(ui) {
        key := "settings:secret-layers"
        if ui.Existing(key)
            return
        settings := this.app.Settings
        window := ui.NewWindow(key, "Secret Layers - Settings", true)
        window.AddText("x20 y20 w560", "Modules is the master switch. These choices control each layer independently.")
        window.AddCheckbox("x20 y70 w540 vpause", "Enable Pause layer").Value := settings.layers["pause"]
        window.AddCheckbox("x20 y115 w540 vcaps", "Enable CapsLock layer").Value := settings.layers["caps"]
        toggle := window.AddCheckbox("x20 y160 w415 vcapsToggleEnabled",
            "Double-tap a modifier to toggle Caps Lock")
        toggle.Value := settings.capsToggleModifier != "Disabled"
        selector := window.AddDropDownList("x445 y158 w135 vcapsToggleModifier", ["Shift", "Ctrl", "Alt"])
        selector.Choose(settings.capsToggleModifierChoice)
        toggle.OnEvent("Click", ObjBindMethod(this, "UpdateSelectorEnabled", selector))
        this.UpdateSelectorEnabled(selector, toggle)
        window.AddText("x20 y235 w560", "Only works while the CapsLock layer is enabled."
            . "`nAn optional shortcut is available in Keybindings.")
        ui.Footer(window, [["Apply and restart", ObjBindMethod(this, "SaveSettings", ui), 160],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]], 300, 600)
        ui.ShowPage(key, 600, 350, 560, 325)
    }

    UpdateSelectorEnabled(selector, checkbox, *) {
        selector.Enabled := checkbox.Value != 0
    }

    SaveSettings(ui, *) {
        key := "settings:secret-layers"
        window := ui.windows[key]
        settings := this.app.Settings
        try {
            settings.Save(settings.modules,
                Map("caps", window["caps"].Value != 0, "pause", window["pause"].Value != 0),
                settings.verbose,
                window["capsToggleEnabled"].Value != 0 ? window["capsToggleModifier"].Text : "Disabled",
                window["capsToggleModifier"].Text)
            ui.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            ui.Report(failure, "Secret Layers / settings")
    }

    HelpText() {
        return "WHY I MADE THIS"
            . "`r`nI wanted to get more out of my existing keyboard. CapsLock and Pause seemed "
            . "like perfect candidates for unlocking an entirely new set of shortcuts "
            . "without adding more keys."
            . "`r`n`r`nHOLD A KEY FOR MORE HOTKEYS"
            . "`r`nHold CapsLock or Pause, then press another key to run its assigned action. "
            . "A short tap instead arms the next key for 1.4 seconds, so you don't need "
            . "to hold both keys at once. Tap the same key again to cancel the layer or "
            . "trigger an assigned double-tap action. Only one layer can be active at a time."
            . "`r`n`r`nTOGGLE CAPS LOCK"
            . "`r`nDouble-tap Shift (by default) to toggle Caps Lock while its layer "
            . "is enabled. You can choose Ctrl or Alt instead, or disable this feature "
            . "in Settings. Only two quick taps of the same modifier count, without "
            . "another key in between. You can also assign a shortcut in Keybindings."
    }
}
