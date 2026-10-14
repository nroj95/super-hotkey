# integration status

## Super Hotkey v1.0.0 draft

five modules: Cascade Kingdom, Wonder Windows, Power-Up Utilities, Paper Pad and Secret Keys. one launcher, one AutoHotkey process, one tray, one Keybindings editor and shared diagnostics. the five Getting started pages contain module-specific guidance; their footer buttons open Settings and Keybindings as appropriate.

module and layer toggles preserve bindings. inactive hotkeys do not fire. the tray provides a persistent verbose-logging preference, a temporary Suspend hotkeys toggle, a startup shortcut toggle, Restart Super Hotkey and separately confirmed reset actions. default data is stored under `%LOCALAPPDATA%\nroj\SuperHotkey`. older suite/standalone settings are not auto-imported.

## verification boundaries

`python tests/check.py` runs portable structural tests, parses all included AHK modules and executes isolated native/GUI checks. native tests use temporary preferences, inert callbacks and test-owned windows. no personal notes, external applications or real power actions are modified.

automated checks cannot guarantee physical keyboard behavior, actual Notepad3 save parity, multi-monitor placement, Windows startup-link operation, or power suspend/resume behavior.

## remaining manual acceptance

1. verify the flat tray and Getting started pages, centered/resizeable windows, Keybindings controls and shared icon. test module-disabled states.
2. test each CapsLock/Pause combination and their held/one-shot modes; disabled layers must return normal keys. test the tray Suspend hotkeys and resume functions.
3. test Wonder Windows layouts, stretch, focus and swap against Cascade Kingdom on actual displays, including explicit adoption and drag placement.
4. use disposable Paper Pad pages: new, save, switch, hide, exit/restart, conflicting on-disk changes and unresolved Notepad3 dialogs. ensure editor-only hotkeys are contextual.
5. test both confirmed reset operations, verbose logging, startup checkbox, saving settings in the new data root and resuming from Windows sleep/unlock.

keep `main` as the migration checkpoint until desktop acceptance and a release are explicitly approved. never delete standalone repositories or personal files as part of repository cleanup.
