; =============================================================================
; One flat tray. Module entries open their guides; module settings, the log,
; module selection and the language are pages built with the shared helpers
; below. Help and pages open at most 80 % of the working display and scroll
; their content under a fixed footer.
; =============================================================================
class SuiteInterface {
    __New(app) {
        this.app := app
        this.windows := Map()
        this.moduleControls := Map()
        this.helpLayouts := Map()
        this.helpWindowIds := Map()
        this.pageLayouts := Map()
        this.scrollPages := Map()  ; window handle -> {help: id} or {page: key}
        this.scrollHandlers := [[0x0115, ObjBindMethod(this, "ScrollBarMessage")], ; WM_VSCROLL
            [0x020A, ObjBindMethod(this, "WheelMessage")], [0x0100, ObjBindMethod(this, "KeyMessage")]]
        this.scrollInstalled := false
        this.pageFooters := Map()
        this.startupPath := A_Startup "\Super Hotkey.lnk"
        this.trayStatus := Map()
    }

    ; A module's line in the tray icon's tooltip, or "" to remove it.
    SetTrayStatus(id, text) {
        if text != ""
            this.trayStatus[id] := text
        else if this.trayStatus.Has(id)
            this.trayStatus.Delete(id)
        this.UpdateTrayTip()
    }

    UpdateTrayTip() {
        tip := SuiteApplication.Name " v" SuiteApplication.Version (this.app.dryRun ? " - dry run" : "")
        for id, text in this.trayStatus
            tip .= "`n" text
        A_IconTip := tip
    }

    BuildTray() {
        this.UpdateTrayTip()
        try TraySetIcon(SuiteIcons.path, , true)
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Modules...", ObjBindMethod(this, "ShowModules"))
        A_TrayMenu.Add("Keybindings...", ObjBindMethod(this.app, "ShowKeybindings"))
        A_TrayMenu.Add(T("Language..."), ObjBindMethod(this, "ShowLanguage"))
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

    ToggleSuspension(*) => this.app.SetSuspended(!this.app.suspended)

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

    ; Buttons along the bottom on an opaque band the page's content scrolls
    ; under, each [label, callback]. y is where the buttons start. Each button
    ; fits its text.
    Footer(window, buttons, y, width := 800) {
        band := window.AddText("x0 y" (y + 49 - SuiteInterface.FooterBand) " w" width
            " h" SuiteInterface.FooterBand " Background" window.BackColor)
        divider := window.AddText("x20 y" (y - 15) " w" (width - 40) " h2 +0x10", "")
        controls := []
        total := 0
        for item in buttons {
            control := window.AddButton("x0 y" y " w" SuiteInterface.ButtonMinWidth " h30", item[1])
            control.OnEvent("Click", SuiteClickAction(item[2]))
            buttonWidth := SuiteInterface.ButtonWidth(control)
            controls.Push({button: control, width: buttonWidth})
            total += buttonWidth + 10
        }
        x := width - 10 - total
        for item in controls {
            item.button.Move(x, y, item.width)
            x += item.width + 10
        }
        ; The page's own scrollbar, beside the content and above the band, so
        ; the size grip keeps its corner.
        bar := window.Add("Custom", "ClassScrollBar x0 y0 w17 h100 Hidden -Tabstop +0x1") ; SBS_VERT
        footer := {band: band, divider: divider, buttons: controls, total: total, bar: bar}
        this.pageFooters[window.Hwnd] := footer
        return footer
    }

    ; Footer buttons fit their text with room on both sides, and are never
    ; narrower than ButtonMinWidth, so most share one width and none clips.
    static ButtonMinWidth := 120

    static ButtonWidth(button) {
        size := Buffer(8, 0)
        SendMessage(0x1601, 0, size.Ptr, button) ; BCM_GETIDEALSIZE: the text and 8 pixels
        return Max(SuiteInterface.ButtonMinWidth, Round(NumGet(size, 0, "int") * 96 / A_ScreenDPI) + 24)
    }

    ; New text for a footer button: it resizes to fit, the buttons to its left
    ; make room, and Help never gets narrower than its footer.
    SetFooterText(button, text) {
        button.Text := text
        window := button.Gui
        if !this.pageFooters.Has(window.Hwnd)
            return
        footer := this.pageFooters[window.Hwnd]
        footer.total := 0
        for item in footer.buttons {
            if item.button = button
                item.width := SuiteInterface.ButtonWidth(button)
            footer.total += item.width + 10
        }
        footer.buttons[-1].button.GetPos(&lastX, &y, &lastWidth)
        x := lastX + lastWidth + 10 - footer.total
        for item in footer.buttons {
            item.button.Move(x, y, item.width)
            x += item.width + 10
        }
        for id, layout in this.helpLayouts
            if layout.footer = footer {
                layout.minWidth := Max(560, footer.total + 20)
                window.Opt("+MinSize" layout.minWidth "x300")
            }
    }

    ; =========================================================================
    ; Scrolling: Help and Settings open at their full size, up to OpenShare of
    ; the working display like a cascade window, and content that does not fit
    ; above the footer band scrolls under it: by the scrollbar, the wheel,
    ; PgUp, PgDn, Home and End while a button has focus, arrows too in Help,
    ; and by tabbing to a field out of view.
    ; =========================================================================
    static OpenShare := 0.8
    static FooterBand := 72  ; from the band's top to the window's bottom
    static WheelStep := 60

    ; Every control clips the siblings above it, and the footer sits above
    ; the content, so content scrolls under the band and never over a button.
    LayerFooter(window, footer) {
        for control in window
            control.Opt("+0x04000000") ; WS_CLIPSIBLINGS
        layers := [footer.bar, footer.band, footer.divider]
        for item in footer.buttons
            layers.Push(item.button)
        if SuiteSizeGrip.grips.Has(window.Hwnd)
            for dot in SuiteSizeGrip.grips[window.Hwnd]
                layers.Push(dot)
        for control in layers ; each to the top, so the last ends uppermost
            DllCall("SetWindowPos", "ptr", control.Hwnd, "ptr", 0, "int", 0, "int", 0,
                "int", 0, "int", 0, "uint", 0x13) ; HWND_TOP; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    }

    WatchScrolling(window, page) {
        this.scrollPages[window.Hwnd] := page
        if this.scrollInstalled
            return
        for handler in this.scrollHandlers
            OnMessage(handler[1], handler[2])
        this.scrollInstalled := true
    }

    ; Shows the scrollbar while the content, measured by contentAt at a width,
    ; is taller than the space above the band, and keeps the offset in range.
    ; Decided at the full width, so showing the bar never undoes itself.
    ; Returns the width left to the content beside the bar, and adds the
    ; bar's place, from the top down to the band, to positions.
    FitScroll(window, layout, contentAt, width, height, positions) {
        view := height - SuiteInterface.FooterBand
        bar := layout.footer.bar
        need := contentAt.Call(width) > view
        barWidth := need ? this.ScrollBarWidth(window) : 0
        content := contentAt.Call(width - barWidth)
        layout.offset := need ? Max(0, Min(layout.offset, content - view)) : 0
        if bar.Visible != need
            bar.Visible := need
        if need
            positions.Push({control: bar, x: width - barWidth, y: 0, w: barWidth, h: view})
        info := Buffer(28, 0) ; SCROLLINFO
        NumPut("uint", 28, "uint", 0x7, "int", 0, "int", Max(0, content - 1), "uint", Max(0, view),
            "int", layout.offset, info) ; SIF_RANGE | SIF_PAGE | SIF_POS
        DllCall("SetScrollInfo", "ptr", bar.Hwnd, "int", 2, "ptr", info, "int", true) ; SB_CTL
        return width - barWidth
    }

    ScrollBarWidth(window) {
        window.GetClientPos(, , &logicalWidth)
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", rect, "int")
        scale := NumGet(rect, 8, "int") / Max(1, logicalWidth)
        return Ceil(DllCall("GetSystemMetrics", "int", 2, "int") / scale) ; SM_CXVSCROLL
    }

    PageLayout(hwnd) {
        page := this.scrollPages[hwnd]
        return page.HasOwnProp("help") ? this.helpLayouts[page.help] : this.pageLayouts[page.page]
    }

    ; Lays the page out again at its current size, scrolled to offset.
    ScrollPage(hwnd, offset) {
        page := this.scrollPages[hwnd]
        layout := this.PageLayout(hwnd)
        offset := Max(0, Round(offset))
        if offset = layout.offset
            return
        layout.offset := offset
        window := GuiFromHwnd(hwnd)
        window.GetClientPos(, , &width, &height)
        layout.renderedWidth := 0
        if page.HasOwnProp("help")
            this.ResizeHelp(page.help, window, 0, width, height)
        else
            this.ResizePage(page.page, window, 0, width, height)
    }

    ScrollView(hwnd) {
        GuiFromHwnd(hwnd).GetClientPos(, , , &height)
        return height - SuiteInterface.FooterBand
    }

    ScrollBarMessage(wParam, lParam, message, hwnd) {
        if !this.scrollPages.Has(hwnd) || lParam != this.PageLayout(hwnd).footer.bar.Hwnd
            return
        offset := this.PageLayout(hwnd).offset
        view := this.ScrollView(hwnd)
        switch wParam & 0xFFFF {
            case 0: offset -= 20                  ; SB_LINEUP
            case 1: offset += 20                  ; SB_LINEDOWN
            case 2: offset -= view - 20           ; SB_PAGEUP
            case 3: offset += view - 20           ; SB_PAGEDOWN
            case 4, 5:                            ; SB_THUMBPOSITION, SB_THUMBTRACK
                info := Buffer(28, 0)
                NumPut("uint", 28, "uint", 0x10, info) ; SIF_TRACKPOS
                DllCall("GetScrollInfo", "ptr", lParam, "int", 2, "ptr", info, "int") ; SB_CTL
                offset := NumGet(info, 24, "int")
            case 6: offset := 0                   ; SB_TOP
            case 7: offset := 0x7FFFFFFF          ; SB_BOTTOM
            default: return 0
        }
        this.ScrollPage(hwnd, offset)
        return 0
    }

    ; The wheel anywhere on a page scrolls it, except over a list that
    ; scrolls itself.
    WheelMessage(wParam, lParam, message, hwnd) {
        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") ; GA_ROOT
        if !this.scrollPages.Has(root) || WinGetClass("ahk_id " hwnd) = "ListBox"
            return
        this.ScrollPage(root, this.PageLayout(root).offset
            - (wParam << 32 >> 48) / 120 * SuiteInterface.WheelStep)
        return 0
    }

    ; Keys scroll a page while a button has focus, where they do nothing else.
    KeyMessage(wParam, lParam, message, hwnd) {
        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
        if !this.scrollPages.Has(root) || WinGetClass("ahk_id " hwnd) != "Button"
            return
        help := this.scrollPages[root].HasOwnProp("help")
        offset := this.PageLayout(root).offset
        view := this.ScrollView(root)
        switch wParam {
            case 0x21: offset -= view - 20        ; PgUp
            case 0x22: offset += view - 20        ; PgDn
            case 0x24: offset := 0                ; Home
            case 0x23: offset := 0x7FFFFFFF       ; End
            case 0x26:                            ; Up
                if !help
                    return
                offset -= 20
            case 0x28:                            ; Down
                if !help
                    return
                offset += 20
            default: return
        }
        this.ScrollPage(root, offset)
        return 0
    }

    ; A field reached by Tab scrolls into view.
    RevealControl(key, control, *) {
        if !this.pageLayouts.Has(key)
            return
        layout := this.pageLayouts[key]
        hwnd := this.windows[key].Hwnd
        view := this.ScrollView(hwnd)
        for item in layout.controls
            if item.control = control {
                if item.y - 10 < layout.offset
                    this.ScrollPage(hwnd, item.y - 10)
                else if item.y + item.h + 10 > layout.offset + view
                    this.ScrollPage(hwnd, item.y + item.h + 10 - view)
                return
            }
    }

    ; Opens a page at its full size, up to OpenShare of the working display;
    ; it can shrink to minHeight, and scrolls when shorter than its content.
    ShowPage(key, width, height, minWidth := 0, minHeight := 0) {
        window := this.windows[key]
        footer := this.pageFooters[window.Hwnd]
        if !minWidth
            minWidth := width
        if !minHeight
            minHeight := height
        minHeight := Min(minHeight, SuiteInterface.FooterBand + 160)
        window.Opt("+Resize +MinSize" minWidth "x" minHeight " +0x02000000")
        controls := []
        footerHandles := Map(footer.band.Hwnd, true, footer.divider.Hwnd, true, footer.bar.Hwnd, true)
        for item in footer.buttons
            footerHandles[item.button.Hwnd] := true
        for control in window {
            if footerHandles.Has(control.Hwnd) || SuiteSizeGrip.Owns(window, control)
                continue
            control.GetPos(&x, &y, &w, &h)
            controls.Push({control: control, x: x, y: y, w: w, h: h,
                stretchWidth: x + w >= width - 50 && w >= 300})
            try control.OnEvent("Focus", ObjBindMethod(this, "RevealControl", key))
        }
        this.LayerFooter(window, footer)
        ; A footer button named Apply saves without closing, like
        ; Keybindings': lit only while the page differs from what it showed
        ; when it opened or was last applied.
        apply := 0
        for item in footer.buttons
            if item.button.Text = "Apply"
                apply := item.button
        if apply {
            apply.Enabled := false
            changed := ObjBindMethod(this, "PageChanged", key)
            for item in controls
                if item.control.Type != "Text" && item.control.Type != "Button" {
                    try item.control.OnEvent("Change", changed)
                    try item.control.OnEvent("Click", changed)
                }
        }
        this.pageLayouts[key] := {footer: footer, controls: controls, apply: apply,
            saved: SuiteInterface.PageValues(window),
            width: width, height: height, minWidth: minWidth, minHeight: minHeight,
            content: height - SuiteInterface.FooterBand, offset: 0,
            renderedWidth: 0, renderedHeight: 0}
        this.WatchScrolling(window, {page: key})
        window.OnEvent("Size", ObjBindMethod(this, "ResizePage", key))
        SuiteShowCentered(window, width, height, ObjBindMethod(this, "ResizePage", key),
            SuiteInterface.OpenShare)
    }

    ; Restore defaults on a module's Settings page asks first, like
    ; Keybindings', then fills the page with the module's defaults; nothing
    ; is saved until Apply.
    RestoreDefaults(id, *) {
        if MsgBox(T("Restore the default settings for {1}?", this.app.modules[id].Name)
            . "`n`n" T("Changes stay pending until Apply. Hotkeys, notes and their folder are untouched."),
            SuiteApplication.Name, "YesNo Default2 Icon?") = "Yes"
            this.FillDefaults(id)
    }

    FillDefaults(id) {
        key := "settings:" id
        if !this.windows.Has(key)
            return
        try this.app.modules[id].RestoreSettings(this.windows[key])
        catch Error as failure {
            this.Report(failure, SuiteSettings.ModuleNames[id] " / restore defaults")
            return
        }
        this.PageChanged(key)
    }

    ; Every value a page's fields hold, in one string to compare.
    static PageValues(window) {
        values := ""
        for hwnd, control in window
            if control.Type != "Text" && control.Type != "Button" && control.Type != "Custom"
                try values .= hwnd "=" control.Value "`n"
        return values
    }

    PageChanged(key, *) {
        if this.pageLayouts.Has(key) && (layout := this.pageLayouts[key]).apply && this.windows.Has(key)
            layout.apply.Enabled := SuiteInterface.PageValues(this.windows[key]) != layout.saved
    }

    ; The index of a display among DisplayChoices' values, Primary meaning
    ; the primary display; the first when it is not there.
    static DisplayIndex(values, value) {
        if value = "Primary"
            value := MonitorGetName(MonitorGetPrimary())
        for index, name in values
            if name = value
                return index
        return 1
    }

    ; The page saved: it stays open with Apply grey until the next change,
    ; handing focus to the last footer button if Apply had it.
    Applied(key) {
        if !this.pageLayouts.Has(key) || !this.pageLayouts[key].apply
            return
        apply := this.pageLayouts[key].apply
        if DllCall("GetFocus", "ptr") = apply.Hwnd
            this.pageLayouts[key].footer.buttons[-1].button.Focus()
        apply.Enabled := false
        if this.windows.Has(key)
            this.pageLayouts[key].saved := SuiteInterface.PageValues(this.windows[key])
    }

    ResizePage(key, window, minMax, width, height) {
        if minMax = -1 || !this.pageLayouts.Has(key)
            return
        layout := this.pageLayouts[key]
        width := Max(layout.minWidth, width)
        height := Max(layout.minHeight, height)
        if width = layout.renderedWidth && height = layout.renderedHeight
            return
        positions := []
        contentWidth := this.FitScroll(window, layout, (*) => layout.content, width, height, positions)
        dx := contentWidth - layout.width
        for item in layout.controls {
            positions.Push({control: item.control, x: item.x, y: item.y - layout.offset,
                w: item.stretchWidth ? Max(45, item.w + dx) : item.w, h: item.h})
        }
        positions.Push({control: layout.footer.band, x: 0, y: height - SuiteInterface.FooterBand,
            w: width, h: SuiteInterface.FooterBand})
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
            if this.scrollPages.Has(this.windows[key].Hwnd)
                this.scrollPages.Delete(this.windows[key].Hwnd)
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
        if this.scrollInstalled {
            for handler in this.scrollHandlers
                OnMessage(handler[1], handler[2], 0)
            this.scrollInstalled := false
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
            "+Resize +MinSize560x300 +0x02000000")
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
        guide := []
        for part in SuiteInterface.HelpParts(module.HelpText()) {
            if part.heading
                window.SetFont("bold")
            control := window.AddText("x20 y55 w860", part.text)
            window.SetFont("norm")
            SuiteBufferedPaint.Attach(control)
            guide.Push({control: control, heading: part.heading})
        }
        buttons := module.HelpButtons()
        if module.hasSettings
            buttons.Push(["Settings...", ObjBindMethod(this, "OpenSettingsFromHelp", id)])
        buttons.Push(["Keybindings...", ObjBindMethod(this, "OpenKeybindingsFromHelp", id)])
        buttons.Push(["Close", ObjBindMethod(this, "CloseWindow", key)])
        footer := this.Footer(window, buttons, 455, 900)
        this.LayerFooter(window, footer)
        width := 820
        height := 480
        ; Narrow enough to sit beside other windows, but never hiding a button.
        minWidth := Max(560, footer.total + 20)
        window.Opt("+MinSize" minWidth "x300")
        this.helpLayouts[id] := {header: header, status: status, statusColor: statusColor,
            guide: guide, footer: footer, width: width, height: height, minWidth: minWidth, offset: 0,
            renderedWidth: 0, renderedHeight: 0}
        this.helpWindowIds[window.Hwnd] := id
        this.WatchScrolling(window, {help: id})
        window.OnEvent("Size", ObjBindMethod(this, "ResizeHelp", id))
        ; Measure after giving the hidden GUI its opening width: the whole
        ; guide when it fits, never shorter than the compact default.
        window.Show("Hide w" width " h" height)
        height := Max(height, this.HelpContentHeight(id, width) + SuiteInterface.FooterBand)
        SuiteShowCentered(window, width, height, ObjBindMethod(this, "ResizeHelp", id),
            SuiteInterface.OpenShare)
    }

    ; The header and the guide above the footer band, at a client width.
    HelpContentHeight(id, clientWidth) => 73 + this.HelpTextHeight(id, clientWidth)

    ResizeHelp(id, window, minMax, width, height) {
        if minMax = -1 || !this.helpLayouts.Has(id)
            return
        layout := this.helpLayouts[id]
        width := Max(layout.minWidth, width)
        height := Max(300, height)
        if width = layout.renderedWidth && height = layout.renderedHeight
            return
        if minMax = 0 {
            layout.width := width
            layout.height := height
        }
        positions := []
        contentWidth := this.FitScroll(window, layout,
            (clientWidth) => this.HelpContentHeight(id, clientWidth), width, height, positions)
        headerWidth := this.HelpHeadingWidth(window, layout.header)
        statusWidth := this.HelpHeadingWidth(window, layout.status)
        headerX := Floor((contentWidth - headerWidth - statusWidth) / 2)
        top := -layout.offset
        positions.Push(
            {control: layout.header, x: headerX, y: top + 18, w: headerWidth, h: 25},
            {control: layout.status, x: headerX + headerWidth, y: top + 18,
                w: statusWidth, h: 25},
            {control: layout.footer.band, x: 0, y: height - SuiteInterface.FooterBand,
                w: width, h: SuiteInterface.FooterBand},
            {control: layout.footer.divider, x: 20, y: height - 64, w: width - 40, h: 2})
        for row in this.HelpGuideRows(id, contentWidth)
            positions.Push({control: row.control, x: 20, y: top + 55 + row.y, w: contentWidth - 40, h: row.h})
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

    ; A guide as modules write it: sections apart by blank lines, one sentence
    ; per line, each section under an optional heading line in capitals.
    ; Returns its parts in order: {text, heading}, a paragraph's sentences
    ; joined into one line for the page to wrap. Each line is shown in the
    ; suite's language; headings are found in the English.
    static HelpParts(text) {
        parts := []
        paragraph := ""
        for line in StrSplit(StrReplace(text, "`r"), "`n") {
            line := Trim(line)
            if line = "" {
                if paragraph != ""
                    parts.Push({text: paragraph, heading: false})
                paragraph := ""
            }
            else if paragraph = "" && line == StrUpper(line) && RegExMatch(line, "[A-Z]")
                parts.Push({text: SuiteLanguage.Text(line), heading: true})
            else
                paragraph .= (paragraph = "" ? "" : " ") SuiteLanguage.Text(line)
        }
        if paragraph != ""
            parts.Push({text: paragraph, heading: false})
        return parts
    }

    HelpTextHeight(id, clientWidth) {
        rows := this.HelpGuideRows(id, clientWidth)
        return rows.Length ? rows[-1].y + rows[-1].h : 0
    }

    ; The guide's parts wrapped at clientWidth, stacked from 0: {control, y, h}.
    ; A blank line ends a paragraph; a heading sits just above its paragraph.
    HelpGuideRows(id, clientWidth) {
        window := this.windows["help:" id]
        window.GetClientPos(, , &logicalWidth)
        rect := Buffer(16, 0)
        if !logicalWidth || !DllCall("GetClientRect", "ptr", window.Hwnd,
            "ptr", rect, "int")
            throw OSError(A_LastError, "Measure Help text")
        scale := NumGet(rect, 8, "int") / logicalWidth
        hdc := DllCall("GetDC", "ptr", window.Hwnd, "ptr")
        if !hdc
            throw OSError(A_LastError, "Get Help text drawing context")
        rows := []
        y := 0
        try {
            for part in this.helpLayouts[id].guide {
                if A_Index > 1
                    y += this.helpLayouts[id].guide[A_Index - 1].heading ? 3 : 17 ; one blank line
                font := SendMessage(0x0031, 0, 0, , part.control.Hwnd)
                previous := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
                bounds := Buffer(16, 0)
                NumPut("int", Max(1, Round((clientWidth - 40) * scale)), bounds, 8)
                DllCall("DrawTextW", "ptr", hdc, "str", part.control.Text, "int", -1,
                    "ptr", bounds, "uint", 0xC10, "int") ; word wrap, measure, no prefix
                if previous
                    DllCall("SelectObject", "ptr", hdc, "ptr", previous)
                rows.Push({control: part.control, y: y, h: Ceil(NumGet(bounds, 12, "int") / scale)})
                y += rows[-1].h
            }
        }
        finally DllCall("ReleaseDC", "ptr", window.Hwnd, "ptr", hdc)
        return rows
    }

    ; Each step opens the next page before closing the one it leaves, so the
    ; next page centers on that page's display. Closed first, focus would
    ; fall back to an app window, perhaps on another display, that decides.
    OpenSettingsFromHelp(id, *) {
        this.ShowModuleSettings(id)
        this.CloseWindow("help:" id)
    }

    BackToHelp(id, *) {
        this.ShowHelp(id)
        this.CloseWindow("settings:" id)
    }

    OpenKeybindingsFromHelp(id, *) {
        this.app.CancelInputs()
        this.app.manager.ShowSettings(id)
        this.CloseWindow("help:" id)
    }

    ShowModules(*) {
        if this.Existing("modules")
            return
        rows := SuitePageRows(this.NewWindow("modules", SuiteApplication.Name " - Modules", true), 600)
        rows.Text("Module changes take effect after restarting.")
        this.moduleControls := Map()
        for id in SuiteSettings.ModuleOrder {
            control := rows.Checkbox(SuiteSettings.ModuleNames[id])
            control.Value := this.app.Settings.modules[id]
            this.moduleControls[id] := control
            rows.Caption(SuiteSettings.ModuleDescriptions[id], true)
        }
        rows.Show(this, "modules", [["Apply and restart", ObjBindMethod(this, "SaveModules")],
            ["Cancel", ObjBindMethod(this, "CloseModules")]])
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

    ; Each language is listed in its own name, English included, in a list that
    ; scrolls past 10 rows. The language loads at startup, so applying a
    ; choice restarts the suite.
    ShowLanguage(*) {
        if this.Existing("language")
            return
        rows := SuitePageRows(this.NewWindow("language", T("{1} - Language", SuiteApplication.Name), true), 440)
        rows.Text(T("Automatic follows the Windows display language."))
        this.languageCodes := ["", "en"]
        names := [T("Automatic"), SuiteLanguage.English]
        for language in SuiteLanguage.Available() {
            this.languageCodes.Push(language.code)
            names.Push(language.name)
        }
        this.languageList := rows.List(names, Min(names.Length, 10))
        for code in this.languageCodes
            if code = this.app.Settings.language
                this.languageList.Choose(A_Index)
        rows.Show(this, "language", [[T("Apply and restart"), ObjBindMethod(this, "SaveLanguage")],
            [T("Cancel"), ObjBindMethod(this, "CloseWindow", "language")]])
    }

    SaveLanguage(*) {
        index := this.languageList.Value
        code := index ? this.languageCodes[index] : this.app.Settings.language
        try {
            this.app.Settings.Save(this.app.Settings.modules, , code)
            this.CloseWindow("language")
            Reload()
        }
        catch Error as failure
            this.Report(failure, "Core / language")
    }

    ShowModuleSettings(id, *) => this.app.modules[id].ShowSettings(this)

    ; =========================================================================
    ; shared helpers for module settings pages
    ; =========================================================================

    ; Display dropdown entries; the stored value is the Windows device name.
    ; Each display is numbered and listed as Windows' Identify numbers it.
    DisplayChoices(selected, includeAll := false) {
        values := includeAll ? ["All"] : []
        names := includeAll ? ["All displays"] : []
        models := this.GetDisplayModels()
        primary := MonitorGetPrimary()
        if selected = "Primary"
            selected := MonitorGetName(primary)
        displays := []
        loop MonitorGetCount() {
            try {
                name := MonitorGetName(A_Index)
                MonitorGetWorkArea(A_Index)
                displays.Push({name: name, number: SuiteInterface.DisplayNumber(name, A_Index),
                    primary: A_Index = primary})
            }
        }
        ; Few displays, so a simple insertion sort by number.
        loop displays.Length - 1 {
            index := A_Index + 1
            while index > 1 && displays[index - 1].number > displays[index].number {
                swapped := displays[index - 1]
                displays[index - 1] := displays[index]
                displays[index] := swapped
                index -= 1
            }
        }
        for display in displays {
            values.Push(display.name)
            names.Push("Display " display.number " - " models.Get(display.name, display.name)
                . (display.primary ? " (primary)" : ""))
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

    ; Windows' own display number, from a device name such as \\.\DISPLAY2;
    ; AutoHotkey's order, which always lists the primary first, otherwise.
    static DisplayNumber(name, fallback) => RegExMatch(name, "i)^\\\\\.\\DISPLAY(\d+)$", &match)
        ? Integer(match[1]) : fallback

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

    ; Verbose logging records window titles, so it lasts only until the
    ; suite exits: forgotten, it never outlives the run it was meant for.
    ApplyVerbose(enabled) {
        SuiteState.Log.verbose := enabled
        SuiteState.Log.Write("Core", "verbose debugging " (enabled ? "enabled" : "disabled"))
        this.UpdateVerboseTray()
    }

    ToggleVerboseTray(*) => this.ApplyVerbose(!SuiteState.Log.verbose)

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
        if MsgBox("Restore the default modules, both layers, hotkeys and preferences?"
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
                choices[id] := SuiteSettings.ModuleDefault(id)
            app.Settings.Save(choices, Map("caps", true, "pause", true), "")
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

; Stacks a page's rows from the top, so a page lists rows, never positions:
; each row starts one gap below the previous one, fields line up in one
; column, and Show places the footer below the last row and sizes the page.
class SuitePageRows {
    static Top := 18
    static Gap := 20
    static CaptionGap := 6
    static FieldX := 240
    static CheckboxTextX := 38 ; where a checkbox's label starts

    __New(window, width) {
        this.window := window
        this.width := width
        this.y := SuitePageRows.Top
    }

    ; A paragraph across the page.
    Text(text, options := "") => this.Advance(
        this.window.AddText("x20 y" this.y " w" (this.width - 40) " " options, text))

    ; A bold section title, set apart from the section above it and close to
    ; the rows below, for pages with more than one section.
    Heading(text) {
        if this.y > SuitePageRows.Top
            this.y += SuitePageRows.Gap
        this.window.SetFont("bold")
        control := this.window.AddText("x20 y" this.y " w" (this.width - 40), text)
        this.window.SetFont("norm")
        control.GetPos(, , , &height)
        this.y += height + SuitePageRows.CaptionGap
        return control
    }

    Checkbox(label, options := "") => this.Advance(
        this.window.AddCheckbox("x20 y" this.y " w" (this.width - 40) " " options, label))

    ; A list of items, rows tall, that scrolls when it holds more.
    List(items, rows) => this.Advance(
        this.window.AddListBox("x20 y" this.y " w" (this.width - 40) " r" rows, items))

    ; A label with a field of type beside it, in the page's field column.
    Field(label, type, options, value?) {
        x := SuitePageRows.FieldX
        labelControl := this.window.AddText("x20 y" (this.y + (type = "Text" ? 0 : 4))
            " w" (x - 30), label)
        options := "x" x " y" this.y " " options
        control := IsSet(value) ? this.window.Add(type, options, value) : this.window.Add(type, options)
        labelControl.GetPos(, , , &labelHeight)
        return this.Advance(control, labelHeight + (type = "Text" ? 0 : 4))
    }

    ; A short note just below the row above it: under a field's column, or
    ; with checkbox true under a checkbox's label.
    Caption(text, checkbox := false) {
        x := checkbox ? SuitePageRows.CheckboxTextX : SuitePageRows.FieldX
        this.y -= SuitePageRows.Gap - SuitePageRows.CaptionGap
        return this.Advance(this.window.AddText("x" x " y" this.y " w" (this.width - 20 - x), text))
    }

    Advance(control, minimumHeight := 0) {
        control.GetPos(, , , &height)
        this.y += Max(height, minimumHeight) + SuitePageRows.Gap
        return control
    }

    ; Adds the footer below the last row and shows the page, which may shrink
    ; a little below its opening size. A module's Settings page leads its
    ; footer with Restore defaults.
    Show(ui, key, buttons) {
        if InStr(key, "settings:") = 1
            buttons.InsertAt(1, [T("Restore defaults"), ObjBindMethod(ui, "RestoreDefaults", SubStr(key, 10))])
        y := this.y + 35
        ui.Footer(this.window, buttons, y, this.width)
        ui.ShowPage(key, this.width, y + 50, this.width - 40, y + 25)
    }
}
