; =============================================================================
; One flat tray. Module entries open their guides; module settings, the log and
; module selection are pages built with the shared helpers below.
; =============================================================================
class SuiteInterface {
    __New(app) {
        this.app := app
        this.windows := Map()
        this.moduleControls := Map()
        this.helpLayouts := Map()
        this.helpWindowIds := Map()
        this.helpSizingCallback := ObjBindMethod(this, "KeepHelpTextVisible")
        this.helpSizingInstalled := false
        this.pageLayouts := Map()
        this.pageFooters := Map()
        this.startupPath := A_Startup "\Super Hotkey.lnk"
    }

    BuildTray() {
        A_IconTip := SuiteApplication.Name " v" SuiteApplication.Version
            . (this.app.dryRun ? " - dry run" : "")
        try TraySetIcon(SuiteIcons.path, , true)
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Modules...", ObjBindMethod(this, "ShowModules"))
        A_TrayMenu.Add("Keybindings...", ObjBindMethod(this.app, "ShowKeybindings"))
        A_TrayMenu.Add()
        for id in SuiteSettings.ModuleOrder
            A_TrayMenu.Add(SuiteSettings.ModuleNames[id], ObjBindMethod(this, "ShowHelp", id))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Debug log", ObjBindMethod(this, "OpenLogFile"))
        A_TrayMenu.Add("Verbose logging", ObjBindMethod(this, "ToggleVerboseTray"))
        A_TrayMenu.Add("Open settings folder", ObjBindMethod(this, "OpenSettingsFolder"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Run at startup", ObjBindMethod(this, "ToggleStartupTray"))
        A_TrayMenu.Add("Suspend", ObjBindMethod(this, "ToggleSuspension"))
        A_TrayMenu.Add("Restart Super Hotkey", (*) => Reload())
        A_TrayMenu.Add("Reset to defaults...", ObjBindMethod(this, "ResetDefaults"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Keybindings..."
        this.UpdateVerboseTray()
        this.UpdateStartupTray()
        this.UpdateSuspension()
    }

    UpdateSuspension() {
        if this.app.suspended
            A_TrayMenu.Check("Suspend")
        else
            A_TrayMenu.Uncheck("Suspend")
    }

    ToggleSuspension(*) {
        this.app.SetSuspended(!this.app.suspended)
        this.UpdateSuspension()
    }

    Existing(key) {
        if !this.windows.Has(key)
            return false
        this.windows[key].Show()
        return true
    }

    NewWindow(key, title, configuration := false, options := "+Resize +0x02000000") {
        window := SuiteGui(options, title)
        window.BackColor := "FAF7F2"
        SuiteWindowOwnership.AllowArranging(window)
        window.SetFont("s10", "Cascadia Mono")
        window.OnEvent("Close", ObjBindMethod(this, "CloseWindow", key))
        window.OnEvent("Escape", ObjBindMethod(this, "CloseWindow", key))
        this.windows[key] := window
        ; Settings pages change what pending input would do; drop it.
        if configuration
            this.app.CancelInputs()
        return window
    }

    Footer(window, buttons, y, width := 800) {
        total := 0
        for item in buttons
            total += (item.Length >= 3 ? item[3] : 130) + 10
        x := width - 10 - total
        divider := window.AddText("x20 y" (y - 15) " w" (width - 40) " h2 +0x10", "")
        controls := []
        for item in buttons {
            buttonWidth := item.Length >= 3 ? item[3] : 130
            control := window.AddButton("x" x " y" y " w" buttonWidth " h30", item[1])
            control.OnEvent("Click", SuiteClickAction(item[2]))
            controls.Push({button: control, width: buttonWidth})
            x += buttonWidth + 10
        }
        footer := {divider: divider, buttons: controls, total: total}
        this.pageFooters[window.Hwnd] := footer
        return footer
    }

    ShowPage(key, width, height, minWidth := 0, minHeight := 0) {
        window := this.windows[key]
        footer := this.pageFooters[window.Hwnd]
        if !minWidth
            minWidth := width
        if !minHeight
            minHeight := height
        window.Opt("+Resize +MinSize" minWidth "x" minHeight " +0x02000000")
        controls := []
        footerHandles := Map(footer.divider.Hwnd, true)
        for item in footer.buttons
            footerHandles[item.button.Hwnd] := true
        for control in window {
            if footerHandles.Has(control.Hwnd)
                continue
            control.GetPos(&x, &y, &w, &h)
            controls.Push({control: control, x: x, y: y, w: w, h: h,
                stretchWidth: x + w >= width - 50 && w >= 300})
        }
        this.pageLayouts[key] := {footer: footer, controls: controls,
            width: width, height: height, minWidth: minWidth, minHeight: minHeight,
            renderedWidth: 0, renderedHeight: 0}
        window.OnEvent("Size", ObjBindMethod(this, "ResizePage", key))
        SuiteShowCentered(window, width, height, ObjBindMethod(this, "ResizePage", key))
    }

    ResizePage(key, window, minMax, width, height) {
        if minMax = -1 || !this.pageLayouts.Has(key)
            return
        layout := this.pageLayouts[key]
        width := Max(layout.minWidth, width)
        height := Max(layout.minHeight, height)
        if width = layout.renderedWidth && height = layout.renderedHeight
            return
        dx := width - layout.width
        dy := height - layout.height
        positions := []
        for item in layout.controls {
            positions.Push({control: item.control, x: item.x, y: item.y,
                w: item.stretchWidth ? Max(45, item.w + dx) : item.w, h: item.h})
        }
        positions.Push({control: layout.footer.divider, x: 20,
            y: height - 64, w: width - 40, h: 2})
        x := width - 10 - layout.footer.total
        for item in layout.footer.buttons {
            positions.Push({control: item.button, x: x,
                y: height - 49, w: item.width, h: 30})
            x += item.width + 10
        }
        SuiteMoveControls(window, positions)
        layout.renderedWidth := width
        layout.renderedHeight := height
    }

    CloseWindow(key, *) {
        if this.windows.Has(key) {
            if this.helpWindowIds.Has(this.windows[key].Hwnd)
                this.helpWindowIds.Delete(this.windows[key].Hwnd)
            if this.pageLayouts.Has(key)
                this.pageLayouts.Delete(key)
            if InStr(key, "help:") = 1 && this.helpLayouts.Has(SubStr(key, 6))
                this.helpLayouts.Delete(SubStr(key, 6))
            if this.pageFooters.Has(this.windows[key].Hwnd)
                this.pageFooters.Delete(this.windows[key].Hwnd)
            SuiteFocusReturn.Destroy(this.windows[key])
            this.windows.Delete(key)
        }
    }

    CloseAll() {
        for key in this.windows.Clone()
            this.CloseWindow(key)
        if this.helpSizingInstalled {
            OnMessage(0x0214, this.helpSizingCallback, 0)
            this.helpSizingInstalled := false
        }
        this.helpWindowIds.Clear()
    }

    CloseModules(*) => this.CloseWindow("modules")

    Report(failure, area) {
        SuiteState.Log.Error(area, failure)
        MsgBox(failure.Message, SuiteApplication.Name, "Icon!")
    }

    ; =========================================================================
    ; Help and suite-wide module selection
    ; =========================================================================

    ; Keyboard shortcuts toggle the active Help page. Tray navigation
    ; continues to show/raise existing pages without unexpectedly closing them.
    ToggleHelp(id, *) {
        key := "help:" id
        if this.windows.Has(key) && WinActive("ahk_id " this.windows[key].Hwnd) {
            this.CloseWindow(key)
            return
        }
        this.ShowHelp(id)
    }

    ShowHelp(id, *) {
        key := "help:" id
        if this.Existing(key)
            return
        module := this.app.modules[id]
        name := module.Name
        window := this.NewWindow(key, name " - Getting started", false,
            "+Resize +MinSize560x400 +0x02000000")
        state := this.app.ModuleActive(id) ? "enabled" : "disabled"
        if this.app.dryRun && this.app.ModuleActive(id)
            state := "dry run; feature effects are inactive"
        window.SetFont("s10", "Cascadia Mono")
        header := window.AddText("x20 y18 w400 h25", name " - ")
        statusColor := !this.app.ModuleActive(id) ? "B02020"
            : this.app.dryRun ? "505050" : "008000"
        window.SetFont("s10 c" statusColor, "Cascadia Mono")
        status := window.AddText("x420 y18 w250 h25", state)
        window.SetFont("s10 cDefault", "Cascadia Mono")
        content := window.AddText("x20 y55 w860 h455 vhelpText", module.HelpText())
        buttons := module.HelpButtons()
        if module.hasSettings
            buttons.Push(["Settings...", ObjBindMethod(this, "OpenSettingsFromHelp", id), 120])
        buttons.Push(["Keybindings...", ObjBindMethod(this, "OpenKeybindingsFromHelp", id), 135])
        buttons.Push(["Close", ObjBindMethod(this, "CloseWindow", key), 100])
        footer := this.Footer(window, buttons, 455, 900)
        width := 820
        height := 480
        this.helpLayouts[id] := {header: header, status: status, statusColor: statusColor,
            content: content, footer: footer, width: width, height: height,
            renderedWidth: 0, renderedHeight: 0}
        this.helpWindowIds[window.Hwnd] := id
        if !this.helpSizingInstalled {
            OnMessage(0x0214, this.helpSizingCallback)
            this.helpSizingInstalled := true
        }
        window.OnEvent("Size", ObjBindMethod(this, "ResizeHelp", id))
        ; Measure after giving the hidden GUI its opening width. Keep the compact
        ; default when it fits, but grow taller rather than clip the new intro.
        window.Show("Hide w" width " h" height)
        height := Max(height, 145 + this.HelpTextHeight(id, width) + 12)
        SuiteShowCentered(window, width, height, ObjBindMethod(this, "ResizeHelp", id))
    }

    ResizeHelp(id, window, minMax, width, height) {
        if minMax = -1 || !this.helpLayouts.Has(id)
            return
        layout := this.helpLayouts[id]
        width := Max(560, width)
        height := Max(400, height)
        if width = layout.renderedWidth && height = layout.renderedHeight
            return
        if minMax = 0 {
            layout.width := width
            layout.height := height
        }

        headerWidth := this.HelpHeadingWidth(window, layout.header)
        statusWidth := this.HelpHeadingWidth(window, layout.status)
        headerX := Floor((width - headerWidth - statusWidth) / 2)
        positions := [
            {control: layout.header, x: headerX, y: 18, w: headerWidth, h: 25},
            {control: layout.status, x: headerX + headerWidth, y: 18,
                w: statusWidth, h: 25},
            {control: layout.content, x: 20, y: 55, w: width - 40, h: height - 145},
            {control: layout.footer.divider, x: 20, y: height - 64, w: width - 40, h: 2}
        ]
        x := width - 10 - layout.footer.total
        for item in layout.footer.buttons {
            positions.Push({control: item.button, x: x, y: height - 49,
                w: item.width, h: 30})
            x += item.width + 10
        }
        SuiteMoveControls(window, positions)
        layout.renderedWidth := width
        layout.renderedHeight := height
    }

    HelpHeadingWidth(window, control) {
        window.GetClientPos(, , &logicalWidth)
        dimensions := Buffer(16, 0)
        if !DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", dimensions, "int")
            throw OSError(A_LastError, "Measure Help heading")
        scale := NumGet(dimensions, 8, "int") / Max(1, logicalWidth)
        hdc := DllCall("GetDC", "ptr", window.Hwnd, "ptr")
        if !hdc
            throw OSError(A_LastError, "Get Help heading drawing context")
        font := SendMessage(0x0031, 0, 0, , control.Hwnd)
        previous := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
        try {
            bounds := Buffer(8, 0)
            if !DllCall("GetTextExtentPoint32W", "ptr", hdc, "str", control.Text,
                "int", StrLen(control.Text), "ptr", bounds, "int")
                throw OSError(A_LastError, "Measure Help heading text")
            return Ceil(NumGet(bounds, 0, "int") / scale) + 3
        }
        finally {
            if previous
                DllCall("SelectObject", "ptr", hdc, "ptr", previous)
            DllCall("ReleaseDC", "ptr", window.Hwnd, "ptr", hdc)
        }
    }

    HelpTextHeight(id, clientWidth) {
        window := this.windows["help:" id]
        text := this.helpLayouts[id].content
        window.GetClientPos(, , &logicalWidth)
        rect := Buffer(16, 0)
        if !logicalWidth || !DllCall("GetClientRect", "ptr", window.Hwnd,
            "ptr", rect, "int")
            throw OSError(A_LastError, "Measure Help text")
        scale := NumGet(rect, 8, "int") / logicalWidth
        hdc := DllCall("GetDC", "ptr", window.Hwnd, "ptr")
        if !hdc
            throw OSError(A_LastError, "Get Help text drawing context")
        font := SendMessage(0x0031, 0, 0, , text.Hwnd)
        previous := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
        try {
            bounds := Buffer(16, 0)
            NumPut("int", Max(1, Round((clientWidth - 40) * scale)), bounds, 8)
            DllCall("DrawTextW", "ptr", hdc, "str", text.Text, "int", -1,
                "ptr", bounds, "uint", 0xC10, "int") ; word wrap, measure, no prefix
            return Ceil(NumGet(bounds, 12, "int") / scale)
        }
        finally {
            if previous
                DllCall("SelectObject", "ptr", hdc, "ptr", previous)
            DllCall("ReleaseDC", "ptr", window.Hwnd, "ptr", hdc)
        }
    }

    KeepHelpTextVisible(edge, proposed, messageId, hwnd) {
        if !this.helpWindowIds.Has(hwnd)
            return
        id := this.helpWindowIds[hwnd]
        window := this.windows["help:" id]
        current := Buffer(16, 0)
        client := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", current, "int")
            || !DllCall("GetClientRect", "ptr", hwnd, "ptr", client, "int")
            return
        window.GetClientPos(, , &logicalWidth)
        if !logicalWidth
            return
        scale := NumGet(client, 8, "int") / logicalWidth
        borderWidth := NumGet(current, 8, "int") - NumGet(current, 0, "int")
            - NumGet(client, 8, "int")
        borderHeight := NumGet(current, 12, "int") - NumGet(current, 4, "int")
            - NumGet(client, 12, "int")

        left := NumGet(proposed, 0, "int")
        top := NumGet(proposed, 4, "int")
        right := NumGet(proposed, 8, "int")
        bottom := NumGet(proposed, 12, "int")
        clientWidth := Max(560, Floor((right - left - borderWidth) / scale))
        ; The footer must remain separate from even the longest wrapped guide.
        requiredClientHeight := Max(400, 145 + this.HelpTextHeight(id, clientWidth))
        requiredOuterHeight := Ceil(requiredClientHeight * scale) + borderHeight
        if bottom - top >= requiredOuterHeight
            return

        ; Preserve the edge being dragged rather than jumping the whole window.
        if edge = 3 || edge = 4 || edge = 5
            NumPut("int", bottom - requiredOuterHeight, proposed, 4)
        else
            NumPut("int", top + requiredOuterHeight, proposed, 12)
        return true
    }

    OpenSettingsFromHelp(id, *) {
        this.CloseWindow("help:" id)
        this.ShowModuleSettings(id)
    }

    BackToHelp(id, *) {
        this.CloseWindow("settings:" id)
        this.ShowHelp(id)
    }

    OpenKeybindingsFromHelp(id, *) {
        this.CloseWindow("help:" id)
        this.app.CancelInputs()
        this.app.manager.ShowSettings(id)
    }

    ShowModules(*) {
        if this.Existing("modules")
            return
        window := this.NewWindow("modules", SuiteApplication.Name " - Modules", true)
        window.AddText("x20 y18 w560", "Module changes take effect after restarting.")
        this.moduleControls := Map()
        y := 60
        for id in SuiteSettings.ModuleOrder {
            control := window.AddCheckbox("x20 y" y " w540", SuiteSettings.ModuleNames[id])
            control.Value := this.app.Settings.modules[id]
            this.moduleControls[id] := control
            window.AddText("x42 y" (y + 25) " w518", SuiteSettings.ModuleDescriptions[id])
            y += 58
        }
        this.Footer(window, [["Apply and restart", ObjBindMethod(this, "SaveModules"), 160],
            ["Cancel", ObjBindMethod(this, "CloseModules"), 100]], 410, 600)
        this.ShowPage("modules", 600, 460, 580, 440)
    }

    SaveModules(*) {
        choices := Map()
        for id, control in this.moduleControls
            choices[id] := control.Value != 0
        try {
            this.app.Settings.Save(choices)
            this.CloseModules()
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Core / module settings")
    }

    ShowModuleSettings(id, *) => this.app.modules[id].ShowSettings(this)

    ; =========================================================================
    ; shared helpers for module settings pages
    ; =========================================================================

    ; Display dropdown entries; the stored value is the Windows device name.
    DisplayChoices(selected, includeAll := false) {
        values := includeAll ? ["All"] : []
        names := includeAll ? ["All displays"] : []
        models := this.GetDisplayModels()
        primary := MonitorGetPrimary()
        if selected = "Primary"
            selected := MonitorGetName(primary)
        loop MonitorGetCount() {
            try {
                name := MonitorGetName(A_Index)
                MonitorGetWorkArea(A_Index)
                values.Push(name)
                names.Push("Display " A_Index " - " models.Get(name, name)
                    . (A_Index = primary ? " (primary)" : ""))
            }
        }
        selectedIndex := 0
        for index, name in values
            if name = selected
                selectedIndex := index
        if !selectedIndex {
            values.Push(selected)
            names.Push(selected " (unavailable)")
            selectedIndex := names.Length
        }
        return {values: values, names: names, selected: selectedIndex}
    }

    GetDisplayModels() {
        models := Map()
        pathCount := 0
        modeCount := 0

        if DllCall("user32\GetDisplayConfigBufferSizes", "UInt", 2,
            "UInt*", &pathCount, "UInt*", &modeCount, "Int")
            return models

        paths := Buffer(pathCount * 72, 0)
        modes := Buffer(modeCount * 64, 0)
        if DllCall("user32\QueryDisplayConfig", "UInt", 2,
            "UInt*", &pathCount, "Ptr", paths,
            "UInt*", &modeCount, "Ptr", modes, "Ptr", 0, "Int")
            return models

        loop pathCount {
            offset := (A_Index - 1) * 72

            source := Buffer(84, 0)
            NumPut("UInt", 1, "UInt", source.Size, source)
            NumPut("Int64", NumGet(paths, offset, "Int64"), source, 8)
            NumPut("UInt", NumGet(paths, offset + 8, "UInt"), source, 16)

            if DllCall("user32\DisplayConfigGetDeviceInfo", "Ptr", source, "Int")
                continue

            display := StrGet(source.Ptr + 20, "UTF-16")

            target := Buffer(420, 0)
            NumPut("UInt", 2, "UInt", target.Size, target)
            NumPut("Int64", NumGet(paths, offset + 20, "Int64"), target, 8)
            NumPut("UInt", NumGet(paths, offset + 28, "UInt"), target, 16)

            if DllCall("user32\DisplayConfigGetDeviceInfo", "Ptr", target, "Int")
                continue

            model := StrGet(target.Ptr + 36, "UTF-16")
            if model != ""
                models[display] := model
        }

        return models
    }

    NumberField(window, name, minimum, maximum) {
        text := Trim(window[name].Value)
        if !IsInteger(text) || Integer(text) < minimum || Integer(text) > maximum
            throw ValueError(name " must be an integer from " minimum " to " maximum ".")
        return Integer(text)
    }

    ; =========================================================================
    ; Global logging and application preferences
    ; =========================================================================

    UpdateVerboseTray() {
        if SuiteState.Log.verbose
            A_TrayMenu.Check("Verbose logging")
        else
            A_TrayMenu.Uncheck("Verbose logging")
    }

    ApplyVerbose(enabled) {
        this.app.Settings.Save(this.app.Settings.modules, this.app.Settings.layers, enabled)
        SuiteState.Log.verbose := enabled
        SuiteState.Log.Write("Core", "verbose debugging " (enabled ? "enabled" : "disabled"))
        this.UpdateVerboseTray()
    }

    ToggleVerboseTray(*) {
        try this.ApplyVerbose(!SuiteState.Log.verbose)
        catch Error as failure
            this.Report(failure, "Core / logging preference")
    }

    CopyLog(*) {
        try {
            A_Clipboard := SuiteState.Log.Read()
            return true
        }
        catch Error as failure {
            this.Report(failure, "Core / copy log")
            return false
        }
    }

    ; No confirmation: the clear and copy hotkeys bracket a reproduction, and
    ; the previous log survives as debug.log.old.
    ClearLog(*) {
        try {
            SuiteState.Log.Clear()
            return true
        }
        catch Error as failure {
            this.Report(failure, "Core / clear log")
            return false
        }
    }

    OpenLogFile(*) {
        if !FileExist(SuiteState.Log.path)
            SuiteState.Log.Write("Core", "log opened")
        ; Full paths so a same-named program elsewhere on the search path never runs.
        Run('"' A_WinDir '\System32\notepad.exe" "' SuiteState.Log.path '"')
    }

    OpenSettingsFolder(*) {
        Run('"' A_WinDir '\explorer.exe" "' this.app.Settings.directory '"')
    }

    UpdateStartupTray() {
        if this.app.dryRun {
            A_TrayMenu.Disable("Run at startup")
            A_TrayMenu.Uncheck("Run at startup")
            return
        }
        A_TrayMenu.Enable("Run at startup")
        if FileExist(this.startupPath)
            A_TrayMenu.Check("Run at startup")
        else
            A_TrayMenu.Uncheck("Run at startup")
    }

    ToggleStartupTray(*) {
        if this.app.dryRun
            return
        try {
            if FileExist(this.startupPath)
                FileDelete(this.startupPath)
            else if A_IsCompiled
                FileCreateShortcut(A_ScriptFullPath, this.startupPath, A_ScriptDir)
            else
                FileCreateShortcut(A_AhkPath, this.startupPath, A_ScriptDir,
                    '"' A_ScriptDir "\super-hotkey.ahk" '"')
            this.UpdateStartupTray()
        }
        catch Error as failure {
            this.UpdateStartupTray()
            this.Report(failure, "Core / startup preference")
        }
    }

    ResetDefaults(*) {
        if MsgBox("Re-enable all five modules and both layers, and restore default hotkeys, modifier toggle and preferences?"
            . "`n`nNotes, their folder, editor path, Notepad3 preferences and page state will be kept."
            . "`nA settings backup will be created. The suite will restart.",
            SuiteApplication.Name, "YesNo Default2 Icon?") != "Yes"
            return
        app := this.app
        root := app.Settings.directory
        backup := ""
        try {
            paths := [app.Settings.path, app.manager.path]
            sections := Map()
            for id, module in app.modules {
                paths.Push(root "\" id "\settings.ini")
                sections[id] := module.resetSections
            }
            backup := app.Settings.Backup(paths)
            app.manager.Apply(app.manager._DefaultConfiguration())
            choices := Map()
            for id in SuiteSettings.ModuleOrder
                choices[id] := true
            app.Settings.Save(choices, Map("caps", true, "pause", true), false, "Shift")
            app.Settings.ResetModulePreferences(sections)
            SuiteState.Log.Write("Core", "defaults restored; backup: " backup)
            Reload()
        }
        catch Error as failure {
            SuiteState.Log.Error("Core / reset to defaults", failure)
            MsgBox("The reset stopped. Some preferences may have changed; notes were not deleted."
                . "`n`n" failure.Message "`n`nBackup: " backup, SuiteApplication.Name, "Icon!")
        }
    }
}
