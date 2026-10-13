; Module choices are persistent data; active modules only change after a restart.
class SuiteSettings {
    static ModuleNames := Map("window-cascade", "Window Cascade", "power-hotkey", "Power Hotkey",
        "scratchpad", "Scratchpad", "keyboard-layers", "Caps + Pause Layers")

    __New(directory) {
        this.directory := directory
        this.path := directory "\settings.ini"
        this.modules := Map()
        for id in SuiteSettings.ModuleNames
            this.modules[id] := true
        if FileExist(this.path) {
            document := KB_Manifest.Read(this.path)
            if KB_Manifest.Get(document, "meta", "schema") != "1"
                throw Error("The suite settings schema is unknown or damaged. No settings were overwritten.")
            for id in this.modules {
                value := KB_Manifest.Get(document, "modules", id, "1")
                if value != "0" && value != "1"
                    throw Error("Invalid module setting: " id)
                this.modules[id] := value = "1"
            }
        }
    }

    Save(modules) {
        document := Map("meta", Map("schema", "1"), "modules", Map())
        for id in SuiteSettings.ModuleNames {
            if !modules.Has(id) || (modules[id] != 0 && modules[id] != 1)
                throw ValueError("Missing or invalid module choice: " id)
            document["modules"][id] := modules[id] ? "1" : "0"
        }
        DirCreate this.directory
        KB_Manifest.WriteAtomic(this.path, document)
        this.modules := modules.Clone()
    }

    ResetModulePreferences() {
        ; Paths, editor profile, page state and notes are deliberately outside this whitelist.
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
