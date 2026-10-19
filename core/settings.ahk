; Saved preferences are independent of the currently running module/layer choices.
class SuiteSettings {
    static ModuleOrder := ["window-cascade", "win-key-overhaul", "power-up-utilities", "scratchpad", "keyboard-layers"]
    static ModuleNames := Map("window-cascade", "Cascade Kingdom", "win-key-overhaul", "Wonder Windows",
        "power-up-utilities", "Power-Up Utilities", "scratchpad", "Paper Pad", "keyboard-layers", "Secret Keys")
    static ModuleDescriptions := Map("window-cascade", "Automatic window placement and cascades.",
        "win-key-overhaul", "Window hotkeys, layouts, stretching and navigation.",
        "power-up-utilities", "Extra keyboard, text and system actions.",
        "scratchpad", "A persistent Notepad3 drawer for quick notes.",
        "keyboard-layers", "Independent CapsLock and Pause hotkey layers.")

    __New(directory) {
        this.directory := directory
        this.path := directory "\settings.ini"
        this.document := FileExist(this.path) ? KB_Manifest.Read(this.path) : Map()
        if FileExist(this.path) && KB_Manifest.Get(this.document, "meta", "schema") != "1"
            throw Error("The suite settings schema is unknown or damaged. No settings were overwritten.")
        this.modules := Map()
        for id in SuiteSettings.ModuleOrder
            this.modules[id] := this.ReadFlag("modules", id, true)
        this.layers := Map("caps", this.ReadFlag("layers", "caps", true),
            "pause", this.ReadFlag("layers", "pause", true))
        this.capsToggleModifier := KB_Manifest.Get(this.document, "layers", "capsToggleModifier", "Shift")
        SuiteSettings.ValidateCapsToggleModifier(this.capsToggleModifier)
        this.capsToggleModifierChoice := KB_Manifest.Get(this.document, "layers",
            "capsToggleModifierChoice",
            this.capsToggleModifier = "Disabled" ? "Shift" : this.capsToggleModifier)
        SuiteSettings.ValidateCapsToggleChoice(this.capsToggleModifierChoice)
        this.verbose := this.ReadFlag("logging", "verbose", false)
    }

    ReadFlag(section, key, fallback) {
        value := KB_Manifest.Get(this.document, section, key, fallback ? "1" : "0")
        if value != "0" && value != "1"
            throw Error("Invalid setting: " section "/" key ". No settings were overwritten.")
        return value = "1"
    }

    static ValidateCapsToggleModifier(modifier) {
        if modifier != "Shift" && modifier != "Ctrl" && modifier != "Alt" && modifier != "Disabled"
            throw ValueError("Invalid Caps Lock double-tap modifier: " modifier)
    }

    static ValidateCapsToggleChoice(modifier) {
        SuiteSettings.ValidateCapsToggleModifier(modifier)
        if modifier = "Disabled"
            throw ValueError("Select a Caps Lock double-tap modifier.")
    }

    Save(modules, layers := unset, verbose := unset, capsToggleModifier := unset,
        capsToggleModifierChoice := unset) {
        if !IsSet(layers)
            layers := this.layers
        if !IsSet(verbose)
            verbose := this.verbose
        if !IsSet(capsToggleModifier)
            capsToggleModifier := this.capsToggleModifier
        SuiteSettings.ValidateCapsToggleModifier(capsToggleModifier)
        if !IsSet(capsToggleModifierChoice)
            capsToggleModifierChoice := capsToggleModifier = "Disabled"
                ? this.capsToggleModifierChoice : capsToggleModifier
        SuiteSettings.ValidateCapsToggleChoice(capsToggleModifierChoice)
        document := Map()
        for section, values in this.document
            document[section] := values.Clone()
        document["meta"] := Map("schema", "1")
        document["modules"] := Map()
        document["layers"] := Map()
        for id in SuiteSettings.ModuleOrder {
            if !modules.Has(id) || (modules[id] != 0 && modules[id] != 1)
                throw ValueError("Missing or invalid module choice: " id)
            document["modules"][id] := modules[id] ? "1" : "0"
        }
        for id in ["caps", "pause"] {
            if !layers.Has(id) || (layers[id] != 0 && layers[id] != 1)
                throw ValueError("Missing or invalid layer choice: " id)
            document["layers"][id] := layers[id] ? "1" : "0"
        }
        document["layers"]["capsToggleModifier"] := capsToggleModifier
        document["layers"]["capsToggleModifierChoice"] := capsToggleModifierChoice
        if verbose != 0 && verbose != 1
            throw ValueError("Invalid verbose logging preference.")
        document["logging"] := Map("verbose", verbose ? "1" : "0")
        DirCreate this.directory
        KB_Manifest.WriteAtomic(this.path, document)
        this.document := document
        this.modules := modules.Clone()
        this.layers := layers.Clone()
        this.capsToggleModifier := capsToggleModifier
        this.capsToggleModifierChoice := capsToggleModifierChoice
        this.verbose := !!verbose
    }

    WritePreferences(id, changes) {
        if !SuiteSettings.ModuleNames.Has(id)
            throw ValueError("Unknown module: " id)
        directory := this.directory "\" id
        DirCreate directory
        path := directory "\settings.ini"
        this.Backup([path])
        temporary := path ".tmp-" DllCall("GetCurrentProcessId", "uint")
        try {
            if FileExist(path)
                FileCopy(path, temporary, true)
            else
                FileAppend("; Super Hotkey module preferences`r`n", temporary, "UTF-16")
            for section, values in changes
                for key, value in values
                    IniWrite(value, temporary, section, key)
            if !DllCall("MoveFileExW", "str", temporary, "str", path, "uint", 0x9, "int")
                throw OSError(A_LastError, "Save module preferences")
        }
        finally {
            if FileExist(temporary)
                FileDelete(temporary)
        }
    }

    ResetModulePreferences() {
        ; Paths, editor profile, page state and notes are outside this whitelist.
        for id, sections in Map("window-cascade", ["FocusTabs", "Controls", "Standalone"],
            "scratchpad", ["Window", "Saving", "Controls"]) {
            path := this.directory "\" id "\settings.ini"
            if FileExist(path)
                for section in sections
                    IniDelete(path, section)
        }
    }

    Backup(paths) {
        folder := this.directory "\backups\" FormatTime(, "yyyyMMdd-HHmmss") "-" A_TickCount
        DirCreate folder
        for path in paths {
            if !FileExist(path)
                continue
            SplitPath(path, &filename, &parent)
            SplitPath(parent, &parentName)
            FileCopy(path, folder "\" parentName "-" filename, false)
        }
        return folder
    }
}
