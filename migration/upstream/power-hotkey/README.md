# Power Hotkey

experimental AutoHotkey v2 application providing optional, configurable keyboard utilities and macros.

all 33 actions are visible in the unified Keybindings window under their original categories.
Every action begins without a shortcut on new installations; existing enabled
assignments are preserved. The first migration backs up the original INI file
next to it with a `.legacy-*.bak` suffix. Previously disabled shortcuts are not
activated automatically. Caps + Pause Layers remains optional.

The classic F13-F24 preset is optional. On a new eligible installation, Power
Hotkey offers Caps + QWER / ASDF / ZXCV only while Caps + Pause Layers is
available and none of those 12 actions has ever been explicitly edited, including
clearing an empty slot. Declining is remembered. An existing/legacy installation
is not offered historical defaults automatically; the tray menu provides an
explicit **Classic F13-F24 layout...** action for later use. Conflicts reject the
whole preset, never only part of it.

**status:** early development. functionality and APIs may change.

## testing

```powershell
.\tests\check-power-hotkey.ps1
```

## dependencies

```powershell
.\tools\sync-dependencies.ps1
```
