# initial source audit

reviewed October 13, 2026. **coverage: repository trees, dependencies, selected entry points, registration code, and startup/lifecycle sections.** this is not a complete function-by-function audit, Windows runtime test, or completed integration.

## pinned sources

| source | commit |
| --- | --- |
| Keybindings | `42261fa924c74ccd0c5887ff3408c03cbcc6c0d0` |
| Power Hotkey | `8838312c1096efbf055a72d79f1bf715aed9297c` |
| Window Cascade | `4153235e454e204a21c04766822a7032a37df02a` |
| Scratchpad | `b26a252b82d11dc965f60717f564bffed6a4eadc` |
| Caps + Pause Layers | `f674ff57543b8ddbadac49b43d7248c89581c003` |

these were the resolved `main` commits at inspection. the initializer deliberately fetches these exact commits, not a moving branch. unpublished local edits are outside this snapshot.

## integration findings

### one manager really means one instance

`Keybindings.__New()` rejects a second manager using `Keybindings.Current`. Power Hotkey constructs its own manager, and `InitializeCascadeKeybindings()` constructs another. simply including both implementations in one script cannot provide the planned shared runtime. inject the single manager and split action registration from manager startup/shutdown. [1, 2, 3]

### existing Keybindings includes cross-process infrastructure

startup creates owner/registry mutexes and message handlers. discovery, remote edits, capture coordination, and maintenance belong to the old independent-process design. preserve the parser/recorder/editor and conflict rules while replacing the coordination layer with a local catalog. inspect the rest of the class before cutting those paths; this audit did not review every method. [1]

### Power Hotkey does not currently use its advertised legacy defaults

`PowerHotkeys.AddAction()` receives a `defaultBinding` but passes an empty slot array to `manager.AddAction()`. the factory catalog therefore needs deliberate reconstruction; copying the current registration verbatim will not give the requested useful first-launch defaults. its startup also contains legacy settings migration and a separately offered F-key preset. those should not become hidden suite startup behavior. [2, 4]

### a real factory-default collision needs a decision

Window Cascade assigns `Caps + K` to opening Keybindings. Power Hotkey's catalog lists `Caps + K` for clearing Windows Terminal, though it currently does not activate that catalog default. blindly restoring both defaults would conflict. proposed suite default: keep `Caps + K` for the core Keybindings action and assign terminal clearing `Caps + Ctrl + K`. **this is a proposed new factory default, not a change to saved user assignments.** validate every default together before activation. [3, 4]

### Window Cascade uses short action IDs

its actions include `swap-up`, `help`, and `keybindings` without a module namespace. use globally unique IDs such as `window-cascade.swap-up` in the suite. opening the shared editor should become one core action rather than multiple copies. retain an explicit mapping if old saved assignments are later imported. [3]

### Scratchpad has contextual shortcuts and an external editor

Scratchpad controls a dedicated Notepad3 window; its source specifies 64-bit AutoHotkey v2 and Notepad3 7.26.602.1. the toggle is a global shortcut, but Escape, save/new/delete and navigation are guarded by `#HotIf` editor/context checks. the existing Keybindings header describes global-only contexts. promoting those editor controls directly into global actions would change behavior. design their context handling explicitly. the suite can still use one AutoHotkey process while retaining the Notepad3 editor process. [1, 5]

### startup defaults and shutdown ownership must be reconciled

Window Cascade starts from its entry point, sets `SetWinDelay 0`, builds a tray, installs hooks, and owns exit cleanup. Scratchpad also starts from its entry point, sets `DetectHiddenWindows True`, `SetTitleMatchMode 2`, `SetWinDelay -1`, and `SetControlDelay -1`, then constructs its controller. Power Hotkey has an include guard, but its `Start()` owns tray/power/exit behavior. move lifecycle decisions into the launcher and review the shared thread defaults instead of relying on include order. [2, 5, 6]

### keyboard layers are currently a service, not just prefix bindings

Caps + Pause Layers owns a named mutex, hidden IPC endpoint, client leases, session notifications, prefix interception, and its own tray. it supports held chords and short-tap one-shot mode, including release suppression. keep that behavior when replacing client/service messages with in-process calls. disabling the module must avoid prefix registration entirely; merely suppressing its feature callbacks would not preserve native keys. [7]

### protect Scratchpad data during configuration work

Scratchpad uses separate controller settings, state, an editor profile, and a configurable scratch directory. source comments describe checked saves and conflict handling. never implement factory reset as recursive deletion of a broad application-data directory. define a whitelist of resettable settings and preserve notes, profiles and backups. complete save/exit behavior still needs review and native testing. [5]

## sources

all references are immutable upstream source links. they are also present under `migration/upstream/` after setup.

1. https://github.com/nroj95/keybindings/blob/42261fa924c74ccd0c5887ff3408c03cbcc6c0d0/lib/keybindings.ahk
2. https://github.com/nroj95/power-hotkey/blob/8838312c1096efbf055a72d79f1bf715aed9297c/power-hotkey.ahk
3. https://github.com/nroj95/window-cascade/blob/4153235e454e204a21c04766822a7032a37df02a/window-cascade/keybindings.ahk
4. https://github.com/nroj95/power-hotkey/blob/8838312c1096efbf055a72d79f1bf715aed9297c/power-hotkey/modules.ahk
5. https://github.com/nroj95/scratchpad/blob/b26a252b82d11dc965f60717f564bffed6a4eadc/scratchpad.ahk
6. https://github.com/nroj95/window-cascade/blob/4153235e454e204a21c04766822a7032a37df02a/window-cascade.ahk
7. https://github.com/nroj95/caps-pause-layers/blob/f674ff57543b8ddbadac49b43d7248c89581c003/caps-pause-layers.ahk
