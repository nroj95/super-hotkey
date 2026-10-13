class PowerHotkeyMigration {
    __New(manager, dryRun := false) {
        this.manager := manager
        this.dryRun := dryRun
        this.name := "Power Hotkey"
        this.stopping := false
        this.systemSuspended := false
        this.modulesWindow := 0
        this.statusWindow := 0
        this.log := []
        this.pending := Map()
        this.generation := 0
        this.activeJob := 0
        this.enabledActions := Map()
        this.catalog := Map()
        this.modules := PH_Modules.Catalog()
        this.pollCallback := ObjBindMethod(this, "CheckPending")
        this.keyboard := PH_Keyboard(this)
        this.terminal := PH_Terminal(this)
        this.utilities := PH_Utilities(this)
        PH_Modules.RegisterActions(this)
    }

    AddAction(moduleId, actionId, label, kind, value, defaultBinding, needsFocus := false) {
        actionId := "power-hotkey." actionId
        if kind = "terminal-clear"
            defaultBinding := "Caps + Ctrl + K"
        this.catalog[actionId] := {id: actionId, moduleId: moduleId, kind: kind,
            value: value, needsFocus: needsFocus}
        this.manager.AddAction(actionId, label, ObjBindMethod(this, "Dispatch"),
            [defaultBinding], {category: "Power Hotkey / " PH_Modules.Label(this.modules, moduleId),
                available: (*) => SuiteState.App.ModuleActive("power-hotkey")})
    }

    Start(*) {
        this.SyncEnabledActions()
    }

    Stop(*) {
        if this.stopping
            return
        this.stopping := true
        this.CancelWork()
        PH_Modules.CloseStatus(this)
    }

    Enabled(actionId) {
        return SuiteState.App.ModuleActive("power-hotkey")
            && this.enabledActions.Has(actionId) && this.enabledActions[actionId]
    }

    OpenKeybindings(*) {
        SuiteState.App.ShowKeybindings()
    }

    Report(text) {
        this.log.Push(FormatTime(, "HH:mm:ss") "  " text)
        if this.log.Length > 100
            this.log.RemoveAt(1)
        SuiteState.Log.Write("Power Hotkey", text)
    }
}
