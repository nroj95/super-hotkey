; =============================================================================
; terminal.ahk - the two Windows Terminal macros from the old CapsLock layer
; =============================================================================
; The original shortcut sequences are preserved. In particular, clearing sends
; Ctrl+Shift+K, Ctrl+C, Enter, Ctrl+Shift+K; it may interrupt a running command.
; Keep the user's corresponding Windows Terminal key assignments in place.
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
        stamp := FileExist(settingsPath)
            ? FileGetTime(settingsPath, "M") ":" FileGetSize(settingsPath) : "defaults"
        cacheKey := executable "|" version "|" stamp

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
                this.bindingsStatus := output
                this.bindingsCacheKey := cacheKey
            }
            finally {
                try FileDelete(resultPath)
            }
        }
        ; Verify only the shortcuts that this macro needs.
        required := action = "clear" ? ["CLEAR=1"] : ["COPY=1", "SELECT=1"]
        for line in required {
            if !InStr("`n" this.bindingsStatus "`n", "`n" line "`n")
                throw Error("Windows Terminal shortcut " (line = "CLEAR=1" ? "Ctrl+Shift+K (Clear buffer)"
                    : line = "COPY=1" ? "Ctrl+Shift+C (Copy text)"
                    : "Ctrl+Shift+A (Select all)")
                    . " is missing or reassigned. Check Terminal Settings > Actions. No keys were sent.")
        }
        return this.Ready(job)
    }

    SendStep(job, shortcut) {
        if !this.Ready(job)
            return false
        Send(shortcut)
        return true
    }

    Clear(job) {
        if !this.CheckBindings(job, "clear")
            return
        for index, shortcut in ["^+k", "^c", "{Enter}", "^+k"] {
            if !this.SendStep(job, shortcut)
                return
            if index < 4
                Sleep(50)
        }
    }

    Copy(job) {
        if !this.CheckBindings(job, "copy")
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
            if !this.SendStep(job, "^+a")
                return
            Sleep(50)
            if !this.SendStep(job, "^+c") || !ClipWait(1)
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
