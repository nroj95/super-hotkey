# Super Hotkey

a small AutoHotkey v2 suite for the Windows shortcuts and window behavior i wanted.

built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; i design, direct and test it.

| module | purpose |
| --- | --- |
| Cascade Kingdom | arrange new windows in cascades |
| Wonder Windows | position, stretch, focus and swap windows |
| Power-Up Utilities | extra keys, text shortcuts and system utilities |
| Paper Pad | a quick-notes drawer using Notepad3 |
| Secret Layers | use CapsLock and Pause as extra keyboard layers |

## start

install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, extract the complete project, and run `super-hotkey.ahk`. close older standalone copies of these utilities first.

right-click the tray icon for module guides and settings. open **Keybindings** with `Ctrl + Alt + K` to inspect or change assignments. all modules start enabled; disable the ones you do not need under **Modules...**. Paper Pad requires Notepad3; setup appears when it cannot find it.

settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`; notes are stored separately. the tray's **Suspend** releases hotkeys without discarding your settings.

## develop

edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) maps the architecture and its rules. `python tests/check.py` runs every check in dry-run mode, with disposable settings and without touching your notes.

code: [MIT](LICENSE). icon: [FatCow attribution](assets/ATTRIBUTION.md).
