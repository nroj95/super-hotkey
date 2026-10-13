# implementation sequence

## 1. establish the shared owner

adapt the existing Keybindings parser, conflict validation, recorder, persistence, and editor for one local action catalog. remove peer discovery, per-owner coordination, remote editing, and service heartbeats from the suite's runtime path. namespace action IDs and separate action availability from saved user enablement.

build core settings, a small rotating logger, the tray, and the launcher. initialize enabled modules at startup; keep the editor accessible from the tray even after a configuration error. do not activate a partial conflicting keymap.

## 2. migrate keyboard layers

preserve held chords, short-tap one-shot behavior, physical releases, cancellation, and synthesized-key cleanup. connect the state machine to the manager in process, rather than retaining the service/client transport.

a disabled layer module installs no CapsLock/Pause/CtrlBreak interception. layer assignments remain visible and editable; replacing one with an ordinary shortcut works without enabling layers. do not clear a saved assignment because its layer is unavailable.

## 3. migrate features incrementally

adapt Power Hotkey to accept the shared manager and remove its independent startup, migration prompt, tray, and manager shutdown. resolve factory-default collisions explicitly before restoring initial assignments. preserve deferred dispatch, foreground identity checks, and output cleanup.

adapt Window Cascade's initialization and cleanup while retaining its placement engine. namespace the short action IDs. coordinate process-wide window defaults, hooks, timers, diagnostics, and restoration of script-hidden windows.

adapt Scratchpad's controller and dedicated Notepad3 editor without replacing its checked save path. preserve editor-scoped shortcuts. centralize only the ownership and configuration after contextual binding rules are designed. document the external editor dependency; one AutoHotkey process does not imply that Notepad3 disappears.

## 4. settings and release checks

| check | expected result |
| --- | --- |
| fresh settings | all four modules enabled, collision-free defaults |
| disable one module and restart | no module actions, hooks, or timers remain active; assignments retained |
| disable layers | native CapsLock/Pause; ordinary shortcuts and Keybindings still usable |
| rebind an inactive layer shortcut | ordinary replacement works without layers |
| re-enable a module | existing assignments restored only after conflict validation |
| reset all shortcuts | default assignments restored after confirmation; notes preserved |
| restore factory defaults | modules/settings reset after confirmation; notes and other personal data preserved |
| pending/held inputs on restart, sleep, or exit | pending actions canceled and synthesized keys released |
| Scratchpad save conflict | no silent overwrite; unsaved work remains recoverable |
| runtime failures | timestamp, module, exception context and stack in the shared log |
| manual regression | compare every migrated action with the pinned original on Windows |

no automated test result substitutes for native multi-monitor, keyboard-hook, input-context, or Notepad3 testing. do not retire the old repositories until the suite passes these checks in ordinary use.
