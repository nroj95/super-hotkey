# Super Hotkey World

a modular Windows productivity suite being consolidated from existing AutoHotkey v2 projects.

**status: source migration checkpoint; not a runnable suite.** the initial commit contains pinned source snapshots, licenses, and an entry-point/dependency audit. it does not start any script or change the existing installations.

## target

one AutoHotkey process, one tray icon, one Keybindings manager, centralized logging, and four optional modules: Window Cascade, Power Hotkey, Scratchpad, and Caps + Pause Layers. all four will be enabled by default; Keybindings remains available independently of the layer module.

reuse the existing implementations. do not add a plugin framework, automatic shortcut reassignment, or profiles. Shell Folders stays separate.

## current layout

- `migration/upstream/`: complete tracked snapshots from the five source repositories, without their Git histories. these are reference implementations, not modules wired into a common launcher.
- `migration/source-manifest.json`: exact source commits and imported file counts.
- `docs/initial-audit.md`: verified entry-point findings, scope limits, and blockers.
- `docs/implementation.md`: the integration order and acceptance checks.

read the audit before creating a combined launcher. including the original entry points directly is not safe: several start services immediately, set process-wide defaults, or install their own hotkeys.

## data and retirement

keep the original repositories and utilities intact until behavior parity has been checked on Windows. imported source does not include unpublished local changes or personal settings. Scratchpad notes, editor profiles, and backups must never be deleted by a shortcut or factory reset.

retain upstream licenses and icon attribution when moving source and assets into their final locations. remove the staging copies only after their replacements have been reviewed; they are not a permanent second implementation.
