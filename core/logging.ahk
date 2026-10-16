; One bounded application log. Errors and lifecycle events do not depend on verbose mode.
class SuiteLog {
    __New(directory, maximumBytes := 2097152, verbose := false) {
        DirCreate directory
        this.path := directory "\debug.log"
        this.maximumBytes := maximumBytes
        this.verbose := verbose
        this.writing := false
    }

    Write(component, message, level := "INFO") {
        if this.writing || (level = "DEBUG" && !this.verbose)
            return
        this.writing := true
        try {
            if FileExist(this.path) && FileGetSize(this.path) >= this.maximumBytes
                FileMove(this.path, this.path ".old", true)
            line := FormatTime(, "yyyyMMdd-HHmmss") " [" component "] " level ": " message "`n"
            FileAppend(line, this.path, "UTF-8-RAW")
        }
        catch Error as failure
            OutputDebug("Super Hotkey: log write failed: " failure.Message)
        finally this.writing := false
    }

    Debug(component, message) => this.Write(component, message, "DEBUG")

    Error(component, failure) {
        detail := failure.Message
        for name in ["File", "Line", "What", "Extra", "Stack"]
            if HasProp(failure, name) && failure.%name% != ""
                detail .= "`n  " name ": " failure.%name%
        this.Write(component, detail, "ERROR")
    }

    Read() => FileExist(this.path) ? FileRead(this.path, "UTF-8") : ""

    ReadRecent(maximumBytes := 24576) {
        if !FileExist(this.path)
            return ""
        file := FileOpen(this.path, "r", "UTF-8")
        try {
            offset := Max(0, file.Length - maximumBytes)
            file.Pos := offset
            recent := file.Read()
            if !offset
                return recent

            ; Discard the potentially partial UTF-8 line at the byte boundary.
            newline := InStr(recent, "`n")
            if newline
                recent := SubStr(recent, newline + 1)
            return "[Showing recent entries. Copy or Open file for the full log.]`r`n`r`n" recent
        }
        finally file.Close()
    }

    Clear(*) {
        if FileExist(this.path)
            FileMove(this.path, this.path ".old", true)
        this.Write("Core", "log cleared; previous log retained as debug.log.old")
    }
}
