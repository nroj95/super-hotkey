#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include "%A_ScriptDir%\..\lib\keybindings.ahk"

; Requires the separate unified-preview.ahk peer process to be running for
; `present` mode. Uses only the preview TEMP registry, never real user settings.
probeOutputPath := A_Args.Length >= 2
    ? A_Args[2] : A_Temp "\nroj-keybindings-owner-probe.log"
probeManager := 0
try {
    requestedState := A_Args.Length ? StrLower(A_Args[1]) : "present"
    if requestedState != "present" && requestedState != "absent"
        throw ValueError("Use present or absent.")
    probeRoot := A_Temp "\nroj-keybindings-unified-preview"
    probeManager := Keybindings("unified-protocol-probe", "Protocol Probe",
        {directory: probeRoot})
    probeManager.Start()
    participants := probeManager.DiscoverParticipants()
    foundPeer := false
    for participant in participants {
        if participant.id != "unified-preview-peer"
            continue
        if !participant.controlReady
            throw Error("Preview Peer is running, but its owner-control channel did not respond.")
        foundPeer := true
        break
    }
    if (requestedState = "present" && !foundPeer)
        throw Error("Start Preview Peer before running the present probe.")
    if (requestedState = "absent" && foundPeer)
        throw Error("Stop Preview Peer before running the absent probe.")
    FileAppend("PASS: owner-control probe (" requestedState ").`n", probeOutputPath, "UTF-8-RAW")
    probeManager.Stop()
    ExitApp 0
} catch Error as probeError {
    FileAppend("FAIL: " probeError.Message "`n" probeError.Stack "`n", probeOutputPath, "UTF-8-RAW")
    if IsObject(probeManager)
        probeManager.Stop()
    ExitApp 1
}