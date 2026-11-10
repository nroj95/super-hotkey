# Super Hotkey

A small AutoHotkey v2 suite for managing windows, taking quick notes and adding useful keyboard shortcuts.

Built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; I design, direct and test it.

![Super Hotkey arranging, switching and stretching windows](assets/super-hotkey-showcase.gif)

*This recording shows v1.0.0-beta.1. Some hotkeys and behavior have changed since. I'll record a new one once things settle.*

## Modules

Enable only the modules you want, or use all five together.

| Module | Purpose |
| --- | --- |
| [Wonder Windows](#wonder-windows) | Position, resize, stack and cycle windows |
| [Cascade Kingdom](#cascade-kingdom) | Keep many windows in an overlapping cascade |
| [Paper Pad](#paper-pad) | A quick-notes drawer using Notepad3 |
| [Power-Up Utilities](#power-up-utilities) | Extra keys, text shortcuts and system utilities |
| [Secret Layers](#secret-layers) | Use CapsLock and Pause as extra keyboard layers |

Open a module's guide and settings from its name in the tray menu or with its help hotkey. To see or change all hotkeys, open **Keybindings** with `Ctrl + Alt + K` or `Caps + Alt + K`. The **Get started** sections highlight selected hotkeys. `Pause + Pause` shows what's running or hidden, such as how long the computer stays awake.

### Wonder Windows

My take on Windows' built-in `Win` key shortcuts, with more predictable ways to position, resize and switch between windows.

#### Get started

- `Ctrl + Alt + H` opens the guide.
- Press `Win + Left` or `Win + Right`, then keep holding `Win`. The arrows move the window between zone positions; add `Shift` to grow or shrink it. Zone edges line up neatly.
- `Win + Up` maximizes a window; `Win + Down` returns it to normal size without minimizing it.
- `Win + Backspace` minimizes the active window; `Win + Shift + Backspace` restores windows minimized this way, newest first.
- `Win + M` minimizes windows on the current display; `Win + Shift + M` brings them back.
- `Win + Enter` cycles through maximized or fullscreen windows on the current display, minimizing the others. Add `Shift` to cycle backward.
- `Win + Alt + Arrow` stacks a window onto its nearest neighbor in that direction; `Win + Shift + PgUp/PgDn` cycles through the stack.
- `Win + PgUp/PgDn` steps focus through windows across your displays. Double-tap `Caps` to outline the current window.

### Cascade Kingdom

Sometimes, I want my windows large, organized and easy to switch between. A cascade keeps each window at 80% of a display's width and height by default, staggered to the right (or left if mirrored). You can adjust its size and direction in Settings.

#### Get started

- `Caps + H` opens the guide.
- `Caps + Insert` adds the active window to a cascade; `Caps + Shift + Insert` removes it and restores its previous position. You can also hold `Caps` and double-click a window to add or remove it.
- Click a slot's focus tab, at its lower-left or upper-right corner, to bring its window forward. Click again to cycle through windows sharing that slot.
- `Caps + PgUp/PgDn` steps through the cascade's windows.
- `Caps + Tab` switches focus to a cascade, including cascades on other displays.
- `Caps + M` hides the cascade on the current display; `Caps + Shift + M` restores it.

### Paper Pad

Inspired by Yakuake, the drop-down terminal on Linux, I wanted a similar drawer for notes: somewhere to jot things down without digging through windows and tabs.

#### Get started

- `Pause + F12` opens the guide.
- `Win + F12` or `Caps + F12` shows or hides the drawer: a dedicated Notepad3 window that stays on top while open. Paper Pad asks you to install or locate [Notepad3](https://www.rizonesoft.com/downloads/notepad3/) if it can't find it.
- `Ctrl + N` creates a timestamped page. `Win + Left/Right` switches pages while you're in the editor.
- Changes save automatically when you switch pages or hide the drawer. Your pages remain ordinary files in your notes folder.

### Power-Up Utilities

Practical shortcuts for everyday tasks that don't fit into the other modules.

#### Get started

- `Pause + H` opens the guide.
- `Pause + End` keeps the computer awake for 30 minutes, then sleeps it once you're away. Press again while the notice is visible to choose 1, 2, 4 or 8 hours, or no limit. `Pause + Shift + End` stops the timer without sleeping.
- `Pause + T` inserts a timestamp; `Pause + -` inserts an en dash.
- `Caps` with the `QWER`, `ASDF` and `ZXCV` keys sends F13–F24; `Caps + 0–9` provides a virtual number pad, even if your keyboard lacks those keys.
- In Windows Terminal, `Caps + C` copies the buffer as Markdown and `Caps + K` clears it. Handy when copying terminal output into AI chats.

### Secret Layers

I wanted more assignable hotkeys without taking over shortcuts used by other apps, so I turned CapsLock and Pause into two extra keyboard layers.

#### Get started

- `Pause + L` opens the guide.
- Hold `Caps` or `Pause` while pressing another key, or tap it first and press the next key within 1.4 seconds.
- Double-tap `Shift` to toggle Caps Lock.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**.
2. Download the newest [release](https://github.com/nroj95/super-hotkey/releases), extract it and run `super-hotkey.ahk`.
3. Right-click the tray icon and enable **Run at startup** to launch Super Hotkey at every sign-in.

The tray menu also has **Modules...** to enable or disable modules and **Language...** to change the language. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`.

## Compatibility

Other window managers and tiling tools may conflict with Super Hotkey if they move windows, rearrange them after display changes or use the same hotkeys.

PowerToys FancyZones is not supported alongside Super Hotkey; disable it in PowerToys.

If you prefer mouse-driven zoning, [ScreenGrid](https://github.com/TtesseractT/ScreenGrid) lets you hold `Shift` while dragging a window to snap it into a customizable grid. It's compatible with Super Hotkey, though I don't use it myself. I kept Super Hotkey's zoning keyboard-first and flexible, without requiring you to set up a preferred layout.

## Troubleshooting

**Sleep only darkens the screens, or the computer wakes by itself.** Turn off Windows' Away Mode, and let only your keyboard wake the computer.

**Something behaves oddly.** `Pause + F4` suspends Super Hotkey, so you can check whether it's the cause. `Pause + F3` restarts it.

**Found a bug?** I'd love to fix it:

1. Turn on **Verbose logging** in the tray menu for more detail. It switches off again when Super Hotkey restarts.
2. Press `Pause + F1` to start a new log, then do what goes wrong.
3. Press `Pause + F2` to copy the log, and paste it into a [GitHub issue](https://github.com/nroj95/super-hotkey/issues) with a few words about what you expected.

Verbose logs include window titles, so read the log before you post it and remove anything private.

## Develop

Edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) explains the architecture. Run `python tests/check.py` before committing.

To translate Super Hotkey into your language, see [lang/README.md](lang/README.md).

Super Hotkey is free, and I'll never charge for it. The official source is [github.com/nroj95/super-hotkey](https://github.com/nroj95/super-hotkey); a paid version anywhere else doesn't come from me.

Code: [MIT](LICENSE). Icon: [FatCow attribution](assets/ATTRIBUTION.md).
