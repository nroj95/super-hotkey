# agent guide

Super Hotkey is one AutoHotkey v2 64-bit process: a launcher, a small core and five modules. there is no build step; edit `core/` and `modules/` directly. earlier generators and snapshots live only in Git history.

## map

| path | owns |
| --- | --- |
| `super-hotkey.ahk` | explicit includes, command-line flags and startup |
| `core/application.ahk` | the `SuiteModule` contract and the lifecycle: start, suspend, reconfigure, exit |
| `core/keybindings.ahk` | actions, their persistence and all native hotkey dispatch, including layer suffixes |
| `core/keybindings-editor.ahk` | the Keybindings window |
| `core/settings.ahk`, `core/logging.ahk` | suite preferences, backups and the shared log |
| `core/ui.ahk`, `core/tray.ahk` | every GUI, on-screen notices and the only tray |
| `core/windows.ahk`, `core/focus-border.ahk` | window queries, activation, closing, DPI boundaries, the working display, and manual and managed window ownership |
| `modules/<id>/module.ahk` | a module's lifecycle, actions, settings page and guide |

## design rules

- users assign **hotkeys** to **actions** in **Keybindings**. use these words consistently.
- a module overrides only the `SuiteModule` methods it needs and registers its actions in `Register`. core never calls module internals, and modules never call each other: they share behavior through core, such as the `SuiteWindowOwnership.OnClaim` hook and the `SuiteManagedWindows` provider. `tests/test_suite_structure.py` enforces both rules and the shared global namespace.
- Keybindings owns every configurable hotkey, including CapsLock and Pause layer suffixes. Secret Layers' `KeyboardLayers` owns only the two prefix keys. only registered complementary scopes may share a hotkey; Paper Pad editor navigation works only in its editor.
- native input callbacks only queue work. cancel queued work on reconfiguration, suspension and exit, and always release held output.
- disabled modules and layers release their inputs and keep their assignments editable. CapsLock and Pause behave normally unless reassigned.
- every feature must make sense to a keyboard-only user whose pointer is parked on another display. the pointer chooses a display only through a click; otherwise the active app window decides. choose displays with `SuiteWorkingMonitor` in `core/windows.ahk`, never the raw pointer position. show messages with `SuiteNotice` in `core/ui.ahk`, centered on the working display, not as tooltips beside the pointer.
- AutoHotkey threads share one OS thread. scope DPI awareness to single native calls with the `*Pixels` helpers, never across `Sleep` or dialogs in a thread that is not `Critical`.
- errors and lifecycle events are always logged; verbose logging is the only debug switch.

## user data and other applications

- settings live in `%LOCALAPPDATA%\nroj\SuperHotkey`. never delete user data automatically and never import old configuration directories. damaged files are kept as `.damaged-yyyyMMdd-HHmmss` copies.
- **Restore defaults** in Keybindings and **Reset to defaults...** in the tray stay separate, ask for confirmation and never touch notes, note paths, editor preferences or page state.
- never change another application's settings automatically. FancyZones is not supported; Wonder Windows only reports that it is running. the Windows Terminal macros send only its default shortcuts; Paper Pad runs Notepad3 with its own settings file and sends menu commands only while the running editor's menu has them.

## checks

- run `python tests/check.py` on Windows; `--autohotkey PATH` selects the interpreter. it runs the portable tests, a parse check and the native harness in dry-run mode.
- tests use disposable preferences and dry-run inputs. never perform real system sleep, speaker actions or personal note operations in automated checks.
- files are UTF-8 without a BOM, with LF line endings.
- keep the root MIT license and the FatCow icon attribution in `assets/`.
