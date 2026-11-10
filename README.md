# Super Hotkey

A small AutoHotkey v2 suite for window management, quick notes and everyday keyboard shortcuts I found useful.

Built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; I design, direct and test it.

![Super Hotkey arranging, switching and stretching windows](assets/super-hotkey-showcase.gif)

*This recording shows v1.0.0-beta.1; some keys and behavior have changed since. I'll record a new one once things settle.*

## Modules

Use any module on its own or combine them.

| Module | Purpose |
| --- | --- |
| [Wonder Windows](#wonder-windows) | Position, size, stack and cycle windows |
| [Cascade Kingdom](#cascade-kingdom) | Keep many windows in an overlapping cascade |
| [Paper Pad](#paper-pad) | A quick-notes drawer using Notepad3 |
| [Power-Up Utilities](#power-up-utilities) | Extra keys, text shortcuts and system utilities |
| [Secret Layers](#secret-layers) | Use CapsLock and Pause as extra keyboard layers |

Each module's full guide, with its settings and hotkeys, opens from its name in the tray menu.

### Wonder Windows

#### Why

There are plenty of window managers for Windows, but the ones I tried tiled windows smaller than I liked, took a while to learn, or spread things across so many workspaces that I lost track of them. Small costs, but they added up. This is my take on window management that builds on the `Win` key shortcuts you already know and makes the ones I found frustrating or incomplete more predictable.

#### Get started

- Press `Win + Left` or `Win + Right` and keep holding `Win`: the arrows slide the window between halves, thirds and fourths, and `Shift` with an arrow makes it bigger or smaller. Windows always fit together.
- `Win + Up` maximizes, and `Win + Down` takes a window back to normal size but never minimizes; `Win + Backspace` does that.
- Press `Win + M`, then `Win + Shift + M`: only your display clears, and everything comes back in order.
- `Win + Enter` shows the next maximized or fullscreen window on your display and minimizes the others, so one big window is out at a time.
- `Win + Alt` with an arrow stacks a window onto its nearest neighbor, and `Win + Shift + PgDn` cycles through the stack.
- `Win + PgUp/PgDn` steps focus through every window on screen, and double-tapping `Caps` outlines where you are.

### Cascade Kingdom

#### Why

I wanted to keep many windows large and neatly organized, and switch between them without digging through a pile. A cascade keeps every window at 80% of the display's width and height, however many you add, stepping down to the right, or to the left with Mirror in Settings.

With two displays, for example, keep focused work in narrow zones on one, wide apps like file managers, video players or Discord on the other, and secondary apps in a cascade on whichever display you choose in Settings.

#### Get started

- Press `Caps + Insert` to add the active window, or hold `Caps` and double-click any window. `Caps + Shift + Insert`, or another double-click, takes it out and puts it back where it was.
- Click a slot's focus tab, at its lower left or upper right, to bring its window forward, and click again to cycle through the windows sharing that slot.
- `Caps + PgUp/PgDn` steps through the cascade's windows, and `Caps + Tab` jumps to the next cascade, on whichever display it is.
- `Caps + M` hides the cascade on your display, and `Caps + Shift + M` brings it back.

### Paper Pad

#### Why

I wanted a place to jot down anything, anytime, without worrying about saving files or finding notes buried in windows and tabs.

#### Get started

- Press `Win + F12` or `Caps + F12` to show or hide the drawer, a dedicated Notepad3 window that stays on top while it's open. It needs [Notepad3](https://www.rizonesoft.com/downloads/notepad3/) and asks you to install or locate it when it can't find it.
- `Ctrl + N` creates a timestamped page, and `Win + Left/Right` move between pages.
- Changes are saved when you switch pages, hide the drawer or exit, and pages stay ordinary files in your notes folder.

### Power-Up Utilities

#### Why

Practical shortcuts for everyday tasks that didn't fit into the other modules.

#### Get started

- `Pause + Escape` puts the computer to sleep, and `Pause + Pause` turns the displays off until you touch the mouse or keyboard.
- `Pause + End` keeps the computer awake for 30 minutes and then puts it to sleep; press again while the notice shows for 1, 2, 4 or 8 hours or no limit. `Pause + Shift + End` stops it without sleeping.
- `Pause + T` inserts a timestamp and `Pause + -` an en dash, without looking them up.
- Send F13-F24 or use a virtual number pad, even if your keyboard doesn't have those keys.
- In Windows Terminal, `Caps + C` copies the buffer as Markdown and `Caps + K` clears it.

### Secret Layers

#### Why

I wanted to get more out of the keyboard I have: CapsLock and Pause unlock a whole new set of hotkeys without adding keys.

#### Get started

- Hold `Caps` or `Pause` and press another key, or tap it first so you don't have to hold both. Every `Caps` and `Pause` hotkey uses these layers.
- Double-tap `Shift` to toggle Caps Lock.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**.
2. Download the newest [release](https://github.com/nroj95/super-hotkey/releases), extract it and run `super-hotkey.ahk`.
3. Right-click the tray icon and check **Run at startup** to have it ready after every sign-in.

Press `Ctrl + Alt + K` to see and change your hotkeys, and `Pause + F4` to suspend or resume Super Hotkey. The tray icon also has **Modules...**, where you can turn off what you don't need, and **Language...**. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`.

## Compatibility

Other window managers and tiling tools can conflict with Super Hotkey when they also move windows, rearrange them after display changes, or use the same hotkeys.

PowerToys FancyZones does all three, so it isn't supported; disable it in PowerToys. Zone mode covers what it did.

## Develop

Edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) explains the architecture. Run `python tests/check.py` before committing.

To translate Super Hotkey into your language, see [lang/README.md](lang/README.md).

Super Hotkey is free, and I'll never charge for it. The official source is [github.com/nroj95/super-hotkey](https://github.com/nroj95/super-hotkey); a paid version anywhere else doesn't come from me.

Code: [MIT](LICENSE). Icon: [FatCow attribution](assets/ATTRIBUTION.md).
