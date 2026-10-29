; =============================================================================
; terminal.ahk - the two Windows Terminal macros: copy as Markdown and clear
; =============================================================================
; Both macros send Windows Terminal's default shortcuts: Ctrl+Shift+A selects
; all, Ctrl+Shift+C copies and Ctrl+Shift+K clears the buffer. A Terminal with
; those remapped needs its defaults back. Clearing sends Ctrl+C and Enter
; between two clears and can interrupt a running command. Never activate
; another window to finish a macro after the user changes focus.
; =============================================================================

class PU_Terminal {
    __New(app) {
        this.app := app
        this.clipboardRestore := 0
    }

    Ready(job) {
        if !this.app.JobValid(job) || !this.app.InputsReleased(job.event)
            return false
        try return WinGetProcessName("ahk_id " job.event.foregroundHwnd) = "WindowsTerminal.exe"
        catch
            return false
    }

    SendStep(job, shortcut) {
        if !this.Ready(job)
            return false
        Send(shortcut)
        return true
    }

    Clear(job) {
        for index, shortcut in ["^+k", "^c", "{Enter}", "^+k"] {
            if !this.SendStep(job, shortcut)
                return
            if index < 4
                Sleep(50)
        }
    }

    Copy(job) {
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
            formatted := PU_Terminal.FormatBuffer(A_Clipboard)
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
