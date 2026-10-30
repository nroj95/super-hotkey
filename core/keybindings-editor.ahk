; The Keybindings window: a searchable, staged editor for every action's two
; hotkey slots. Edits stay in a draft until Apply; the manager validates and
; saves them. Rows are a fixed pool of controls reused while scrolling.
class KeybindingsEditor {
    ; Binding boxes never shrink below the longest four-key hotkey; in a
    ; narrower window titles give up the space and end in an ellipsis.
    ; FullWidth adds 398px for the longest title, the gaps and Reset.
    static MinWidth := 820
    static BindingWidth := 232
    static FullWidth := 1004

    __New(manager) {
        this.manager := manager
        this.window := 0
        this.draft := 0
        this.moduleId := ""
        this.recording := 0
        this.rows := []
        this.visibleRows := []
        this.rowPool := []
        this.scrollPosition := 0
        this.wheelRemainder := 0
        this.captureMouse := Map()
        this.resizing := false
        this.renderedWidth := 0
        this.renderedHeight := 0
        this.wheelCallback := ObjBindMethod(this, "_Wheel")
        this.scrollCallback := ObjBindMethod(this, "_VerticalScroll")
    }

    Title() {
        if this.moduleId != ""
            return SuiteSettings.ModuleNames[this.moduleId] " - Keybindings"
        if IsObject(SuiteState.App) && !SuiteState.App.ModuleActive("secret-layers")
            return "Keybindings — Secret Layers disabled"
        capsActive := this.manager.LayerEnabled("caps")
        pauseActive := this.manager.LayerEnabled("pause")
        if !capsActive && !pauseActive
            return "Keybindings — CapsLock and Pause layers disabled"
        if !capsActive
            return "Keybindings — CapsLock layer disabled"
        if !pauseActive
            return "Keybindings — Pause layer disabled"
        return "Keybindings"
    }

    ; moduleId "" shows every action; a module ID shows only that module's.
    Show(moduleId := "") {
        if !this.manager.running
            throw Error("Start the keybinding manager first.")
        if moduleId != "" && !SuiteSettings.ModuleNames.Has(moduleId)
            throw ValueError("Unknown Keybindings module: " moduleId)
        if IsObject(this.window) {
            if this.moduleId = moduleId {
                this.window.Show()
                return
            }
            ; Switching views discards that view's unapplied edits.
            this.Close()
        }

        this.moduleId := moduleId
        this.draft := this.manager.GetConfiguration()
        ; Buffer child-window painting while the editor updates many row controls.
        window := SuiteGui("+Resize +MinSize" KeybindingsEditor.MinWidth "x520 +0x02000000 +E0x02000000", this.Title())
        this.window := window
        window.BackColor := "FAF7F2"
        SuiteWindowOwnership.AllowArranging(window)
        window.SetFont("s10 w400", "Cascadia Mono")
        this.search := window.AddEdit("x210 y13 w400 vsearch")
        DllCall("SendMessageW", "ptr", this.search.Hwnd, "uint", 0x1501, ; EM_SETCUEBANNER
            "uptr", 1, "str", "Search… (LMB to record, RMB to type)", "ptr")
        this.search.OnEvent("Change", ObjBindMethod(this, "SearchChanged"))
        this.rowPool := []
        this.visibleRows := []
        this.scroll := window.AddCustom("ClassScrollBar x778 y48 w24 h140 +0x1")
        this.divider := window.AddText("x22 y300 w752 h2 +0x10", "")
        this.resetAllButton := this._AddButton("x244 y320 w180 h31", "Restore defaults", "_ResetAll")
        this.applyButton := this._AddButton("x438 y320 w120 h31", "Apply", "ApplyStaged")
        ; The title bar and Escape close the window; a module view adds Back to its Help.
        this.doneButton := moduleId = "" ? 0 : this._AddButton("x572 y320 w110 h31", "Back", "BackToHelp")
        window.OnEvent("Size", ObjBindMethod(this, "Resize"))
        window.OnEvent("ContextMenu", ObjBindMethod(this, "_EditBindingText"))
        window.OnEvent("Close", ObjBindMethod(this, "RequestClose"))
        window.OnEvent("Escape", ObjBindMethod(this, "RequestClose"))
        this.scrollPosition := 0
        this.resizing := false
        this.renderedWidth := 0
        this.renderedHeight := 0
        SuiteShowCentered(window, 1060, Min(860, Max(560, A_ScreenHeight - 125)),
            ObjBindMethod(this, "Resize"), true)
        OnMessage(0x020A, this.wheelCallback) ; WM_MOUSEWHEEL
        OnMessage(0x0115, this.scrollCallback) ; WM_VSCROLL
    }

    _AddButton(options, text, handler) {
        button := this.window.AddButton(options, text)
        button.OnEvent("Click", SuiteClickAction(ObjBindMethod(this, handler)))
        return button
    }

    ; Small, explanatory context tags, only for positive application scopes.
    ; Inverse scopes are exclusion rules, not single-application shortcuts.
    static ContextTagText(scope) {
        switch scope {
            case "paper-pad": return "editor only"
            case "windows-terminal": return "terminal only"
            default: return ""
        }
    }

    ; Anchor context tags before the first binding box, not after the
    ; variable-length description. Ellipsize labels that run into the tag.
    static ContextRowLayout(label, tag, primaryX) {
        available := Max(80, primaryX - 33) ; x22 to 11px before binding
        if tag = ""
            return {titleWidth: available, tagX: 22, tagWidth: 0}
        tagWidth := Ceil(StrLen(tag) * 6.0) + 6 ; 7.25pt text, 3px horizontal padding
        tagX := primaryX - tagWidth - 12 ; 12px before the first binding box
        titleWidth := Max(1, Min(StrLen(label) * 8, tagX - 22 - 8))
        return {titleWidth: titleWidth, tagX: tagX, tagWidth: tagWidth}
    }

    ; Avoid dispatching redundant WM_SETTEXT, ShowWindow and EnableWindow updates.
    static _SetText(control, value) {
        if control.Text != value
            control.Text := value
    }

    static _SetVisible(control, visible) {
        if control.Visible != visible
            control.Visible := visible
    }

    static _SetEnabled(control, enabled) {
        if control.Enabled != enabled
            control.Enabled := enabled
    }

    static _MoveHeading(control, x, width) {
        control.GetPos(&currentX, , &currentWidth)
        if currentX != x || currentWidth != width
            control.Move(x, , width)
    }

    _AddRow() {
        index := this.rowPool.Length + 1
        window := this.window
        ; SS_NOPREFIX keeps "&" in labels such as &nbsp; from becoming an accelerator.
        title := window.AddText("Hidden x22 y48 w290 h25 +0x4000 +0x80", "") ; SS_ENDELLIPSIS | SS_NOPREFIX
        categoryTitle := window.AddText("Hidden x22 y48 w752 h25 Center", "")
        contextTag := window.AddText("Hidden x22 y48 w80 h16 Border Center c777777", "")
        contextTag.SetFont("s7.25 c777777", "Cascadia Mono")
        primary := window.AddButton("Hidden x358 y48 w167 h29", "Unbound")
        secondary := window.AddButton("Hidden x535 y48 w153 h29", "Unbound")
        reset := window.AddButton("Hidden x698 y48 w76 h29", "Reset")
        primary.OnEvent("Click", ObjBindMethod(this, "BeginRecording", index, 1))
        secondary.OnEvent("Click", ObjBindMethod(this, "BeginRecording", index, 2))
        reset.OnEvent("Click", ObjBindMethod(this, "_ResetAction", index))
        this.rowPool.Push({title: title, categoryTitle: categoryTitle,
            contextTag: contextTag, primary: primary, secondary: secondary,
            reset: reset, actionId: ""})
    }

    Resize(window, minMax, width, height) {
        if !IsObject(this.window) || this.window != window || minMax = -1
            return
        if this.resizing
            return
        width := Max(KeybindingsEditor.MinWidth, width)
        height := Max(320, height)
        widthChanged := width != this.renderedWidth
        heightChanged := height != this.renderedHeight
        rowCount := Min(128, Max(4, Floor((height - 120) / 35)))
        rowsChanged := rowCount != this.visibleRows.Length
        if !widthChanged && !heightChanged && !rowsChanged
            return

        this.resizing := true
        redrawSuspended := false
        try {
            positions := []
            if rowsChanged {
                ; Only suspend painting when controls are created or shown/hidden.
                SendMessage(0x000B, 0, 0, , window.Hwnd) ; WM_SETREDRAW
                redrawSuspended := true
                while this.rowPool.Length < rowCount
                    this._AddRow()
                this.visibleRows := []
                for index, row in this.rowPool {
                    if index > rowCount {
                        row.title.Visible := false
                        row.categoryTitle.Visible := false
                        row.contextTag.Visible := false
                        row.primary.Visible := false
                        row.secondary.Visible := false
                        row.reset.Visible := false
                    } else
                        this.visibleRows.Push(row)
                }
            }

            if widthChanged {
                searchWidth := Min(600, width // 2)
                positions.Push({control: this.search,
                    x: Floor((width - searchWidth) / 2), y: 13, w: searchWidth, h: 23})
            }

            if widthChanged || rowsChanged {
                ; Both binding boxes share one width, growing only once every
                ; title fits; titles take the rest and the reset button stays fixed.
                bindingWidth := KeybindingsEditor.BindingWidth
                    + Max(0, Floor((width - KeybindingsEditor.FullWidth) * 0.32))
                resetX := width - 122
                secondaryX := resetX - bindingWidth - 10
                primaryX := secondaryX - bindingWidth - 10
                for index, row in this.visibleRows {
                    y := 48 + (index - 1) * 35
                    tag := row.contextTag.Visible ? row.contextTag.Text : ""
                    layout := KeybindingsEditor.ContextRowLayout(row.title.Text, tag, primaryX)
                    positions.Push({control: row.title,
                        x: 22, y: y + 6, w: layout.titleWidth, h: 25})
                    positions.Push({control: row.contextTag,
                        x: layout.tagX, y: y + 6, w: layout.tagWidth, h: 16})
                    positions.Push({control: row.categoryTitle,
                        x: 22, y: y + 6, w: width - 68, h: 25})
                    positions.Push({control: row.primary,
                        x: primaryX, y: y, w: bindingWidth, h: 29})
                    positions.Push({control: row.secondary,
                        x: secondaryX, y: y, w: bindingWidth, h: 29})
                    positions.Push({control: row.reset,
                        x: resetX, y: y, w: 76, h: 29})
                }
                positions.Push({control: this.scroll,
                    x: width - 42, y: 48, w: 24, h: rowCount * 35})
            }

            if widthChanged || heightChanged {
                positions.Push({control: this.divider,
                    x: 22, y: height - 64, w: width - 68, h: 2})
                ; A 314px or 438px button group with a 46px right margin.
                footerX := width - (this.doneButton ? 484 : 360)
                positions.Push({control: this.resetAllButton,
                    x: footerX, y: height - 49, w: 180, h: 31})
                positions.Push({control: this.applyButton,
                    x: footerX + 194, y: height - 49, w: 120, h: 31})
                if this.doneButton
                    positions.Push({control: this.doneButton,
                        x: footerX + 328, y: height - 49, w: 110, h: 31})
            }
            SuiteMoveControls(window, positions)
            if rowsChanged
                this.Render()
            this.renderedWidth := width
            this.renderedHeight := height
        }
        finally {
            if redrawSuspended {
                SendMessage(0x000B, 1, 0, , window.Hwnd)
                DllCall("RedrawWindow", "ptr", window.Hwnd, "ptr", 0, "ptr", 0,
                    "uint", 0x185, "int") ; invalidate, erase and refresh child controls once
            }
            this.resizing := false
        }
    }

    SearchChanged(*) {
        this.scrollPosition := 0
        this.wheelRemainder := 0
        this.Render()
    }

    _Wheel(wParam, lParam, messageId, receiverHwnd) {
        if !IsObject(this.window) || IsObject(this.recording)
            return
        ; Handle only wheel messages for this GUI or its child controls.
        if receiverHwnd != this.window.Hwnd
            && DllCall("GetAncestor", "ptr", receiverHwnd, "uint", 2, "ptr") != this.window.Hwnd
            return
        ; Windows can deliver the wheel to the focused control even when the
        ; pointer is elsewhere. Never scroll a window behind the cursor.
        MouseGetPos(, , &hoverWindow)
        if hoverWindow != this.window.Hwnd
            return

        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        if maximum = 0
            return 0
        ; Wheel delta is a signed 16-bit number in the high word of wParam.
        wheelDelta := (wParam >> 16) & 0xFFFF
        if wheelDelta >= 0x8000
            wheelDelta -= 0x10000
        this.wheelRemainder += wheelDelta
        wheelSteps := Floor(Abs(this.wheelRemainder) / 120)
        if wheelSteps = 0
            return 0
        wheelDirection := this.wheelRemainder > 0 ? -1 : 1
        this.wheelRemainder += wheelDirection * wheelSteps * 120
        this.scrollPosition := Min(Max(this.scrollPosition + wheelDirection * wheelSteps * 3,
            0), maximum)
        this.Render()
        return 0
    }

    _VerticalScroll(wParam, lParam, messageId, receiverHwnd) {
        if !IsObject(this.window) || receiverHwnd != this.window.Hwnd
            || lParam != this.scroll.Hwnd
            return
        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        nextPosition := this.scrollPosition
        switch wParam & 0xFFFF {
            case 0: nextPosition -= 1             ; SB_LINEUP
            case 1: nextPosition += 1             ; SB_LINEDOWN
            case 2: nextPosition -= this.visibleRows.Length ; SB_PAGEUP
            case 3: nextPosition += this.visibleRows.Length ; SB_PAGEDOWN
            case 4, 5:                           ; SB_THUMBPOSITION / SB_THUMBTRACK
                scrollInfo := Buffer(28, 0)
                NumPut("uint", 28, scrollInfo, 0)
                NumPut("uint", 0x10, scrollInfo, 4) ; SIF_TRACKPOS
                if DllCall("GetScrollInfo", "ptr", lParam, "int", 2,
                    "ptr", scrollInfo, "int")
                    nextPosition := NumGet(scrollInfo, 24, "int")
            case 6: nextPosition := 0             ; SB_TOP
            case 7: nextPosition := maximum       ; SB_BOTTOM
            default: return 0                    ; SB_ENDSCROLL / unknown
        }
        nextPosition := Min(Max(nextPosition, 0), maximum)
        if nextPosition = this.scrollPosition
            return 0
        this.scrollPosition := nextPosition
        this.Render()
        return 0
    }

    Render(*) {
        if !IsObject(this.window)
            return
        manager := this.manager
        newTitle := this.Title()
        if this.window.Title != newTitle
            this.window.Title := newTitle
        this.rows := Keybindings.DisplayRows(manager.Catalog(this.draft, this.moduleId),
            this.window["search"].Value)
        this.applyButton.Enabled := this.HasPending()
        maximum := Max(0, this.rows.Length - this.visibleRows.Length)
        this.scrollPosition := Min(Max(this.scrollPosition, 0), maximum)
        KeybindingsEditor._SetVisible(this.scroll, maximum > 0)
        ; SCROLLINFO controls both the actual offset and the proportional thumb.
        ; nMax is the final row index, and nPage is the visible row count.
        scrollInfo := Buffer(28, 0)
        NumPut("uint", 28, scrollInfo, 0)
        NumPut("uint", 0x7, scrollInfo, 4) ; SIF_RANGE | SIF_PAGE | SIF_POS
        NumPut("int", 0, scrollInfo, 8)
        NumPut("int", Max(0, this.rows.Length - 1), scrollInfo, 12)
        NumPut("uint", this.visibleRows.Length, scrollInfo, 16)
        NumPut("int", this.scrollPosition, scrollInfo, 20)
        DllCall("SetScrollInfo", "ptr", this.scroll.Hwnd, "int", 2,
            "ptr", scrollInfo, "int", true, "int")
        this.window.GetClientPos(, , &clientWidth)
        for index, row in this.visibleRows {
            position := this.scrollPosition + index
            visible := position <= this.rows.Length
            entry := visible ? this.rows[position] : 0
            isAction := visible && entry.id != ""
            row.actionId := isAction ? entry.id : ""
            KeybindingsEditor._SetVisible(row.title, isAction)
            KeybindingsEditor._SetVisible(row.categoryTitle, visible && !isAction)
            if !isAction
                KeybindingsEditor._SetVisible(row.contextTag, false)
            KeybindingsEditor._SetVisible(row.primary, isAction)
            KeybindingsEditor._SetVisible(row.secondary, isAction)
            KeybindingsEditor._SetVisible(row.reset, isAction)
            if !visible
                continue
            if !isAction {
                heading := entry.label = "Global" ? "★ Global ★" : entry.label
                KeybindingsEditor._SetText(row.categoryTitle, heading)
                KeybindingsEditor._MoveHeading(row.categoryTitle, 22, clientWidth - 68)
                continue
            }
            KeybindingsEditor._SetText(row.title, entry.label)
            tag := KeybindingsEditor.ContextTagText(entry.scope)
            KeybindingsEditor._SetText(row.contextTag, tag)
            row.primary.GetPos(&primaryX)
            layout := KeybindingsEditor.ContextRowLayout(entry.label, tag, primaryX)
            KeybindingsEditor._MoveHeading(row.title, 22, layout.titleWidth)
            if tag != ""
                KeybindingsEditor._MoveHeading(row.contextTag, layout.tagX, layout.tagWidth)
            KeybindingsEditor._SetVisible(row.contextTag, tag != "")
            setting := this.draft[entry.id]
            for slot, control in [row.primary, row.secondary] {
                parsed := Keybindings.Parse(setting.bindings[slot])
                if !IsObject(parsed) {
                    KeybindingsEditor._SetText(control, "+ Add")
                    continue
                }
                ; A layer binding stays editable while its layer is off; it is only marked.
                inactiveLayer := parsed.layer != "normal" && manager.BindingUnavailable(parsed) != ""
                KeybindingsEditor._SetText(control, (inactiveLayer ? "⚠ " : "") parsed.label)
            }
            defaults := manager.actions[entry.id].defaults
            KeybindingsEditor._SetEnabled(row.reset,
                setting.bindings[1] != defaults[1] || setting.bindings[2] != defaults[2])
        }
    }

    _ResetAction(index, *) {
        if index > this.visibleRows.Length
            return
        actionId := this.visibleRows[index].actionId
        if actionId = ""
            return
        configuration := this.manager._CloneConfiguration(this.draft)
        configuration[actionId].bindings := this.manager.actions[actionId].defaults.Clone()
        this.Stage(configuration)
    }

    _ResetAll(*) {
        subject := this.moduleId = "" ? "all actions, including disabled modules"
            : SuiteSettings.ModuleNames[this.moduleId]
        if MsgBox("Restore default hotkey assignments for " subject "?"
            . "`n`nChanges stay pending until Apply. Other preferences and notes are untouched.",
            this.manager.name, "YesNo Default2 Icon?") != "Yes"
            return
        this.StageDefaults()
    }

    StageDefaults() {
        manager := this.manager
        configuration := manager._CloneConfiguration(this.draft)
        for actionId, action in manager.actions
            if manager._ActionInSettingsModule(actionId, this.moduleId)
                configuration[actionId].bindings := action.defaults.Clone()
        this.Stage(configuration)
    }

    HasPending() {
        if !IsObject(this.draft)
            return false
        for actionId, setting in this.draft {
            current := this.manager.configuration[actionId]
            if setting.enabled != current.enabled || setting.bindings[1] != current.bindings[1]
                || setting.bindings[2] != current.bindings[2]
                return true
        }
        return false
    }

    ; Editing is purely in-memory. Conflicts are checked against all modules
    ; by Apply(), before anything is saved or the active hotkeys change.
    Stage(configuration) {
        if !IsObject(this.window)
            return false
        this.draft := this.manager._CloneConfiguration(configuration)
        this.Render()
        return true
    }

    ApplyStaged(*) {
        if !IsObject(this.window) || !this.HasPending()
            return false
        if IsObject(this.recording) {
            this.EndRecording()
            return false
        }
        try {
            this.manager.Apply(this.draft)
            this.manager._Report("keybinding changes saved")
            ; Stay open for further edits; Apply turns grey once nothing is pending.
            this.Stage(this.manager.GetConfiguration())
            return true
        }
        catch Error as failure {
            SuiteState.Log.Error("Keybindings", failure)
            MsgBox(failure.Message, this.manager.name " - binding rejected", "Icon!")
            return false
        }
    }

    BackToHelp(*) {
        if !this.CanLeave()
            return true
        moduleId := this.moduleId
        this.Close()
        if moduleId != "" && IsObject(SuiteState.App) && IsObject(SuiteState.App.ui)
            SuiteState.App.ui.ShowHelp(moduleId)
    }

    ; The title bar, Escape and the opening hotkey close the window. Returning
    ; true keeps it open, because Gui Close otherwise hides it.
    RequestClose(*) {
        if !this.CanLeave()
            return true
        this.Close()
    }

    ; Leaving first cancels a recording in progress, then asks before
    ; discarding changes that were never applied.
    CanLeave() {
        if IsObject(this.recording) {
            this.EndRecording()
            return false
        }
        return !this.HasPending() || MsgBox("Discard keybinding changes that were not applied?",
            this.manager.name, "YesNo Default2 Icon? Owner" this.window.Hwnd) = "Yes"
    }

    Close(*) {
        this.EndRecording()
        OnMessage(0x020A, this.wheelCallback, 0)
        OnMessage(0x0115, this.scrollCallback, 0)
        this.wheelRemainder := 0
        if IsObject(this.window) {
            SuiteFocusReturn.Destroy(this.window)
        }
        this.window := 0
        this.draft := 0
        this.moduleId := ""
    }

    ; =========================================================================
    ; direct keyboard and mouse capture (no second editor window)
    ; =========================================================================

    BeginRecording(index, slot, *) {
        if IsObject(this.recording) || !IsObject(this.window)
            return
        actionId := this.visibleRows[index].actionId
        if actionId = ""
            return
        record := {hook: 0, pending: "", pendingKey: "", clearing: false,
            actionId: actionId, slot: slot,
            prefixDown: "", prefixDownAt: 0, prefixUsed: false,
            prefixCancel: false, armedLayer: "", armedAt: 0,
            finish: ObjBindMethod(this, "_FinishRecordedKey"),
            timeout: ObjBindMethod(this, "EndRecording")}
        this.recording := record
        try {
            ; Recording gates every hotkey so the pressed keys reach the recorder.
            this.manager.SetCapture(true)
            record.button := slot = 1 ? this.visibleRows[index].primary : this.visibleRows[index].secondary
            record.button.Text := "Press keys..."
            hook := InputHook("L0 I101")
            hook.KeyOpt("{All}", "SN")
            hook.OnKeyDown := ObjBindMethod(this, "_RecordKey")
            hook.OnKeyUp := ObjBindMethod(this, "_RecordKeyUp")
            record.hook := hook
            hook.Start()
            HotIf()
            for mouseName in ["LButton", "RButton", "MButton", "XButton1", "XButton2",
                "WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
                hotkeyName := "$*" mouseName
                Hotkey(hotkeyName, ObjBindMethod(this, "_RecordMouse", mouseName), "On I100 B0")
                this.captureMouse[hotkeyName] := true
            }
            SetTimer(record.finish, 25)
            SetTimer(record.timeout, -10000)
        }
        catch Error as failure {
            this.EndRecording()
            SuiteState.Log.Error("Keybindings", failure)
            MsgBox(failure.Message, this.manager.name " - could not record", "Icon!")
        }
    }

    _CaptureLayer() {
        if this.manager.LayerEnabled("caps") && GetKeyState("CapsLock", "P")
            return "caps"
        if this.manager.LayerEnabled("pause") && (GetKeyState("Pause", "P") || GetKeyState("CtrlBreak", "P"))
            return "pause"
        return "normal"
    }

    ; The recorder is active while Secret Layers is gated, so it must track
    ; prefix taps itself instead of relying on the running layer dispatcher.
    _RecordingPrefixLayer(vk) {
        if vk = 0x14 && this.manager.LayerEnabled("caps")
            return "caps"
        if (vk = 0x13 || vk = 3) && this.manager.LayerEnabled("pause")
            return "pause"
        return ""
    }

    ; These transition helpers are deterministic so timing and tap-then-hold
    ; behavior can be tested without injecting real keyboard input.
    static RecordingPrefixDown(record, layer, now, oneShotMs := 1400) {
        if record.prefixDown != ""
            return false
        elapsed := now - record.armedAt
        record.prefixCancel := record.armedLayer = layer
            && elapsed >= 0 && elapsed < oneShotMs
        record.prefixDown := layer
        record.prefixDownAt := now
        record.prefixUsed := false
        record.armedLayer := ""
        return true
    }

    static RecordingPrefixUp(record, layer, now, modifiers, tapMaxMs := 250) {
        if record.prefixDown != layer
            return ""
        elapsed := now - record.prefixDownAt
        quick := !record.prefixUsed && modifiers = 0
            && elapsed >= 0 && elapsed <= tapMaxMs
        doubleTap := quick && record.prefixCancel
        cancelled := record.prefixCancel
        record.prefixDown := ""
        record.prefixCancel := false
        record.prefixUsed := false
        if doubleTap
            return "double"
        if quick && !cancelled {
            record.armedLayer := layer
            record.armedAt := now
            return "armed"
        }
        return ""
    }

    static RecordingOneShotLayer(record, now, oneShotMs := 1400) {
        elapsed := now - record.armedAt
        if record.armedLayer != "" && elapsed >= 0 && elapsed < oneShotMs
            return record.armedLayer
        return ""
    }

    static RecordingBareKey(record, physicalLayer, now, modifiers) {
        ; Escape cancels and Backspace clears only without a held or one-shot prefix.
        return physicalLayer = "normal" && record.prefixDown = ""
            && KeybindingsEditor.RecordingOneShotLayer(record, now) = "" && modifiers = 0
    }

    _RecordPrefixRelease(layer) {
        if !IsObject(this.recording) || this.recording.pending != ""
            return
        record := this.recording
        result := KeybindingsEditor.RecordingPrefixUp(record, layer, A_TickCount,
            Keybindings.ModifierMask())
        if result = "double" {
            ; No prefix is physically held on release. The normal finish watcher
            ; will stage this complete, non-repeating double-tap assignment.
            key := layer = "caps" ? "CapsLock" : "vk13"
            this._StageRecordedBinding(layer, 0, key, "")
        } else if result = "armed"
            record.button.Text := "Press next key..."
        else
            record.button.Text := "Press keys..."
    }

    _RecordKeyUp(hook, vk, sc) {
        if !IsObject(this.recording)
            return
        layer := this._RecordingPrefixLayer(vk)
        if layer != "" && this.recording.prefixDown = layer
            this._RecordPrefixRelease(layer)
    }

    _RecordKey(hook, vk, sc) {
        if !IsObject(this.recording)
            return
        if !WinActive("ahk_id " this.window.Hwnd) {
            this.EndRecording()
            return
        }
        record := this.recording
        layer := this._CaptureLayer()
        bare := KeybindingsEditor.RecordingBareKey(record, layer, A_TickCount,
            Keybindings.ModifierMask())
        if vk = 0x1B && bare {
            this.EndRecording()
            return
        }
        key := vk = 0x13 || vk = 3 ? Format("vk{:02X}", vk)
            : sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        if (vk = 0x08 || vk = 0x2E) && bare {
            record.pending := "CLEAR"
            record.pendingKey := key
            record.clearing := true
            record.button.Text := "Unbound ..."
            return
        }
        if vk = 0x10 || vk = 0x11 || vk = 0x12 || (vk >= 0xA0 && vk <= 0xA5)
            || vk = 0x5B || vk = 0x5C
            return
        prefix := this._RecordingPrefixLayer(vk)
        if prefix != "" {
            if record.pending = "" && KeybindingsEditor.RecordingPrefixDown(record,
                prefix, A_TickCount)
                record.button.Text := "Press next key..."
            return
        }
        if record.pending != ""
            return
        ; A held prefix records a normal chord. A released, quickly tapped
        ; prefix supplies the one-shot layer for the next key (up to 1400 ms).
        if record.prefixDown != "" {
            layer := record.prefixDown
            record.prefixUsed := true
        } else {
            oneShotLayer := KeybindingsEditor.RecordingOneShotLayer(record, A_TickCount)
            if oneShotLayer != ""
                layer := oneShotLayer
        }
        record.armedLayer := ""
        this._StageRecordedBinding(layer, Keybindings.ModifierMask(), key, key)
    }

    _RecordMouse(mouseName, *) {
        if !IsObject(this.recording)
            return
        ; Either primary mouse button is a safe, no-save cancel gesture.
        ; Handle it before the focus check so clicking outside also cancels.
        if mouseName = "LButton" || mouseName = "RButton" {
            this.EndRecording()
            return
        }
        if !WinActive("ahk_id " this.window.Hwnd) {
            this.EndRecording()
            return
        }
        if this.recording.pending != ""
            return
        this._StageRecordedBinding(this._CaptureLayer(), Keybindings.ModifierMask(), mouseName, "")
    }

    _StageRecordedBinding(layer, modifiers, key, waitKey) {
        try {
            binding := Keybindings.Parse(layer "|" modifiers "|" key)
            this.recording.pending := binding.signature
            this.recording.pendingKey := waitKey
            this.recording.button.Text := binding.label " ..."
        }
        catch Error as captureError {
            this.EndRecording()
            MsgBox(captureError.Message, this.manager.name " - unsupported binding", "Icon!")
        }
    }

    ; Stage the recorded hotkey once every key of it has been released.
    _FinishRecordedKey(*) {
        if !IsObject(this.recording)
            return
        record := this.recording
        if !IsObject(this.window) || !WinActive("ahk_id " this.window.Hwnd) {
            this.EndRecording()
            return
        }
        ; Pause may not generate a conventional key-up on every keyboard.
        ; Poll physical state as a fallback; normal InputHook key-up is preferred.
        if record.pending = "" && record.prefixDown != "" {
            released := record.prefixDown = "caps" ? !GetKeyState("CapsLock", "P")
                : !GetKeyState("Pause", "P") && !GetKeyState("CtrlBreak", "P")
            if released && A_TickCount - record.prefixDownAt >= 20
                this._RecordPrefixRelease(record.prefixDown)
        }
        if record.pending = "" || (record.pendingKey != "" && GetKeyState(record.pendingKey, "P"))
            return
        if Keybindings.ModifierMask() || GetKeyState("CapsLock", "P")
            || GetKeyState("Pause", "P") || GetKeyState("CtrlBreak", "P")
            return
        value := record.clearing ? "" : record.pending
        actionId := record.actionId
        slot := record.slot
        this.EndRecording()
        if Keybindings.NeedsMouseConfirmation(Keybindings.Parse(value))
            && MsgBox("This hotkey intercepts ordinary middle-click or mouse-wheel input. Assign it?",
                this.manager.name, "YesNo Default2 Icon!") != "Yes"
            return
        configuration := this.manager._CloneConfiguration(this.draft)
        configuration[actionId].bindings[slot] := value
        this.Stage(configuration)
    }

    EndRecording(*) {
        if !IsObject(this.recording)
            return
        record := this.recording
        this.recording := 0
        SetTimer(record.finish, 0)
        SetTimer(record.timeout, 0)
        if IsObject(record.hook)
            record.hook.Stop()
        HotIf()
        for hotkeyName in this.captureMouse
            Hotkey(hotkeyName, "Off")
        this.captureMouse.Clear()
        this.manager.SetCapture(false)
        this.Render()
    }

    ; Right-click a binding to type it instead of recording it.
    _EditBindingText(window, control, *) {
        if !IsObject(control) || IsObject(this.recording)
            return
        for row in this.visibleRows {
            if row.actionId = ""
                continue
            for slot, button in [row.primary, row.secondary] {
                if button.Hwnd != control.Hwnd
                    continue
                configuration := this.manager._CloneConfiguration(this.draft)
                old := Keybindings.Parse(configuration[row.actionId].bindings[slot])
                input := InputBox("Type a hotkey, for example CapsLock, Escape, or Ctrl + Alt + J."
                    . "`n`nLeave empty to clear.",
                    "Edit hotkey", "w550 h170", IsObject(old) ? old.label : "")
                if input.Result != "OK"
                    return
                try parsed := Keybindings.Parse(input.Value)
                catch Error as failure {
                    MsgBox(failure.Message, this.manager.name, "Icon!")
                    return
                }
                if Keybindings.NeedsMouseConfirmation(parsed)
                    && MsgBox("Intercept ordinary middle-click or mouse-wheel input?", this.manager.name,
                        "YesNo Default2 Icon!") != "Yes"
                    return
                configuration[row.actionId].bindings[slot] := IsObject(parsed) ? parsed.signature : ""
                this.Stage(configuration)
                return
            }
        }
    }
}
