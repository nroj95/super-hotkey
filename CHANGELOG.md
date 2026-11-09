# Changelog

## Unreleased

### Breaking changes

- **Galaxy Rhythm** is removed, with its bedtime messages, fade to sleep and energy bar, since it isn't about hotkeys. Super Hotkey now has five modules, all on by default, and `Pause + G` is free. Its settings and state in `%LOCALAPPDATA%\nroj\SuperHotkey\galaxy-rhythm` are left as they are.
- **Cascade Kingdom:** dropping a window onto a slot no longer adds it; `Caps + Insert` and the new double-click do. Dragging a window outside a cascade shows no guides. Dragging a window in a cascade shows them, as before: dropped on one, it takes that slot, on any display. Dropped anywhere else, it leaves the cascade where you dropped it, now at the size, or maximized, as it was before joining, instead of cascade-sized. Resizing it by any edge now always takes it out, where and as large as you made it.
- **Cascade Kingdom:** *bring cascade on this display to front* (`Caps + Shift + Space`) is removed, since `Caps + Tab` now does its job: when another window covers part of the cascade you're in, `Caps + Tab` brings it back to the front first and moves on to the next cascade on the next press. Always-on-top windows and the cascade's own dialogs don't count as covering it. A hotkey you gave the removed action is not carried over.
- **Wonder Windows:** `Win + Down` takes a window back to normal size and never minimizes: out of maximized or fullscreen, or back from a zone, a half or a full height or width. A window already at normal size gets a notice instead. `Win + Backspace` stays the key to minimize.
- **Wonder Windows:** `Win + Shift + Enter` now cycles the current stack backwards, the Shift twin of `Win + Enter`, and stretching moves to `Win + Shift`, replacing Windows' own versions: `Win + Shift + Up` stretches a window to full height, then full width, then puts it back, and `Win + Shift + Down` stretches it into the largest free space around it and back. That stretch now only stops at windows you can see, a stack counting once, and finds the biggest gap in one press instead of three steps. With nothing beside the window, it maximizes it for real, so a cascade window stays in its cascade. A hotkey you gave the old stretch is not carried over.
- **Cascade Kingdom:** `Win + Up` now maximizes a cascade window without lending it to Wonder Windows, like the maximize button, so it simply keeps its slot. A zone, a half or a stretch still lends it out, and `Win + Down` still brings it back to its slot, now also after a restart when it isn't maximized, as does the last press of `Win + Shift + Up` or `Win + Shift + Down` when the stretch began in the cascade.

### Changes

- **Wonder Windows:** each display picks its own zone layout in Settings: *Fourths, then halves*, *Thirds*, *Halves and corners*, *Rows of fourths, then halves* or *Rows of thirds*, with separate choices for landscape and portrait if you tick the box. Portrait displays default to *Halves and corners* instead of slivers a fourth of their width. You can also type your own layout, such as `1:1:1:1 > 1:1 / 1:1`: `:` between columns, `/` between rows and `>` for "and then", with any number of rows; whitespace doesn't matter. A choice of thirds carries over. ScreenGrid is no longer suggested in Settings.
- `Pause + F1` is renamed from *clear debug log* to *start new debug log*, since it never threw anything away. The previous log is now kept zipped in a `logs` folder in `%LOCALAPPDATA%\nroj\SuperHotkey`, one archive per new log, instead of a single `debug.log.old` that the next new log overwrote. Archives are never deleted, and they're small: about an eighth of the log's size. Logs that reach 2 MB are archived the same way. Archives with verbose lines, which record window titles, end in `-verbose`, so you can find and delete them. A `debug.log.old` from earlier versions moves into `logs` too. Restarts still keep writing to the same log.
- Display choices in **Cascade Kingdom** and **Paper Pad** settings are now numbered as Windows Settings numbers them. They used the number in the display's device name, which Settings doesn't follow, so with two displays the numbers could be swapped. Your chosen display stays the same.
- **Cascade Kingdom:** while you drag a window in a cascade, drop guides show only on the slots it can take, those the cascade can fill, and the guide of the slot it will take lights up in your accent color, twice as long and thick as the rest, and the others show in your inactive tab color, as faint as inactive focus tabs. With no guide lit, letting go takes the window out. Slots also catch a dropped window from much farther, 200 px from their corner instead of 56, so it takes a bigger move to drag a window out. A window dragged off its slot swaps with the nearest window instead of sliding back into its own gap, and the lit slot is always where it lands.
- With three or more displays, a notice for a display that a game in exclusive fullscreen covers now shows on every other display instead of only the next one.
- **Cascade Kingdom:** hold `Caps` and double-click anywhere on a window to add it to its display's cascade, as `Caps + Insert` does; keep holding to add more. Double-clicking a window already in a cascade takes it out, back to where it was, as `Caps + Shift + Insert` does. While `Caps` is held, a click only focuses a window, and no click, drag, scroll or other mouse button reaches what is inside it. The taskbar, the desktop, Start and focus tabs work as usual. *Click to focus while holding* in Settings picks `Pause` or `Win` instead, or turns it off. `Caps` and `Pause` need Secret Layers; `Win` works without it.

## v1.0.0-beta.4

Meet Galaxy Rhythm: gentle bedtimes and an energy bar for the day that rewards breaks, not less time at the computer. `Pause + Pause` turns the displays off, sleepy speakers can be kept awake, and every Settings page can restore its defaults.

### Breaking changes

- **Power-Up Utilities:** `Pause + Pause` now turns the displays off. *Wake speakers* is gone; **keep speakers awake** replaces it, and a hotkey you gave wake speakers is not carried over.
- **Power-Up Utilities:** `Pause + Shift + End` allows sleep again instead of cycling long durations. `Pause + End` steps through 30 min, 1 h, 2 h, 4 h, 8 h and no limit while its notice shows; once the notice has gone, the next press starts over at 30 min instead of carrying on from a press long ago. A hotkey you assigned to the long cycle is not carried over.
- Verbose logging lasts until Super Hotkey exits or restarts, so it can't be forgotten on: it records window titles. It always starts off, and a saved choice from earlier versions is dropped. A new *turn verbose logging on / off* action in Keybindings, unassigned by default, switches it from the keyboard and says which way it went.

### Changes

- Super Hotkey can be translated. Language files in `lang/` turn its English text into another language, and the suite follows the Windows display language when it has a file for it. A new **Language...** page in the tray can pick another language or English. So far only Secret Layers and the Language page go through translations, and `nb.lang` translates a few of their lines; the rest stays English. [lang/README.md](lang/README.md) shows how to add a language.
- **Galaxy Rhythm**, a new sixth module, brings gentle structure to an irregular sleep rhythm. Its settings show up to three bedtime messages: by default *It's getting late* at 00:00, *zzz…* at 01:00 and *You feel sleepy* at 02:00, each with its own time and words. The last is the sleep: the screen fades to grey over 10 minutes, says *Good night* and puts the computer to sleep. Stay awake keeps it up and says *Stay awake prevented sleep*, also while fading or saying good night; if it ends before your day starts, at 06:00 by default, the fade starts over. Until your day starts it's night: waking the computer begins the fade again, so a quick look is fine but the night stays a night. Each message shows on every display at its time while you use the unlocked computer; a time missed while asleep or locked is skipped. The module starts disabled; turned on in Modules, the whole night is on, and every time, length and message can be changed.
- **Galaxy Rhythm** also shows an upright, see-through energy bar marked E and outlined so it shows on dark backgrounds, blending smoothly from green through yellow to red as it empties, bottom right on the primary display by default; Settings can put it in any corner, on any display or on all of them. It is your energy for the day. Every minute you use the computer drains it, with the keyboard, the mouse or an Xbox-style game controller, 8 hours empty it, and watching or reading without touching anything drains it at half the pace, never into the grey. Only your day starting fills it: when your day starts, at 06:00 by default, it starts over, and as in Stardew Valley a late night costs you. A changed day start applies from the next day, so it never cuts today short. Leave the computer before the first bedtime message and the day starts full; stay later and it starts with less, down to half if you're still there at the bedtime sleep, and half of that again if the bar ran dry. What happens after the sleep doesn't count, so a quick look in the night or an early start costs nothing; during the night the bar drains quietly while you're there, without warnings, deeper grey or a faint, though running dry then still counts for tomorrow, and bedtime's fade takes over from any grey already showing. Breaks give some back, silently, and short ones the most: 5 minutes away, the least screen-work guidance asks for, gives back 15 and pays best per minute, 10 gives 25 and 30 gives 45, up to an hour, even out of the grey. A break counts from when the computer sees you go, locked, with the screens off, asleep, signed out or off, so reading or a film before the screens turn off is no break. Lock the computer or put it to sleep however you like when you leave; `Win + L` and `Pause + Escape` do it in one press. If you often just walk off, set a short screen timeout. Time while Super Hotkey is suspended is no break, even if you lock meanwhile. *You're running low on energy* comes at 10 %; at zero *You're running on fumes*, the screen greys over half an hour of activity, and *Lights out* puts the computer to sleep. Running dry also turns the bar's E red until your day starts over, a reminder that tomorrow starts tired, even after a break or Second wind refills it. After *Lights out* you wake halfway back into the grey, with time to save your work, until a break or Second wind lifts you out; the day still counts as having run dry. Stay awake doesn't touch the bar: it keeps the computer up while you're away, and the bar only drains while you're here. For a game night, **Tonight off**, a button in Galaxy Rhythm's Help, silences bedtime and hides the bar until your day starts, a time Settings shares between bedtime, the night off and the bar. The bar keeps counting out of sight, without warnings, grey or a faint, so the next morning pays for what you spend and how late you stay up, nothing more. It can't be taken back: it asks first, then its button shows 🔒 and when it ends, and Settings keeps *Your day starts at* locked until then. Suspending Super Hotkey pauses the bar too, but how late you're at the computer still counts. Once a day, **Second wind** beside it in Help gives back a quarter of a full bar, even out of the grey. The bar hides over fullscreen windows. Its sizes, the length of the fade, the words when running low, at zero and at the faint, and whether it fades and faints at all can be changed in Settings.
- **Galaxy Rhythm**'s Help, with its *Second wind* and *Tonight off* buttons, opens with `Pause + G` while the module is on.
- **Wonder Windows:** Keybindings now lists the improved Windows keys `Win + Up`, `Win + Down`, `Win + M`, `Win + Shift + M`, `Win + Home`, `Win + Shift + Home`, `Win + D` and `Win + Shift + D` under Better Windows keys, so you can move or clear them. The module's other actions are grouped like the sections of its guide. Moved or cleared, an improved key, `Win + Left` and `Win + Right` included, does nothing instead of falling back to Windows' own version. A new Wonder Windows setting gives those keys back to Windows.
- **Power-Up Utilities:** `Pause + Escape` sleeps for real even on computers that let Away Mode replace sleep, keeping them running with their screens dark. A new Settings checkbox, ticked by default, can leave that to Windows, so the hotkey sleeps as Start's Sleep does. Galaxy Rhythm's *Good night* and *Lights out* always sleep for real.
- **Power-Up Utilities:** **keep speakers awake: on / off**, an action without a default hotkey, keeps speakers that fall asleep in silence from missing notifications and the starts of videos. While you're at the unlocked computer with its displays on, it nudges them every 8 minutes and as you come back, with a 25 Hz tone too low for most speakers to play, sized to reach them at any Windows volume; muted, nothing plays. It stays on until you switch it off. A new Settings page can nudge every 1 to 60 minutes, or play a soft chime instead for speakers the tone doesn't keep awake.
- **Power-Up Utilities:** `Pause + Pause` turns the displays off, as Windows' screen timeout does, for a break or to save power. Any touch wakes them, as with Windows' own timeout, and Galaxy Rhythm counts it as a break.
- Settings that apply without restarting, in Cascade Kingdom, Wonder Windows and Galaxy Rhythm, stay open after **Apply**, like Keybindings. Apply, like Keybindings', is lit only while the page differs from what's saved: changing a value back, restoring defaults you already have or saving greys it again.
- Every module's Help page shows its section headings in bold, like the Galaxy Rhythm settings page.
- **Cascade Kingdom** shows no focus tabs on a cascade of one window, since there is nothing to switch to. They return as soon as a second window joins, and leave again when it is closed, minimized or maximized, hidden to the tray or moved to another virtual desktop. Each display's cascade decides for itself.
- Every Settings page has **Restore defaults**, like Keybindings: it asks first, then fills the page with the module's defaults, and nothing is saved until you apply. Paper Pad's notes folder and editor path, a night off and the energy bar's level are never restored.
- Notices stay where they first appear until they go: a new one takes the center of its display when that is free, otherwise the first free spot below, and the rest no longer move when one goes. News from different sources, such as bedtime and the energy bar, now shows together instead of one replacing the other.
- Buttons along the bottom of Help and Settings fit their text, at least one shared width, so labels are never cut short, translated ones included.

### Fixes

- Help and Settings pages open at most 80 % of the display, like a cascade window, and scroll when their content is taller, by the scrollbar, the wheel, `PgUp`, `PgDn`, `Home` and `End`, or by tabbing to a field. On a small or scaled screen, such as 1366 × 768 or 1080p at 150 %, the longest guides and Galaxy Rhythm's Settings no longer run off the bottom.
- Settings, Keybindings and Back open on the display the page you came from is on. Moving Help to another display and pressing Settings... no longer opens Settings back on the display of the app you were in before.
- With more than one display, notices no longer hide behind a game in exclusive fullscreen: a notice for the game's display shows on the next one instead, and news shown on every display skips it.
- **Power-Up Utilities:** when stay awake runs out, its "Sleep allowed again" notice shows on every display for 3 seconds. If the computer sleeps or is locked, the notice shows a second after you unlock instead of behind the lock screen.

### Install

Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, download and extract the source code below, and run `super-hotkey.ahk`. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`; this version keeps those from earlier betas.

### Known limitations

- PowerToys FancyZones isn't supported; disable it in PowerToys while using Super Hotkey.
- Paper Pad needs Notepad3 and asks you to install it or locate it when it can't find it.
- Galaxy Rhythm's energy bar can't tell walking away from reading while the screens stay on, so a break counts only once the computer locks, turns its screens off or sleeps.
- Keep speakers awake was measured on one set of speakers; if yours still fall asleep, nudge more often or switch to the chime in Power-Up Utilities' Settings.

## v1.0.0-beta.3

Windows' own keys, made predictable: `Win + M`, `Win + Home` and `Win + D` keep to your display, never forget, and take `Shift` to bring windows back. Cascades gain a mirrored direction, tabs on both sides and `Caps + Tab` between displays, and `Pause + End` keeps the computer awake.

### Breaking changes

- **Secret Layers:** double-tapping Shift always toggles Caps Lock while the CapsLock layer is enabled. The checkbox, the Ctrl and Alt choices and the Toggle Caps Lock action are gone; turn off the CapsLock layer to give the key back to Windows.

### Changes

- **Wonder Windows:** `Win + M` minimizes the windows on your display only, and `Win + Shift + M` brings back that display's, keeping their stacking order with the frontmost focused. Unlike in Windows, a `Win + M` with nothing left to minimize no longer makes `Win + Shift + M` forget what to bring back, and a later `Win + M` adds to it.
- **Wonder Windows:** `Win + Home` minimizes the other windows on your display only and keeps the active one in front, and `Win + Shift + Home` brings them back behind it. Unlike in Windows, `Win + Home` only minimizes, and moving or switching windows in between never makes it forget. It shares its memory with `Win + M`, so `Win + Shift + M` brings back what either minimized, frontmost on top.
- **Wonder Windows:** `Win + D` minimizes the windows on every display and `Win + Shift + D` brings them all back, instead of one key that shows the desktop or restores and forgets at the next window change. Each display remembers its own, so `Win + Shift + M` can bring back just yours. Like `Win + M`, windows without a minimize button stay.
- **Wonder Windows:** `Win + Alt + Enter` cycles maximized and fullscreen windows again, now only on your display, with `Win + Alt + Shift + Enter` going back; `Caps + Win + Enter` and `Caps + Win + Shift + Enter` work too. Each press shows the next one, minimized or not, and minimizes the others there. The loop no longer stops with all of them minimized: from any other window the first press brings back the one shown last, and `Win + Backspace` puts it away. Maximized cascade windows take part too, and a notice says when there is no other maximized or fullscreen window to show.
- **Cascade Kingdom:** `Caps + Tab` brings the next cascade forward and outlines its front window, from left to right across your displays and wrapping. From outside a cascade it starts with the one on your display. A notice says when there are no cascades, or no other one.
- **Cascade Kingdom:** focus tabs appear on the right side too, mirroring the left: one outside each window's upper-right corner, and a full-height one along the right side of the lowest window. Both tabs of a slot do the same thing.
- **Cascade Kingdom:** Mirror in Settings makes cascades step down to the left instead of the right. Focus tabs, full-height tabs and drop guides swap sides with it, a drop is judged by the window's top-right corner, and open cascades rearrange when you click Apply.
- **Cascade Kingdom** closes the gap a window leaves when you minimize or maximize it, hide it to the tray or move it to another virtual desktop, as it does for a closed one. The window stays in its cascade: bring it back and it returns to its slot while the window that filled in moves back. Maximizing no longer takes a window out of its cascade.
- **Paper Pad:** `Caps + F12` shows or hides the drawer too, beside `Win + F12`.
- **Power-Up Utilities:** `Pause + End` keeps the computer awake for 30 minutes, 1 h or 2 h, and `Pause + Shift + End` for 4 h, 8 h or until turned off. Each press steps to the next duration, counted from now, with a notice; after the last step sleep is allowed again. The tray icon's tooltip shows how long. Screens still turn off and lock, choosing Sleep or closing a laptop lid still sleeps, and suspending or exiting Super Hotkey ends it.
- **Suite windows** that resize, such as Help, Settings and Keybindings, show the Windows sizing grip in the lower-right corner again, on the window's own background. It hides while a window is maximized.

### Fixes

- **Cascade Kingdom** no longer counts windows hidden to the tray as filling their slot, so new windows use it, and navigation and `Caps + Shift + Space` no longer pick a hidden window.
- **Cascade Kingdom:** `Caps + Shift + Space`, `Caps + PgUp` and `Caps + PgDn` work while a maximized window has focus, bringing the cascade forward over it or focusing into it. Commands that rearrange the cascade still wait, and verbose logging says why a cascade command was skipped.
- **Cascade Kingdom** keeps a window lent to Wonder Windows across restarts, so `Win + Down` still returns it to its slot.
- **Cascade Kingdom:** when a display disconnects, its cascade joins the one on the primary display and spreads into free slots instead of landing on top of it, two windows to a slot. When the display reconnects, those windows return to its cascade.
- **Cascade Kingdom:** dragging a window that Windows Snap arranged shows the drop guides on the first drag and can join the cascade. Windows giving it back its earlier size no longer counts as a resize.
- **Secret Layers:** the "Caps held" and "Pause held" notices go away once a hotkey answers, so they no longer show next to that hotkey's own notice. Notices that show together always stack, whichever came first, and the rest move back to the center when one hides.
- **Power-Up Utilities:** characters type as you press them, like real keys, and repeat while held; the timestamp types on the press too. `Pause` held with `- -` types each en dash as you tap, in order; before, repeated presses typed one dash after you let go. Text and Terminal hotkeys no longer wait for Caps or Pause, only for Shift, Ctrl, Alt or Win; Terminal actions still run once you release their key, and sleep still waits for every key.
- **Wonder Windows** counts every tap made during a slow move, in the order pressed, so three quick `Win + Right` taps step three zones instead of two. A fast `Win + scroll` spin still steps once, so it cannot fling a window several zones on.
- **Help pages** no longer flicker while you resize them.

### Install

Install [AutoHotkey v2](https://www.autohotkey.com/) **64-bit**, download and extract the source code below, and run `super-hotkey.ahk`. Settings and logs live in `%LOCALAPPDATA%\nroj\SuperHotkey`; this version keeps those from earlier betas.

### Known limitations

- PowerToys FancyZones isn't supported; disable it in PowerToys while using Super Hotkey.
- Paper Pad needs Notepad3 and asks you to install it or locate it when it can't find it.

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
