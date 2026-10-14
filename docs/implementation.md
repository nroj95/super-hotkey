# implementation

## ownership

`super-hotkey.ahk` loads explicit includes. `SuiteApplication` owns startup, shutdown, module choices and the one Keybindings manager. `SuiteInterface` owns the flat tray, help, settings and global log viewer. `SuiteGui` applies the shared application icon and marks suite windows before showing them.

module IDs and preference directories stay stable across the user-facing renames. Wonder Windows has its own `win-key-overhaul.*` action IDs and namespaced `WW_` functions/state. no plugin discovery, background layer service, inter-process owner registry or separate module startup entries are used.

## input

Keybindings owns assignments, persistence, conflict checks and registration. native input observers fan out identical passive observations to participating modules. only an explicitly registered scope and its exact complement may share a signature; arbitrary context predicates do not bypass conflicts. the `paper-pad` scope keeps editor commands separate from Wonder Windows.

Secret Keys installs only enabled prefixes. disabling a prefix preserves assignments and permits explicit native-key reassignment. module/layer changes use restart-based lifecycle. queued work is invalidated on configuration, suspension and shutdown. callbacks use short dispatch paths and defer window operations.

## geometry and data

Wonder Windows claims per-window manual ownership before geometry changes. Cascade Kingdom ignores these windows until explicit adoption; stale HWND/process ownership is rejected. focus-only navigation does not detach windows. original layout and save algorithms remain adapted source, not a wholesale rewrite.

Paper Pad saves before exit/restart and may veto when a command or editor dialog is unresolved. changing its paths first closes the owned editor through checked saves, never moves notes, and leaves ordinary editor windows alone. settings updates use same-directory replacement and backups. reset scope is whitelisted; note data and editor state are excluded.

## development

run `python tests/check.py` on Windows with AutoHotkey v2 64-bit. portable tests are available with `python -m unittest discover -s tests -p 'test_*.py'`. CI tests committed runtime files rather than regenerating them. historical source transforms and pinned upstream snapshots remain for provenance, not normal editing or runtime loading.

physical keyboard, multi-monitor and Notepad3 acceptance remains necessary; automated dry-run success is not a claim of complete behavior parity.
