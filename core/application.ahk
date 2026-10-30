; =============================================================================
; Super Hotkey - application lifecycle, the shared input gate and modules.
; Modules never launch another AutoHotkey process or own the application tray.
; =============================================================================
class SuiteState {
    static App := 0
    static Log := 0
}

; One feature module. The application constructs one per entry in
; SuiteSettings.ModuleOrder and drives it through these methods. Every method
; is optional; the defaults do nothing.
class SuiteModule {
    started := false
    hasSettings := false
    ; INI sections in <settings>\<id>\settings.ini restored by Reset to defaults.
    resetSections := []

    __New(app, id) {
        this.app := app
        this.id := id
    }

    Name => SuiteSettings.ModuleNames[this.id]

    Register(manager) => 0             ; add actions in Keybindings display order
    Start() => 0                       ; begin native work; never called in a dry run
    Stop(reason := "Exit", code := 0) => 0  ; release everything; safe if never started
    PrepareExit(reason) => 0           ; throw to keep the suite running
    CancelWork() => 0                  ; expire queued work after any input change
    Suspend() => 0                     ; tray suspension, sleep or a locked session
    Resume() => 0
    ShowSettings(ui) => 0
    HelpText() => ""
    HelpButtons() => []                ; extra Help footer buttons: [label, callback, width]
}

class SuiteApplication {
    static Name := "Super Hotkey"
    static Version := "1.0.0-beta.1"
    ; Keybindings lists the compact Paper Pad section right after Global.
    static KeybindingsOrder := ["paper-pad", "cascade-kingdom", "wonder-windows",
        "power-up-utilities", "secret-layers"]

    __New(dryRun := false, directory := "") {
        this.dryRun := dryRun
        if directory = ""
            directory := dryRun ? A_Temp "\SuperHotkey-" FormatTime(, "yyyyMMdd-HHmmss") "-" DllCall("GetCurrentProcessId", "uint")
                : EnvGet("LOCALAPPDATA") "\nroj\SuperHotkey"
        this.Settings := SuiteSettings(directory)
        this.activeModules := this.Settings.modules.Clone()
        this.activeLayers := this.Settings.layers.Clone()
        this.modules := Map()
        this.manager := 0
        this.ui := 0
        this.stopping := false
        this.systemSuspended := false
        this.sessionLocked := false
        this.suspended := false
        this.inputGeneration := 0
        this.mutex := 0
        this.sessionNotifications := false
        this.startupWarnings := []
        this.exitCallback := ObjBindMethod(this, "Stop")
        this.errorCallback := ObjBindMethod(this, "UnhandledError")
        this.powerCallback := ObjBindMethod(this, "PowerEvent")
        this.sessionCallback := ObjBindMethod(this, "SessionEvent")
        this.resumeCallback := ObjBindMethod(this, "ResumeInputs")
        SuiteState.App := this
        SuiteState.Log := SuiteLog(directory, 2097152, this.Settings.verbose)
        if this.Settings.loadWarning != "" {
            this.startupWarnings.Push(this.Settings.loadWarning)
            SuiteState.Log.Write("Core", StrReplace(this.Settings.loadWarning, "`n", " "), "ERROR")
        }
        SuiteIcons.Initialize()
    }

    Start(openSettings := false) {
        name := "Local\nroj.SuperHotkey" (this.dryRun ? ".Preview." DllCall("GetCurrentProcessId", "uint") : "")
        this.mutex := DllCall("CreateMutexW", "ptr", 0, "int", false, "str", name, "ptr")
        if !this.mutex || A_LastError = 183
            throw Error("Another Super Hotkey instance is running. Close it before starting another copy.")
        OnExit(this.exitCallback)
        OnError(this.errorCallback)
        Persistent true
        SetWinDelay 0
        SetControlDelay -1
        DetectHiddenWindows true
        SetTitleMatchMode 2
        SetStoreCapsLockMode false
        ; Hides a Win release from Start. Shell tools use vkFF for this too and
        ; ignore it, while vkE8 can count as a key pressed with the next Win hold.
        A_MenuMaskKey := "vkFF"
        CoordMode "Mouse", "Screen"
        SuiteState.Log.Write("Core", "starting " SuiteApplication.Version " / AutoHotkey " A_AhkVersion)
        if !FileExist(this.Settings.path)
            this.Settings.Save(this.Settings.modules)
        this.InitializeCatalog()
        this.manager.SetPaused(true)
        try this.manager.Start()
        catch Error as failure {
            if !this.manager.running
                throw failure
            this.startupWarnings.Push(failure.Message "`n`nAll hotkeys remain inactive until the conflict is resolved."
                . "`nUse Keybindings to restore defaults, or disable a conflicting module and restart.")
            SuiteState.Log.Error("Keybindings", failure)
        }
        for warning in this.manager.loadWarnings
            this.startupWarnings.Push(warning)
        if !this.dryRun {
            SuiteWorkingMonitor.Start(this.manager)
            for id in SuiteSettings.ModuleOrder
                if this.ModuleActive(id)
                    this.StartModule(this.modules[id])
        }
        this.ui := SuiteInterface(this)
        this.ui.BuildTray()
        OnMessage(0x0218, this.powerCallback)
        OnMessage(0x02B1, this.sessionCallback)
        this.sessionNotifications := DllCall("Wtsapi32\WTSRegisterSessionNotification",
            "ptr", A_ScriptHwnd, "uint", 0, "int") != 0
        this.RefreshInputGate()
        for id in SuiteSettings.ModuleOrder
            SuiteState.Log.Write(SuiteSettings.ModuleNames[id], this.ModuleActive(id)
                ? (this.dryRun ? "dry run; effects disabled" : this.modules[id].started ? "enabled" : "failed to start")
                : "disabled")
        SuiteState.Log.Write("Core", "startup complete")
        for warning in this.startupWarnings
            MsgBox(warning, SuiteApplication.Name, "Icon!")
        if this.startupWarnings.Length || openSettings || this.dryRun
            this.manager.ShowSettings()
    }

    ; One failing module must not keep the rest of the suite from starting.
    StartModule(module) {
        module.started := true
        try module.Start()
        catch Error as failure {
            SuiteState.Log.Error(module.Name " / start", failure)
            this.startupWarnings.Push(module.Name " could not start:`n`n" failure.Message
                . "`n`nThe other modules are running.")
            this.Cleanup(module.Name, ObjBindMethod(module, "Stop", "Error", 1))
            module.started := false
            this.activeModules[module.id] := false
        }
    }

    InitializeCatalog() {
        this.modules := Map(
            "cascade-kingdom", CascadeKingdomModule(this),
            "wonder-windows", WonderWindowsModule(this),
            "power-up-utilities", PowerUpUtilities(this),
            "paper-pad", PaperPadModule(this),
            "secret-layers", SecretLayersModule(this))
        options := {directory: this.Settings.directory "\keybindings",
            statusCallback: ObjBindMethod(this, "BindingStatus")}
        if factory := this.modules["secret-layers"].LayerFactory()
            options.layerFactory := factory
        this.manager := Keybindings("super-hotkey", SuiteApplication.Name, options)
        this.manager.RegisterScope("paper-pad", PaperPadWindowActive)
        this.manager.RegisterScope("windows-terminal",
            (*) => (hwnd := SuiteWorkingMonitor.UserWindow()) && WinExist("ahk_exe WindowsTerminal.exe ahk_id " hwnd))
        ; One foreground window cannot be both Notepad3 Paper Pad and Windows Terminal.
        this.manager.RegisterDisjointScopes("paper-pad", "windows-terminal")
        this.manager.AddAction("core.keybindings", "open Keybindings", ObjBindMethod(this, "OpenBindingsEvent"),
            ["Caps + Alt + K", "Ctrl + Alt + K"], {category: "Global"})
        ; Global so that closing works whichever modules are enabled.
        this.manager.AddAction("core.close-active", "close active window", ObjBindMethod(this, "CloseWindowEvent"),
            ["Caps + Delete", "Win + Delete"], {category: "Global",
                context: (*) => SuiteWindowOwnership.AllowsWonderWindows(SuiteWorkingMonitor.UserWindow())})
        this.manager.AddAction("core.focus-outline", "show focus outline", ObjBindMethod(this, "FocusOutlineEvent"),
            ["Caps + Caps"], {category: "Global"})
        ; Listed in default-key order: F1 clear, F2 copy, F3 restart.
        this.manager.AddAction("core.clear-log", "clear debug log",
            ObjBindMethod(this, "LogShortcutEvent", "clear"), ["Pause + F1"], {category: "Global"})
        this.manager.AddAction("core.copy-log", "copy debug log",
            ObjBindMethod(this, "LogShortcutEvent", "copy"), ["Pause + F2"], {category: "Global"})
        this.manager.AddAction("core.restart", "restart Super Hotkey", ObjBindMethod(this, "RestartEvent"),
            ["Pause + F3"], {category: "Global"})
        ; The one action that still answers while suspended, so it can resume.
        this.manager.AddAction("core.suspend", "suspend / resume Super Hotkey", ObjBindMethod(this, "SuspendEvent"),
            ["Pause + F4"], {category: "Global", whilePaused: true})
        for id in SuiteApplication.KeybindingsOrder
            this.modules[id].Register(this.manager)
    }

    ModuleActive(id) => this.activeModules.Has(id) && this.activeModules[id]

    BindingStatus(message) {
        SuiteState.Log.Write("Keybindings", message)
    }

    OpenBindingsEvent(event) {
        if event.phase = "down"
            this.QueueInput(ObjBindMethod(this, "ToggleKeybindings"))
    }

    ; Capture the target at the press; a delayed close never hits a later window.
    CloseWindowEvent(event) {
        if event.phase != "down"
            return
        if this.dryRun {
            SuiteState.Log.Write("Core", "dry run: " event.actionId)
            return
        }
        hwnd := event.foregroundHwnd
        this.QueueInput(ObjBindMethod(SuiteCloseWindow, "Close", hwnd, WindowProcessId(hwnd)))
    }

    FocusOutlineEvent(event) {
        if event.phase != "down"
            return
        if this.dryRun {
            SuiteState.Log.Write("Core", "dry run: " event.actionId)
            return
        }
        this.QueueInput(ObjBindMethod(this, "ShowFocusOutline"))
    }

    ; Where am I? Outlines the window the user is in, or says that none has focus.
    ShowFocusOutline(*) {
        hwnd := SuiteWorkingMonitor.UserWindow()
        if IsSwitchableWindow(hwnd) && SuiteFocusBorder.Show(hwnd, "core")
            return
        SuiteNotice.Show("status", "No window has focus", 1400)
    }

    LogShortcutEvent(kind, event) {
        if event.phase != "down"
            return
        if this.dryRun {
            SuiteState.Log.Write("Core", "dry run: " event.actionId)
            return
        }
        this.QueueInput(ObjBindMethod(this, "RunLogShortcut", kind))
    }

    RunLogShortcut(kind, *) {
        if !IsObject(this.ui)
            return
        if kind = "copy"
            SuiteNotice.Show("status", this.ui.CopyLog() ? "Debug log copied" : "Debug log copy failed", 1400)
        else
            SuiteNotice.Show("status", this.ui.ClearLog() ? "Debug log cleared" : "Debug log clear failed", 1400)
    }

    ; Restart on release, so the new process never inherits held keys.
    RestartEvent(event) {
        if event.phase != "up" || this.stopping
            return
        if this.dryRun {
            SuiteState.Log.Write("Core", "dry run: " event.actionId)
            return
        }
        this.QueueInput(ObjBindMethod(this, "Restart"))
    }

    SuspendEvent(event) {
        if event.phase != "down" || this.stopping
            return
        if this.dryRun {
            SuiteState.Log.Write("Core", "dry run: " event.actionId)
            return
        }
        ; Not QueueInput: queued input does not run while suspended.
        SetTimer((*) => this.ToggleSuspended(), -1)
    }

    ToggleSuspended() {
        this.SetSuspended(!this.suspended)
        SuiteNotice.Show("status", "Super Hotkey " (this.suspended ? "suspended" : "resumed"), 1400)
    }

    Restart(*) {
        SuiteNotice.Show("status", "Restarting Super Hotkey", 1400)
        ; Let the notice be read before the process exits.
        SetTimer((*) => Reload(), -500)
    }

    HelpShortcutEvent(moduleId, event) {
        if event.phase != "down" || this.dryRun || this.stopping
            return
        this.QueueInput(ObjBindMethod(this, "ShowModuleHelp", moduleId))
    }

    ShowModuleHelp(moduleId, *) {
        if !this.stopping && IsObject(this.ui)
            this.ui.ToggleHelp(moduleId)
    }

    InputIsCurrent(generation) {
        return generation = this.inputGeneration && !this.dryRun && !this.stopping
            && IsObject(this.manager) && this.manager.running
            && !this.manager.gated && !this.manager.applying
    }

    QueueInput(callback, arguments*) {
        generation := this.inputGeneration
        SetTimer((*) => this.RunInput(generation, callback, arguments*), -1)
    }

    RunInput(generation, callback, arguments*) {
        if this.InputIsCurrent(generation)
            callback.Call(arguments*)
    }

    CancelInputs() {
        ; Expire deferred callbacks even if input resumes before their timer runs.
        this.inputGeneration += 1
        for id, module in this.modules
            module.CancelWork()
        SuiteCloseWindow.Cancel()
        SuiteFocusBorder.Hide()
    }

    SuspendModules() {
        for id, module in this.modules
            if module.started
                module.Suspend()
    }

    ResumeModules() {
        for id, module in this.modules
            if module.started
                module.Resume()
    }

    ToggleKeybindings(*) {
        editor := this.manager.editor
        if IsObject(editor.window) && WinActive("ahk_id " editor.window.Hwnd) {
            editor.RequestClose()
            return
        }
        this.ShowKeybindings()
    }

    ShowKeybindings(*) {
        this.CancelInputs()
        this.manager.ShowSettings()
    }

    SetSuspended(suspend) {
        suspend := !!suspend
        if this.stopping || this.suspended = suspend
            return
        if suspend {
            this.suspended := true
            this.RefreshInputGate()
            this.CancelInputs()
            this.SuspendModules()
        } else {
            this.ResumeModules()
            this.suspended := false
            this.RefreshInputGate()
        }
        if IsObject(this.ui)
            this.ui.UpdateSuspension()
        SuiteState.Log.Write("Core", "application " (suspend ? "suspended" : "resumed"))
    }

    RefreshInputGate() {
        if !IsObject(this.manager) || this.manager.disposed
            return
        other := this.dryRun || this.stopping || this.systemSuspended || this.sessionLocked
        ; Only a suspension the user chose can be ended with the suspend toggle.
        this.manager.SetPaused(other || this.suspended, !other)
    }

    PowerEvent(event, *) {
        ; PBT_APMSUSPEND, PBT_APMRESUMESUSPEND, PBT_APMRESUMEAUTOMATIC
        if event != 4 && event != 7 && event != 0x12
            return
        SetTimer(this.resumeCallback, 0)
        this.systemSuspended := true
        this.RefreshInputGate()
        this.CancelInputs()
        this.SuspendModules()
        if event != 4
            SetTimer(this.resumeCallback, -500)
    }

    SessionEvent(event, *) {
        ; WTS_SESSION_LOGOFF, WTS_SESSION_LOCK, WTS_SESSION_UNLOCK
        if event = 6 || event = 7 {
            this.sessionLocked := true
            this.RefreshInputGate()
            this.CancelInputs()
            this.SuspendModules()
        } else if event = 8 {
            this.sessionLocked := false
            SetTimer(this.resumeCallback, -500)
        }
    }

    ResumeInputs(*) {
        if this.stopping
            return
        InstallKeybdHook(true, true)
        if !this.sessionLocked && !this.suspended
            this.ResumeModules()
        ; Automatic power resume is not evidence that the session was unlocked.
        this.systemSuspended := false
        this.RefreshInputGate()
        SuiteState.Log.Write("Core", this.sessionLocked
            ? "power resumed; session remains locked" : "inputs recovered after resume/unlock")
    }

    Stop(reason := "Exit", code := 0) {
        if this.stopping
            return 0
        if IsObject(this.manager)
            this.manager.SetPaused(true)
        ; Only interactive exits ask modules for approval. Windows shutdown may
        ; already have closed their windows.
        if reason != "Shutdown" && reason != "Logoff" {
            for id, module in this.modules {
                if !module.started
                    continue
                try module.PrepareExit(reason)
                catch Error as failure {
                    SuiteState.Log.Error(module.Name " / exit refused", failure)
                    this.RefreshInputGate()
                    MsgBox(failure.Message "`n`nThe suite is still running. No notes were discarded.",
                        SuiteApplication.Name, "Icon!")
                    return 1
                }
            }
        }
        this.stopping := true
        SetTimer(this.resumeCallback, 0)
        if IsObject(this.manager)
            this.Cleanup("Keybindings", ObjBindMethod(this.manager, "Stop"))
        if IsObject(this.ui)
            this.Cleanup("Core / interfaces", ObjBindMethod(this.ui, "CloseAll"))
        for id in SuiteSettings.ModuleOrder
            if this.modules.Has(id)
                this.Cleanup(SuiteSettings.ModuleNames[id], ObjBindMethod(this.modules[id], "Stop", reason, code))
        this.Cleanup("Core / focus border", (*) => SuiteFocusBorder.Hide("", true))
        this.Cleanup("Core / working monitor", (*) => SuiteWorkingMonitor.Stop())
        this.Cleanup("Core / notices", (*) => SuiteNotice.Destroy())
        SuiteWindowOwnership.Clear()
        OnMessage(0x0218, this.powerCallback, 0)
        OnMessage(0x02B1, this.sessionCallback, 0)
        if this.sessionNotifications
            DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "ptr", A_ScriptHwnd, "int")
        if this.mutex {
            DllCall("CloseHandle", "ptr", this.mutex)
            this.mutex := 0
        }
        SuiteState.Log.Write("Core", "stopped: " reason " (" code ")")
        return 0
    }

    Cleanup(component, callback) {
        try callback.Call()
        catch Error as failure
            SuiteState.Log.Error(component " / cleanup", failure)
    }

    UnhandledError(failure, mode) {
        component := "Core"
        if HasProp(failure, "File") && RegExMatch(failure.File, "i)\\modules\\([^\\]+)\\", &match)
            component := match[1]
        SuiteState.Log.Error(component " / " mode, failure)
        ; Retain AutoHotkey's normal error dialog/termination instead of hiding faults.
        return 0
    }
}
