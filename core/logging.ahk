; One bounded application log with an unbounded pile of zipped earlier logs.
;
; debug.log in the settings directory is the current log. Errors and lifecycle
; events do not depend on verbose mode. Restarts keep appending to it; a new
; log starts only when it reaches the size limit or the user asks for one
; (Pause + F1). The previous log then moves to logs\debug-yyyyMMdd-HHmmss.log
; and Windows' own tar.exe zips it there in the background, deleting the plain
; copy only once the zip is written. Archives are never pruned: logs zip to
; about an eighth of their size. An archive holding verbose lines, which record
; which programs and windows were used, is named with -verbose so the user can
; find and delete it. Without tar.exe the plain .log stays in logs\, so nothing
; is lost.
;
; Logs get posted in bug reports, so no line names the user: the profile
; folder, C:\Users\<name>, is written as %USERPROFILE%, and verbose window
; descriptions give a title's length instead of its text (DescribeWindow).
class SuiteLog {
    __New(directory, maximumBytes := 2097152, verbose := false) {
        DirCreate directory
        this.path := directory "\debug.log"
        this.archiveDirectory := directory "\logs"
        this.maximumBytes := maximumBytes
        this.verbose := verbose
        this.writing := false
        this.profile := EnvGet("USERPROFILE")
        ; Earlier versions kept one previous log beside the current one.
        if FileExist(this.path ".old")
            try this.Archive(this.path ".old", FileGetTime(this.path ".old"))
    }

    Write(component, message, level := "INFO") {
        if this.writing || (level = "DEBUG" && !this.verbose)
            return
        this.writing := true
        try {
            ; An open log viewer can block the rename; rotate on a later write instead.
            if FileExist(this.path) && FileGetSize(this.path) >= this.maximumBytes
                try this.Archive(this.path)
            if this.profile != ""
                message := StrReplace(message, this.profile, "%USERPROFILE%")
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

    ; Returns the archive's name relative to the settings directory, or "" when
    ; there was no log to archive.
    StartNew(*) {
        archive := FileExist(this.path) ? this.Archive(this.path) : ""
        this.Write("Core", archive = "" ? "new log started" : "new log started; previous log archived as " archive)
        return archive
    }

    ; Moves source into logs\ and zips it there without waiting; returns the
    ; name the archive will have.
    Archive(source, time := A_Now) {
        DirCreate this.archiveDirectory
        base := "debug-" FormatTime(time, "yyyyMMdd-HHmmss")
            . (InStr(FileRead(source, "UTF-8"), "] DEBUG: ") ? "-verbose" : "")
        name := base
        while FileExist(this.archiveDirectory "\" name ".log") || FileExist(this.archiveDirectory "\" name ".zip")
            name := base "-" (A_Index + 1)
        FileMove(source, this.archiveDirectory "\" name ".log")
        tar := A_WinDir "\System32\tar.exe"
        if !FileExist(tar)
            return "logs\" name ".log"
        ; The outer quotes keep cmd from stripping the quotes around tar's path.
        Run(A_ComSpec ' /c ""' tar '" -a -cf "' name '.zip" "' name '.log" && del "' name '.log""',
            this.archiveDirectory, "Hide")
        return "logs\" name ".zip"
    }
}
