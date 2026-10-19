# implementation constraints

- target AutoHotkey v2 64-bit Windows. preserve existing feature behavior and avoid unnecessary scope expansion.
- this is a runnable draft, not yet a stable release. complete `docs/integration-status.md` acceptance checks before publishing.
- use one launcher, process, tray, application icon, Keybindings manager and shared debug log. avoid plugin frameworks and module-specific trays.
- each module tray entry opens its Getting started guide. module Settings and shared Keybindings navigation belong in those pages.
- use **hotkeys** for user-facing configurable triggers, **Keybindings** for the editor and **actions** for their effects.
- only registered complementary input scopes may share hotkeys. Paper Pad editor navigation is not global.
- disabled modules and layers release inputs; the assignments remain editable. CapsLock/Pause behave normally unless independently reassigned.
- defer feature work out of native input callbacks; cancel queued work on reconfiguration, suspension and exit. preserve held-output cleanup.
- errors and lifecycle logging remain active without verbose logging; there are no per-module debug switches.
- keep Restore defaults in Keybindings separate from Reset to defaults in the tray. require confirmation and do not delete notes, note paths, editor preferences or page state.
- Windows Snap and FancyZones configuration require explicit consent. never change other applications' settings automatically.
- the default suite settings path is `%LOCALAPPDATA%\nroj\SuperHotkey`. old configuration directories are not imported; never delete user data automatically. internal mutex and ownership identifiers may retain legacy names to preserve compatibility.
- edit committed source in `core/` and `modules/` directly. historical generators and snapshots remain available through Git history, not in the working source tree.
- preserve root MIT license and icon attribution.
- tests use disposable preferences and dry-run inputs; never perform real system sleep, speaker actions or personal note operations in automated checks.
- retain LF line endings. run portable tests and `python tests/check.py` on Windows.
