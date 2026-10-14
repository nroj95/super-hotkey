# Super Hotkey

an AutoHotkey v2 64-bit Windows productivity suite: one process, tray icon, Keybindings editor and debug log.

**version 1.0.0 (no GitHub release yet).** the draft integration still needs real-desktop acceptance before publication.

| module | purpose |
| --- | --- |
| Cascade Kingdom | automatic window placement and cascades |
| Wonder Windows | Windows shortcuts, layouts, stretch, swap and navigation |
| Power-Up Utilities | extra keyboard, text and system actions |
| Paper Pad | quick notes in a dedicated Notepad3 drawer |
| Secret Keys | independent CapsLock and Pause shortcut layers |

## start

run `super-hotkey.ahk` with AutoHotkey v2 64-bit. close the standalone replacements first, including Win Key Overhaul. every module is enabled by default; existing suite module choices and shortcut assignments are retained.

```powershell
python .\tests\check.py
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" .\super-hotkey.ahk --dry-run
```

adjust the executable path for your installation. `--dry-run` uses separate temporary preferences, opens the shared editor and keeps real feature effects inactive. omit it only after inspecting the preview. `--check` parses and exits; `--settings` opens Keybindings on a normal launch.

## navigation

the tray is flat: Modules, Keybindings, five Getting started guides, Debug log, Verbose logging, Open settings folder, Run at startup, Suspend hotkeys, Restart Super Hotkey, Reset to defaults and Exit. each module opens its own practical guide first, with relevant navigation at the lower right. all Keybindings links reuse the same global window.

factory shortcuts open Keybindings with **Caps + K** or **Ctrl + Alt + K**. module settings and individual Secret Keys changes apply after restart. inactive shortcuts remain visible and editable. Windows Snap and optional FancyZones changes require confirmation; no compatibility settings are silently changed at startup.

## preferences and safety

suite data remains in `%LOCALAPPDATA%\nroj\SuperHotkeyWorld` so existing settings, shortcut assignments, Paper Pad notes and paths keep working. internal settings ownership and mutex IDs are intentionally stable. the old `super-hotkey-world.ahk` launcher is retained temporarily as a compatibility alias. Paper Pad retains its existing notes folder and dedicated Notepad3 profile. errors are always logged; optional verbose diagnostics use one global switch.

Reset all shortcuts and Reset to defaults are separate confirmed operations. note files, their folder, the editor path, editor profile and page state are preserved. startup, restart, hotkey suspension, reset and settings-folder access live directly in the tray; there is no separate App settings window. Suspend hotkeys temporarily gates configured hotkeys and CapsLock/Pause layers without pausing Paper Pad autosave or other background features; use the tray again to resume. application GUIs use Cascadia Mono; Windows provides native title-bar and tray-menu fonts.

see [integration status](docs/integration-status.md) for manual acceptance checks and [implementation](docs/implementation.md) for architecture. pinned original snapshots, licenses and attribution remain under `migration/upstream`; historical migration scripts are not runtime dependencies and must not be rerun over ongoing development.
