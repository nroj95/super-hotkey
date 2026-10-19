; =============================================================================
; terminal.ahk - the two Windows Terminal macros from the old CapsLock layer
; =============================================================================
; Discover effective Terminal shortcuts without modifying Terminal's settings.
; Clearing still sends Ctrl+C and Enter between two clear actions and can
; interrupt a running command. Both extra keys are checked for safe behavior.
; Never activate another window to finish a macro after the user changes focus.
; =============================================================================

class PH_Terminal {
    __New(app) {
        this.app := app
        this.clipboardRestore := 0
        this.bindingsCacheKey := ""
        this.bindingsStatus := ""
    }

    Ready(job) {
        if !this.app.JobValid(job) || !this.app.InputsReleased(job.event)
            return false
        try return WinGetProcessName("ahk_id " job.event.foregroundHwnd) = "WindowsTerminal.exe"
        catch
            return false
    }

    ; Only the stable packaged Terminal has a known settings location.
    CheckBindings(job, action) {
        if !this.Ready(job)
            return false
        executable := WinGetProcessPath("ahk_id " job.event.foregroundHwnd)
        if !RegExMatch(executable, "i)\\Microsoft\.WindowsTerminal_\d+\.\d+\.\d+\.\d+_[^\\]+\\WindowsTerminal\.exe$")
            throw Error("This Windows Terminal installation is not supported by the shortcut checker. No keys were sent.")
        version := FileGetVersion(executable)
        settingsPath := EnvGet("LOCALAPPDATA") "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        ; Compare file contents, not second-resolution timestamps: users can
        ; edit and restore bindings within the same second.
        settingsSnapshot := FileExist(settingsPath) ? FileRead(settingsPath, "UTF-8") : "<defaults>"
        cacheKey := executable "|" version "|" settingsSnapshot

        if cacheKey != this.bindingsCacheKey {
            helper := A_ScriptDir "\modules\power-up-utilities\terminal-bindings.ps1"
            powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
            if !FileExist(helper) || !FileExist(powershell)
                throw Error("Windows Terminal shortcut checker is unavailable. No keys were sent.")
            resultPath := A_Temp "\super-hotkey-terminal-"
                . DllCall("GetCurrentProcessId", "uint") "-" A_TickCount ".txt"
            command := '"' powershell '" -NoLogo -NoProfile -NonInteractive'
                . ' -WindowStyle Hidden -ExecutionPolicy Bypass -File "' helper '"'
                . ' -TerminalVersion "' version '" -SettingsPath "' settingsPath '"'
                . ' -ResultPath "' resultPath '"'
            try {
                exitCode := RunWait(command, , "Hide")
                output := FileExist(resultPath) ? Trim(FileRead(resultPath, "UTF-8"), "`r`n ") : ""
                if exitCode != 0 || !RegExMatch(output, "^OK\R")
                    throw Error("Windows Terminal shortcut check failed: " (output != "" ? output : "no result")
                        . ". No keys were sent.")
                if (FileExist(settingsPath) ? FileRead(settingsPath, "UTF-8") : "<defaults>") != settingsSnapshot
                    throw Error("Windows Terminal settings changed during verification. Retry the shortcut.")
                this.bindingsStatus := output
                this.bindingsCacheKey := cacheKey
            }
            finally {
                try FileDelete(resultPath)
            }
        }
        if !this.Ready(job)
            return false
        if action = "clear" {
            if !InStr("`n" this.bindingsStatus "`n", "`nSAFE_CLEAR_STEPS=1`n")
                throw Error("Windows Terminal Ctrl+C or Enter is reassigned. No keys were sent.")
            return {clear: this.ResolvedShortcut("CLEAR")}
        }
        return {copy: this.ResolvedShortcut("COPY"),
            select: this.ResolvedShortcut("SELECT")}
    }

    ResolvedShortcut(name) {
        for line in StrSplit(this.bindingsStatus, "`n", "`r") {
            if InStr(line, name "=") != 1
                continue
            shortcut := SubStr(line, StrLen(name) + 2)
            ; Accept only the exact safe AHK Send format emitted by our helper.
            if RegExMatch(shortcut, "^[\^!+]{1,3}(?:[a-z0-9]|\{F(?:[1-9]|1[0-9]|2[0-4])\})$")
                return shortcut
            break
        }
        throw Error("No supported Windows Terminal shortcut for " name ". Check Terminal Settings > Actions. No keys were sent.")
    }

    SendStep(job, shortcut) {
        if !this.Ready(job)
            return false
        Send(shortcut)
        return true
    }

    Clear(job) {
        shortcuts := this.CheckBindings(job, "clear")
        if !shortcuts
            return
        for index, shortcut in [shortcuts.clear, "^c", "{Enter}", shortcuts.clear] {
            if !this.SendStep(job, shortcut)
                return
            if index < 4
                Sleep(50)
        }
    }

    Copy(job) {
        shortcuts := this.CheckBindings(job, "copy")
        if !shortcuts
            return
        savedClipboard := ClipboardAll()
        if !this.Ready(job)
            return
        previousCritical := A_IsCritical
        Critical "On"
        try {
            ; Publish restoration ownership before the first clipboard mutation.
            this.clipboardRestore := {previous: savedClipboard, sequence: 0}
            A_Clipboard := ""
            this.clipboardRestore.sequence := DllCall("GetClipboardSequenceNumber", "uint")
        }
        finally Critical previousCritical
        try {
            if !this.SendStep(job, shortcuts.select)
                return
            Sleep(50)
            if !this.SendStep(job, shortcuts.copy) || !ClipWait(1)
                return
            if !this.Ready(job)
                return
            copiedSequence := DllCall("GetClipboardSequenceNumber", "uint")
            formatted := PH_Terminal.FormatBuffer(A_Clipboard)
            ; Preserve a newer clipboard copy, even when the original Terminal
            ; still has focus. Sequence checking also protects intervening apps.
            if this.Ready(job) && DllCall("GetClipboardSequenceNumber", "uint") = copiedSequence
                A_Clipboard := formatted
        }
        finally this.RestoreClipboard()
    }

    static FormatBuffer(text) {
        trimmed := RegExReplace(text, "(\R[ \t]*)+$")
        fence := Chr(96) Chr(96) Chr(96)
        return fence "`n" trimmed "`n" fence
    }

    RestoreClipboard() {
        restoration := this.clipboardRestore
        if !IsObject(restoration)
            return
        ; Only undo our own still-empty clipboard, never a successful or newer copy.
        if restoration.sequence
            && DllCall("GetClipboardSequenceNumber", "uint") = restoration.sequence
            A_Clipboard := restoration.previous
        this.clipboardRestore := 0
    }
}
