# Win Key Overhaul

launch `../win-key-overhaul.ahk`. the files in this directory are modules of that one AutoHotkey v2 process, not separate window managers. the launcher is fully standalone and does not depend on any other root-level AutoHotkey script.

## migration

rename the launcher, module directory, and tray icon together:

````text
windows-key-overhaul.ahk       -> win-key-overhaul.ahk
windows-key-overhaul\          -> win-key-overhaul\
icons\windows-key-overhaul.ico -> icons\win-key-overhaul.ico
````

the canonical startup shortcut is `Win Key Overhaul.lnk`. startup can migrate this installation's previous `Windows Key Overhaul.lnk` or older `Window Hotkeys.lnk` after confirmation.

the preference file now lives at `%APPDATA%\WinKeyOverhaul\preferences.ini`. when the new file does not exist, startup copies the previous `%APPDATA%\WindowsKeyOverhaul\preferences.ini` once so the ScreenGrid recommendation state is preserved.

debug logging is off by default and can be toggled for the current run from the tray menu. it is not persisted across script restarts. when enabled, the machine-local log is `%LOCALAPPDATA%\WinKeyOverhaul\win-key-overhaul-debug.log`.

## shortcuts

| shortcut | action |
| --- | --- |
| `Win + Ctrl + H` | toggle the help window; `Escape` closes it. |
| `Win + Up` | maximize; another press enters borderless fullscreen; another returns to maximized. |
| `Win + Down` | restore an ordinary window, including the rectangle saved before script-managed layout/stretch where available. |
| `Win + Backspace` | minimize the active window and focus another eligible window when available; when focus is on the shell/desktop, restore the last window minimized with this shortcut. |
| `Win + Shift + Home` | isolate the active window, or restore this command's minimized group. |
| `Win + M` | minimize eligible windows, or restore this command's minimized group. |
| `Win + Shift + Up` | stretch to full height, retaining the existing one-pixel vertical overscan. |
| `Win + Shift + Down` | reset remembered horizontal and vertical stretch. |
| `Win + Shift + Left/Right` | toggle that edge's collision-limited horizontal stretch. |
| `Win + Left/Right` | cycle the corresponding full-height side layouts. |
| `Win + Insert/Delete` | top-left / bottom-left, alternating 25% and 50% width. |
| `Win + PgUp/PgDn` | top-right / bottom-right, alternating 25% and 50% width. |
| `Win + Home/End` | top-center / bottom-center, alternating centered 50% and offset 25%. |
| `Win + Enter` | swap with the next eligible window clockwise on the current monitor. |
| `Win + Shift + Enter` | swap with the next eligible window counter-clockwise. |
| `Win + Alt + Arrow` | start a spatial-focus session on the active window; subsequent presses move focus. |
| `Win + Shift + Tab` | cycle visible maximized, fullscreen, and borderless windows without changing their geometry or minimize state. |
| `Ctrl + Alt + Arrow` | optional FancyZones zone navigation. |
| `Ctrl + Alt + PgUp/PgDn` | optional FancyZones previous / next window in the current zone. |

when the marked Scratchpad window is active, Win Key Overhaul yields `Win + Left/Right` and `Win + PgUp/PgDn` so Scratchpad can use them for page navigation. this is optional coordination through a window property; Win Key Overhaul remains standalone.

spatial focus and maximized/fullscreen cycling are direct standalone shortcuts. the focus outline reuses four non-activating GUI windows during the script run; expiry hides them and exit destroys them. the window switcher keeps a stable cycle across focus-driven Z-order changes and accepts ordinary maximized windows, Win Key Overhaul borderless windows, and other visible windows whose frame fills a physical monitor. it never minimizes, restores, resizes, or moves a candidate, so the switcher does not directly alter Window Cascade geometry or membership. when switching away from a Win Key Overhaul borderless window, that window is temporarily lowered so a non-topmost target can become visible; its borderless topmost state is restored automatically if it becomes foreground again, including through another switching method. Win Key Overhaul remains standalone and does not call into Window Cascade.

## exact layout geometry

`2:6` is a **25% window / 75% remaining-space** split; `4:4` is **50% / 50%**. three-part ratios below mean **left space : window width : right space**. percentages refer to the monitor work area, excluding the taskbar. all top/bottom tiles use half the work-area height.

| step | `Win + Left` | `Win + Right` |
| --- | --- | --- |
| 1 | left 25% — `0:2:6` | right 25% — `6:2:0` |
| 2 | left 50% — `0:4:4` | right 50% — `4:4:0` |
| 3 | near-left 25% — `2:2:4` | near-right 25% — `4:2:2` |
| 4 | centered 50% — `2:4:2` | centered 50% — `2:4:2` |

both cycles loop back to step 1. the right near-center placement is deliberately mirrored. switching arrows starts the other side at its 25% edge layout instead of walking backwards through the old cycle. a fresh entry from an arbitrary, maximized, minimized, or borderless state starts at 25%; an existing matching layout can advance from its current step.

`Win + Home` and `Win + End` each follow:

````text
centered 50% -> near-left 25% -> centered 50% -> near-right 25% -> repeat
2:4:2          2:2:4            2:4:2          4:2:2
````

top and bottom remember separate next-narrow-side choices for each window. those choices survive switching shortcuts during the same script run, but are not persisted across script restarts. a fresh center entry starts at centered 50%.

shared pixel boundaries are rounded consistently, including odd resolutions and negative monitor coordinates. window commands use a scoped per-monitor DPI context so native geometry and DWM frame bounds agree. placement accounts for invisible window-frame borders. application-enforced minimum sizes can still exceed a requested tile; the cycle records actual geometry so it can keep advancing.

## collision stretch and normal restore

horizontal stretch considers other visible, non-minimized, eligible top-level windows on the current monitor whose vertical spans overlap the active window. it stops at the nearest facing edge. already-overlapping windows are ignored rather than causing the active window to shrink; shell, tool, cloaked, and hidden windows are excluded. if nothing blocks the extension, the work-area edge is used.

each edge has an independent restore position. repeating its shortcut restores that edge while retaining the opposite live edge, including during exit cleanup. an already-touching edge is a no-op. restoring an edge skips the collision scan. both stretch axes verify the resulting bounds and attempt to roll back rejected resizes. stretch snapshots are discarded if the owning process, monitor, or work area no longer matches.

swaps exchange visible frames and verify both results. when an app clamps a requested size or a move fails, the script attempts to restore both original rectangles rather than accepting a partial swap.

`Win + Down` uses a saved pre-placement/pre-stretch normal rectangle when available. this is more than just calling `WinRestore` on an already-normal tiled window. saved rectangles are discarded rather than carried across a changed monitor work area. `Win + Shift + Down` remains the stretch-only reset. ordinary layout placements are not undone just because the script exits; existing stretch and borderless exit cleanup is retained.

## startup and optional tools

the tray's **Recommended setup** command opens a small GUI showing the preferred stack and the detected current state: Windows Snap off, ScreenGrid on for drag snapping, and FancyZones off. it also provides direct access to Windows Snap settings, ScreenGrid's GitHub releases, and the optional FancyZones compatibility check. **Debug logging** toggles diagnostics for the current run only; enabling it installs the unhandled-error logger and detailed window diagnostics, while disabling it removes that error hook and skips expensive diagnostic inspection.

startup queries native Windows Snap with `SPI_GETWINARRANGING`. when enabled, a confirmation offers to disable it with `SPI_SETWINARRANGING`, persisting and broadcasting the change. declining changes nothing. **Windows Snap settings** in the **Recommended setup** GUI opens the Windows Multitasking page.

ScreenGrid is recommended once per user profile unless already running. accepting opens its official GitHub releases page; it does not download or install anything. the recommendation flag is stored in `%APPDATA%\WinKeyOverhaul\preferences.ini`. the GitHub link remains in the tray. use one drag-snapping tool at a time to avoid competing overlays.

### FancyZones

FancyZones remains optional. the script detects it on startup and when its process starts later, using the existing five-second watcher. keyboard-hook conditions use that watcher's cached PID; an invoked forwarding command rechecks the process before sending keys. compatibility setup requires confirmation and configures only:

- **Override Windows Snap hotkeys** and **Switch between windows in the current zone**;
- previous window as **Ctrl + Alt + PgUp**, and next window as **Ctrl + Alt + PgDn**.

the existing **Zone index** / **Relative position** choice is preserved. with Zone index, `Ctrl + Alt + Left/Right` move between zones; with Relative position, all four `Ctrl + Alt + Arrow` directions are available. native Windows Snap may remain disabled; the FancyZones override setting is a separate feature. close the PowerToys Settings window before applying the change so it does not write stale settings back. the helper preserves unrelated setting values and makes an exact timestamped `.bak` beside `settings.json` using an atomic replacement. unfamiliar/incomplete settings, non-boolean toggles/modifiers, and invalid virtual-key codes are rejected instead of guessed. JSON formatting may change.

FancyZones owns the two page-key shortcuts itself. the script forwards the arrow shortcuts with Ctrl and Alt temporarily released so FancyZones receives plain `Win + Arrow`. forwarding sends one step per arrow press and restores still-physically-held Ctrl and Alt keys on release. the keyboard hook is reasserted after FancyZones starts so the script retains bare `Win + Arrow`.

use **Check FancyZones compatibility** from the **Recommended setup** GUI after changing relevant PowerToys settings. rejecting setup keeps existing PowerToys settings intact; shortcut availability follows those settings. the internal PowerShell helper runs with a process-only execution-policy override; no persistent execution policy is changed.

## module map

| module | responsibility |
| --- | --- |
| `settings.ahk` | defaults, runtime state, paths, and debug settings. |
| `controls.ahk` | standalone hotkeys, click-to-abandon target, and optional FancyZones bindings. |
| `window-state.ahk` | group toggles, target selection, maximize/minimize/restore, and normal snapshots. |
| `layout-geometry.ahk` | pure ratio, rounding, cycle-index, and collision calculations. |
| `layouts.ahk` | stretch, side/corner/center actions, alternation, matching, and placement tracking. |
| `swapping.ahk` | shared clockwise ordering, both swap directions, and rectangle transactions. |
| `focus.ahk` | spatial focus and the original accent-colored highlight/session behavior. |
| `window-switcher.ahk` | maximized/fullscreen/borderless discovery, stable cycling, and focus-only activation. |
| `borderless.ahk` | fullscreen entry/restoration, switcher Z-order coordination, and exit cleanup. |
| `fancyzones.ahk` | compatibility detection, prompts, forwarding, and helper invocation. |
| `fancyzones-settings.ps1` | narrowly scoped JSON reading/update with an exact backup. |
| `windows.ahk` | shared filters, geometry, native placement, activation, and visible-frame movement. |
| `interface.ahk` | help and startup-shortcut creation/toggling. |
| `startup.ahk` | old-instance guard, startup migration, Snap prompt, and ScreenGrid recommendation. |
| `debug.ahk` | logging, error handling, and diagnostics. |

all includes are explicit in the root launcher. the modules communicate only within this one script process. window commands use a 10 ms default settling delay instead of AutoHotkey's 100 ms default, while retaining bounded geometry and activation retries. this reduces deliberate waiting; it is not a measured latency guarantee.

## validation

from the repository root:

````powershell
.\validate.ps1
````

the repository validator automatically validates every root-level AutoHotkey script and its include tree with AutoHotkey `/Validate`.

manual Windows behavior should still be checked after major changes, especially both full side cycles and arrow switching; top/bottom center alternation across multiple windows; `Win + Down` from tiled/maximized/borderless/minimized states; both swap directions; collision stretch and independent edge resets; maximized/fullscreen switching with one and multiple candidates, including Win Key Overhaul borderless windows; spatial focus navigation and highlight expiry; startup migration/declines; and FancyZones launched before and after this script. include mixed-DPI monitors and size-constrained apps when applicable.

## implementation references

- [AutoHotkey script loading and `/Validate`](https://www.autohotkey.com/docs/v2/Scripts.htm)
- [AutoHotkey keyboard-hook precedence](https://www.autohotkey.com/docs/v2/lib/InstallKeybdHook.htm)
- [AutoHotkey Send and Blind mode](https://www.autohotkey.com/docs/v2/lib/Send.htm)
- [Microsoft SystemParametersInfoW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow)
- [Microsoft FancyZones documentation](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones)
- [ScreenGrid source and releases](https://github.com/TtesseractT/ScreenGrid)
