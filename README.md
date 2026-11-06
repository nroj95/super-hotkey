# Super Hotkey

A small AutoHotkey v2 suite for window management, quick notes and everyday keyboard shortcuts I found useful.

Built by a non-programmer: ChatGPT wrote the early versions and Claude Code the later ones; I design, direct and test it.

![Super Hotkey arranging, switching and stretching windows](assets/super-hotkey-showcase.gif)

*This recording shows v1.0.0-beta.1; some keys and behavior have changed since. I'll record a new one once things settle.*

## Modules

Use any module on its own or combine them.

| Module | Purpose |
| --- | --- |
| [Wonder Windows](#wonder-windows) | Position, stretch, stack and cycle windows |
| [Cascade Kingdom](#cascade-kingdom) | Keep many windows in an overlapping cascade |
| [Paper Pad](#paper-pad) | A quick-notes drawer using Notepad3 |
| [Power-Up Utilities](#power-up-utilities) | Extra keys, text shortcuts and system utilities |
| [Secret Layers](#secret-layers) | Use CapsLock and Pause as extra keyboard layers |
| [Galaxy Rhythm](#galaxy-rhythm) | Bedtime nudges, a fade to sleep and an energy bar, off until you turn it on |

### Wonder Windows

There are plenty of window managers for Windows, but the ones I tried tiled windows smaller than I liked, took a while to learn, or spread things across so many workspaces that I lost track of them. Small costs, but they added up. This is my take on window management that builds on the `Win` key shortcuts you already know and makes the ones I found frustrating or incomplete more predictable.

Hold `Win` and scroll, or press `Win + Left/Right`, to walk the active window through zones: full-height fourths and halves first, then the same zones in the upper and lower half of the display. The other direction steps back, and releasing `Win` starts over next time. Settings offers thirds instead.

Windows can also sit side by side with others stacked behind them: `Win + Enter` cycles through the stack, and `Alt + Win + arrow` moves a window onto its nearest neighbor to stack them. `Win + Shift + Enter` stretches a window across to its neighbors, then into all the free space around it, then back.

For big windows, `Win + Alt + Enter` shows the next maximized or fullscreen window on your display and minimizes the others, so one is out at a time. Add `Shift` to go back.

Windows' own keys work as you know them, with fewer surprises. `Win + M`, `Win + Home` and `Win + D` take `Shift` to bring back what they minimized, however much you do in between, and act on your display only, except `Win + D`, which reaches every display.

### Cascade Kingdom

Keep windows in an overlapping cascade, which helps most when many apps are open. Every window keeps 80% of the display's width and height, however many you add. It steps down to the right, or to the left with Mirror in Settings.

Add the active window with `Caps + Insert`, or hold `Caps`, `Win` or `Pause` and double-click any window; double-click it again, or press `Caps + Shift + Insert`, to take it out and put it back where it was. While one of those keys is held, clicks only focus windows, so you can bring a window forward from anywhere on it without clicking what is inside. Drag a window in the cascade onto another slot to move it there, or anywhere else to take it out at its old size.

Each slot in the cascade gets a small colored focus tab on both sides, at the lower left and the upper right, so every slot stays one click away from either side: click a tab to bring its window forward, and click it again to cycle through the windows sharing that slot. From the keyboard, `Caps + PgUp/PgDn` steps through them, and `Caps + Tab` jumps to the next cascade, on whichever display it is. `Caps + M` hides the cascade on your display and `Caps + Shift + M` brings it back together.

With two displays, for example, keep focused work in narrow zones on one, wide apps like file managers, video players or Discord on the other, and secondary apps in a cascade on whichever display you choose in Settings.

### Paper Pad

A quick-notes drawer: `Win + F12` or `Caps + F12` shows or hides a dedicated Notepad3 window that stays on top while it's open, so you can jot something down without hunting through other windows and tabs.

`Ctrl + N` creates a timestamped page, and `Win + Left/Right` move between pages inside the drawer. Changes are saved automatically when you switch pages, hide the drawer or exit, and pages stay ordinary files in your notes folder.

### Power-Up Utilities

Send F13-F24 or use a virtual number pad, even if your keyboard doesn't have those keys. Insert punctuation, special characters or a timestamp without looking them up.

In Windows Terminal, copy the buffer as Markdown or clear it; both use Terminal's default `Ctrl + Shift + A`, `C` and `K` shortcuts. Other shortcuts put the computer to sleep, and `Pause + Pause` turns the displays off until you touch the mouse or keyboard; waking speakers that have gone into standby is an action you can give a hotkey in Keybindings. `Pause + End` keeps it awake for 30 minutes; press again while the notice shows for 1, 2, 4 or 8 hours or no limit, and `Pause + Shift + End` lets it sleep again.

### Secret Layers

Hold CapsLock or Pause and press another key for extra hotkeys, or tap it first so you don't have to hold both. `Caps` and `Pause` hotkeys use these layers. Double-tap Shift to toggle Caps Lock.

### Galaxy Rhythm

Gentle structure for an irregular sleep rhythm, without nagging. Its settings show up to three bedtime messages at times you choose, by default *It's getting late* at midnight, *zzz…* at 1:00 and *You feel sleepy* at 2:00. After the last, the screen fades to grey over 10 minutes, says *Good night* and puts the computer to sleep, and until your day starts, waking it fades it back to sleep; Power-Up Utilities' stay awake keeps it up. A small, see-through energy bar marked E, upright in the bottom-right corner of the primary display unless you move it, is your energy for the day. It drains while you use the computer, and breaks give some back, short ones the most, counted from the moment the computer locks, turns its screens off or sleeps, so lock it with `Win + L` when you leave. It starts over when your day starts, and as in Stardew Valley a late night or running dry means a smaller bar the next day. Run it empty and the screen greys over half an hour until you faint into sleep. For a game night, *Tonight off* in its Help pauses all of it until your day starts. The module starts disabled: turn it on in Modules and all of it is on, ready to adjust in Settings.

## Start

1. Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**.
2. Download the newest [release](https://github.com/nroj95/super-hotkey/releases), extract it and run `super-hotkey.ahk`.
3. Right-click the tray icon and check **Run at startup** to have it ready after every sign-in.

Try these first:

- Hold `Win` and scroll to walk the active window through zones.
- Press `Win + M`, then `Win + Shift + M`: only your display clears, and everything comes back in order.
- Press `Win + F12` to open the Paper Pad notes drawer. It needs [Notepad3](https://www.rizonesoft.com/downloads/notepad3/) and asks you to install or locate it when it can't find it.
- Press `Ctrl + Alt + K` to see and change your hotkeys.

The tray icon also has guides, settings and **Modules...**, where you can turn off what you don't need, and **Language...**. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`.

## Compatibility

Other window managers and tiling tools can conflict with Super Hotkey when they also move windows, rearrange them after display changes, or use the same hotkeys.

PowerToys FancyZones does all three, so it isn't supported; disable it in PowerToys. For `Shift + drag` window placement, I recommend [ScreenGrid](https://github.com/TtesseractT/ScreenGrid) instead. It shows a grid overlay for dropping windows into zones and works well alongside Super Hotkey.

## Develop

Edit `core/` and `modules/` directly; [AGENTS.md](AGENTS.md) explains the architecture. Run `python tests/check.py` before committing.

To translate Super Hotkey into your language, see [lang/README.md](lang/README.md).

Super Hotkey is free, and I'll never charge for it. The official source is [github.com/nroj95/super-hotkey](https://github.com/nroj95/super-hotkey); a paid version anywhere else doesn't come from me.

Code: [MIT](LICENSE). Icon: [FatCow attribution](assets/ATTRIBUTION.md).
