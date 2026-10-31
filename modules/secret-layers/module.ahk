; Secret Layers: CapsLock and Pause hotkey layers, the Caps Lock double-tap
; toggle, settings page and guide. Layer changes take effect after a restart.
class SecretLayersModule extends SuiteModule {
    hasSettings := true

    __New(app) {
        super.__New(app, "secret-layers")
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
        manager.AddAction("secret-layers.help", "show Secret Layers help",
            ObjBindMethod(this.app, "HelpShortcutEvent", this.id), [],
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

    ShowSettings(ui) {
        key := "settings:secret-layers"
        if ui.Existing(key)
            return
        settings := this.app.Settings
        rows := SuitePageRows(ui.NewWindow(key, "Secret Layers - Settings", true), 600)
        rows.Text("Modules is the master switch. These choices control each layer independently.")
        rows.Checkbox("Enable Pause layer", "vpause").Value := settings.layers["pause"]
        rows.Checkbox("Enable CapsLock layer", "vcaps").Value := settings.layers["caps"]
        rows.Caption("Double-tap Shift to toggle Caps Lock while this layer is enabled.", true)
        rows.Show(ui, key, [["Apply and restart", ObjBindMethod(this, "SaveSettings", ui), 160],
            ["Back", ObjBindMethod(ui, "BackToHelp", this.id), 100]])
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
            . "in between. Turn off the CapsLock layer and the key works normally again."
    }
}
