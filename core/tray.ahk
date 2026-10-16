; =============================================================================
; One flat tray. Module entries open help; settings and diagnostics live in GUIs.
; Every Keybindings button returns to the same manager-owned editor.
; =============================================================================
class SuiteInterface {
    __New(app) {
        this.app := app
        this.windows := Map()
        this.configurationWindows := Map()
        this.modulesWindow := 0
        this.moduleControls := Map()
        this.helpLayouts := Map()
        this.helpWindowIds := Map()
        this.helpSizingCallback := ObjBindMethod(this, "KeepHelpTextVisible")
        this.helpSizingInstalled := false
        this.pageLayouts := Map()
        this.pageFooters := Map()
        this.footerButtons := Map()
        this.footerDrawCallback := ObjBindMethod(this, "DrawFooterButton")
        this.footerDrawInstalled := false
        this.footerPaintCount := 0
        this.logColorCallback := ObjBindMethod(this, "ColorLog")
        OnMessage(0x0138, this.logColorCallback) ; WM_CTLCOLORSTATIC for read-only Edit
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
        A_TrayMenu.Add("Debug log", ObjBindMethod(this, "OpenLog"))
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
        SuiteFullscreen.Enable(window)
        window.SetFont("s10", "Cascadia Mono")
        window.OnEvent("Close", ObjBindMethod(this, "CloseWindow", key))
        window.OnEvent("Escape", ObjBindMethod(this, "CloseWindow", key))
        this.windows[key] := window
        if configuration {
            this.configurationWindows[key] := true
            this.app.CancelInputs()
        }
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
            this.footerButtons[control.Hwnd] := window.Hwnd
            if !this.footerDrawInstalled {
                OnMessage(0x004E, this.footerDrawCallback)
                this.footerDrawInstalled := true
            }
            control.OnEvent("Click", item[2])
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
                stretchWidth: x + w >= width - 50 && w >= 300,
                stretchHeight: key = "log" && control.Type = "Edit" && h >= 200})
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
        SuiteSizeGrip.Move(window, minMax)
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
                w: item.stretchWidth ? Max(45, item.w + dx) : item.w,
                h: item.stretchHeight ? Max(45, item.h + dy) : item.h})
        }
        positions.Push({control: layout.footer.divider, x: 20,
            y: height - 64, w: width - 40, h: 2})
        x := width - 10 - layout.footer.total
        for item in layout.footer.buttons {
            positions.Push({control: item.button, x: x,
                y: height - 49, w: item.width, h: 30})
            x += item.width + 10
        }
        this.MoveHelpControls(window, positions)
        layout.renderedWidth := width
        layout.renderedHeight := height
    }

    DrawFooterButton(wParam, lParam, messageId, receiverHwnd) {
        hwnd := NumGet(lParam, 0, "ptr")
        if !this.footerButtons.Has(hwnd) || this.footerButtons[hwnd] != receiverHwnd
            || NumGet(lParam, 16, "int") != -12 ; NM_CUSTOMDRAW
            || NumGet(lParam, 24, "uint") != 1 ; CDDS_PREPAINT
            return

        hdc := NumGet(lParam, 32, "ptr")
        state := NumGet(lParam, 64, "uint")
        pressed := !!(state & 0x1)
        hovered := !!(state & 0x40)
        enabled := !!DllCall("IsWindowEnabled", "ptr", hwnd, "int")
        fillColor := pressed ? 0xE5E5E5 : hovered ? 0xF5F5F5 : 0xFFFFFF
        frameColor := 0xC9C9C9
        textColor := enabled ? 0x202020 : 0x999999
        fillBrush := DllCall("CreateSolidBrush", "uint", fillColor, "ptr")
        frameBrush := DllCall("CreateSolidBrush", "uint", frameColor, "ptr")
        if !fillBrush || !frameBrush {
            if fillBrush
                DllCall("DeleteObject", "ptr", fillBrush)
            if frameBrush
                DllCall("DeleteObject", "ptr", frameBrush)
            return
        }

        bounds := Buffer(16, 0)
        DllCall("RtlMoveMemory", "ptr", bounds, "ptr", lParam + 40, "uptr", 16)
        try {
            DllCall("FillRect", "ptr", hdc, "ptr", bounds, "ptr", fillBrush, "int")
            DllCall("FrameRect", "ptr", hdc, "ptr", bounds, "ptr", frameBrush, "int")
            inner := Buffer(16, 0)
            DllCall("RtlMoveMemory", "ptr", inner, "ptr", bounds, "uptr", 16)
            DllCall("InflateRect", "ptr", inner, "int", -5, "int", -3, "int")
            length := DllCall("GetWindowTextLengthW", "ptr", hwnd, "int")
            label := Buffer((length + 1) * 2, 0)
            DllCall("GetWindowTextW", "ptr", hwnd, "ptr", label, "int", length + 1, "int")
            font := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x31,
                "uptr", 0, "ptr", 0, "ptr")
            originalFont := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
            originalMode := DllCall("SetBkMode", "ptr", hdc, "int", 1, "int")
            originalText := DllCall("SetTextColor", "ptr", hdc, "uint", textColor, "uint")
            try DllCall("DrawTextW", "ptr", hdc, "ptr", label, "int", -1,
                "ptr", inner, "uint", 0x8825, "int")
            finally {
                DllCall("SetTextColor", "ptr", hdc, "uint", originalText)
                DllCall("SetBkMode", "ptr", hdc, "int", originalMode)
                if originalFont
                    DllCall("SelectObject", "ptr", hdc, "ptr", originalFont)
            }
            if state & 0x10
                DllCall("DrawFocusRect", "ptr", hdc, "ptr", inner, "int")
            this.footerPaintCount += 1
        }
        finally {
            DllCall("DeleteObject", "ptr", fillBrush)
            DllCall("DeleteObject", "ptr", frameBrush)
        }
        return 4 ; CDRF_SKIPDEFAULT
    }

    CloseWindow(key, *) {
        if this.windows.Has(key) {
            if this.helpWindowIds.Has(this.windows[key].Hwnd)
                this.helpWindowIds.Delete(this.windows[key].Hwnd)
            for control in this.windows[key]
                if control.Type = "Button" && this.footerButtons.Has(control.Hwnd)
                    this.footerButtons.Delete(control.Hwnd)
            if this.pageLayouts.Has(key)
                this.pageLayouts.Delete(key)
            if InStr(key, "help:") = 1 && this.helpLayouts.Has(SubStr(key, 6))
                this.helpLayouts.Delete(SubStr(key, 6))
            if this.pageFooters.Has(this.windows[key].Hwnd)
                this.pageFooters.Delete(this.windows[key].Hwnd)
            SuiteFullscreen.Forget(this.windows[key])
            SuiteSizeGrip.Detach(this.windows[key])
            this.windows[key].Destroy()
            this.windows.Delete(key)
        }
        if this.configurationWindows.Has(key)
            this.configurationWindows.Delete(key)
        if key = "modules"
            this.modulesWindow := 0
    }

    CloseAll() {
        for key in this.windows.Clone()
            this.CloseWindow(key)
        if this.helpSizingInstalled {
            OnMessage(0x0214, this.helpSizingCallback, 0)
            this.helpSizingInstalled := false
        }
        this.helpWindowIds.Clear()
        if this.footerDrawInstalled {
            OnMessage(0x004E, this.footerDrawCallback, 0)
            this.footerDrawInstalled := false
        }
        this.footerButtons.Clear()
        OnMessage(0x0138, this.logColorCallback, 0)
    }

    HasSettingsOpen() => this.configurationWindows.Count != 0
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
        name := SuiteSettings.ModuleNames[id]
        window := this.NewWindow(key, name " - Getting started", false,
            "+Resize +MinSize560x400 +0x02000000")
        state := this.app.ModuleActive(id) ? "enabled" : "disabled"
        if this.app.dryRun && this.app.ModuleActive(id)
            state := "dry run; feature effects are inactive"
        ; The original Window Cascade help used regular Cascadia Mono at 10 pt.
        window.SetFont("s10", "Cascadia Mono")
        header := window.AddText("x20 y18 w400 h25", name " - ")
        statusColor := !this.app.ModuleActive(id) ? "B02020"
            : this.app.dryRun ? "505050" : "008000"
        window.SetFont("s10 c" statusColor, "Cascadia Mono")
        status := window.AddText("x420 y18 w250 h25", state)
        window.SetFont("s10 cDefault", "Cascadia Mono")
        content := window.AddText("x20 y55 w860 h455 vhelpText",
            ModuleHelp.Text(id, this.app.manager))
        buttons := []
        if id = "scratchpad"
            buttons.Push(["Open Pad", ObjBindMethod(this, "OpenPad"), 110])
        if id != "power-hotkey"
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
        SuiteSizeGrip.Move(window, minMax)
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
        this.MoveHelpControls(window, positions)
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

    MoveHelpControls(window, positions) {
        window.GetClientPos(, , &logicalWidth)
        dimensions := Buffer(16, 0)
        if !logicalWidth || !DllCall("GetClientRect", "ptr", window.Hwnd,
            "ptr", dimensions, "int")
            throw Error("Cannot measure the Help window client area.")
        scale := NumGet(dimensions, 8, "int") / logicalWidth

        batch := DllCall("BeginDeferWindowPos", "int", positions.Length, "ptr")
        if !batch
            throw OSError(A_LastError, "Begin Help window resize")
        for entry in positions {
            batch := DllCall("DeferWindowPos", "ptr", batch, "ptr", entry.control.Hwnd,
                "ptr", 0, "int", Round(entry.x * scale), "int", Round(entry.y * scale),
                "int", Round(entry.w * scale), "int", Round(entry.h * scale),
                "uint", 0x114, "ptr") ; SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOCOPYBITS
            if !batch
                throw OSError(A_LastError, "Position Help control")
        }
        if !DllCall("EndDeferWindowPos", "ptr", batch, "int")
            throw OSError(A_LastError, "Finish Help window resize")

        ; Batch movement avoids intermediate paint states. Explicitly invalidate
        ; the moved buttons so they do not retain stale fragments after dragging.
        for entry in positions
            if entry.control.Type = "Button"
                DllCall("RedrawWindow", "ptr", entry.control.Hwnd, "ptr", 0,
                    "ptr", 0, "uint", 0x105, "int")
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

    RefreshHelp(*) {
        for id in SuiteSettings.ModuleOrder {
            key := "help:" id
            if this.windows.Has(key)
                this.windows[key]["helpText"].Value := ModuleHelp.Text(id, this.app.manager)
        }
    }

    ShowModules(*) {
        if this.Existing("modules")
            return
        window := this.NewWindow("modules", SuiteApplication.Name " - Modules", true)
        this.modulesWindow := window
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

    ShowModuleSettings(id, *) {
        switch id {
            case "keyboard-layers": this.ShowLayerSettings()
            case "window-cascade": this.ShowCascadeSettings()
            case "scratchpad": this.ShowPaperSettings()
            case "win-key-overhaul": this.ShowWonderSettings()
        }
    }

    ; =========================================================================
    ; Secret Keys: persistent, independent layer choices; restart-based hooks
    ; =========================================================================

    UpdateSelectorEnabled(selector, checkbox, *) {
        selector.Enabled := checkbox.Value != 0
    }

    ShowLayerSettings(*) {
        key := "settings:keyboard-layers"
        if this.Existing(key)
            return
        window := this.NewWindow(key, "Secret Keys - Settings", true)
        window.AddText("x20 y20 w560", "Modules is the master switch. These choices control each layer independently.")
        window.AddCheckbox("x20 y70 w540 vcaps", "Enable CapsLock Layer").Value := this.app.Settings.layers["caps"]
        window.AddCheckbox("x20 y115 w540 vpause", "Enable Pause Layer").Value := this.app.Settings.layers["pause"]
        toggle := window.AddCheckbox("x20 y160 w415 vcapsToggleEnabled",
            "Double-tap a modifier to toggle Caps Lock")
        toggle.Value := this.app.Settings.capsToggleModifier != "Disabled"
        selector := window.AddDropDownList("x445 y158 w135 vcapsToggleModifier", ["Shift", "Ctrl", "Alt"])
        selector.Choose(this.app.Settings.capsToggleModifierChoice)
        toggle.OnEvent("Click", ObjBindMethod(this, "UpdateSelectorEnabled", selector))
        this.UpdateSelectorEnabled(selector, toggle)
        window.AddText("x20 y235 w560", "Only works while the CapsLock layer is enabled."
            . "`nAn optional shortcut is available in Keybindings.")
        this.Footer(window, [["Apply and restart", ObjBindMethod(this, "SaveLayers"), 160],
            ["Back", ObjBindMethod(this, "BackToHelp", "keyboard-layers"), 100]], 300, 600)
        this.ShowPage(key, 600, 350, 560, 325)
    }

    SaveLayers(*) {
        key := "settings:keyboard-layers"
        window := this.windows[key]
        try {
            this.app.Settings.Save(this.app.Settings.modules,
                Map("caps", window["caps"].Value != 0, "pause", window["pause"].Value != 0),
                this.app.Settings.verbose,
                window["capsToggleEnabled"].Value != 0 ? window["capsToggleModifier"].Text : "Disabled",
                window["capsToggleModifier"].Text)
            this.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Secret Keys / settings")
    }

    ; =========================================================================
    ; Cascade Kingdom settings replace the old tray submenus
    ; =========================================================================

    ShowCascadeSettings(*) {
        key := "settings:window-cascade"
        if this.Existing(key)
            return
        global cascade_auto_placement_paused, cascade_hold_to_skip_key, cascade_hold_to_skip_choice
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        window := this.NewWindow(key, "Cascade Kingdom - Settings", true)
        window.AddCheckbox("x20 y25 w550 vpaused", "Pause automatic placement of new windows").Value := cascade_auto_placement_paused
        skipToggle := window.AddCheckbox("x20 y72 w300 vholdToSkipEnabled",
            "Hold to skip automatic placement")
        skipToggle.Value := cascade_hold_to_skip_key != "Disabled"
        skipKey := window.AddDropDownList("x330 y70 w170 vholdToSkipKey", ["CapsLock", "Pause"])
        skipKey.Choose(cascade_hold_to_skip_choice)
        skipToggle.OnEvent("Click", ObjBindMethod(this, "UpdateSelectorEnabled", skipKey))
        this.UpdateSelectorEnabled(skipKey, skipToggle)
        window.AddCheckbox("x20 y115 w550 vtabs", "Show focus tabs").Value := focus_corner_visible
        colors := []
        for name in focus_tab_color_presets
            colors.Push(name)
        window.AddText("x20 y165 w200", "Active-slot tab color")
        active := window.AddDropDownList("x240 y160 w210 vactiveColor", colors)
        active.Choose(focus_corner_active_slot_color_name)
        window.AddText("x20 y210 w200", "Inactive-slot tab color")
        inactive := window.AddDropDownList("x240 y205 w210 vinactiveColor", colors)
        inactive.Choose(focus_corner_inactive_slot_color_name)
        window.AddText("x20 y265 w550", "Changes apply immediately. Existing cascades stay intact.")
        this.Footer(window, [["Apply", ObjBindMethod(this, "SaveCascade"), 120],
            ["Back", ObjBindMethod(this, "BackToHelp", "window-cascade"), 100]], 335, 600)
        this.ShowPage(key, 600, 385, 560, 350)
    }

    SaveCascade(*) {
        global cascade_auto_placement_paused, cascade_hold_to_skip_key, cascade_hold_to_skip_choice
        global focus_corner_visible, focus_tab_color_presets
        global focus_corner_active_slot_color_name, focus_corner_inactive_slot_color_name
        global focus_corner_active_slot_color, focus_corner_inactive_slot_color

        key := "settings:window-cascade"
        window := this.windows[key]
        try {
            paused := window["paused"].Value != 0
            holdToSkipChoice := window["holdToSkipKey"].Text
            if holdToSkipChoice != "CapsLock" && holdToSkipChoice != "Pause"
                throw ValueError("Select a valid hold-to-skip key.")
            holdToSkipKey := window["holdToSkipEnabled"].Value != 0 ? holdToSkipChoice : "Disabled"
            visible := window["tabs"].Value != 0
            activeName := window["activeColor"].Text
            inactiveName := window["inactiveColor"].Text
            if !focus_tab_color_presets.Has(activeName) || !focus_tab_color_presets.Has(inactiveName)
                throw ValueError("Select valid focus-tab colors.")

            ; Persist first. No running state changes if the write fails.
            this.app.Settings.WritePreferences("window-cascade", Map(
                "Controls", Map("AutoPlacementPaused", paused ? 1 : 0,
                    "HoldToSkipKey", holdToSkipKey, "HoldToSkipChoice", holdToSkipChoice),
                "FocusTabs", Map("Visible", visible ? 1 : 0,
                    "ActiveSlotColor", activeName, "InactiveSlotColor", inactiveName)))

            ; Reuse the same pause/resume transition as Caps + P, preserving
            ; the rule that windows opened while paused remain unmanaged.
            if cascade_auto_placement_paused != paused
                ToggleCascadeAutoPlacement()
            if cascade_auto_placement_paused != paused
                throw Error("Automatic placement could not change mode. See the debug log.")
            cascade_hold_to_skip_key := holdToSkipKey
            cascade_hold_to_skip_choice := holdToSkipChoice

            if focus_corner_visible != visible
                ToggleFocusCornerVisibility()
            focus_corner_active_slot_color_name := activeName
            focus_corner_inactive_slot_color_name := inactiveName
            focus_corner_active_slot_color := focus_tab_color_presets[activeName]
            focus_corner_inactive_slot_color := focus_tab_color_presets[inactiveName]
            QueueFocusCornerUpdate()
            this.CloseWindow(key)
        }
        catch Error as failure
            this.Report(failure, "Cascade Kingdom / settings")
    }

    ; =========================================================================
    ; Paper Pad: checked preference changes, never moving or deleting note files
    ; =========================================================================

    ShowPaperSettings(*) {
        key := "settings:scratchpad"
        if this.Existing(key)
            return
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        window := this.NewWindow(key, "Paper Pad - Settings", true)
        window.AddText("x20 y18 w740", "Changing the notes folder does not move or delete existing notes.")
        window.AddText("x20 y60 w150", "Notes folder")
        window.AddEdit("x180 y55 w590 vfolder", IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad"))
        window.AddText("x20 y105 w150", "Notepad3 executable")
        window.AddEdit("x180 y100 w590 veditor", IniRead(path, "Paths", "Notepad3Executable", ""))
        window.AddText("x180 y132 w590", "Leave the executable blank for automatic detection.")
        this.padMonitors := ["Primary"]
        names := ["Main display"]
        loop MonitorGetCount() {
            try {
                name := MonitorGetName(A_Index)
                MonitorGetWorkArea(A_Index)
                this.padMonitors.Push(name)
                names.Push("Display " A_Index " (" name ")")
            }
        }
        selected := IniRead(path, "Window", "Monitor", "Primary")
        selectedIndex := 0
        for index, name in this.padMonitors
            if name = selected
                selectedIndex := index
        if !selectedIndex {
            this.padMonitors.Push(selected)
            names.Push(selected " (unavailable)")
            selectedIndex := names.Length
        }
        window.AddText("x20 y180 w150", "Display")
        window.AddDropDownList("x180 y175 w380 vdisplay", names).Choose(selectedIndex)
        fields := [["width", "Width (%)", "Window", "WidthPercent", 45],
            ["height", "Height (%)", "Window", "HeightPercent", 35],
            ["animation", "Animation (ms)", "Window", "AnimationDurationMs", 180],
            ["autosave", "Autosave (ms)", "Saving", "AutosaveIntervalMs", 10000]]
        y := 225
        for item in fields {
            window.AddText("x20 y" (y + 5) " w150", item[2])
            window.AddEdit("x180 y" y " w140 v" item[1], IniRead(path, item[3], item[4], item[5]))
            y += 43
        }
        this.Footer(window, [["Open notes folder", ObjBindMethod(this, "OpenNotesFolder"), 165],
            ["Apply and restart", ObjBindMethod(this, "SavePaper"), 160],
            ["Back", ObjBindMethod(this, "BackToHelp", "scratchpad"), 100]], 435)
        this.ShowPage(key, 800, 485, 760, 460)
    }

    NumberField(window, name, minimum, maximum) {
        text := Trim(window[name].Value)
        if !IsInteger(text) || Integer(text) < minimum || Integer(text) > maximum
            throw ValueError(name " must be an integer from " minimum " to " maximum ".")
        return Integer(text)
    }

    SavePaper(*) {
        global scratchpad
        key := "settings:scratchpad"
        window := this.windows[key]
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        try {
            folder := Trim(window["folder"].Value)
            editor := Trim(window["editor"].Value)
            if !RegExMatch(folder, "i)^(?:[a-z]:\\|\\\\)") || RegExMatch(folder, "[\r\n]")
                throw ValueError("Use an absolute Windows path for the notes folder.")
            if editor != "" && (!RegExMatch(editor, "i)^(?:[a-z]:\\|\\\\)") || !FileExist(editor))
                throw ValueError("Select an existing Notepad3 executable, or leave the field blank.")
            changes := Map("Paths", Map("ScratchDirectory", folder, "Notepad3Executable", editor),
                "Window", Map("Monitor", this.padMonitors[window["display"].Value],
                    "WidthPercent", this.NumberField(window, "width", 30, 100),
                    "HeightPercent", this.NumberField(window, "height", 20, 100),
                    "AnimationDurationMs", this.NumberField(window, "animation", 0, 1000)),
                "Saving", Map("AutosaveIntervalMs", this.NumberField(window, "autosave", 500, 60000)))
            pathsChanged := folder != IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad")
                || editor != IniRead(path, "Paths", "Notepad3Executable", "")
            if pathsChanged && this.app.scratchpadStarted && IsSet(scratchpad) {
                if MsgBox("Save and close the owned Notepad3 window before changing these paths?"
                    . "`nExisting notes remain where they are; no files will be moved or deleted.",
                    "Paper Pad", "YesNo Default2 Icon?") != "Yes"
                    return
                scratchpad.PrepareSuiteExit("Exit")
            }
            this.app.Settings.WritePreferences("scratchpad", changes)
            this.CloseWindow(key)
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Paper Pad / settings")
    }

    OpenNotesFolder(*) {
        path := this.app.Settings.directory "\scratchpad\settings.ini"
        folder := IniRead(path, "Paths", "ScratchDirectory", EnvGet("USERPROFILE") "\Scratchpad")
        if DirExist(folder)
            Run('explorer.exe "' folder '"')
        else
            MsgBox("The notes folder does not exist yet: " folder, "Paper Pad", "Iconi")
    }

    OpenPad(*) {
        global scratchpad
        if this.app.dryRun || !this.app.scratchpadStarted || !IsSet(scratchpad) {
            MsgBox("Enable Paper Pad and use a normal launch to open the editor.", SuiteApplication.Name, "Iconi")
            return
        }
        this.CloseWindow("help:scratchpad")
        scratchpad.QueueCommand("show")
    }

    ; =========================================================================
    ; Wonder Windows: explicit external compatibility actions, never startup writes
    ; =========================================================================

    ShowWonderSettings(*) {
        key := "settings:win-key-overhaul"
        if this.Existing(key)
            return
        window := this.NewWindow(key, "Wonder Windows - Settings", true)
        snap := WW_GetNativeWindowsSnapState()
        window.AddText("x20 y20 w760",
            "Use one drag-snapping tool at a time. ScreenGrid is optional; FancyZones remains supported.")
        this.WonderStatus(window, "Windows Snap", snap < 0 ? "unknown" : snap ? "on" : "off",
            80, "snapStatus")
        this.WonderStatus(window, "ScreenGrid", WW_IsScreenGridRunning() ? "running" : "not running",
            105, "screenGridStatus")
        this.WonderStatus(window, "FancyZones", WW_IsFancyZonesRunning() ? "running" : "not running",
            130, "fancyZonesStatus")
        window.AddText("x20 y180 w760", "Windows and PowerToys preferences are not changed at startup."
            . "`nThe actions below either open settings or ask for confirmation before applying changes."
            . "`nFancyZones owns its zone-window switching hotkeys; they are not registered twice here.")
        this.Footer(window, [["Windows Snap...", ObjBindMethod(this, "WonderAction", "snap"), 145],
            ["Disable Snap...", ObjBindMethod(this, "WonderAction", "disable"), 140],
            ["ScreenGrid...", ObjBindMethod(this, "WonderAction", "screengrid"), 125],
            ["FancyZones...", ObjBindMethod(this, "WonderAction", "fancyzones"), 135],
            ["Back", ObjBindMethod(this, "BackToHelp", "win-key-overhaul"), 90]], 290)
        this.ShowPage(key, 800, 340, 740, 320)
    }

    WonderStatusColor(value) {
        switch value {
            case "on", "running": return "008000"
            case "off", "not running": return "B02020"
            default: return "505050"
        }
    }

    WonderStatus(window, label, value, y, controlName) {
        window.AddText("x20 y" y " w150 h23", label ":")
        window.SetFont("s10 c" this.WonderStatusColor(value), "Cascadia Mono")
        window.AddText("x175 y" y " w220 h23 v" controlName, value)
        window.SetFont("s10 cDefault", "Cascadia Mono")
    }

    WonderAction(action, *) {
        if this.app.dryRun {
            MsgBox("Compatibility actions are inactive in the dry run.", SuiteApplication.Name, "Iconi")
            return
        }
        try {
            switch action {
                case "snap": WW_OpenWindowsSnapSettings()
                case "disable": WW_PromptToDisableNativeWindowsSnap()
                case "screengrid": WW_OpenScreenGridReleases()
                case "fancyzones": WW_CheckFancyZonesIntegration()
            }
        }
        catch Error as failure
            this.Report(failure, "Wonder Windows / compatibility")
    }

    ; =========================================================================
    ; Global logging and application preferences
    ; =========================================================================

    OpenLog(*) {
        if this.Existing("log") {
            this.RefreshLog()
            return
        }
        window := this.NewWindow("log", SuiteApplication.Name " - Debug log")
        verbose := window.AddCheckbox("x20 y18 w750 vverbose", "Verbose debugging for the whole application")
        verbose.Value := SuiteState.Log.verbose
        verbose.OnEvent("Click", ObjBindMethod(this, "SetVerbose"))
        window.AddText("x20 y50 w760", "Errors are always logged. Verbose diagnostics may include window titles and paths, not note or clipboard contents.")
        window.AddEdit("x20 y85 w760 h335 ReadOnly +VScroll vlog", SuiteState.Log.Read())
        footer := this.Footer(window, [["Copy", ObjBindMethod(this, "CopyLog"), 100],
            ["Clear...", ObjBindMethod(this, "ClearLog"), 100],
            ["Open file", ObjBindMethod(this, "OpenLogFile"), 115],
            ["Close", ObjBindMethod(this, "CloseWindow", "log"), 100]], 455)
        footer.divider.Visible := false
        this.ShowPage("log", 800, 505, 560, 430)
    }

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
        if this.windows.Has("log")
            this.windows["log"]["verbose"].Value := enabled
        this.UpdateVerboseTray()
        this.RefreshLog()
    }

    ToggleVerboseTray(*) {
        try this.ApplyVerbose(!SuiteState.Log.verbose)
        catch Error as failure
            this.Report(failure, "Core / logging preference")
    }

    SetVerbose(control, *) {
        try this.ApplyVerbose(control.Value != 0)
        catch Error as failure {
            control.Value := SuiteState.Log.verbose
            this.Report(failure, "Core / logging preference")
        }
    }

    ColorLog(hdc, controlHwnd, *) {
        if !this.windows.Has("log") || controlHwnd != this.windows["log"]["log"].Hwnd
            return
        DllCall("SetBkColor", "ptr", hdc, "uint", 0xFFFFFF)
        return DllCall("GetStockObject", "int", 0, "ptr") ; WHITE_BRUSH
    }

    RefreshLog(*) {
        if this.windows.Has("log")
            this.windows["log"]["log"].Value := SuiteState.Log.Read()
    }

    CopyLog(*) {
        try A_Clipboard := SuiteState.Log.Read()
        catch Error as failure
            this.Report(failure, "Core / copy log")
    }

    ClearLog(*) {
        if MsgBox("Clear the current log? Its previous contents will be retained in debug.log.old.",
            SuiteApplication.Name, "YesNo Default2 Icon?") = "Yes" {
            SuiteState.Log.Clear()
            this.RefreshLog()
        }
    }

    OpenLogFile(*) {
        if !FileExist(SuiteState.Log.path)
            SuiteState.Log.Write("Core", "log opened")
        Run('notepad.exe "' SuiteState.Log.path '"')
    }

    OpenSettingsFolder(*) {
        Run('explorer.exe "' this.app.Settings.directory '"')
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
            backup := app.Settings.Backup([app.Settings.path, app.manager.path,
                root "\window-cascade\settings.ini", root "\scratchpad\settings.ini"])
            app.manager.Apply(app.manager._DefaultConfiguration())
            choices := Map()
            for id in SuiteSettings.ModuleOrder
                choices[id] := true
            app.Settings.Save(choices, Map("caps", true, "pause", true), false, "Shift")
            app.Settings.ResetModulePreferences()
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
