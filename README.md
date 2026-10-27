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

install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, extract the project and run `super-hotkey.ahk`.

press `Ctrl + Alt + K` to see and change every hotkey. right-click the tray icon for guides, settings and **Modules...**, where you can turn off what you don't need. Paper Pad needs Notepad3 and offers setup when it can't find it.

settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`.

## develop

edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) explains the architecture. run `python tests/check.py` before committing.

code: [MIT](LICENSE). icon: [FatCow attribution](assets/ATTRIBUTION.md).
