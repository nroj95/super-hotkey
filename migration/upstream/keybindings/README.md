# Keybindings

An experimental, opt-in AutoHotkey v2 library for configurable shortcuts, conflict detection, and a Minecraft-style keybinding editor. Scripts remain independent: there is no central controller, background Keybindings service, or global configuration writer.

**Status:** `0.2.0-preview.6`. The API and on-disk protocol are still experimental. This is not a stable release.

## What it provides

- Two editable shortcut slots per action, with immediate persistence and optional Caps/Pause layer support.
- A unified, searchable settings window containing actions from other **running** scripts that use a compatible Keybindings library and the same settings directory.
- Remote editing through the owning process. Each script validates and saves its own changes; the window never directly edits another script's INI file.
- Conflict checks across local actions and participating scripts. Active conflicts are rejected; saved assignments belonging to unavailable scripts can produce warnings.
- A native scrollbar, keyboard/mouse recording, and a fixed footer. A **Refresh** button updates the participant list; the list is not continuously polled.

## Integrating a script

Include the library, create one manager per process, register the actions, then start it:

```autohotkey
#Requires AutoHotkey v2.0
#Include "lib\keybindings.ahk"

manager := Keybindings("my-script", "My Script")
manager.AddAction("my-script.open", "Open panel", (*) => MsgBox("Opened"), ["Ctrl + Alt + J"])
manager.Start()
manager.ShowSettings()
Persistent true
```

Call `manager.Stop()` when shutting down if the script does not exit immediately. For optional Caps/Pause shortcuts, provide a compatible `layerFactory`; the library does **not** start or install that service. See `lib/keybindings.ahk` for the `AddAction()` options and layer adapter contract.

Scripts must share the same Keybindings settings root to appear together. By default, it is:

```text
%LOCALAPPDATA%\nroj\AutoHotkey\keybindings-v1
```

The optional constructor argument `{directory: "C:\absolute\path"}` selects a different root. Owner IDs must be unique within that root. Participating scripts must be restarted after updating their bundled library copy; an old process does not dynamically load the new implementation.

## Unified editing and safety

Open `ShowSettings()` from any participating script and press **Refresh** to rediscover running owners. A peer is editable only if its control handshake succeeds; older or unavailable peers may be shown as **view only**. Each script retains authority over its own action enablement, defaults, and saved file. **Reset mine** and per-action **reset** apply to the window owner's actions only.

A remote edit is sent to the owning process with a bounded Windows message. The owner compares the action's enabled state and prior shortcut before applying the new one. If the value has changed, the request is rejected rather than overwriting a newer choice. The sender also checks the participant's original process ID and window handle so a restarted script cannot silently inherit a pending edit. A timeout is ambiguous: **refresh instead of automatically retrying**.

While recording, use these controls:

| Input | Behavior |
| --- | --- |
| **Esc**, **left click**, or **right click** | Cancel without changing the saved shortcut |
| **Backspace** or **Delete** | Clear the selected slot |
| Supported keyboard combination | Capture the shortcut |
| **XButton1/XButton2** | Capture as ordinary mouse shortcuts |
| Unmodified **middle click** or **mouse wheel** | Ask for confirmation, with **No** selected by default |

`LButton` and `RButton` are **never assignable**, including from defaults or saved configuration. This is deliberately stricter than older previews: an existing INI containing one of those shortcuts must be corrected before that script can start. The library fails closed rather than silently rewriting a damaged or unsupported configuration. For mouse shortcuts with modifiers, standard binding and conflict rules still apply.

The editor captures physical scan codes where possible; available modifiers are Ctrl, Alt, Shift, and Win. Caps/Pause layer shortcuts require a compatible layer client. Windows-reserved combinations and unsupported expressions are rejected. Participating scripts should not simultaneously register hardcoded hotkeys for the same inputs outside this manager.

## Testing

Run the isolated parser, persistence, ownership, and regression checks:

```powershell
pwsh -NoProfile -File .\tests\check-keybindings.ps1
```

To exercise two real processes manually, start `tests/unified-preview.ahk` once with `peer` and once with `host`. The preview uses `%TEMP%\nroj-keybindings-unified-preview`, isolated from real Keybindings settings. The host opens the unified GUI automatically. Exit old preview instances before launching replacements.

The live remote-edit probe (`tests/remote-slot-probe.ahk`) checks an owner-mediated update, stale-request rejection, and undo. Run it alongside a fresh Preview Peer; the test action must initially be unassigned.

For a real **owner restart during recording**, run:

```powershell
pwsh -NoProfile -File .\tests\restart-during-recording.ps1
```

This starts a Host and Peer in a **unique temporary registry**, waits for you to begin recording a Peer shortcut, stops and restarts only the Peer process it launched, and asks you to finish recording. An edit captured for the previous instance must be rejected and the saved Peer shortcut must remain unchanged. The test cleans up its own processes and temporary directory; it never touches the normal configuration directory.

## Limitations

- Only running scripts with a compatible Keybindings version and matching settings root participate in the unified window.
- The recorder supports two slots per action, not sequences, hotstrings, joystick inputs, or arbitrary AutoHotkey expressions.
- Cross-process control is cooperative same-user IPC, **not** a security boundary against hostile code running as the same user.
- Timeouts and script exits can interrupt a remote edit. Reopen or refresh the window to retrieve current state.
- Preview APIs and the registry schema can change before a stable release.
