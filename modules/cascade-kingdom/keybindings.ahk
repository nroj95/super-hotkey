; Cascade Kingdom hotkeys. Commands run from a serialized queue, never inside
; the input callback. Registration order is the Keybindings display order.

RegisterCascadeActions(manager)
{
    manager.AddAction("cascade-kingdom.help", "show Cascade Kingdom help",
        ObjBindMethod(SuiteState.App, "HelpShortcutEvent", "cascade-kingdom"), ["Caps + H"],
        {category: "Cascade Kingdom", available: CascadeModuleActive})
    for item in [["focus-previous", "focus visible window up", "Caps + PgUp"],
        ["focus-next", "focus visible window down", "Caps + PgDn"],
        ["next-cascade", "focus next cascade", "Caps + Tab"],
        ["slot-previous", "show previous window in slot", "Caps + Left"],
        ["slot-next", "show next window in slot", "Caps + Right"],
        ["swap-up", "swap visible window up", "Caps + Up"],
        ["swap-down", "swap visible window down", "Caps + Down"],
        ["rotate-next", "show next window in each slot", "Caps + Shift + Enter"],
        ["adopt", "place active window in cascade", "Caps + Insert"],
        ["release", "take active window out of cascade", "Caps + Shift + Insert"],
        ["bring-forward", "bring cascade on this display to front", "Caps + Shift + Space"],
        ["minimize", "hide cascade windows on this display", "Caps + M"],
        ["restore", "restore hidden cascade windows on this display", "Caps + Shift + M"],
        ["gather", "gather all cascades onto one display", "Caps + Home"],
        ["close-monitor", "close cascade windows on this display", "Caps + F4"]]
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
