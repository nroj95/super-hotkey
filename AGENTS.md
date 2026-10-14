# implementation constraints

- target AutoHotkey v2, 64-bit Windows. preserve working feature behavior before expanding scope.
- this is a runnable integration preview, not a stable release. use `docs/integration-status.md` for acceptance boundaries.
- one launcher, process, tray, application icon, Keybindings manager and global log. no plugin framework.
- each flat tray module entry opens How to use. settings and shared Keybindings navigation belong at the lower right.
- preserve stable action IDs, personal settings paths, window markers, licenses and attribution when renaming features.
- disabled modules and Secret Keys layers release inputs but retain editable assignments. native CapsLock/Pause return unless explicitly reassigned.
- only registered complementary input scopes may share shortcuts. Paper Pad editor navigation is not a global shortcut.
- defer feature work out of input callbacks; cancel queued work on reconfiguration, suspend and exit. preserve held-output cleanup.
- automatic errors and lifecycle logging remain active with verbose debugging off. there are no per-module debug switches.
- reset shortcuts separately from factory settings. confirmation defaults to cancellation; neither operation may erase notes, paths, editor preferences or page state.
- Windows Snap and FancyZones changes require explicit consent. never modify standalone repositories, startup entries or configurations automatically.
- work directly on committed `core/` and `modules/` source. historical migration generators are provenance only; do not rerun them over later development.
- tests use temporary settings, dry-run callbacks and owned fixtures. never invoke real power/sleep/audio/text actions or personal note operations in automated checks.
- keep LF, descriptive names and the existing comment style. run portable checks plus `python tests/check.py` on Windows.
