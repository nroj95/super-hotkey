; Global toggle and editor-only commands share the suite's configurable bindings.
class ScratchpadModule {
    static Register(manager) {
        manager.AddAction("scratchpad.help", "show Paper Pad help",
            ObjBindMethod(SuiteState.App, "HelpShortcutEvent", "scratchpad"), ["Pause + F12"],
            {category: "Paper Pad", help: true, available: ObjBindMethod(this, "Available")})
        manager.AddAction("scratchpad.toggle", "show / hide Paper Pad", ObjBindMethod(this, "Event", "toggle"),
            ["Win + F12"], {category: "Paper Pad", available: ObjBindMethod(this, "Available")})
        actions := [
            ["hide", "hide Paper Pad / dismiss completion", ["Escape"]],
            ["new", "new page", ["Ctrl + N"]],
            ["save", "save page", ["Ctrl + S"]],
            ["delete", "delete page to Recycle Bin", ["Win + F4"]],
            ["previous", "previous page", ["Win + Left", "Win + PgDn"]],
            ["next", "next page", ["Win + Right", "Win + PgUp"]]
        ]
        for item in actions
            manager.AddAction("scratchpad." item[1], item[2], ObjBindMethod(this, "Event", item[1]), item[3],
                {category: "Paper Pad / Inside the editor", available: ObjBindMethod(this, "Available"),
                    scope: "paper-pad", context: ScratchpadEditorFocused})
    }

    static Available(*) => SuiteState.App.ModuleActive("scratchpad")

    static Start(manager) {
        global scratchpad
        scratchpad := ScratchpadController(SuiteState.App.Settings.directory "\scratchpad")
        manager.Observe("~#.", ScratchpadEditorFocused,
            (*) => scratchpad.NoteSystemTextInputInvocation())
        pending := (*) => IsSet(scratchpad) && scratchpad.SystemTextInputEscapePending()
        for key in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
            manager.Observe("~" key " Up", pending, (*) => scratchpad.HandleSystemTextInputClick())
    }

    static Event(command, event) {
        if event.phase != "down"
            return
        if SuiteState.App.dryRun {
            SuiteState.Log.Write("Paper Pad", "dry run: " command)
            return
        }
        SuiteState.App.QueueInput(ObjBindMethod(this, "Execute", command, event.foregroundHwnd))
    }

    static Execute(command, foreground, *) {
        global scratchpad
        if !this.Available() || !IsSet(scratchpad) || SuiteState.App.stopping
            return
        if command != "toggle" && (!ScratchpadEditorFocused() || foreground != scratchpad.window_hwnd)
            return
        if command = "hide" {
            if scratchpad.SystemTextInputEscapePending() {
                scratchpad.ConsumeSystemTextInputEscape()
                Send "{Escape}"
            } else
                scratchpad.HandleEscape(SuiteState.App.inputGeneration)
        } else
            scratchpad.QueueCommand(command, SuiteState.App.inputGeneration)
    }
}
