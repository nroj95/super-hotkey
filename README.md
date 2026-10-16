# Super Hotkey

an AutoHotkey v2 64-bit Windows productivity suite with one process, tray icon, Keybindings editor and global debug log.

**version 1.0.0 — draft integration.** not yet released or merged to `main`.

| module | purpose |
| --- | --- |
| Cascade Kingdom | automatic window placement and cascades |
| Wonder Windows | manual window hotkeys, layouts, stretch, swap and navigation |
| Power-Up Utilities | keyboard outputs, text tools and system actions |
| Paper Pad | quick notes in a dedicated Notepad3 drawer |
| Secret Keys | independent CapsLock and Pause hotkey layers |

## run and verify

launch `super-hotkey.ahk` using AutoHotkey v2 64-bit. close any standalone versions of the modules before launching.

```powershell
python .\tests\check.py
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" .\super-hotkey.ahk --dry-run
```

adjust the AutoHotkey executable location if necessary. `--dry-run` uses temporary settings, opens the editor and prevents real feature effects. `--check` parses and exits; `--settings` opens Keybindings when launching normally.

## navigation

the tray contains Modules, Keybindings, five module Getting started pages, Debug log, Verbose logging, Open settings folder, Run at startup, Suspend, Restart Super Hotkey, Reset to defaults and Exit. module Settings and Keybindings are accessible from each module's guide.

double-tap Shift (configurable to Ctrl, Alt or Disabled) toggles Caps Lock while the CapsLock layer is enabled. a separate optional toggle shortcut is in Secret Keys → Keybindings. context-specific categories have a subtle `[scoped]` heading marker. Windows Terminal macros work only in Windows Terminal, and Paper Pad editor shortcuts work only inside the editor. non-overlapping scopes can share shortcuts. narrow scoped shortcuts also override global shortcuts while active; the global shortcut remains available elsewhere. broad inverse scopes still conflict with globals.

default Keybindings hotkeys are **Caps + Alt + K** and **Ctrl + Alt + K**. inactive layer hotkeys remain visible and editable. module and Secret Keys layer changes take effect after restarting. Windows Snap and optional FancyZones changes are never applied at startup without permission.

## data and safety

fresh installations save suite preferences under `%LOCALAPPDATA%\nroj\SuperHotkey`. this checkout does **not** automatically import the previous SuperHotkeyWorld folder or settings from standalone tools. old folders and external personal files are never deleted by the suite.

Paper Pad uses a dedicated Notepad3 profile, and its note files may be kept elsewhere. restoring default hotkeys in Keybindings is separate from the confirmed **Reset to defaults...** tray action. neither reset deletes personal notes or resets their folder, editor preferences or page state. errors are logged even when verbose logging is off.

**Suspend** temporarily pauses hotkeys, keyboard layers and automatic window management without closing modules. windows opened while suspended remain where they are when resumed. Paper Pad autosave and safety functions continue. the native Windows tray and title-bar fonts remain system-controlled; app GUIs use Cascadia Mono.

see [integration status](docs/integration-status.md), [implementation](docs/implementation.md) and [source provenance](docs/source-provenance.md). historical migration snapshots and scripts can be recovered from Git history, rather than occupying the current checkout.
