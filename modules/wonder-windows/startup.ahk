WW_IsFancyZonesRunning()
{
    return !!ProcessExist("PowerToys.FancyZones.exe")
}

; FancyZones is not supported: it also moves windows (new windows, display
; changes) and takes hotkeys, competing with Wonder Windows and Cascade
; Kingdom. Say so once per FancyZones process and never touch its settings.
WW_CheckFancyZones()
{
    global WW_fancyzones_process_id
    process_id := ProcessExist("PowerToys.FancyZones.exe")
    if process_id = WW_fancyzones_process_id
        return
    WW_fancyzones_process_id := process_id
    if !process_id
        return
    SuiteState.Log.Write("Wonder Windows", "FancyZones is running; it is not supported")
    SuiteNotice.Show("status", "FancyZones isn't supported alongside Super Hotkey", 5000)
}
