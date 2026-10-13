; =============================================================================
; modules.ahk - feature categories, action registrations, and status window
; =============================================================================
; All actions are assignable in the shared Keybindings interface. No separate
; module selector is needed; unbound actions install no hotkeys.
; =============================================================================

class PH_Modules {
    static Catalog() {
        return [
            {id: "function-keys", label: "Extra function keys",
                description: "F13-F24 outputs can be assigned to any supported shortcut."},
            {id: "number-pad", label: "Virtual number pad",
                description: "Numpad 0-9 through the number row, with held-key release handling."},
            {id: "terminal", label: "Windows Terminal",
                description: "Copy the buffer as Markdown, or clear it. Only acts in Windows Terminal."},
            {id: "text", label: "Text and symbols",
                description: "Insert ß, an en dash, a curly apostrophe, or the literal text &nbsp;."},
            {id: "timestamp", label: "Timestamps",
                description: "Insert the current local time as yyyyMMdd-HHmmss."},
            {id: "caps-lock", label: "Caps Lock toggle",
                description: "Toggle actual capitalization using a configurable shortcut."},
            {id: "speaker-wake", label: "Speaker wake",
                description: "Play the original Windows sound; temporarily raise low volume to 16%."},
            {id: "sleep", label: "Computer sleep",
                description: "Put Windows to sleep after the trigger keys are released. Wake events stay enabled."},
            {id: "interface", label: "Power Hotkey controls",
                description: "Open this window from a configurable shortcut. The tray menu is always available."}
        ]
    }

    static Label(modules, moduleId) {
        for module in modules
            if module.id = moduleId
                return module.label
        throw ValueError("Unknown module: " moduleId)
    }

    static RegisterActions(app) {
        for index, key in ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"] {
            output := "F" (12 + index)
            app.AddAction("function-keys", "keyboard." StrLower(output), "send " output,
                "virtual", output, "Caps + " key)
        }
        loop 10 {
            numpadDigit := A_Index - 1
            app.AddAction("number-pad", "keyboard.numpad" numpadDigit, "send Numpad" numpadDigit,
                "virtual", "Numpad" numpadDigit, "Caps + " numpadDigit)
        }
        ; The old Caps+C override and F23 cannot both own one global signature.
        ; Keep the actions independently configurable instead of hiding a router.
        app.AddAction("terminal", "terminal.copy", "copy buffer as Markdown",
            "terminal-copy", "", "Caps + Ctrl + C", true)
        app.AddAction("terminal", "terminal.clear", "clear buffer",
            "terminal-clear", "", "Caps + K", true)
        app.AddAction("text", "text.sharp-s", "insert ß", "text", "ß", "Pause + S", true)
        app.AddAction("text", "text.en-dash", "insert en dash", "text", "–", "Pause + -", true)
        app.AddAction("text", "text.apostrophe", "insert curly apostrophe", "text", "’", "Pause + '", true)
        app.AddAction("text", "text.nbsp", "insert literal &nbsp;", "text", "&nbsp;", "Pause + N", true)
        app.AddAction("timestamp", "text.timestamp", "insert timestamp",
            "timestamp", "", "Pause + T", true)
        ; Sequences/modifier-only gestures are not part of the current library.
        app.AddAction("caps-lock", "keyboard.toggle-caps", "toggle Caps Lock",
            "caps-lock", "", "Caps + Shift + Space")
        app.AddAction("speaker-wake", "system.wake-speakers", "wake speakers",
            "speaker-wake", "", "Pause + W")
        app.AddAction("sleep", "system.sleep", "sleep computer", "sleep", "", "Pause + Escape")
        app.AddAction("interface", "interface.open", "open Power Hotkey",
            "interface", "", "Pause + H")
    }

    static ShowStatus(app, *) {
        if IsObject(app.statusWindow) {
            this.RefreshStatus(app)
            app.statusWindow.Show()
            return
        }
        window := Gui("-Resize", app.name " - status")
        app.statusWindow := window
        window.SetFont("s10", "Segoe UI")
        window.AddEdit("x14 y14 w720 h380 ReadOnly -Wrap vstatus")
        window.AddButton("x236 y406 w110 h28", "refresh").OnEvent("Click", ObjBindMethod(this, "RefreshStatus", app))
        window.AddButton("x360 y406 w110 h28", "close").OnEvent("Click", ObjBindMethod(this, "CloseStatus", app))
        window.OnEvent("Close", ObjBindMethod(this, "CloseStatus", app))
        window.OnEvent("Escape", ObjBindMethod(this, "CloseStatus", app))
        this.RefreshStatus(app)
        window.Show("w748 h448")
    }

    static RefreshStatus(app, *) {
        if !IsObject(app.statusWindow)
            return
        lines := ["Power Hotkey " PowerHotkeys.Version,
            "mode: " (app.dryRun ? "dry run - no real effects" : "normal"),
            "settings: " app.manager.path, "", "bindings"]
        statuses := app.manager.GetStatus()
        if !statuses.Length
            lines.Push("none - assign a shortcut first")
        for status in statuses
            lines.Push(status.label " / " status.binding ": " status.state)
        lines.Push("", "recent messages")
        for line in app.log
            lines.Push(line)
        app.statusWindow["status"].Value := Keybindings.Join(lines, "`r`n")
    }

    static CloseStatus(app, *) {
        if IsObject(app.statusWindow)
            app.statusWindow.Destroy()
        app.statusWindow := 0
    }
}
