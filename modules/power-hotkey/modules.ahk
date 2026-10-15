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
                description: "F13-F24 outputs can be assigned to any supported hotkey."},
            {id: "number-pad", label: "Virtual number pad",
                description: "Numpad 0-9 through the number row, with held-key release handling."},
            {id: "terminal", label: "Windows Terminal",
                description: "Copy the buffer as Markdown, or clear it. Only acts in Windows Terminal."},
            {id: "text", label: "Text and symbols",
                description: "Insert ß, an en dash, a curly apostrophe, or the literal text &nbsp;."},
            {id: "timestamp", label: "Timestamps",
                description: "Insert the current local time as yyyyMMdd-HHmmss."},
            {id: "speaker-wake", label: "Speaker wake",
                description: "Play the original Windows sound; temporarily raise low volume to 16%."},
            {id: "sleep", label: "Computer sleep",
                description: "Put Windows to sleep after the trigger keys are released. Wake events stay enabled."},
            {id: "interface", label: "Power-Up Utilities controls",
                description: "Open this window from a configurable hotkey. The tray menu is always available."}
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
        app.AddAction("speaker-wake", "system.wake-speakers", "wake speakers",
            "speaker-wake", "", "Pause + W")
        app.AddAction("sleep", "system.sleep", "sleep computer", "sleep", "", "Pause + Escape")
        app.AddAction("interface", "interface.open", "show Power-Up Utilities help",
            "interface", "", "Pause + H")
    }






}
