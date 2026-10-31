# Changelog

## Unreleased

### Breaking changes

- **Secret Layers:** double-tapping Shift always toggles Caps Lock while the CapsLock layer is enabled. The checkbox, the Ctrl and Alt choices and the Toggle Caps Lock action are gone; turn off the CapsLock layer to give the key back to Windows.

### Changes

- **Cascade Kingdom:** `Caps + Tab` brings the next cascade forward and outlines its front window, from left to right across your displays and wrapping. From outside a cascade it starts with the one on your display. A notice says when there are no cascades, or no other one.
- **Paper Pad:** `Caps + F12` shows or hides the drawer too, beside `Win + F12`.
- **Cascade Kingdom:** focus tabs appear on the right side too, mirroring the left: one outside each window's upper-right corner, and a full-height one along the right side of the lowest window. Both tabs of a slot do the same thing.
- **Cascade Kingdom:** Mirror in Settings makes cascades step down to the left instead of the right. Focus tabs, full-height tabs and drop guides swap sides with it, a drop is judged by the window's top-right corner, and open cascades rearrange when you click Apply.
- **Power-Up Utilities:** `Pause + End` keeps the computer awake for 30 minutes, 1 h or 2 h, and `Pause + Shift + End` for 4 h, 8 h or until turned off. Each press steps to the next duration, counted from now, with a notice; after the last step sleep is allowed again. The tray icon's tooltip shows how long. Screens still turn off and lock, choosing Sleep or closing a laptop lid still sleeps, and suspending or exiting Super Hotkey ends it.
- **Wonder Windows:** `Win + Alt + Enter` cycles maximized and fullscreen windows again, now only on your display, with `Win + Alt + Shift + Enter` going back; `Caps + Win + Enter` and `Caps + Win + Shift + Enter` work too. Each press shows the next one, minimized or not, and minimizes the others there. The loop no longer stops with all of them minimized: from any other window the first press brings back the one shown last, and `Win + Backspace` puts it away. Maximized cascade windows take part too, and a notice says when there is no other maximized or fullscreen window to show.
- **Cascade Kingdom** closes the gap a window leaves when you minimize or maximize it, hide it to the tray or move it to another virtual desktop, as it does for a closed one. The window stays in its cascade: bring it back and it returns to its slot while the window that filled in moves back. Maximizing no longer takes a window out of its cascade.

### Fixes

- **Cascade Kingdom** no longer counts windows hidden to the tray as filling their slot, so new windows use it, and navigation and `Caps + Shift + Space` no longer pick a hidden window.
- **Cascade Kingdom:** `Caps + Shift + Space`, `Caps + PgUp` and `Caps + PgDn` work while a maximized window has focus, bringing the cascade forward over it or focusing into it. Commands that rearrange the cascade still wait, and verbose logging says why a cascade command was skipped.
- **Cascade Kingdom** keeps a window lent to Wonder Windows across restarts, so `Win + Down` still returns it to its slot.
- **Cascade Kingdom:** when a display disconnects, its cascade joins the one on the primary display and spreads into free slots instead of landing on top of it, two windows to a slot. When the display reconnects, those windows return to its cascade.
- **Cascade Kingdom:** dragging a window that Windows Snap arranged shows the drop guides on the first drag and can join the cascade. Windows giving it back its earlier size no longer counts as a resize.
- **Secret Layers:** the "Caps held" and "Pause held" notices go away once a hotkey answers, so they no longer show next to that hotkey's own notice. Notices that show together always stack, whichever came first, and the rest move back to the center when one hides.
- **Power-Up Utilities:** characters type as you press them, like real keys, and repeat while held; the timestamp types on the press too. `Pause` held with `- -` types each en dash as you tap, in order; before, repeated presses typed one dash after you let go. Text and Terminal hotkeys no longer wait for Caps or Pause, only for Shift, Ctrl, Alt or Win; Terminal actions still run once you release their key, and sleep still waits for every key.
- **Wonder Windows** counts every tap made during a slow move, in the order pressed, so three quick `Win + Right` taps step three zones instead of two. A fast `Win + scroll` spin still steps once, so it cannot fling a window several zones on.

## v1.0.0-beta.2

Fewer, smarter hotkeys: this version cuts features that overlapped and hands several keys back to Windows.

### Breaking changes

- If you customized these hotkeys, set them again in Keybindings: Clear log, Copy log, Toggle Caps Lock and Power-Up help have new action IDs and start from their defaults.
- **Paper Pad:** `Win + PgUp` now goes to the previous page and `Win + PgDn` to the next, like PgUp and PgDn everywhere else. Saved hotkeys keep the old order, so swap them in Keybindings.
- **Cascade Kingdom:** `Caps + M` only hides the cascade on your display; `Caps + Shift + M` brings it back, like `Win + M` and `Win + Shift + M`. Each display keeps its own hidden windows, and hiding again before restoring adds to what comes back, so nothing hidden is left behind. Focus stays on that display: the next window there gets it, outlined, or else the desktop.
- **Cascade Kingdom:** pressing `Caps + Insert` again no longer undoes. `Caps + Shift + Insert` takes the active window out of its cascade and returns it to where it was before it joined, maximized or not, whenever you press it. Windows dropped onto a slot remember their place too.
- **Cascade Kingdom:** bringing the cascade forward moves to `Caps + Shift + Space`, showing the next window in each slot to `Caps + Shift + Enter`, and gathering all cascades to `Caps + Home`. Shift keeps a stray Caps tap followed by Space or Enter from moving focus while you type. Saved hotkeys keep the old keys, so set them again in Keybindings.
- **Cascade Kingdom** corrects a window that resizes itself after a move, as Firefox and Discord do when they reach a display with a different scale, once and then leaves it to the app, instead of retrying for up to two and a half minutes.
- **Wonder Windows:** `Win + Backspace` only minimizes; on the desktop it no longer brings back the last minimized window. `Win + Shift + Backspace` does that instead, wherever focus is, and each press brings back one more window minimized with `Win + Backspace` or `Win + Down`, newest first. After a minimize, focus stays on that display while it has windows left, outlined, and only then moves to the next display, left to right.
- **Suspend:** `Pause + F4` suspends and resumes Super Hotkey with an on-screen notice. While suspended it is the only key that still answers; CapsLock and every other hotkey behave natively, and Pause stays a prefix only for the suspend key's own combination.
- **Wonder Windows:** `Win + Down` steps down: it undoes a placement, then minimizes. It no longer brings a window back on a third press (`Win + Shift + Backspace` does), and after a minimize every Wonder Windows key acts on the window you are in, never on the one just minimized. `Win + Up` and `Win + Down`, improved Windows keys, no longer have rows in Keybindings.
- **Focus outline:** double-tap Caps to outline the window you are in, or see "No window has focus" on the desktop. `Win + PgUp` and `PgDn` now step on the first press instead of only outlining the current window first.
- **Windows Terminal helpers** send Terminal's default shortcuts (`Ctrl + Shift + A`, `C` and `K`). If you remapped those in Terminal, restore them.

### Changes

- **Wonder Windows:** `Win + Shift + Enter` replaces the stretch actions. It stretches a window across to its neighbors, then into all the free space around it, then back, and Windows' own `Win + Shift + arrows` work again. Swap with neighbor and the maximized and fullscreen cycle are gone, `Win + M` and `Win + Home` belong to Windows again, and stacking on the nearest window also works with `Caps + Win + arrows`.
- **Cascade Kingdom:** windows join a cascade only through `Caps + Insert` or a drop onto a slot. Automatic mode, launching while holding the cascade key, `Caps` + double-click on a title bar and the Cascade key setting are gone, so Cascade Kingdom no longer needs Secret Layers. Active focus tabs and drop guides follow the Windows accent color.
- **Cascade Kingdom** keeps your cascades when Super Hotkey restarts: windows still in their slots rejoin, and `Caps + Shift + Insert` still returns them to where they were before they joined.
- **Paper Pad** no longer installs Notepad3 or locks the open page; the lock could block sync clients. The slide always takes 180 ms unless Windows' Animation effects are off.
- **Suite windows** use standard Windows title bars and borders. Tray > Debug log opens the log in Notepad, and Keybindings names every action by what it does.

### Fixes

- Clicks are no longer held while a hotkey checks its context, so a busy moment can't delay or drop clicks, for example in the tray menu.
- Windows moved to another display with Windows' own keys stay in the right cascade.
- A cascade window placed with Wonder Windows rejoins its slot when `Win + Down` returns it to its original shape, instead of only looking cascaded. `Caps + Shift + Insert` then takes it back to where Wonder Windows had placed it.
- **Cascade Kingdom** reads each display's scale from Windows. Its hidden helper windows kept the old scale after a change, so cascade slots, focus tabs and drop guides could stay sized for the previous scale.
- **Cascade Kingdom** retries focusing a window when Windows refuses at first, and a window spanning two displays belongs to the one holding most of it, as Windows decides.
- A hotkey pressed while an overlay pops up in front, such as a shortcut guide shown while Win is held, now acts on the window underneath instead of falling through to another action, and the next Win hold shows the guide as usual.
- `&nbsp;` shows correctly in Keybindings.

### Install

Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, download and extract the source code below, and run `super-hotkey.ahk`. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`; this version keeps those from beta.1.

### Known limitations

- PowerToys FancyZones isn't supported; disable it in PowerToys while using Super Hotkey.
- Paper Pad needs Notepad3 and asks you to install it or locate it when it can't find it.

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
