; Secret Layers: CapsLock and Pause hotkey layers, the Caps Lock double-tap
; toggle, settings page and guide. Layer changes take effect after a restart.
class SecretLayersModule extends SuiteModule {
    hasSettings := true

    __New(app) {
        super.__New(app, "secret-layers")
        this.manager := 0
        this.capsToggle := 0
    }

    ; Keybindings creates the prefix engine at start, only for enabled layers.
    LayerFactory() {
        app := this.app
        if !app.ModuleActive(this.id) || !(app.activeLayers["caps"] || app.activeLayers["pause"])
            return 0
        return (manager) => KeyboardLayers(manager, app.activeLayers)
    }

    Register(manager) {
        this.manager := manager
        manager.AddAction("secret-layers.help", "show Secret Layers help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), [],
            {category: "Secret Layers", available: ObjBindMethod(this, "Available")})
        manager.AddAction("secret-layers.toggle-caps", "toggle Caps Lock",
            ObjBindMethod(this, "ToggleCapsLockEvent"), [],
            {category: "Secret Layers", available: ObjBindMethod(this, "Available")})
        if this.Available() && this.app.activeLayers["caps"]
            this.capsToggle := CapsLockShiftToggle()
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
        ; A caption for the checkbox above, aligned with its text.
        window.AddText("x38 y147 w542", "Double-tap Shift to toggle Caps Lock while this layer is enabled.")
        ui.Footer(window, [["Apply and restart", ObjBindMethod(this, "SaveSettings", ui), 160],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]], 195, 600)
        ui.ShowPage(key, 600, 245, 560, 220)
    }

    SaveSettings(ui, *) {
        key := "settings:secret-layers"
        window := ui.windows[key]
        settings := this.app.Settings
        try {
            settings.Save(settings.modules,
                Map("caps", window["caps"].Value != 0, "pause", window["pause"].Value != 0))
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
            . "`r`nDouble-tap Shift to toggle Caps Lock while its layer is enabled. "
            . "Only two quick taps of the same Shift key count, without another key "
            . "in between. Turn off the CapsLock layer and the key works normally again. "
            . "You can also assign a hotkey in Keybindings."
    }
}
