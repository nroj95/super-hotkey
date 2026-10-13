; One bounded log, with a single rotated backup. Never log notes or clipboard text.
class SuiteLog {
    __New(directory, maximumBytes := 2097152) {
        DirCreate directory
        this.path := directory "\debug.log"
        this.maximumBytes := maximumBytes
        this.writing := false
    }

    Write(component, message, level := "INFO") {
        if this.writing
            return
        this.writing := true
        try {
            if FileExist(this.path) && FileGetSize(this.path) >= this.maximumBytes
                FileMove(this.path, this.path ".old", true)
            line := FormatTime(, "yyyyMMdd-HHmmss") " [" component "] " level ": " message "`n"
            FileAppend(line, this.path, "UTF-8-RAW")
        }
        catch Error as failure
            OutputDebug("Super Hotkey World: log write failed: " failure.Message)
        finally this.writing := false
    }

    Error(component, failure) {
        detail := failure.Message
        for name in ["File", "Line", "What", "Extra", "Stack"]
            if HasProp(failure, name) && failure.%name% != ""
                detail .= "`n  " name ": " failure.%name%
        this.Write(component, detail, "ERROR")
    }

    Clear(*) {
        if FileExist(this.path)
            FileMove(this.path, this.path ".old", true)
        this.Write("Core", "log cleared; previous log retained as debug.log.old")
    }
}
