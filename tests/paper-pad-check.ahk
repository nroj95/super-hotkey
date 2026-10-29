; Paper Pad: autosave, native New and Save, topmost restoration and dialog ownership.
; Disposable preferences, dry-run inputs and test-owned windows only.
class PaperPadChecks {
    static Run() {
        this.CheckAutosavePolicy()
        this.NativeNewPolicy()
        this.NativeSaveDelegation()
        this.PaperPadTopmostRestoration()
        this.PaperPadDialogOwnership()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    static CheckAutosavePolicy() {
        tracking := {sampled: false, text: "", last_change: 0}
        PaperPadController.TrackAutosaveChanges(tracking, true, "abc", 1000)
        this.Assert(tracking.sampled && tracking.last_change = 1000,
            "first dirty snapshot starts Paper Pad's idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "abc", 1500)
        this.Assert(tracking.last_change = 1000,
            "unchanged document text preserves the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "aBc", 1600)
        this.Assert(tracking.last_change = 1600,
            "case-only edits reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "xyz", 1700)
        this.Assert(tracking.last_change = 1700,
            "equal-length replacements reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, true, "", 1800)
        this.Assert(tracking.last_change = 1800,
            "deletions reset the idle clock")
        PaperPadController.TrackAutosaveChanges(tracking, false, "", 1900)
        this.Assert(!tracking.sampled && tracking.text = "" && tracking.last_change = 0,
            "clean documents release their retained snapshot")
        this.Assert(!PaperPadController.ShouldAutosave(false, 2000, 9999, 9999),
            "clean Paper Pad skips idle autosave")
        this.Assert(!PaperPadController.ShouldAutosave(true, 999, 5000, 2000),
            "recent document edits defer autosave")
        this.Assert(!PaperPadController.ShouldAutosave(true, 1000, 5000, 999),
            "failed saves cannot trigger a rapid retry loop")
        this.Assert(PaperPadController.ShouldAutosave(true, 1000, 5000, 2000),
            "dirty Paper Pad saves one second after the last document change")
        this.Assert(PaperPadController.ShouldAutosave(true, 0, 10000, 1000),
            "continuous edits receive a ten-second fallback")
        this.Assert(PaperPadController.ShouldAutosave(false, 0, 10000, 1000),
            "encoding-only changes retain periodic save attempts")
    }

    static NativeNewPolicy() {
        this.Assert(!PaperPadController.UntitledHasEdits(false, ""),
            "clean native New can be converted into a managed page")
        this.Assert(PaperPadController.UntitledHasEdits(true, "")
            && PaperPadController.UntitledHasEdits(false, "typed text"),
            "native New never replaces an edited untitled document")
    }

    static NativeSaveDelegation() {
        path := SuiteChecks.directory "\release-native-save.md"
        savedPath := SuiteChecks.directory "\release-native-save-as.md"
        FileAppend "original", path, "UTF-8-RAW"
        window := SuiteGui("+ToolWindow", "Paper Pad native Save As regression")
        pad := CheckNativeSavePad(path, window.Hwnd)
        try {
            ; A previous disk version must not prevent native Save.
            FileDelete path
            FileAppend "native version", path, "UTF-8-RAW"
            pad.bridge.text := "native version plus new edits"
            pad.bridge.dirty := true
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") == pad.bridge.text,
                "native Save works without shortcut tracking")

            ; Notepad3 can reload an externally changed document.
            FileDelete path
            FileAppend "externally reloaded", path, "UTF-8-RAW"
            pad.bridge.text := "externally reloaded"
            pad.bridge.dirty := false
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") = "externally reloaded",
                "native reload becomes the current document")

            ; An unsuccessful native Save must not count as success.
            pad.bridge.text := "unsaved editor text"
            pad.bridge.dirty := true
            pad.bridge.suppress_save := true
            SuiteChecks.Rejects((*) => pad.SaveCurrentPage(false),
                "a failed native Save cannot be accepted")
            this.Assert(FileRead(path, "UTF-8") = "externally reloaded",
                "a failed native Save preserves the disk contents")

            pad.bridge.suppress_save := false
            this.Assert(pad.SaveCurrentPage(false)
                && FileRead(path, "UTF-8") = "unsaved editor text",
                "native Save succeeds after a previous failure")

            ; A clean document can recover a paused autosave.
            pad.autosave_paused := true
            this.Assert(pad.ResumeAutosaveAfterCleanNativeSave(path)
                && !pad.autosave_paused,
                "clean native Save resumes autosave")

            pad.bridge.dirty := true
            pad.autosave_paused := true
            this.Assert(!pad.ResumeAutosaveAfterCleanNativeSave(path),
                "dirty documents do not falsely resume autosave")

            ; The watcher must adopt native Save As while autosave is paused.
            FileAppend "saved under a new name", savedPath, "UTF-8-RAW"
            pad.bridge.path := savedPath
            pad.bridge.text := "saved under a new name"
            pad.bridge.dirty := false
            pad.autosave_paused := true
            pad.SyncPageLock()
            this.Assert(!pad.autosave_paused && pad.current_path = savedPath
                && pad.page_lock_path = savedPath,
                "clean native Save As resumes autosave on the new page")

            pad.bridge.text := "new page edits"
            pad.bridge.dirty := true
            pad.last_verified_save_tick := A_TickCount - PaperPadController.AutosaveMaxMs
            pad.last_autosave_attempt_tick := A_TickCount - PaperPadController.AutosaveIdleMs
            pad.Autosave()
            this.Assert(FileRead(savedPath, "UTF-8") = "new page edits"
                && FileRead(path, "UTF-8") = "unsaved editor text",
                "recovered autosave writes the new page and leaves the original intact")
        }
        finally {
            window.Destroy()
            FileDelete path
            if FileExist(savedPath)
                FileDelete savedPath
        }
    }

    static PaperPadTopmostRestoration() {
        window := SuiteGui("+ToolWindow", "Paper Pad topmost regression")
        pad := CheckTopmostPad(window.Hwnd)
        try {
            window.Show("NA w160 h100")
            pad.SetDrawerTopmost(true)
            this.Assert(!!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad can become topmost")
            pad.SetDrawerTopmost(false)
            this.Assert(!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad can yield to a real dialog")
            pad.SetDrawerTopmost(true)
            this.Assert(!!(WinGetExStyle("ahk_id " window.Hwnd) & 0x8),
                "Paper Pad restores topmost after yielding")
        }
        finally window.Destroy()
    }

    static PaperPadDialogOwnership() {
        windows := []
        try {
            drawer := SuiteGui("+ToolWindow", "Paper Pad ownership test")
            windows.Push(drawer)
            owner := SuiteGui("+ToolWindow", "External dialog owner")
            windows.Push(owner)
            unrelated := SuiteGui("+ToolWindow", "Unrelated same-process window")
            windows.Push(unrelated)
            helper := SuiteGui("+ToolWindow +E0x1 +Owner" owner.Hwnd, "Owned helper")
            windows.Push(helper)
            nested := SuiteGui("+ToolWindow +Owner" helper.Hwnd, "Nested modal dialog")
            windows.Push(nested)
            padDialog := SuiteGui("+ToolWindow +Owner" drawer.Hwnd, "Paper Pad dialog")
            windows.Push(padDialog)
            for window in [drawer, owner, unrelated, helper]
                window.Show("NA w160 h100")
            pad := CheckTopmostPad(drawer.Hwnd)
            pad.last_external_window := owner.Hwnd

            ; Explicit candidates keep the test independent of personal windows.
            this.Assert(!PaperPadIsDialogWindow(helper.Hwnd)
                && !pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd]),
                "an owned framed helper cannot lower Paper Pad while its owner is enabled")
            owner.Opt("+Disabled")
            this.Assert(PaperPadIsDialogWindow(helper.Hwnd)
                && pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd]) = helper.Hwnd,
                "a custom modal dialog is recognized through its disabled owner")
            this.Assert(!pad.FindYieldDialog(unrelated.Hwnd, [helper.Hwnd]),
                "sharing a process with the foreground window is not a dialog relationship")

            helper.Opt("+Disabled")
            nested.Show("NA w160 h100")
            this.Assert(!PaperPadIsDialogWindow(helper.Hwnd)
                && pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd, nested.Hwnd]) = nested.Hwnd,
                "nested owner chains select the enabled modal dialog, not its disabled parent")
            nested.Hide()
            helper.Opt("-Disabled")
            owner.Opt("-Disabled")
            this.Assert(!pad.FindYieldDialog(owner.Hwnd, [helper.Hwnd, nested.Hwnd]),
                "reenabling the owner and hiding the nested dialog removes the yield target")

            drawer.Opt("+Disabled")
            padDialog.Show("NA w160 h100")
            this.Assert(pad.FindYieldDialog(unrelated.Hwnd, [padDialog.Hwnd]) = padDialog.Hwnd,
                "Paper Pad's own modal dialog remains eligible when another window is active")
        }
        finally {
            while windows.Length
                windows.Pop().Destroy()
        }
    }
}

class CheckPad extends PaperPadController {
    __New() {
        this.busy := false
        this.command_queue := []
        this.executed := []
        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
    }

    ExecuteCommand(request) => this.executed.Push(request.name)
}

class CheckNativeSavePad extends PaperPadController {
    __New(path, hwnd) {
        this.window_hwnd := hwnd
        this.current_path := path
        this.bridge := CheckNativeSaveBridge(path)
        SplitPath(path, , &directory)
        this.notes_directory := directory
        this.allowed_extensions := "|md|"
        this.busy := false
        this.command_queue := []
        this.page_lock_path := ""
        this.disk_stamp := PaperPadFileStamp(path)
        this.autosave_paused := false
        this.autosave_tracking := {sampled: false, text: "", last_change: 0}
    }

    HasWindow() => true
    IsVisible() => true
    SyncZOrder() => 0
    ProtectPage(path) => this.page_lock_path := path
    ReleasePageLock() => this.page_lock_path := ""
    PersistCurrentState() => 0

    AcceptSave(path, stamp) {
        this.disk_stamp := stamp
    }

    ReportError(failure, notification := false) {
        throw failure
    }
}

class CheckNativeSaveBridge {
    __New(path) {
        this.path := path
        this.text := FileRead(path, "UTF-8")
        this.dirty := false
        this.tainted := false
        this.suppress_save := false
    }

    CheckReady() => 0
    CurrentPath() => this.path
    DocumentText() => this.text
    MatchesDisk(path) => FileRead(path, "UTF-8") == this.text
    MatchesDiskText(path, text) => FileRead(path, "UTF-8") == text
    IsDirty() => this.dirty

    Save() {
        if this.suppress_save
            return
        FileDelete this.path
        FileAppend this.text, this.path, "UTF-8-RAW"
        this.dirty := false
    }
}

class CheckTopmostPad extends PaperPadController {
    __New(hwnd) => this.window_hwnd := hwnd
}
