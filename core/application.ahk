; =============================================================================
; Super Hotkey - shared lifecycle and native thread defaults.
; Modules never launch another AutoHotkey process or own the application tray.
; =============================================================================
class SuiteState {
    static App := 0
    static Log := 0
    static CascadeStatus := ""
    static ScratchpadStatus := ""
}

class SuiteApplication {
    static Name := "Super Hotkey"
    static Version := "1.0.0"

    __New(dryRun := false, directory := "") {
        this.dryRun := dryRun
        if directory = ""
            directory := dryRun ? A_Temp "\SuperHotkey-" FormatTime(, "yyyyMMdd-HHmmss") "-" DllCall("GetCurrentProcessId", "uint")
                : EnvGet("LOCALAPPDATA") "\nroj\SuperHotkey"
        this.Settings := SuiteSettings(directory)
        this.activeModules := this.Settings.modules.Clone()
        this.activeLayers := this.Settings.layers.Clone()
        this.wonder := 0
        this.wonderStarted := false
        this.manager := 0
        this.power := 0
        this.capsToggle := 0
        this.ui := 0
        this.stopping := false
        this.systemSuspended := false
        this.sessionLocked := false
        this.suspended := false
        this.inputGeneration := 0
        this.cascadeInitialized := false
        this.cascadeStarted := false
        this.scratchpadStarted := false
        this.mutex := 0
        this.sessionNotifications := false
        this.bindingFailure := ""
        this.exitCallback := ObjBindMethod(this, "Stop")
        this.errorCallback := ObjBindMethod(this, "UnhandledError")
        this.powerCallback := ObjBindMethod(this, "PowerEvent")
        this.sessionCallback := ObjBindMethod(this, "SessionEvent")
        this.resumeCallback := ObjBindMethod(this, "ResumeInputs")
        SuiteState.App := this
        SuiteState.Log := SuiteLog(directory, 2097152, this.Settings.verbose)
        SuiteIcons.Initialize()
    }

    Start(openSettings := false) {
        name := "Local\nroj.SuperHotkey" (this.dryRun ? ".Preview." DllCall("GetCurrentProcessId", "uint") : "")
        this.mutex := DllCall("CreateMutexW", "ptr", 0, "int", false, "str", name, "ptr")
        if !this.mutex || A_LastError = 183
            throw Error("Another Super Hotkey instance is running. Close it before starting another copy.")
        OnExit(this.exitCallback)
        OnError(this.errorCallback)
        if !this.dryRun
            this.CheckOriginalScripts()
        Persistent true
        SetWinDelay 0
        SetControlDelay -1
        DetectHiddenWindows true
        SetTitleMatchMode 2
        SetStoreCapsLockMode false
        A_MenuMaskKey := "vkE8"
        CoordMode "Mouse", "Screen"
        CoordMode "ToolTip", "Screen"
        SuiteState.Log.Write("Core", "starting " SuiteApplication.Version " / AutoHotkey " A_AhkVersion)
        if !FileExist(this.Settings.path)
            this.Settings.Save(this.Settings.modules)
        this.InitializeCatalog()
        this.manager.SetPaused(true)
        try this.manager.Start()
        catch Error as failure {
            if !this.manager.running
                throw failure
            this.bindingFailure := failure.Message
            SuiteState.Log.Error("Keybindings", failure)
        }
        this.power.Start()
        if !this.dryRun {
            if this.ModuleActive("window-cascade") {
                this.cascadeStarted := true
                WindowCascadeModule.Start(this.manager)
            }
            if this.ModuleActive("win-key-overhaul") {
                this.wonderStarted := true
                this.wonder.Start()
            }
            if this.ModuleActive("scratchpad") {
                ScratchpadModule.Start(this.manager)
                this.scratchpadStarted := true
            }
        }
        this.ui := SuiteInterface(this)
        this.ui.BuildTray()
        OnMessage(0x0218, this.powerCallback)
        OnMessage(0x02B1, this.sessionCallback)
        this.sessionNotifications := DllCall("Wtsapi32\WTSRegisterSessionNotification",
            "ptr", A_ScriptHwnd, "uint", 0, "int") != 0
        this.RefreshInputGate()
        if !this.dryRun && IsObject(this.capsToggle)
            this.capsToggle.Start()
        for id, enabled in this.activeModules
            SuiteState.Log.Write(SuiteSettings.ModuleNames[id], enabled ? (this.dryRun ? "dry run; effects disabled" : "enabled") : "disabled")
        SuiteState.Log.Write("Core", "startup complete")
        if this.bindingFailure != "" {
            MsgBox(this.bindingFailure "`n`nAll hotkeys remain inactive until the conflict is resolved."
                . "`nUse Keybindings to restore defaults, or disable a conflicting module and restart.",
                SuiteApplication.Name, "Icon!")
            this.manager.ShowSettings()
        } else if openSettings || this.dryRun
            this.manager.ShowSettings()
    }

    InitializeCatalog() {
        InitializeCascadeState()
        WW_InitializeState()
        this.cascadeInitialized := true
        options := {directory: this.Settings.directory "\keybindings",
            statusCallback: ObjBindMethod(this, "BindingStatus")}
        if this.ModuleActive("keyboard-layers") && (this.activeLayers["caps"] || this.activeLayers["pause"])
            options.layerFactory := (name, status) => LocalKeyboardLayers(name, status, this.activeLayers)
        this.manager := Keybindings("super-hotkey", SuiteApplication.Name, options)
        this.manager.RegisterScope("paper-pad", PaperPadWindowActive)
        this.manager.RegisterScope("windows-terminal", (*) => WinActive("ahk_exe WindowsTerminal.exe"))
        ; One foreground window cannot be both Notepad3 Paper Pad and Windows Terminal.
        this.manager.RegisterDisjointScopes("paper-pad", "windows-terminal")
        this.manager.AddAction("core.keybindings", "open Keybindings", ObjBindMethod(this, "OpenBindingsEvent"),
            ["Caps + Alt + K", "Ctrl + Alt + K"], {category: "Global"})
        this.power := PowerHotkeys(this.manager, this.dryRun)
        WindowCascadeModule.Register(this.manager)
        ScratchpadModule.Register(this.manager)
        this.wonder := WonderWindowsModule(this.manager, this.dryRun)
        this.manager.AddAction("keyboard-layers.help", "show Secret Keys help",
            ObjBindMethod(this, "HelpShortcutEvent", "keyboard-layers"), [],
            {category: "Secret Keys", help: true,
                available: (*) => this.ModuleActive("keyboard-layers")})
        ; Retain the old ID so saved shortcuts survive the change of module owner.
        this.manager.AddAction("power-hotkey.keyboard.toggle-caps", "toggle Caps Lock",
            ObjBindMethod(this, "ToggleCapsLockEvent"), [],
            {category: "Secret Keys", available: (*) => this.ModuleActive("keyboard-layers")})
        if this.ModuleActive("keyboard-layers") && this.activeLayers["caps"]
            && this.Settings.capsToggleModifier != "Disabled"
            this.capsToggle := CapsLockModifierToggle(this.Settings.capsToggleModifier)
    }

    ModuleActive(id) => this.activeModules.Has(id) && this.activeModules[id]

    ToggleCapsLock(*) => SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")

    ToggleCapsLockEvent(event) {
        if event.phase = "up" && !this.dryRun && !this.stopping && !this.suspended
            && !this.manager.gated && this.ModuleActive("keyboard-layers")
            this.ToggleCapsLock()
    }

    BindingStatus(message) {
        SuiteState.Log.Write("Keybindings", message)
        if message = "keybinding changes saved" {
            this.bindingFailure := ""
            if IsObject(this.power)
                this.power.SyncEnabledActions()
            if this.cascadeInitialized
                SetTimer(RefreshCascadeHelpBindings, -1)
        }
    }

    OpenBindingsEvent(event) {
        if event.phase = "down"
            this.QueueInput(ObjBindMethod(this, "ToggleKeybindings"))
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
        if IsObject(this.capsToggle)
            this.capsToggle.Reset()
        if IsObject(this.wonder)
            this.wonder.CancelWork()
        if IsObject(this.power)
            this.power.CancelWork()
        SuiteFocusBorder.Hide()
        if this.cascadeStarted {
            global cascade_command_queue
            cascade_command_queue := []
            CancelNewWindowFocus()
            StopFocusTabClick()
        }
    }

    ToggleKeybindings(*) {
        if IsObject(this.manager.settings)
            && WinActive("ahk_id " this.manager.settings.Hwnd) {
            this.manager._RequestCloseSettings()
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
            if this.cascadeStarted
                WindowCascadeModule.Suspend()
        } else {
            ; Snapshot windows opened during suspension before allowing placement.
            if this.cascadeStarted
                WindowCascadeModule.Resume()
            this.suspended := false
            this.RefreshInputGate()
        }
        SuiteState.Log.Write("Core", "application " (suspend ? "suspended" : "resumed"))
    }

    RefreshInputGate() {
        if !IsObject(this.manager) || this.manager.disposed
            return
        this.manager.SetPaused(this.dryRun || this.stopping
            || this.systemSuspended || this.sessionLocked || this.suspended)
    }

    PowerEvent(event, *) {
        if event != 4 && event != 7 && event != 0x12
            return
        SetTimer(this.resumeCallback, 0)
        this.systemSuspended := true
        this.RefreshInputGate()
        this.CancelInputs()
        if this.cascadeStarted
            WindowCascadeModule.Suspend()
        if event != 4
            SetTimer(this.resumeCallback, -500)
    }

    SessionEvent(event, *) {
        if event = 6 || event = 7 {
            this.sessionLocked := true
            this.RefreshInputGate()
            this.CancelInputs()
            if this.cascadeStarted
                WindowCascadeModule.Suspend()
        } else if event = 8 {
            this.sessionLocked := false
            SetTimer(this.resumeCallback, -500)
        }
    }

    ResumeInputs(*) {
        if this.stopping
            return
        InstallKeybdHook(true, true)
        if this.cascadeStarted && !this.sessionLocked && !this.suspended
            WindowCascadeModule.Resume()
        ; Automatic power resume is not evidence that the session was unlocked.
        this.systemSuspended := false
        this.RefreshInputGate()
        SuiteState.Log.Write("Core", this.sessionLocked
            ? "power resumed; session remains locked" : "inputs recovered after resume/unlock")
    }

    Stop(reason := "Exit", code := 0) {
        global scratchpad
        if this.stopping
            return 0
        if IsObject(this.manager)
            this.manager.SetPaused(true)
        ; Save/close refusal must happen before dismantling the rest of the suite.
        if this.scratchpadStarted && IsSet(scratchpad) {
            try scratchpad.PrepareSuiteExit(reason)
            catch Error as failure {
                SuiteState.Log.Error("Paper Pad / exit refused", failure)
                this.RefreshInputGate()
                MsgBox(failure.Message "`n`nThe suite is still running. No notes were discarded.",
                    SuiteApplication.Name, "Icon!")
                return 1
            }
        }
        this.stopping := true
        SetTimer(this.resumeCallback, 0)
        if IsObject(this.capsToggle)
            this.Cleanup("Secret Keys / Caps Lock", ObjBindMethod(this.capsToggle, "Stop"))
        if IsObject(this.manager)
            this.Cleanup("Keybindings", ObjBindMethod(this.manager, "Stop"))
        if IsObject(this.power)
            this.Cleanup("Power-Up Utilities", ObjBindMethod(this.power, "Stop"))
        if IsObject(this.ui)
            this.Cleanup("Core / interfaces", ObjBindMethod(this.ui, "CloseAll"))
        if this.wonderStarted
            this.Cleanup("Wonder Windows", (*) => this.wonder.Stop(reason, code))
        if this.cascadeStarted
            this.Cleanup("Cascade Kingdom", (*) => WindowCascadeModule.Stop())
        if this.scratchpadStarted && IsSet(scratchpad)
            this.Cleanup("Paper Pad", (*) => scratchpad.OnScriptExit(reason, code))
        this.Cleanup("Core / focus border", (*) => SuiteFocusBorder.Hide("", true))
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

    CheckOriginalScripts() {
        previous := A_DetectHiddenWindows
        DetectHiddenWindows true
        try {
            for hwnd in WinGetList("ahk_class AutoHotkey") {
                if hwnd = A_ScriptHwnd
                    continue
                try title := WinGetTitle(hwnd)
                catch
                    continue
                if RegExMatch(title, "i)\\(?:window-cascade|win-key-overhaul|windows-key-overhaul|window-hotkeys|power-hotkey|scratchpad|caps-pause-layers|capslock-layer|pause-command-mode)(?:\([^\\]*\))?\.ahk - AutoHotkey")
                    throw Error("Close the original AutoHotkey utilities before starting the suite."
                        . "`nNo process was stopped automatically.`n`nDetected: " title)
            }
        }
        finally DetectHiddenWindows previous
    }
}
