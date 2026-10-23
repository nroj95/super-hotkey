; Cascade Kingdom hotkeys. Commands run from a serialized queue, never inside
; the input callback. Registration order is the Keybindings display order.

RegisterCascadeActions(manager)
{
    manager.AddAction("cascade-kingdom.help", "show Cascade Kingdom help",
        ObjBindMethod(SuiteState.App, "HelpShortcutEvent", "cascade-kingdom"), ["Caps + H"],
        {category: "Cascade Kingdom", available: CascadeModuleActive})
    for item in [["focus-previous", "focus visible window up", "Caps + PgUp"],
        ["focus-next", "focus visible window down", "Caps + PgDn"],
        ["slot-previous", "previous layer in this slot", "Caps + Left"],
        ["slot-next", "next layer in this slot", "Caps + Right"],
        ["swap-up", "swap visible window up", "Caps + Up"],
        ["swap-down", "swap visible window down", "Caps + Down"],
        ["rotate-next", "rotate all slots forward", "Caps + Space"],
        ["adopt", "adopt or re-slot active window", "Caps + Insert"],
        ["bring-forward", "bring this monitor's cascade forward", "Caps + Home"],
        ["minimize", "minimize / restore managed windows", "Caps + M"],
        ["gather", "gather cascades onto this monitor", "Caps + Alt + Enter"],
        ["close-active", "close active window", "Caps + Delete"],
        ["close-monitor", "close this monitor's cascade", "Caps + F4"]]
        manager.AddAction("cascade-kingdom." item[1], item[2], CascadeBindingEvent.Bind(item[1]),
            [item[3]], {category: "Cascade Kingdom", available: CascadeModuleActive})
}

CascadeModuleActive(*) => SuiteState.App.ModuleActive("cascade-kingdom")

CascadeBindingEvent(command, event)
{
    ; Down starts a command; up/cancel carry no work for window commands.
    if event.phase != "down"
        return
    if SuiteState.App.dryRun {
        SuiteState.Log.Write("Cascade Kingdom", "dry run: " event.actionId)
        return
    }
    QueueCascadeCommand(command, event.foregroundHwnd)
}
