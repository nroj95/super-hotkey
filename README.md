# Super Hotkey

a small AutoHotkey v2 suite for the Windows shortcuts and window behavior i wanted.

built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; i design, direct and test it.

![Super Hotkey arranging, switching and stretching windows](assets/super-hotkey-showcase.gif)

## when it helps

keep windows at sizes that suit what you're doing, whether you work with a few apps side by side or keep many open.

### Wonder Windows

position, stretch and swap windows in your main workspace. zone cycles use fourths and halves by default; Settings offers thirds instead.

windows can sit side by side, with others stacked behind them. `Win + Enter` cycles through the windows stacked with the active one and leaves the other stacks alone.

### Cascade Kingdom

keep windows in an overlapping cascade, which helps most when many apps are open. for example, keep your main apps in place and gather secondary ones into the cascade.

click a colored focus tab to bring its window forward; click it again to cycle through the windows sharing that spot. `Caps + M` hides the cascade and brings it back together.

use either module on its own or combine them. `Caps` hotkeys use the CapsLock layer from Secret Layers.

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

## compatibility

other window managers and tiling tools can conflict with Super Hotkey when they move the same windows or use the same hotkeys.

PowerToys FancyZones isn't supported, so disable it in PowerToys. for `Shift + drag` window placement, i recommend [ScreenGrid](https://github.com/TtesseractT/ScreenGrid): it shows a grid overlay for dropping windows into zones, and Super Hotkey doesn't need it.

## develop

edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) explains the architecture. run `python tests/check.py` before committing.

Super Hotkey is free, and i'll never charge for it. the official source is [github.com/nroj95/super-hotkey](https://github.com/nroj95/super-hotkey); a paid version anywhere else doesn't come from me.

code: [MIT](LICENSE). icon: [FatCow attribution](assets/ATTRIBUTION.md).
