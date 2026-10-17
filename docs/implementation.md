# implementation

## ownership

`super-hotkey.ahk` loads the explicit AHK include tree. `SuiteApplication` owns the lifecycle, module switches and single Keybindings manager. `SuiteInterface` owns the flat tray, Getting started guides, Settings and log window.

`SuiteGui` supplies the shared icon and excludes suite windows from automatic cascading. Wonder Windows can arrange normal suite GUIs and the marked Paper Pad editor; private overlays remain excluded. Keybindings fits its opening viewport to the current monitor's work area, accounting for DPI and the native frame.

module IDs retain their legacy names to preserve saved assignments and layout ownership. settings use `%LOCALAPPDATA%\nroj\SuperHotkey`; startup does not import older suite or standalone settings. Paper Pad notes default to `%USERPROFILE%\Scratchpad`, separate from preferences.

## input and modules

Keybindings owns persistence, conflict validation, native registration and recording. registered disjoint scopes may share a hotkey, and an application-specific route takes priority over a global fallback. Paper Pad editor navigation and Windows Terminal macros stay contextual.

Secret Keys installs only enabled CapsLock/Pause prefixes. disabling a layer restores its native key unless that key was explicitly reassigned. saved assignments remain editable. Apply changes live; Cancel, Back and closing the editor discard uncommitted edits.

reconfiguration and input gating invalidate module queues and deferred callbacks. cancelled utility presses are discarded, not treated as releases. Paper Pad tags hotkey requests so they cannot replay after a pause; direct UI operations and save-safety work remain available.

tray suspension, Windows sleep and session locking gate input and pause Cascade Kingdom. automatic power resume cannot clear a session lock or explicit tray suspension. windows opened during suspension remain unmanaged on resume.

new windows stay unmanaged by default unless the user enables the persistent Automatically cascade newly opened windows checkbox. CapsLock-assisted taskbar, Start, desktop and Explorer launches capture one short-lived opt-in, including the mouse monitor; the first eligible new window consumes it. automatic mode instead selects the pointer monitor at discovery and preserves it during deferred placement. a held CapsLock at window discovery is a fallback. deferred placement keeps the captured display identity. A startup-hidden Explorer HWND may enter a cascade on its first foreground reveal when auto mode or CapsLock is active; other startup windows stay protected. CapsLock plus native title-bar double-click explicitly adopts an existing normal or maximized window. a disconnected destination falls back to primary. wrong-monitor corrections remain bounded.

Wonder Windows claims manually positioned windows until explicit cascade adoption. stale ownership is rejected. focus-tab rendering reuses the validated per-monitor DPI snapshot instead of repeating monitor discovery inside its critical section. optional FancyZones changes require confirmation.

Paper Pad controls a dedicated Notepad3 instance and saves before hiding, switching pages or exiting. unsafe operations can be refused. resets preserve notes, editor paths and page state; settings writes use atomic replacements and backups.

## testing and history

see [release checks](integration-status.md) for automated checks and desktop acceptance. CI tests the committed source without regeneration. the live implementation is in `core/` and `modules/`; historical migration scripts and source snapshots are not runtime dependencies.

original repositories, pinned commits and licensing are listed in [source provenance](source-provenance.md).
