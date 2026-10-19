; Global toggle and editor-only commands share the suite's configurable bindings.
class PaperPadModule {
    static Register(manager) {
        manager.AddAction("paper-pad.help", "show Paper Pad help",
            ObjBindMethod(SuiteState.App, "HelpShortcutEvent", "paper-pad"), ["Pause + F12"],
            {category: "Paper Pad", help: true, available: ObjBindMethod(this, "Available")})
        manager.AddAction("paper-pad.toggle", "show / hide Paper Pad", ObjBindMethod(this, "Event", "toggle"),
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
            manager.AddAction("paper-pad." item[1], item[2], ObjBindMethod(this, "Event", item[1]), item[3],
                {category: "Paper Pad / Inside the editor", available: ObjBindMethod(this, "Available"),
                    scope: "paper-pad", context: PaperPadEditorFocused})
    }

    static Available(*) => SuiteState.App.ModuleActive("paper-pad")

    static Start(manager) {
        global paperPad
        paperPad := PaperPadController(SuiteState.App.Settings.directory "\paper-pad")
        manager.Observe("~#.", PaperPadEditorFocused,
            (*) => paperPad.NoteSystemTextInputInvocation())
        pending := (*) => IsSet(paperPad) && paperPad.SystemTextInputEscapePending()
        for key in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
            manager.Observe("~" key " Up", pending, (*) => paperPad.HandleSystemTextInputClick())
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
        global paperPad
        if !this.Available() || !IsSet(paperPad) || SuiteState.App.stopping
            return
        if command != "toggle" && (!PaperPadEditorFocused() || foreground != paperPad.window_hwnd)
            return
        if command = "hide" {
            if paperPad.SystemTextInputEscapePending() {
                paperPad.ConsumeSystemTextInputEscape()
                Send "{Escape}"
            } else
                paperPad.HandleEscape(SuiteState.App.inputGeneration)
        } else
            paperPad.QueueCommand(command, SuiteState.App.inputGeneration)
    }
}
