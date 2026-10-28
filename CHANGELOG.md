# Changelog

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
