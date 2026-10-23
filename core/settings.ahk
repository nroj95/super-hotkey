; Saved suite preferences, per-module preference files and their backups.
; Saved choices are independent of the module/layer choices of this run.
class SuiteSettings {
    static BackupsKept := 20

    static ModuleOrder := ["cascade-kingdom", "wonder-windows", "power-up-utilities", "paper-pad", "secret-layers"]
    static ModuleNames := Map("cascade-kingdom", "Cascade Kingdom", "wonder-windows", "Wonder Windows",
        "power-up-utilities", "Power-Up Utilities", "paper-pad", "Paper Pad", "secret-layers", "Secret Layers")
    static ModuleDescriptions := Map("cascade-kingdom", "Automatic window placement and cascades.",
        "wonder-windows", "Window hotkeys, layouts, stretching and navigation.",
        "power-up-utilities", "Extra keyboard, text and system actions.",
        "paper-pad", "A persistent Notepad3 drawer for quick notes.",
        "secret-layers", "Independent CapsLock and Pause hotkey layers.")

    ; Defaults apply to unreadable settings only after a recovery copy succeeds.
    ; If preservation fails, stop before any subsequent save can replace them.
    __New(directory) {
        this.directory := directory
        this.path := directory "\settings.ini"
        this.loadWarning := ""
        try {
            this.document := FileExist(this.path) ? KB_Manifest.Read(this.path) : Map()
            if FileExist(this.path) && KB_Manifest.Get(this.document, "meta", "schema") != "1"
                throw Error("The schema is unknown or damaged.")
            this.ReadValues()
        }
        catch Error as failure {
            copy := KB_Manifest.KeepDamagedFile(this.path)
            this.loadWarning := "The suite settings could not be read: " failure.Message
                . "`nDefaults are active until you change a setting. The original file was kept as:`n" copy
            this.document := Map()
            this.ReadValues()
        }
    }

    ReadValues() {
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
            throw Error("Invalid setting: " section "/" key ".")
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

    ; sectionsById: module ID -> INI sections to delete. Paths, editor profiles,
    ; page state and notes are never in these whitelists.
    ResetModulePreferences(sectionsById) {
        for id, sections in sectionsById {
            path := this.directory "\" id "\settings.ini"
            if FileExist(path)
                for section in sections
                    IniDelete(path, section)
        }
    }

    ; Copies the existing files into a new timestamped folder and keeps only
    ; the newest BackupsKept backup folders. Returns the folder, or "" if nothing existed.
    Backup(paths) {
        existing := []
        for path in paths
            if FileExist(path)
                existing.Push(path)
        if !existing.Length
            return ""
        root := this.directory "\backups"
        base := root "\" FormatTime(, "yyyyMMdd-HHmmss") "-"
        tick := A_TickCount
        while DirExist(base tick)
            tick += 1
        folder := base tick
        DirCreate folder
        for path in existing {
            SplitPath(path, &filename, &parent)
            SplitPath(parent, &parentName)
            FileCopy(path, folder "\" parentName "-" filename, false)
        }
        ; Retention touches only folders created here, never anything else.
        folders := ""
        loop files root "\*", "D"
            if RegExMatch(A_LoopFileName, "^\d{8}-\d{6}-\d+$")
                folders .= A_LoopFileName "`n"
        folders := StrSplit(Trim(Sort(folders, "R"), "`n"), "`n")
        while folders.Length > SuiteSettings.BackupsKept
            try DirDelete(root "\" folders.Pop(), true)
        return folder
    }
}
