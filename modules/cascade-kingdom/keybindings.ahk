; Cascade Kingdom hotkeys. Commands run from a serialized queue, never inside
; the input callback. Registration order is the Keybindings display order.

RegisterCascadeActions(manager)
{
    manager.AddAction("cascade-kingdom.help", "Cascade Kingdom help",
        ObjBindMethod(SuiteState.App, "HelpShortcutEvent", "cascade-kingdom"), ["Caps + H"],
        {category: "Cascade Kingdom", available: CascadeModuleActive})
    for item in [["focus-previous", "focus window up", "Caps + PgUp"],
        ["focus-next", "focus window down", "Caps + PgDn"],
        ["next-cascade", "focus next cascade", "Caps + Tab"],
        ["slot-previous", "previous window in slot", "Caps + Left"],
        ["slot-next", "next window in slot", "Caps + Right"],
        ["swap-up", "swap window up", "Caps + Up"],
        ["swap-down", "swap window down", "Caps + Down"],
        ["rotate-next", "next window in each slot", "Caps + Shift + Enter"],
        ["adopt", "add window to cascade", "Caps + Insert"],
        ["release", "remove window from cascade", "Caps + Shift + Insert"],
        ["gather", "gather all cascades", "Caps + Home"],
        ["minimize", "hide cascade (this display)", "Caps + M"],
        ["restore", "restore cascade (this display)", "Caps + Shift + M"],
        ["close-monitor", "close cascade windows (this display)", "Caps + F4"]]
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
