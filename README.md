# Super Hotkey World

an AutoHotkey v2 64-bit Windows productivity suite: one process, tray icon, Keybindings editor and debug log.

**status: five-module integration preview.** test on your Windows PC before replacing the standalone tools.

| module | purpose |
| --- | --- |
| Cascade Kingdom | automatic window placement and cascades |
| Wonder Windows | Windows shortcuts, layouts, stretch, swap and navigation |
| Power-Up Utilities | extra keyboard, text and system actions |
| Paper Pad | quick notes in a dedicated Notepad3 drawer |
| Secret Keys | independent CapsLock and Pause shortcut layers |

## start

run `super-hotkey-world.ahk` with AutoHotkey v2 64-bit. close the standalone replacements first, including Win Key Overhaul. every module is enabled by default; existing suite module choices and shortcut assignments are retained.

```powershell
python .\tests\check.py
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" .\super-hotkey-world.ahk --dry-run
```

adjust the executable path for your installation. `--dry-run` uses separate temporary preferences, opens the shared editor and keeps real feature effects inactive. omit it only after inspecting the preview. `--check` parses and exits; `--settings` opens Keybindings on a normal launch.

## navigation

the tray is flat: Modules, Keybindings, five module help pages, Debug log and Exit. each module opens How to use first, with relevant navigation at the lower right. all Keybindings links reuse the same global window.

factory shortcuts open Keybindings with **Caps + K** or **Ctrl + Alt + K**. module settings and individual Secret Keys changes apply after restart. inactive shortcuts remain visible and editable. Windows Snap and optional FancyZones changes require confirmation; no compatibility settings are silently changed at startup.

## preferences and safety

suite data lives in `%LOCALAPPDATA%\nroj\SuperHotkeyWorld`. human-facing module names do not change stable action IDs or existing personal paths. Paper Pad retains its existing notes folder and dedicated Notepad3 profile. errors are always logged; optional verbose diagnostics use one global switch.

Reset all shortcuts and Restore factory defaults are separate confirmed operations. note files, their folder, the editor path, editor profile and page state are not reset. App settings, including the single opt-in startup entry, is accessible from Modules.

see [integration status](docs/integration-status.md) for manual acceptance checks and [implementation](docs/implementation.md) for architecture. pinned original snapshots, licenses and attribution remain under `migration/upstream`; historical migration scripts are not runtime dependencies and must not be rerun over ongoing development.
