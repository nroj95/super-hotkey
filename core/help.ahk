; Module help uses the live shared catalog rather than maintaining a second shortcut list.
class ModuleHelp {
    static Introduction(id) {
        switch id {
            case "window-cascade":
                return "New application windows are arranged into monitor-relative cascade slots."
                    . "`r`nUse focus tabs or shortcuts to rotate layers, swap windows and change focus."
                    . "`r`nPausing automatic placement leaves existing cascade controls available."
                    . "`r`n`r`nDrag near a slot to adopt a window. A window deliberately laid out by Wonder Windows"
                    . "`r`nstays manual until you use the adopt/re-slot action below. Focus-only navigation"
                    . "`r`ndoes not remove a window from its cascade."
                    . "`r`n`r`nSettings contains automatic placement, focus-tab visibility and colors."
            case "win-key-overhaul":
                return "Replace selected Windows shortcuts with predictable manual window controls."
                    . "`r`nSide layouts cycle through quarter-width, half-width and near-center positions."
                    . "`r`nStretch toward neighboring windows; swap clockwise or move focus spatially."
                    . "`r`nMaximize again to enter borderless fullscreen; maximize once more to leave it."
                    . "`r`n`r`nManual layouts take precedence over Cascade Kingdom until explicitly re-adopted."
                    . "`r`nPaper Pad keeps its own page-navigation shortcuts while its editor is active."
                    . "`r`n`r`nSettings explains Windows Snap, ScreenGrid and optional FancyZones compatibility."
                    . "`r`nNo Windows or PowerToys setting is changed without your confirmation."
            case "power-hotkey":
                return "Extra keyboard and system actions, with all assignments in Keybindings."
                    . "`r`nF13-F24 provide extra function-key outputs; the virtual number pad supplies Numpad 0-9."
                    . "`r`nText actions insert symbols or a yyyyMMdd-HHmmss timestamp."
                    . "`r`nTerminal actions only act in Windows Terminal. Speaker wake and sleep are system actions."
                    . "`r`n`r`nHeld virtual keys are released when their trigger is released or input is cancelled."
                    . "`r`nText and system commands wait for the trigger keys to be released."
                    . "`r`nThere is no separate shortcut editor or module-specific debug switch."
            case "scratchpad":
                return "Paper Pad controls one dedicated Notepad3 window; your normal editor windows stay separate."
                    . "`r`nToggle the drawer for quick notes. New pages have timestamped filenames."
                    . "`r`nEditor-only shortcuts below act only inside the pad, not in other applications."
                    . "`r`n`r`nPages are ordinary files. Save As may rename a page inside the notes folder."
                    . "`r`nUndo survives hiding and suite reloads, but not switching pages."
                    . "`r`nSaves are checked before hiding, switching or exiting; disk conflicts stop overwriting."
                    . "`r`nIf Notepad3 has a pending dialog, resolve it before retrying a save or restart."
                    . "`r`n`r`nSettings controls the notes folder, editor path, display, size and autosave interval."
            case "keyboard-layers":
                return "CapsLock and Pause can each open an additional shortcut layer."
                    . "`r`n`r`nHold a layer key and press another key for a chord."
                    . "`r`nA short unused tap arms the next key for 1.4 seconds. Tap again to cancel."
                    . "`r`nAn unassigned key cancels the one-shot layer and passes through. Layers do not stack."
                    . "`r`n`r`nSettings can disable CapsLock or Pause independently. Modules is the master switch."
                    . "`r`nDisabled layers keep their saved assignments visible and editable in Keybindings."
                    . "`r`nTheir native keys return unless you explicitly assign those keys to another action."
                    . "`r`n`r`nFactory shortcuts open Keybindings with Caps + K or Ctrl + Alt + K."
                    . "`r`nThe ordinary shortcut remains usable when both layers are disabled."
        }
        return ""
    }

    static Text(id, manager) {
        text := this.Introduction(id)
        if id = "keyboard-layers"
            return text
        text .= "`r`n`r`nCURRENT SAVED SHORTCUTS`r`n"
        configuration := manager.GetConfiguration()
        for actionId, action in manager.actions {
            if InStr(actionId, id ".") != 1 || action.category = "Super Hotkey World"
                continue
            labels := []
            for encoded in configuration[actionId].bindings {
                binding := Keybindings.Parse(encoded)
                if !IsObject(binding)
                    continue
                label := binding.label
                if manager.BindingUnavailable(binding) != ""
                    label .= " (inactive)"
                labels.Push(label)
            }
            assignment := labels.Length ? Keybindings.Join(labels, " / ") : "unassigned"
            if !configuration[actionId].enabled || !manager.IsAvailable(action)
                assignment .= " (module/action disabled)"
            text .= "`r`n" action.label "`r`n    " assignment "`r`n"
        }
        return text
    }
}
