# implementation

## ownership

`super-hotkey.ahk` loads the explicit AHK include tree. `SuiteApplication` owns the lifecycle, module switches and the single Keybindings manager. `SuiteInterface` owns the flat tray, Getting started guides, Settings and log window. `SuiteGui` supplies the icon and excludes suite windows from feature layout operations.

module IDs retain their legacy internal names for stable hotkey registration and layout ownership, but the default data root is `%LOCALAPPDATA%\nroj\SuperHotkey`. startup does not import the old suite or standalone settings.

## input and modules

Keybindings owns binding persistence, conflict validation, native registration and the recording UI. passive observers fan out to eligible modules. only registered complementary input scopes may share a signature; the Paper Pad editor scope is complementary to normal Wonder Windows navigation.

Secret Keys installs independent CapsLock/Pause prefixes when active. suspending hotkeys releases their interception, while retaining saved assignments; resuming reactivates the hooks only once all gate conditions are clear. queued actions are cancelled on suspension, reconfiguration or shutdown, without suspending background modules.

Wonder Windows claims manually moved windows. Cascade Kingdom respects that claim until explicit adoption. stale window ownership is rejected; changing focus alone does not adopt a window. optional FancyZones integration uses `modules/wonder-windows/fancyzones-settings.ps1` on demand, with user confirmation.

Paper Pad controls a dedicated Notepad3 instance, saves before hide, page switch and exit/restart, and may refuse unsafe operations. editor and note files are not altered by a suite reset; settings writes use atomic replacements and backups.

## testing and history

run `python tests/check.py` on Windows with AutoHotkey v2 64-bit. portable checks are available with `python -m unittest discover -s tests -p 'test_*.py'`. CI checks committed runtime sources; no source transformation runs as part of tests.

previous migration generators, original project snapshots, and the deprecated `super-hotkey-world.ahk` shim were removed from the current tree. Git history preserves those committed files. source repositories, pinned commits and licensing are documented in [source provenance](source-provenance.md).

physical keyboard hooks, multi-monitor layouts, Windows startup links and real Notepad3 saves still need manual acceptance.
