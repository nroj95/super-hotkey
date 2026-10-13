#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include "%A_ScriptDir%\..\lib\keybindings.ahk"

; Run alongside unified-preview.ahk peer. Uses only the TEMP preview registry.
reportPath := A_Args.Length ? A_Args[1] : A_Temp "\nroj-keybindings-slot-probe.log"
probeManager := 0
try {
    root := A_Temp "\nroj-keybindings-unified-preview"
    probeManager := Keybindings("unified-edit-probe", "Remote Edit Probe", {directory: root})
    probeManager.Start()
    peer := 0
    for participant in probeManager.DiscoverParticipants()
        if participant.id = "unified-preview-peer"
            peer := participant
    if !IsObject(peer) || !peer.controlReady
        throw Error("Start Preview Peer with the new library before testing remote edits.")

    original := peer.actions[1].bindings[1]
    proposed := Keybindings.Parse("Ctrl + Alt + F9").signature

    ; Recover a previous interrupted test before starting another.
    if original = proposed {
        if probeManager.RequestRemoteSlotEdit(peer, "preview.one", 1, "") != 1
            throw Error("Could not restore the previous test binding.")

        peer := 0
        for participant in probeManager.DiscoverParticipants()
            if participant.id = "unified-preview-peer"
                peer := participant

        if !IsObject(peer)
            throw Error("Preview Peer disappeared during recovery.")

        original := peer.actions[1].bindings[1]
    }

    if original != ""
        throw Error("Preview Peer has an unexpected existing binding.")

    ; A peer that restarted after discovery must not receive the old edit.
    if !peer.pid || !peer.hwnd
        throw Error("Preview Peer did not publish a process/window identity.")
    genuinePid := peer.pid
    try {
        peer.pid := genuinePid + 1
        if probeManager.RequestRemoteSlotEdit(peer, "preview.one", 1, proposed) != 4
            throw Error("A request from a mismatched peer PID was not rejected.")
    }
    finally {
        peer.pid := genuinePid
    }
    genuineHwnd := peer.hwnd
    try {
        peer.hwnd := genuineHwnd + 1
        if probeManager.RequestRemoteSlotEdit(peer, "preview.one", 1, proposed) != 4
            throw Error("A request from a mismatched peer window was not rejected.")
    }
    finally {
        peer.hwnd := genuineHwnd
    }

    if probeManager.RequestRemoteSlotEdit(peer, "preview.one", 1, proposed) != 1
        throw Error("Owner did not accept the first edit.")
    if probeManager.RequestRemoteSlotEdit(peer, "preview.one", 1, "") != 2
        throw Error("Stale request was not rejected.")

    updatedPeer := 0
    for participant in probeManager.DiscoverParticipants()
        if participant.id = "unified-preview-peer"
            updatedPeer := participant
    if !IsObject(updatedPeer) || updatedPeer.actions[1].bindings[1] != proposed
        throw Error("The owning process did not persist the new binding.")
    if probeManager.RequestRemoteSlotEdit(updatedPeer, "preview.one", 1, "") != 1
        throw Error("Owner did not accept the undo request.")
    finalPeer := 0
    for participant in probeManager.DiscoverParticipants()
        if participant.id = "unified-preview-peer"
            finalPeer := participant
    if !IsObject(finalPeer) || finalPeer.actions[1].bindings[1] != ""
        throw Error("Preview Peer binding was not restored to unassigned.")

    probeManager.Stop()
    FileAppend("PASS: remote slot update, stale edit rejection, and undo.`n", reportPath, "UTF-8-RAW")
    ExitApp 0
}
catch Error as probeError {
    try FileAppend("FAIL: " probeError.Message "`n" probeError.Stack "`n", reportPath, "UTF-8-RAW")
    if IsObject(probeManager)
        probeManager.Stop()
    ExitApp 1
}