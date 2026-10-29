# Changelog

## Unreleased

Fewer, smarter hotkeys: this version cuts features that overlapped and hands several keys back to Windows.

### Breaking changes

- If you customized these hotkeys, set them again in Keybindings: Clear log, Copy log, Toggle Caps Lock and Power-Up help have new action IDs and start from their defaults.
- **Paper Pad:** `Win + PgUp` now goes to the previous page and `Win + PgDn` to the next, like PgUp and PgDn everywhere else. Saved hotkeys keep the old order, so swap them in Keybindings.
- **Windows Terminal helpers** send Terminal's default shortcuts (`Ctrl + Shift + A`, `C` and `K`). If you remapped those in Terminal, restore them.

### Changes

- **Wonder Windows:** `Win + Shift + Enter` replaces the stretch actions. It stretches a window across to its neighbors, then into all the free space around it, then back, and Windows' own `Win + Shift + arrows` work again. Swap with neighbor and the maximized and fullscreen cycle are gone, `Win + M` and `Win + Home` belong to Windows again, and stacking on the nearest window also works with `Caps + Win + arrows`.
- **Cascade Kingdom:** windows join a cascade only through `Caps + Insert` or a drop onto a slot. Automatic mode, launching while holding the cascade key, `Caps` + double-click on a title bar and the Cascade key setting are gone, so Cascade Kingdom no longer needs Secret Layers. Active focus tabs and drop guides follow the Windows accent color.
- **Paper Pad** no longer installs Notepad3 or locks the open page; the lock could block sync clients. The slide always takes 180 ms unless Windows' Animation effects are off.
- **Suite windows** use standard Windows title bars and borders. Tray > Debug log opens the log in Notepad, and Keybindings names every action by what it does.

### Fixes

- Clicks are no longer held while a hotkey checks its context, so a busy moment can't delay or drop clicks, for example in the tray menu.
- Windows moved to another display with Windows' own keys stay in the right cascade.
- A hotkey pressed while an overlay pops up in front, such as a shortcut guide shown while Win is held, now acts on the window underneath instead of falling through to another action.
- `&nbsp;` shows correctly in Keybindings.

## v1.0.0-beta.1

The first public test version. Everything described in the [README](README.md) is included, but expect some bugs; I'd be grateful for [reports](https://github.com/nroj95/super-hotkey/issues) of anything that misbehaves.

- **Wonder Windows:** walk windows through zones with `Win + scroll` or `Win + Left/Right`, stack windows and cycle through them with `Win + Enter`, and stretch a window until it meets its neighbors.
- **Cascade Kingdom:** an overlapping cascade where every window keeps 80% of the display, with a focus tab for each slot.
- **Paper Pad:** a quick-notes drawer on `Win + F12`, using a dedicated Notepad3 window and plain files in your notes folder.
- **Power-Up Utilities:** F13-F24, a virtual number pad, special characters, timestamps, Windows Terminal helpers, speaker wake-up and sleep.
- **Secret Layers:** CapsLock and Pause as extra keyboard layers.

Every hotkey can be changed in Keybindings (`Ctrl + Alt + K`), and each module can be turned off under **Modules...** in the tray menu.

### Install

Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, download and extract the source code below, and run `super-hotkey.ahk`. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`, and later versions keep them.

### Known limitations

- PowerToys FancyZones isn't supported; disable it in PowerToys while using Super Hotkey.
- Paper Pad needs Notepad3 and offers to set it up when it can't find it.
