# Super Hotkey

a small AutoHotkey v2 suite for the Windows shortcuts and window behavior i wanted.

built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; i design, direct and test it.

![Super Hotkey arranging, switching and stretching windows](assets/super-hotkey-showcase.gif)

## when it helps

keeping every window visible can leave too little room to work. Super Hotkey lets you keep windows comfortably sized and bring others forward when you need them.

cycle through stacked windows in your main workspace, or keep secondary apps in a cascade you can hide and restore together. the cascade helps most when you have many apps open.

| need | how |
| --- | --- |
| keep main apps large | Wonder Windows positions, stretches and swaps them; `Win + Enter` cycles the windows stacked with the active one |
| keep many apps nearby | Cascade Kingdom overlaps them in a cascade, so more windows add depth instead of shrinking the rest |
| reach a buried window | click its colored focus tab to bring it forward; click again to cycle through the windows behind it |
| clear the screen | `Caps + M` hides the whole cascade and brings it back together |

if you'd rather see every window at once, a tiling layout fits better. `Caps` hotkeys use the CapsLock layer from Secret Layers.

## modules

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

Super Hotkey is free, and i'll never charge for it. the official source is [github.com/nroj95/super-hotkey](https://github.com/nroj95/super-hotkey); a paid version anywhere else doesn't come from me.

code: [MIT](LICENSE). icon: [FatCow attribution](assets/ATTRIBUTION.md).
