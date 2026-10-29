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
            ; An open log viewer can block the rename; rotate on a later write instead.
            if FileExist(this.path) && FileGetSize(this.path) >= this.maximumBytes
                try FileMove(this.path, this.path ".old", true)
            line := FormatTime(, "yyyyMMdd-HHmmss") " [" component "] " level ": " message "`n"
            ; FileOpen shares the file, so a viewer cannot block the write as with FileAppend.
            logFile := FileOpen(this.path, "a", "UTF-8-RAW")
            logFile.Write(line)
            logFile.Close()
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

    Clear(*) {
        if FileExist(this.path)
            FileMove(this.path, this.path ".old", true)
        this.Write("Core", "log cleared; previous log retained as debug.log.old")
    }
}
