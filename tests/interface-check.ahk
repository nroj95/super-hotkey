; Suite windows: settings pages, guides, navigation, sizing and centering.
; Disposable preferences, dry-run inputs and test-owned windows only.
class InterfaceChecks {
    static Run() {
        this.SettingsCheckboxes()
        this.Interfaces()
        this.ClickedNavigation()
        this.WindowSizingAndCloaking()
    }

    static Assert(condition, label) => SuiteChecks.Assert(condition, label)

    ; Six dots in the lower-right corner, disabled so the mouse reaches the
    ; window, which answers the corner as its bottom-right sizing border.
    static AssertSizeGrip(window, label) {
        window.GetClientPos(, , &width, &height)
        placed := SuiteSizeGrip.grips.Has(window.Hwnd) && SuiteSizeGrip.grips[window.Hwnd].Length = 6
        if placed
            for index, dot in SuiteSizeGrip.grips[window.Hwnd] {
                dot.GetPos(&x, &y, &w, &h)
                placed := placed && dot.Visible && !dot.Enabled && w = 2 && h = 2
                    && x = width - 17 + SuiteSizeGrip.Dots[index][1]
                    && y = height - 17 + SuiteSizeGrip.Dots[index][2]
            }
        this.Assert(placed, "a sizing grip's dots sit in the lower-right corner: " label)
        rect := Buffer(16, 0)
        corner := Buffer(8, 0)
        DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", rect, "int")
        NumPut("int", NumGet(rect, 8, "int") - 4, "int", NumGet(rect, 12, "int") - 4, corner)
        DllCall("ClientToScreen", "ptr", window.Hwnd, "ptr", corner, "int")
        point := NumGet(corner, 4, "int") << 16 | NumGet(corner, 0, "int") & 0xFFFF
        this.Assert(SendMessage(0x0084, 0, point, , "ahk_id " window.Hwnd) = 17,
            "the sizing grip's corner resizes the window: " label)
    }

    static AssertCentered(window, label) {
        rect := Buffer(16, 0)
        this.Assert(!!DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int"),
            "window geometry is available: " label)
        MonitorGetWorkArea(SuiteWorkingMonitor.Get(window.Hwnd), &left, &top, &right, &bottom)
        x := NumGet(rect, 0, "int")
        y := NumGet(rect, 4, "int")
        w := NumGet(rect, 8, "int") - x
        h := NumGet(rect, 12, "int") - y
        expectedX := left + Floor((right - left - w) / 2)
        expectedY := top + Floor((bottom - top - h) / 2)
        this.Assert(Abs(x - expectedX) <= 2 && Abs(y - expectedY) <= 2,
            "window opens centered on the working monitor: " label)
    }

    static SettingsCheckboxes() {
        app := SuiteApplication(true, SuiteChecks.directory "\checkbox-settings")
        app.InitializeCatalog()
        app.Settings.Save(app.Settings.modules, Map("caps", true, "pause", false), false)
        manager := app.manager
        try {
            manager.SetPaused(true)
            manager.Start()
            app.ui := SuiteInterface(app)
            app.ui.ShowModuleSettings("secret-layers")
            window := app.ui.windows["settings:secret-layers"]
            this.Assert(window["caps"].Value && !window["pause"].Value,
                "Secret Layers settings show each saved layer choice")
            app.ui.CloseWindow("settings:secret-layers")
            app.ui.ShowModuleSettings("cascade-kingdom")
            window := app.ui.windows["settings:cascade-kingdom"]
            this.Assert(window["tabs"].Enabled && window["inactiveColor"].Enabled,
                "Cascade Kingdom settings offer focus-tab controls")
        }
        finally {
            if IsObject(app.ui)
                app.ui.CloseAll()
            manager.Stop()
        }
    }

    static Interfaces() {
        app := SuiteApplication(true, SuiteChecks.directory "\new-interfaces")
        try {
            app.Start()
            this.Assert(SuiteApplication.Name = "Super Hotkey"
                && SuiteApplication.Version = "1.0.0-beta.2",
                "application identity is Super Hotkey v1.0.0-beta.2")
            this.Assert(A_IconTip = "Super Hotkey v1.0.0-beta.2 - dry run",
                "tray hover text includes its assigned version and dry-run suffix")
            count := DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle, "int")
            this.Assert(count = 19,
                "tray includes application suspension and an explicit app restart")
            loop count
                this.Assert(!DllCall("GetSubMenu", "ptr", A_TrayMenu.Handle, "int", A_Index - 1, "ptr"),
                    "tray entry has no submenu: " A_Index)
            for item in [[10, "Verbose logging"], [11, "Open settings folder"],
                [13, "Run at startup"], [14, "Suspend"],
                [15, "Restart Super Hotkey"], [16, "Reset to defaults..."]] {
                name := Buffer(256, 0)
                DllCall("GetMenuStringW", "ptr", A_TrayMenu.Handle,
                    "uint", item[1], "ptr", name, "int", 128, "uint", 0x400, "int")
                this.Assert(StrGet(name, "UTF-16") = item[2],
                    "tray exposes " item[2] " directly")
            }
            verboseStatus := (*) => DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 10, "uint", 0x400, "uint")
            this.Assert(!(verboseStatus.Call() & 8),
                "verbose logging starts unchecked in the tray")
            startupState := DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 13, "uint", 0x400, "uint")
            this.Assert(startupState & 3,
                "Run at startup is disabled during safe dry-run testing")
            this.Assert(!HasMethod(app.ui, "ShowAppSettings"),
                "the redundant App settings window is removed")
            hotkeyState := (*) => DllCall("GetMenuState", "ptr", A_TrayMenu.Handle,
                "uint", 14, "uint", 0x400, "uint")
            this.Assert(!(hotkeyState.Call() & 8) && !app.suspended,
                "Suspend starts unchecked")
            app.ui.ToggleSuspension()
            this.Assert(app.suspended && app.manager.paused
                && (hotkeyState.Call() & 8),
                "Suspend checks its menu item and gates the keybinding manager")
            app.ui.ToggleSuspension()
            this.Assert(!app.suspended && !(hotkeyState.Call() & 8)
                && app.manager.paused,
                "Resume hotkeys preserves another pause reason, including dry run")
            app.ui.ToggleVerboseTray()
            this.Assert(SuiteState.Log.verbose && app.Settings.verbose
                && (verboseStatus.Call() & 8),
                "tray enables and checks persistent verbose logging")
            app.ui.ToggleVerboseTray()
            this.Assert(!SuiteState.Log.verbose && !app.Settings.verbose
                && !(verboseStatus.Call() & 8),
                "tray disables and unchecks verbose logging")
            firstEditor := app.manager.editor.window.Hwnd
            app.ShowKeybindings()
            this.Assert(app.manager.editor.window.Hwnd = firstEditor, "every Keybindings entry reuses the global editor")
            editor := app.manager.editor.window
            this.Assert(app.manager.editor.resetAllButton.Text = "Restore defaults"
                && app.manager.editor.applyButton.Text = "Apply"
                && !app.manager.editor.doneButton,
                "global Keybindings has Restore defaults and Apply; the title bar closes it")
            editor.GetClientPos(, , &firstWidth, &firstHeight)
            this.AssertCentered(editor, "Keybindings")
            this.AssertSizeGrip(editor, "Keybindings")
            overlay := SuiteGui("-Caption +ToolWindow", "Sizing grip probe")
            try this.Assert(!SuiteSizeGrip.grips.Has(overlay.Hwnd), "windows that cannot resize have no sizing grip")
            finally overlay.Destroy()
            expectedKeybindingsHeight := Min(860, Max(560, A_ScreenHeight - 125))
            monitor := WindowMonitorIndex(editor.Hwnd)
            MonitorGetWorkArea(monitor, &workLeft, &workTop, &workRight, &workBottom)
            expectedSize := SuiteFitClientSize(editor, 1060, expectedKeybindingsHeight,
                workRight - workLeft, workBottom - workTop)
            this.Assert(Abs(firstWidth - expectedSize.width) <= 1
                && Abs(firstHeight - expectedSize.height) <= 1,
                "Keybindings opening size fits the current monitor: " firstWidth "x" firstHeight)
            this.Assert(!HasProp(app.manager, "settingsRefresh"),
                "Keybindings no longer has a Refresh button")
            this.Assert(app.manager.editor.rows[1].label = "Global"
                && app.manager.editor.visibleRows[1].categoryTitle.Text = "★ Global ★",
                "Global heading has decorative stars without changing its category identity")
            editorStyle := WinGetStyle("ahk_id " editor.Hwnd)
            this.Assert(!!(editorStyle & 0x00040000) && !!(editorStyle & 0x00010000),
                "Keybindings supports native edge resizing and maximizing")
            controls := [app.manager.editor.visibleRows[1].title,
                app.manager.editor.visibleRows[1].categoryTitle,
                app.manager.editor.visibleRows[1].primary,
                app.manager.editor.visibleRows[1].secondary,
                app.manager.editor.visibleRows[1].reset,
                app.manager.editor.search,
                app.manager.editor.resetAllButton, app.manager.editor.applyButton]
            weights := []
            sizes := []
            faces := []
            for control in controls {
                fontHandle := SendMessage(0x0031, 0, 0, , control.Hwnd) ; WM_GETFONT
                fontData := Buffer(92, 0) ; LOGFONTW
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size,
                    "Keybindings control exposes its font")
                weights.Push(NumGet(fontData, 16, "int"))
                sizes.Push(NumGet(fontData, 0, "int"))
                faces.Push(StrGet(fontData.Ptr + 28, 32, "UTF-16"))
            }
            sameFont := true
            for index, weight in weights
                if weight != 400 || sizes[index] != sizes[1]
                    sameFont := false
            this.Assert(sameFont,
                "all Keybindings text uses the same regular font weight and size")
            consistentFamily := true
            for fontFace in faces
                if fontFace != "Cascadia Mono" && fontFace != "Consolas"
                    consistentFamily := false
            this.Assert(consistentFamily,
                "Keybindings uses the Help-page font family")
            this.Assert(!!(WinGetExStyle("ahk_id " editor.Hwnd) & 0x02000000),
                "Keybindings composites child-control painting")
            initialRows := app.manager.editor.visibleRows.Length
            editor.Show("w1120 h1100")
            editor.GetClientPos(, , &expandedWidth, &expandedHeight)
            app.manager.editor.Resize(editor, 0, expandedWidth, expandedHeight)
            expandedRows := app.manager.editor.visibleRows.Length
            this.Assert(expandedRows > initialRows,
                "live resizing reveals more rows (old " initialRows
                ", new " expandedRows ", height " expandedHeight
                ", layout " app.manager.editor.renderedHeight ")")
            markerRow := app.manager.editor.visibleRows[1]
            markerRow.title.Text := "layout-only marker"
            editor.Show("w1080 h" expandedHeight)
            editor.GetClientPos(, , &adjustedWidth, &adjustedHeight)
            app.manager.editor.Resize(editor, 0, adjustedWidth, adjustedHeight)
            this.Assert(markerRow.title.Text = "layout-only marker",
                "width-only resize does not re-render shortcut labels")
            expectedWidth := 160 + Floor((adjustedWidth - KeybindingsEditor.MinWidth) * 0.32)
            expectedPrimaryX := adjustedWidth - 142 - 2 * expectedWidth
            markerRow.primary.GetPos(&actualPrimaryX, , &actualPrimaryWidth)
            markerRow.secondary.GetPos(&actualSecondaryX, , &actualSecondaryWidth)
            markerRow.reset.GetPos(&actualResetX)
            this.Assert(Abs(actualPrimaryX - expectedPrimaryX) <= 2
                && Abs(actualPrimaryWidth - expectedWidth) <= 2
                && Abs(actualSecondaryWidth - expectedWidth) <= 2,
                "both binding boxes share one width across resized window widths")
            this.Assert(Abs(actualSecondaryX - (actualPrimaryX + actualPrimaryWidth + 10)) <= 2
                && Abs(actualResetX - (actualSecondaryX + actualSecondaryWidth + 10)) <= 2,
                "binding boxes keep their gaps and the reset button alignment")
            longHotkey := "Caps + Alt + Shift + Win + Enter"
            app.manager.editor._SetBindingText(markerRow.secondary, longHotkey)
            this.Assert(markerRow.secondary.Text = longHotkey
                && app.manager.editor.bindingSizes[markerRow.secondary.Hwnd] < 10,
                "a hotkey too long for its box keeps every key in a smaller font")
            app.manager.editor._SetBindingText(markerRow.secondary, "Win + Enter")
            this.Assert(markerRow.secondary.Text = "Win + Enter"
                && app.manager.editor.bindingSizes[markerRow.secondary.Hwnd] = 10,
                "a hotkey that fits returns to the editor's font")
            app.manager.editor.resetAllButton.GetPos(, &oldFooterY)
            editor.Show("w1080 h700")
            editor.GetClientPos(, , &shorterWidth, &shorterHeight)
            app.manager.editor.Resize(editor, 0, shorterWidth, shorterHeight)
            app.manager.editor.resetAllButton.GetPos(, &newFooterY)
            this.Assert(newFooterY < oldFooterY,
                "live vertical resize moves the footer as one coherent layout")
            editor.Show("w1080 h850")
            editor.GetClientPos(, , &adjustedWidth, &adjustedHeight)
            app.manager.editor.Resize(editor, 0, adjustedWidth, adjustedHeight)
            app.manager.editor.Render()
            this.Assert(expandedRows > initialRows, "resizing taller reveals more shortcut rows")
            app.manager.editor.scroll.GetPos(&scrollX)
            this.Assert(scrollX > 950, "scrollbar stays anchored to the right edge")
            app.manager.editor.applyButton.GetPos(, &doneY)
            editor.GetClientPos(, , , &clientHeight)
            this.Assert(Abs(doneY - (clientHeight - 49)) <= 2,
                "footer buttons stay pinned to the bottom")
            app.manager.editor.resetAllButton.GetPos(&restoreX, , &restoreW)
            app.manager.editor.applyButton.GetPos(&applyX, , &applyW)
            this.Assert(Abs(applyX + applyW - (adjustedWidth - 46)) <= 2
                && Abs(applyX - (restoreX + restoreW + 14)) <= 2,
                "Keybindings footer buttons are right-aligned with consistent gaps")
            editor.Show("w" KeybindingsEditor.MinWidth " h420")
            editor.GetClientPos(, , &compactWidth, &compactHeight)
            app.manager.editor.Resize(editor, 0, compactWidth, compactHeight)
            compactRow := app.manager.editor.visibleRows[1]
            app.manager.editor._SetBindingText(compactRow.secondary, longHotkey "+ Alt + Shift")
            this.Assert(SubStr(compactRow.secondary.Text, -1) = "…"
                && app.manager.editor.bindingSizes[compactRow.secondary.Hwnd]
                    = KeybindingsEditor.BindingFontSizes[-1],
                "a hotkey too long even at the smallest font ends in an ellipsis")
            app.manager.editor.Render()
            this.Assert(app.manager.editor.visibleRows.Length < expandedRows,
                "resizing smaller reduces the visible row count without losing the catalog")
            app.manager.editor.search.Value := "page"
            app.manager.editor.SearchChanged()
            headingRow := app.manager.editor.visibleRows[1]
            this.Assert(headingRow.categoryTitle.Visible
                && headingRow.categoryTitle.Text = "Paper Pad"
                && !headingRow.contextTag.Visible,
                "merged Paper Pad heading has no scope marker")
            paperRow := app.manager.editor.visibleRows[2]
            paperRow.title.GetPos(&descriptionX, &descriptionY, &descriptionWidth, &descriptionHeight)
            paperRow.contextTag.GetPos(&tagX, &tagY, &tagWidth, &tagHeight)
            paperRow.primary.GetPos(&bindingX, &bindingY, , &bindingHeight)
            this.Assert(paperRow.contextTag.Visible && paperRow.contextTag.Text = "editor only"
                && descriptionX + descriptionWidth + 8 <= tagX
                && tagX + tagWidth + 12 = bindingX,
                "Paper Pad context tag sits immediately before the first binding")
            this.Assert(tagWidth <= 80 && tagHeight = 16
                && tagY = bindingY + 6
                && Abs((tagY + tagHeight / 2) - (bindingY + bindingHeight / 2)) <= 1
                && tagHeight < descriptionHeight,
                "context tag is compact and vertically centered with the binding")
            nextPaperRow := app.manager.editor.visibleRows[3]
            nextPaperRow.contextTag.GetPos(&nextTagX, , &nextTagWidth)
            nextPaperRow.primary.GetPos(&nextBindingX)
            this.Assert(nextPaperRow.contextTag.Visible
                && nextTagX = tagX && nextTagWidth = tagWidth
                && nextBindingX = bindingX,
                "Paper Pad context tags align across different description lengths")
            app.manager.editor.search.Value := "power-up-utilities.terminal"
            app.manager.editor.SearchChanged()
            this.Assert(app.manager.editor.visibleRows[1].categoryTitle.Text = "Power-Up Utilities",
                "Terminal actions display under the main heading")
            terminalRow := app.manager.editor.visibleRows[2]
            terminalRow.title.GetPos(&terminalDescriptionX, , &terminalDescriptionWidth)
            terminalRow.contextTag.GetPos(&terminalTagX, , &terminalTagWidth)
            terminalRow.primary.GetPos(&terminalBindingX)
            this.Assert(terminalRow.contextTag.Visible
                && terminalRow.contextTag.Text = "terminal only"
                && terminalTagWidth <= 100
                && terminalDescriptionX + terminalDescriptionWidth + 8 <= terminalTagX
                && terminalTagX + terminalTagWidth + 12 = terminalBindingX,
                "Windows Terminal context tag is aligned before its binding")
            editor.Show("w1080 h420")
            editor.GetClientPos(, , &widerWidth, &widerHeight)
            app.manager.editor.Resize(editor, 0, widerWidth, widerHeight)
            terminalRow.contextTag.GetPos(&wideTagX, , &wideTagWidth)
            terminalRow.primary.GetPos(&wideBindingX)
            this.Assert(wideTagX + wideTagWidth + 12 = wideBindingX,
                "context tag remains anchored beside its binding after resizing")
            app.manager.editor.search.Value := ""
            app.manager.editor.SearchChanged()
            this.Assert(!app.manager.editor.visibleRows[1].contextTag.Visible,
                "unscoped heading hides the reused row's context tag")
            app.manager.editor.Close()
            IniWrite("1300", app.manager.root "\window.ini", "Window", "Width")
            IniWrite("900", app.manager.root "\window.ini", "Window", "Height")
            app.manager.ShowSettings()
            app.manager.editor.window.GetClientPos(, , &reopenedW, &reopenedH)
            this.Assert(Abs(reopenedW - expectedSize.width) <= 1
                && Abs(reopenedH - expectedSize.height) <= 1,
                "Keybindings ignores size history and reopens at its adaptive default")
            this.AssertCentered(app.manager.editor.window, "reopened Keybindings")
            app.manager.editor.Close()
            this.Assert(IniRead(app.manager.root "\window.ini", "Window", "Width") = "1300"
                && IniRead(app.manager.root "\window.ini", "Window", "Height") = "900",
                "Keybindings does not update old saved window sizes")
            IniWrite("1600", app.Settings.directory "\help-window.ini", "Window", "Width")
            IniWrite("950", app.Settings.directory "\help-window.ini", "Window", "Height")
            for id in SuiteSettings.ModuleOrder {
                app.ui.ShowHelp(id)
                key := "help:" id
                window := app.ui.windows[key]
                this.Assert(window.Title = SuiteSettings.ModuleNames[id] " - Getting started",
                    "module Help uses Getting started only in the title bar: " id)
                guide := window["helpText"].Value
                this.Assert(StrLen(guide) > 300 && !InStr(guide, "CURRENT SAVED SHORTCUTS"),
                    "help explains usage without listing every keybinding: " id)
                firstHeading := Map("cascade-kingdom", "ADD A WINDOW",
                    "wonder-windows", "ARRANGE YOUR WINDOWS",
                    "power-up-utilities", "MORE KEYS WITHOUT A NEW KEYBOARD",
                    "paper-pad", "YOUR OWN QUICK-NOTES DRAWER",
                    "secret-layers", "HOLD A KEY FOR MORE HOTKEYS")
                this.Assert(InStr(guide, "WHY I MADE THIS`r`n") = 1
                    && InStr(guide, "`r`n`r`n" firstHeading[id]) > 0
                    && !InStr(guide, "GETTING STARTED"),
                    "each module starts with a personal introduction: " id)
                this.Assert(StrLen(guide) >= 600,
                    "each Help guide provides substantial practical usage details: " id)
                if id = "cascade-kingdom"
                    this.Assert(InStr(guide, "Caps + Shift + Insert to take it out again") > 0,
                        "Cascade Kingdom explains how to take a window out again")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                expectedHelpHeight := Max(480, 145 + app.ui.HelpTextHeight(id, 820) + 12)
                this.Assert(helpWidth = 820 && helpHeight = expectedHelpHeight,
                    "Help opens tall enough for its introduction: " id)
                this.AssertCentered(window, SuiteSettings.ModuleNames[id] " Help")
                this.AssertSizeGrip(window, SuiteSettings.ModuleNames[id] " Help")
                subclassData := 0
                this.Assert(DllCall("comctl32\GetWindowSubclass", "ptr", window["helpText"].Hwnd,
                    "ptr", SuiteBufferedPaint.callback, "uptr", 1, "uptr*", &subclassData, "int"),
                    "the guide paints off-screen, so resizing never shows it half-drawn: " id)
                titlePart := app.ui.helpLayouts[id].header
                statusPart := app.ui.helpLayouts[id].status
                titlePart.GetPos(&headingX, , &headingW)
                statusPart.GetPos(&statusX, , &statusW)
                this.Assert(titlePart.Text = SuiteSettings.ModuleNames[id] " - "
                    && statusPart.Text = "dry run; feature effects are inactive"
                    && app.ui.helpLayouts[id].statusColor = "505050"
                    && statusX = headingX + headingW
                    && Abs(headingX + (headingW + statusW) / 2 - helpWidth / 2) <= 2,
                    "Help module name and status are centered as one line: " id)
                guideControl := window["helpText"]
                guideControl.GetPos(, &textY, , &textHeight)
                this.Assert(guideControl.Type = "Text"
                    && app.ui.helpLayouts[id].footer.divider.Visible,
                    "help is plain GUI text with a shared footer divider: " id)
                app.ui.helpLayouts[id].footer.divider.GetPos(, &dividerY)
                this.Assert(dividerY > textY + textHeight,
                    "the Help footer divider stays below the guide: " id)
                fontHandle := SendMessage(0x0031, 0, 0, , guideControl.Hwnd)
                fontData := Buffer(92, 0)
                this.Assert(fontHandle && DllCall("GetObjectW", "ptr", fontHandle,
                    "int", fontData.Size, "ptr", fontData, "int") = fontData.Size
                    && NumGet(fontData, 16, "int") = 400,
                    "help uses the original regular-weight font: " id)
                fontFace := StrGet(fontData.Ptr + 28, 32, "UTF-16")
                this.Assert(fontFace = "Cascadia Mono" || fontFace = "Consolas",
                    "help font is the old Cascadia Mono or the Windows fallback: " id)
                this.Assert(helpWidth >= 560 && helpHeight >= 400
                    && textHeight > 310 && textY + textHeight < helpHeight - 60,
                    "initial help page fits its complete guide: " id)
                this.Assert(app.ui.HelpTextHeight(id, helpWidth) <= textHeight,
                    "all Help guide paragraphs fit above the footer at startup: " id)
                this.Assert(app.ui.helpWindowIds.Has(window.Hwnd),
                    "Help window has its own wrap-aware sizing guard: " id)
                fullWidthHeight := app.ui.HelpTextHeight(id, 820)
                narrowHeight := app.ui.HelpTextHeight(id, 560)
                this.Assert(narrowHeight > fullWidthHeight,
                    "Help paragraphs wrap into more lines when narrower: " id)
                this.Assert(560 > app.ui.helpLayouts[id].footer.total + 20,
                    "minimum width keeps every footer button visible: " id)
                physicalWindow := Buffer(16, 0)
                physicalClient := Buffer(16, 0)
                DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", physicalWindow, "int")
                DllCall("GetClientRect", "ptr", window.Hwnd, "ptr", physicalClient, "int")
                scale := NumGet(physicalClient, 8, "int") / helpWidth
                borderW := NumGet(physicalWindow, 8, "int")
                    - NumGet(physicalWindow, 0, "int") - NumGet(physicalClient, 8, "int")
                borderH := NumGet(physicalWindow, 12, "int")
                    - NumGet(physicalWindow, 4, "int") - NumGet(physicalClient, 12, "int")
                sizing := Buffer(16, 0)
                NumPut("int", 100, sizing, 0)
                NumPut("int", 100, sizing, 4)
                NumPut("int", 100 + Round(560 * scale) + borderW, sizing, 8)
                NumPut("int", 100 + Round(400 * scale) + borderH, sizing, 12)
                app.ui.KeepHelpTextVisible(8, sizing.Ptr, 0, window.Hwnd)
                minimumHeight := Ceil(Max(400, 145 + narrowHeight) * scale) + borderH
                this.Assert(NumGet(sizing, 12, "int") - NumGet(sizing, 4, "int")
                    >= minimumHeight,
                    "narrow window can't hide wrapped text under its footer: " id)
                style := WinGetStyle("ahk_id " window.Hwnd)
                this.Assert(!!(style & 0x00040000) && !!(style & 0x00010000),
                    "help window is resizable and maximizable: " id)
                firstHeight := textHeight
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                window["helpText"].GetPos(, , , &textHeight)
                this.Assert(textHeight > firstHeight, "help body grows vertically: " id)
                this.Assert(app.ui.helpLayouts[id].renderedWidth = helpWidth
                    && app.ui.helpLayouts[id].renderedHeight = helpHeight,
                    "help live resizing processes one coherent control layout: " id)
                app.ui.helpLayouts[id].footer.divider.GetPos(, &dividerY, &dividerWidth)
                this.Assert(dividerY = helpHeight - 64
                    && dividerWidth = helpWidth - 40,
                    "help footer divider stays anchored during resizing: " id)
                for iteration in [1, 2, 3] {
                    window.Show("w" (960 + iteration * 25) " h" (610 + iteration * 20))
                    window.GetClientPos(, , &helpWidth, &helpHeight)
                    app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                    for item in app.ui.helpLayouts[id].footer.buttons {
                        item.button.GetPos(&buttonX, &buttonY, &buttonW)
                        this.Assert(buttonY = helpHeight - 49
                            && buttonX + buttonW <= helpWidth,
                            "buttons remain correctly placed after repeated resizing: " id)
                    }
                }
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                window.Show("w720 h400")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                this.Assert(helpWidth = 720 && helpHeight = 400,
                    "Help can shrink below its starting size: " id)
                window.Show("w560 h650")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                this.Assert(helpWidth = 560
                    && app.ui.helpLayouts[id].footer.divider.Visible,
                    "Help narrows to a footer-safe width and keeps the divider: " id)
                window.Show("w1080 h750")
                window.GetClientPos(, , &helpWidth, &helpHeight)
                app.ui.ResizeHelp(id, window, 0, helpWidth, helpHeight)
                for control in window {
                    if control.Type != "Button"
                        continue
                    control.GetPos(&buttonX, &buttonY, &buttonWidth)
                    this.Assert(buttonY > textY + textHeight
                        && buttonX >= 0 && buttonX + buttonWidth <= helpWidth,
                        "help navigation stays in the footer: " id "/" control.Text)
                }
                if SuiteIcons.handles.Length
                    this.Assert(SendMessage(0x007F, 0, 0, , window.Hwnd)
                        = SuiteIcons.handles[1], "module help uses one application icon: " id)

                if id != "power-up-utilities" {
                    app.ui.OpenSettingsFromHelp(id)
                    this.Assert(!app.ui.windows.Has(key)
                        && app.ui.windows.Has("settings:" id),
                        "Settings replaces Help rather than stacking over it: " id)
                    settings := app.ui.windows["settings:" id]
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    if id = "wonder-windows" {
                        for pair in [["fancyZonesStatus", ["running, not supported", "not running, you're all set!"]],
                            ["zoneUnit", ["Fourths and halves", "Thirds"]]] {
                            statusValue := settings[pair[1]].Text
                            allowed := false
                            for permitted in pair[2]
                                if statusValue = permitted
                                    allowed := true
                            this.Assert(allowed,
                                "Wonder Windows shows an explicit " pair[1] " status")
                        }
                        this.Assert(WonderWindowsModule.StatusColor("not running, you're all set!") = "008000"
                            && WonderWindowsModule.StatusColor("running, not supported") = "B02020"
                            && WonderWindowsModule.StatusColor("unknown") = "505050",
                            "Wonder Windows status values use green, red or neutral colors")
                        noSnap := true
                        for control in settings
                            if InStr(control.Text, "Snap")
                                noSnap := false
                        this.Assert(noSnap, "Wonder Windows Settings do not mention Windows Snap")
                        screenGridButtons := 0
                        for control in settings
                            if control.Type = "Button" && control.Text = "ScreenGrid..."
                                screenGridButtons += 1
                        this.Assert(screenGridButtons = 1
                            && WonderWindowsModule.ScreenGridUrl = "https://github.com/TtesseractT/ScreenGrid",
                            "Wonder Windows suggests ScreenGrid with a link to its GitHub page")
                        statusCoords := []
                        for name in ["zoneUnit", "fancyZonesStatus"] {
                            settings[name].GetPos(&statusX, &statusY)
                            statusCoords.Push(statusY)
                            this.Assert(statusX = SuitePageRows.FieldX,
                                "Wonder Windows " name " value sits in the page's field column")
                        }
                        this.Assert(statusCoords[1] < statusCoords[2],
                            "Wonder Windows settings rows are spaced in reading order")
                    }
                    this.Assert(app.ui.pageLayouts.Has("settings:" id)
                        && !!(WinGetStyle("ahk_id " settings.Hwnd) & 0x00040000),
                        "module Settings are resizable: " id)
                    defaultW := app.ui.pageLayouts["settings:" id].width
                    defaultH := app.ui.pageLayouts["settings:" id].height
                    this.Assert(settingsW = defaultW && settingsH = defaultH,
                        "module Settings open at a sensible size: " id)
                    this.Assert(app.ui.pageLayouts["settings:" id].minWidth < defaultW
                        && app.ui.pageLayouts["settings:" id].minHeight < defaultH,
                        "Settings can shrink below the opening size: " id)
                    this.AssertCentered(settings, SuiteSettings.ModuleNames[id] " Settings")
                    this.AssertSizeGrip(settings, SuiteSettings.ModuleNames[id] " Settings")
                    settings.Show("w" (defaultW + 120) " h" (defaultH + 140))
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    app.ui.ResizePage("settings:" id, settings, 0, settingsW, settingsH)
                    pageFooter := app.ui.pageLayouts["settings:" id].footer
                    pageFooter.divider.GetPos(, &settingsDividerY)
                    pageFooter.buttons[-1].button.GetPos(&lastButtonX, &lastButtonY, &lastButtonW)
                    this.Assert(settingsDividerY = settingsH - 64
                        && lastButtonY = settingsH - 49
                        && lastButtonX + lastButtonW <= settingsW,
                        "module Settings footer follows resizing: " id)
                    settings.Show("w" app.ui.pageLayouts["settings:" id].minWidth
                        " h" app.ui.pageLayouts["settings:" id].minHeight)
                    settings.GetClientPos(, , &settingsW, &settingsH)
                    app.ui.ResizePage("settings:" id, settings, 0, settingsW, settingsH)
                    this.Assert(settingsW = app.ui.pageLayouts["settings:" id].minWidth
                        && settingsH = app.ui.pageLayouts["settings:" id].minHeight,
                        "Settings support smaller manual resizing: " id)
                    backFound := false
                    for control in settings
                        if control.Type = "Button" && control.Text = "Back"
                            backFound := true
                    this.Assert(backFound, "module settings provides Back navigation: " id)
                    settingsDivider := 0
                    for control in settings
                        if control.Type = "Text"
                            && (WinGetStyle("ahk_id " control.Hwnd) & 0x00000010)
                            settingsDivider := control
                    this.Assert(IsObject(settingsDivider) && settingsDivider.Visible,
                        "module settings retains the same visible footer divider: " id)
                    app.ui.BackToHelp(id)
                    this.Assert(!app.ui.windows.Has("settings:" id)
                        && app.ui.windows.Has(key),
                        "Back closes Settings and restores Help: " id)
                }

                app.ui.OpenKeybindingsFromHelp(id)
                this.Assert(!app.ui.windows.Has(key)
                    && IsObject(app.manager.editor.window)
                    && app.manager.editor.moduleId = id
                    && app.manager.editor.doneButton.Text = "Back",
                    "module Help opens its own filtered Keybindings view: " id)
                moduleName := SuiteSettings.ModuleNames[id]
                onlyModule := true
                for item in app.manager.editor.rows
                    if item.id != "" && !app.manager._ActionInSettingsModule(item.id, id)
                        onlyModule := false
                this.Assert(onlyModule, "module Keybindings excludes unrelated shortcuts: " id)
                app.manager.editor.BackToHelp()
                this.Assert(!IsObject(app.manager.editor.window) && app.ui.windows.Has(key),
                    "Back from module Keybindings restores the Help page: " id)
                app.ui.CloseWindow(key)
            }
            app.ui.ShowHelp("paper-pad")
            this.Assert(!!WinActive("ahk_id " app.ui.windows["help:paper-pad"].Hwnd),
                "the Help page becomes active for its keyboard shortcut")
            app.ui.ToggleHelp("paper-pad")
            this.Assert(!app.ui.windows.Has("help:paper-pad"),
                "the same Help shortcut closes its active page")
            app.ui.ToggleHelp("paper-pad")
            this.Assert(app.ui.windows.Has("help:paper-pad"),
                "the Help shortcut opens the page again")
            app.ui.windows["help:paper-pad"].GetClientPos(, , &lastHelpW, &lastHelpH)
            expectedHelpHeight := Max(480, 145 + app.ui.HelpTextHeight("paper-pad", 820) + 12)
            this.Assert(lastHelpW = 820 && lastHelpH = expectedHelpHeight,
                "Help reopens at its content-based default regardless of prior resizing")
            this.AssertCentered(app.ui.windows["help:paper-pad"], "reopened Paper Pad Help")
            app.ui.CloseWindow("help:paper-pad")
            this.Assert(IniRead(app.Settings.directory "\help-window.ini",
                "Window", "Width") = "1600",
                "Help ignores existing saved window size history")
            app.activeModules["paper-pad"] := false
            app.ui.ShowHelp("paper-pad")
            this.Assert(IsObject(app.ui.windows["help:paper-pad"]),
                "disabled modules still expose their How to use page")
            this.Assert(app.ui.helpLayouts["paper-pad"].header.Text = "Paper Pad - "
                && app.ui.helpLayouts["paper-pad"].status.Text = "disabled"
                && app.ui.helpLayouts["paper-pad"].statusColor = "B02020",
                "disabled Help pages show a centered red status")
            app.ui.CloseWindow("help:paper-pad")
            page := "modules"
            app.ui.ShowModules()
            window := app.ui.windows[page]
            layout := app.ui.pageLayouts[page]
            window.GetClientPos(, , &pageW, &pageH)
            style := WinGetStyle("ahk_id " window.Hwnd)
            this.Assert(!!(style & 0x00040000) && !!(style & 0x00010000),
                "all shared utility windows support resize and maximize: " page)
            this.Assert(pageW = layout.width && pageH = layout.height,
                "utility page opens at its intended size: " page)
            this.Assert(layout.minWidth < layout.width && layout.minHeight < layout.height,
                "utility page allows smaller manual sizes: " page)
            this.AssertCentered(window, page)
            this.Assert(layout.footer.buttons.Length >= 2,
                "utility footer has its buttons: " page)
            this.Assert(app.ui.moduleControls.Count = 5,
                "Modules presents all five renamed features")
            obsoleteLine := false
            for control in window
                if control.Type = "Text" && InStr(control.Text, "Disabled modules keep")
                    obsoleteLine := true
            this.Assert(!obsoleteLine,
                "Modules no longer has the redundant line under Secret Layers")
            appSettingsFound := false
            for control in window
                if control.Type = "Button" && control.Text = "App settings..."
                    appSettingsFound := true
            this.Assert(!appSettingsFound,
                "Modules has no redundant App settings button")
            descriptionCount := 0
            for id in SuiteSettings.ModuleOrder {
                app.ui.moduleControls[id].GetPos(, &checkY, , &checkHeight)
                this.Assert(checkHeight < 40,
                    "Module checkbox keeps its natural height: " id)
                checkboxFont := SendMessage(0x0031, 0, 0, ,
                    app.ui.moduleControls[id].Hwnd)
                checkboxData := Buffer(92, 0)
                this.Assert(checkboxFont
                    && DllCall("GetObjectW", "ptr", checkboxFont, "int",
                        checkboxData.Size, "ptr", checkboxData, "int") = checkboxData.Size
                    && (StrGet(checkboxData.Ptr + 28, 32, "UTF-16") = "Cascadia Mono"
                        || StrGet(checkboxData.Ptr + 28, 32, "UTF-16") = "Consolas"),
                    "Module controls use the Help-page font: " id)
                for control in window {
                    if control.Type != "Text"
                        || control.Text != SuiteSettings.ModuleDescriptions[id]
                        continue
                    control.GetPos(, &descriptionY, , &descriptionHeight)
                    this.Assert(descriptionY > checkY
                        && descriptionHeight < 40
                        && descriptionY + descriptionHeight <= checkY + 58,
                        "Module description remains readable without overlap: " id)
                    descriptionCount += 1
                }
            }
            this.Assert(descriptionCount = 5,
                "all five Module descriptions are actually present and visible")
            window.Show("w" (layout.width + 100) " h" (layout.height + 130))
            window.GetClientPos(, , &pageW, &pageH)
            app.ui.ResizePage(page, window, 0, pageW, pageH)
            layout.footer.divider.GetPos(, &footerDividerY)
            this.Assert(footerDividerY = pageH - 64,
                "shared utility footer follows resizing: " page)
            window.Show("w" layout.minWidth " h" layout.minHeight)
            window.GetClientPos(, , &pageW, &pageH)
            app.ui.ResizePage(page, window, 0, pageW, pageH)
            this.Assert(pageW = layout.minWidth && pageH = layout.minHeight,
                "utility page shrinks to its smaller minimum: " page)
            app.ui.CloseWindow(page)
            this.Assert(app.manager.paused && app.modules["wonder-windows"].pending.Count = 0,
                "interface navigation keeps dry-run inputs and Wonder Windows effects inactive")
        }
        finally {
            app.Stop("Exit", 0)
            OnExit(app.exitCallback, 0)
            OnError(app.errorCallback, 0)
        }
        this.Assert(!InStr(SuiteState.Log.Read(), "ERROR"), "the five-module GUI smoke test emits no errors")
    }

    ; Posts BN_CLICKED, so the button's action runs through AutoHotkey's real
    ; Click dispatch rather than a direct method call.
    static Click(window, label) {
        for control in window
            if control.Type = "Button" && control.Text = label {
                PostMessage(0x0111, DllCall("GetDlgCtrlID", "ptr", control.Hwnd, "int") & 0xFFFF,
                    control.Hwnd, , "ahk_id " window.Hwnd) ; WM_COMMAND
                return
            }
        throw Error("Missing button: " label)
    }

    ; Waits until the page opened is shown and the page closed is gone;
    ; "keybindings" stands for the Keybindings window.
    static WaitForPage(app, opened, closed) {
        shown := (key) => key = "keybindings" ? IsObject(app.manager.editor.window) : app.ui.windows.Has(key)
        deadline := A_TickCount + 3000
        while !shown(opened) || shown(closed) {
            if A_TickCount > deadline
                throw Error("Timed out opening " opened " from " closed)
            Sleep(5)
        }
    }

    ; AutoHotkey 2.0.26 corrupted pages built inside a footer button's Click
    ; event once that event returned: Help lost its footer width after Back.
    static ClickedNavigation() {
        app := SuiteApplication(true, SuiteChecks.directory "\clicked-navigation")
        failures := []
        collect := (failure, *) => (failures.Push(failure.Message), 1)
        previousCritical := 0
        try {
            app.Start()
            OnError(collect, -1)
            ; Posted clicks only run while this thread can be interrupted.
            previousCritical := Critical("Off")
            intact := (label) => this.AssertFootersIntact(app, failures, label)
            loop 10 {
                for id, module in app.modules {
                    help := "help:" id
                    app.ui.ShowHelp(id)
                    settings := "settings:" id
                    if module.hasSettings {
                        this.Click(app.ui.windows[help], "Settings...")
                        this.WaitForPage(app, settings, help)
                        intact("Settings from Help: " id)
                        this.Click(app.ui.windows[settings], "Back")
                        this.WaitForPage(app, help, settings)
                        intact("Help from Settings: " id)
                    }
                    if A_Index = 1 {
                        this.Click(app.ui.windows[help], "Keybindings...")
                        this.WaitForPage(app, "keybindings", help)
                        this.Click(app.manager.editor.window, "Back")
                        this.WaitForPage(app, help, "keybindings")
                        intact("Help from Keybindings: " id)
                    }
                    app.ui.CloseWindow(help)
                }
            }
        }
        finally {
            Critical(previousCritical)
            OnError(collect, 0)
            app.Stop("Exit", 0)
            OnExit(app.exitCallback, 0)
            OnError(app.errorCallback, 0)
        }
        this.Assert(!failures.Length, "clicked navigation raises no errors")
    }

    static AssertFootersIntact(app, failures, label) {
        this.Assert(!failures.Length, "clicked navigation raises no errors: " label
            (failures.Length ? " (" failures[1] ")" : ""))
        for hwnd, footer in app.ui.pageFooters
            this.Assert(HasProp(footer, "divider") && HasProp(footer, "buttons") && HasProp(footer, "total"),
                "pages opened by a click keep their footer: " label)
        for key, window in app.ui.windows
            this.Assert(window.Hwnd, "pages opened by a click keep their window: " label)
    }

    static WindowSizingAndCloaking() {
        owner := SuiteGui("+Disabled +ToolWindow", "Release dialog owner")
        window := SuiteGui("+Resize +E0x1 +Owner" owner.Hwnd, "Release sizing test")
        try {
            SuiteShowCentered(window, 1600, 1200, 0, true)
            rect := Buffer(16, 0)
            DllCall("GetWindowRect", "ptr", window.Hwnd, "ptr", rect, "int")
            monitor := WindowMonitorIndex(window.Hwnd)
            MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
            this.Assert(NumGet(rect, 0, "int") >= left && NumGet(rect, 4, "int") >= top
                && NumGet(rect, 8, "int") <= right && NumGet(rect, 12, "int") <= bottom,
                "fitted GUI frames stay within the selected work area")
            window.GetClientPos(, , &width, &height)
            unchanged := SuiteFitClientSize(window, width, height, right - left, bottom - top)
            this.Assert(Abs(unchanged.width - width) <= 1 && Abs(unchanged.height - height) <= 1,
                "fitting an already fitting client does not resize it again")
            smaller := SuiteFitClientSize(window, 100, 100, right - left, bottom - top)
            this.Assert(smaller.width = 100 && smaller.height = 100,
                "fitting preserves deliberately small windows")
            this.Assert(PaperPadIsDialogWindow(window.Hwnd), "a visible test dialog can yield Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("PseudoConsoleWindow", 0x1, 123),
                "owned pseudoconsole helpers never count as dialogs")
            this.Assert(!PaperPadIsDialogCandidate("Button", 0x1, 123),
                "Explorer Button controls cannot lower Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("#32768", 0x1, 123)
                && !PaperPadIsDialogCandidate("Desktop User Picture", 0x1, 123),
                "native popup menus and Start-menu chrome do not lower Paper Pad")
            this.Assert(PaperPadIsDialogCandidate("#32770", 0, 0)
                && PaperPadIsDialogCandidate("OperationStatusWindow", 0, 0),
                "standard and operation-status dialogs remain eligible")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0x1, 0)
                && !PaperPadIsDialogCandidate("OtherWindow", 0, 123),
                "a dialog border or ownership alone cannot lower Paper Pad")
            this.Assert(!PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0, 123)
                && !PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0x1, 123),
                "Edge helper windows with an enabled owner are not dialogs")
            this.Assert(PaperPadIsDialogCandidate("OtherWindow", 0, 123, false)
                && PaperPadIsDialogCandidate("Chrome_WidgetWin_2", 0, 123, false),
                "custom modal dialogs remain eligible without a Chromium blacklist")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0x08000000, 123, false),
                "non-activating helpers do not become dialogs when their owner is disabled")
            this.Assert(!PaperPadIsDialogCandidate("OtherWindow", 0, 0),
                "ordinary unowned windows do not count as dialogs")
            cloaked := Buffer(4, 0)
            NumPut("uint", 1, cloaked)
            result := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int") ; DWMWA_CLOAK
            this.Assert(result = 0 && IsWindowCloaked(window.Hwnd), "the test owns its cloaked dialog")
            this.Assert(!PaperPadIsDialogWindow(window.Hwnd),
                "a cloaked dialog on another desktop does not lower Paper Pad")
            NumPut("uint", 0, cloaked)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", window.Hwnd,
                "uint", 13, "ptr", cloaked, "uint", 4, "int")
        }
        finally {
            window.Destroy()
            owner.Destroy()
        }
    }
}
