; Wonder Windows implementation. Launch the suite, not this file.

; =============================================================================
; startup detection and explicit compatibility setup
; =============================================================================

WW_CheckFancyZonesStartup(*)
{
    global WW_fancyzones_process_id, WW_fancyzones_integration_state
    process_id := ProcessExist("PowerToys.FancyZones.exe")
    if process_id = WW_fancyzones_process_id
        return
    WW_fancyzones_process_id := process_id
    ; A restarted process must not use the previous instance's readiness state.
    WW_fancyzones_integration_state := false
    if !process_id
        return

    WW_fancyzones_integration_state := WW_ReadFancyZonesIntegrationState()
    ; FancyZones may install its hook just after its process first appears.
    SetTimer(WW_ReassertFancyZonesKeyboardHook, -1000)
}

WW_ReassertFancyZonesKeyboardHook(*)
{
    if WW_IsFancyZonesRunning()
        InstallKeybdHook(true, true)
}

WW_CheckFancyZonesIntegration(*)
{
    global WW_fancyzones_integration_state, WW_fancyzones_check_in_progress
    if WW_fancyzones_check_in_progress
        return

    if !WW_IsFancyZonesRunning() {
        MsgBox("FancyZones is not running. No settings were changed.", "Wonder Windows", "Iconi")
        return
    }

    WW_fancyzones_check_in_progress := true
    try {
        state := WW_ReadFancyZonesIntegrationState()
        WW_fancyzones_integration_state := state
        if !state {
            MsgBox(
                "The FancyZones settings could not be read.`n`n"
                . "Configure Override Windows Snap and zone-window switching, and "
                . "Ctrl + Alt + PgUp/PgDn manually in PowerToys.",
                "Wonder Windows", "Icon!"
            )
            return
        }
        if WW_FancyZonesArrowsReady(state) && WW_FancyZonesSwitchingReady(state)
            return "ready"

        arrow_shortcut := WW_GetFancyZonesArrowShortcutLabel(state)

        response := MsgBox(
            "Set up the optional FancyZones shortcuts?`n`n"
            . arrow_shortcut ": move between zones`n"
            . "Ctrl + Alt + PgUp: previous window in the current zone`n"
            . "Ctrl + Alt + PgDn: next window in the current zone`n`n"
            . "This enables Override Windows Snap and zone-window switching, "
            . "configures the two switching shortcuts, and leaves your Zone index / "
            . "Relative position choice unchanged. Layouts and unrelated settings "
            . "stay unchanged.`n`n"
            . "Close PowerToys Settings before choosing Yes. An exact backup "
            . "will be saved beside settings.json. No leaves everything unchanged.",
            "Wonder Windows", "YesNo Default2 Icon?"
        )
        if response != "Yes"
            return

        state := WW_ReadFancyZonesIntegrationState("Apply")
        if state && WW_FancyZonesArrowsReady(state) && WW_FancyZonesSwitchingReady(state) {
            WW_fancyzones_integration_state := state
        } else {
            MsgBox(
                "FancyZones setup could not be completed. Check the debug log "
                . "or configure the shortcuts manually in PowerToys.",
                "Wonder Windows", "Icon!"
            )
        }
    }
    finally {
        WW_fancyzones_check_in_progress := false
        ; Keep bare Win+Arrow in this script even when FancyZones starts later.
        WW_ReassertFancyZonesKeyboardHook()
    }
}

WW_IsFancyZonesRunning()
{
    return !!ProcessExist("PowerToys.FancyZones.exe")
}

WW_GetFancyZonesArrowShortcutLabel(state)
{
    return state && !state.relative_position_enabled
        ? "Ctrl + Alt + Left/Right"
        : "Ctrl + Alt + Arrow"
}

WW_FancyZonesArrowsReady(state)
{
    return state && state.override_snap_enabled
}

WW_FancyZonesSwitchingReady(state)
{
    return state && state.window_switching_enabled
        && WW_IsDesiredFancyZonesHotkey(state.previous_hotkey, 33)
        && WW_IsDesiredFancyZonesHotkey(state.next_hotkey, 34)
}

WW_IsDesiredFancyZonesHotkey(hotkey, code)
{
    return !hotkey.win && hotkey.ctrl && hotkey.alt && !hotkey.shift && hotkey.code = code
}

; =============================================================================
; forwarding without triggering our own Win+Arrow bindings
; =============================================================================

WW_MoveWindowThroughFancyZones(direction)
{
    global WW_fancyzones_process_id, WW_fancyzones_integration_state
    if !WW_FancyZonesArrowsReady(WW_fancyzones_integration_state)
        return
    ; Recheck only an invoked command, not every #HotIf evaluation. The watcher
    ; will detect a later process restart and run its compatibility check again.
    if ProcessExist("PowerToys.FancyZones.exe") != WW_fancyzones_process_id
        return

    ; Zone index uses only Win+Left/Right. Relative position uses all four
    ; arrows. Respect the user's PowerToys navigation mode instead of changing it.
    if !WW_fancyzones_integration_state.relative_position_enabled
        && (StrLower(direction) = "up" || StrLower(direction) = "down")
    {
        return
    }

    hwnd := WW_GetWindowControlTarget()
    if !hwnd
        return

    try {
        WW_RunWindowCommand(WW_PrepareWindowForPlacement, hwnd)
        WW_ForgetWindowLayoutCycle(hwnd)

        ; Forward Ctrl+Alt+Arrow as plain Win+Arrow for FancyZones. Temporarily
        ; release Ctrl and Alt first. Blind mode prevents an
        ; immediate automatic modifier restore before FancyZones processes its queue.
        SendEvent("{Blind}{vkE8}{LCtrl up}{RCtrl up}{LAlt up}{RAlt up}#{" direction "}")
        Sleep 40
    }
    catch Error as err {
        WW_DebugError("Forward FancyZones navigation", err)
    }
    finally {
        ; Restore only modifiers the user still physically holds.
        for key in ["LCtrl", "RCtrl", "LAlt", "RAlt"] {
            if GetKeyState(key, "P")
                SendEvent("{Blind}{" key " down}")
        }
    }
}

; =============================================================================
; settings bridge
; =============================================================================

WW_ReadFancyZonesIntegrationState(mode := "Read")
{
    local_app_data := EnvGet("LOCALAPPDATA")
    fancyzones_settings_path := local_app_data "\Microsoft\PowerToys\FancyZones\settings.json"
    helper_path := A_ScriptDir "\modules\wonder-windows\fancyzones-settings.ps1"
    powershell_path := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(fancyzones_settings_path) || !FileExist(helper_path) || !FileExist(powershell_path)
        return false

    result_path := A_Temp "\wonder-windows-fancyzones-"
        . DllCall("GetCurrentProcessId", "uint") "-" A_TickCount ".txt"

    ; Bypass applies only to this helper process; no stored execution policy is
    ; changed. The helper is a local part of this package, never downloaded code.
    command := '"' powershell_path '" -NoLogo -NoProfile -NonInteractive'
        . ' -WindowStyle Hidden -ExecutionPolicy Bypass -File "' helper_path '"'
        . ' -Mode ' mode ' -SettingsPath "' fancyzones_settings_path '" -ResultPath "' result_path '"'

    try {
        exit_code := RunWait(command, , "Hide")
        result := FileExist(result_path) ? Trim(FileRead(result_path, "UTF-8")) : ""
        if exit_code != 0 {
            WW_DebugLog("FancyZones helper failed. " result)
            return false
        }
        lines := StrSplit(result, "`n", "`r")
        fields := StrSplit(lines[1], ",")
        if fields.Length != 13
            return false
        if mode = "Apply" && lines.Length >= 2
            WW_DebugLog("FancyZones settings backup: " lines[2])

        return {
            override_snap_enabled: fields[1] = "1",
            relative_position_enabled: fields[2] = "1",
            window_switching_enabled: fields[3] = "1",
            previous_hotkey: {
                win: fields[4] = "1", ctrl: fields[5] = "1",
                alt: fields[6] = "1", shift: fields[7] = "1", code: fields[8] + 0
            },
            next_hotkey: {
                win: fields[9] = "1", ctrl: fields[10] = "1",
                alt: fields[11] = "1", shift: fields[12] = "1", code: fields[13] + 0
            }
        }
    }
    catch Error as err {
        WW_DebugError("Read FancyZones setup", err)
        return false
    }
    finally {
        try FileDelete(result_path)
    }
}
