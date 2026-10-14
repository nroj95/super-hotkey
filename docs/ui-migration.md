# five-module UI migration

## implemented

human-facing names are Cascade Kingdom, Wonder Windows, Power-Up Utilities, Paper Pad and Secret Keys. existing internal IDs, note locations and editor/window markers remain stable. Wonder Windows is imported from `nroj95/win-key-overhaul` at `02a28d906868a883a33d3081c1bd4bd7ad0e0274`; the original snapshot and license are retained without importing its Git history.

the flat tray opens module Getting started guides first. Keybindings alone lists and edits shortcuts; the guides explain module behavior instead of duplicating assignments. module preferences live in their Settings GUIs, while Run at startup, Suspend hotkeys, Restart Super Hotkey, Reset to defaults, the settings folder and Verbose logging are directly available in the tray. Suspension uses the shared input gate, allowing background features to continue and returning CapsLock/Pause to native behavior until hotkeys resume. the separate App settings window, former module submenus, Power Hotkey status window, per-module debugging switches and runtime icons were removed. GUI content uses a shared Cascadia Mono font.

Secret Keys uses persistent independent CapsLock/Pause flags beneath the existing module master switch. only enabled prefixes are hooked. inactive layer bindings stay saved and editable. ordinary CapsLock/Pause assignments are allowed when their corresponding layer is disabled.

explicit complementary contexts allow Paper Pad navigation and Wonder Windows layouts to share Win-arrow shortcuts without weakening other conflict checks. passive observers with the same native input variant fan out to all eligible module callbacks. manual layout ownership uses both process identity and a window property to reject stale HWND reuse. explicit cascade adoption clears obsolete manual stretch/restore history, preventing later cleanup from undoing the cascade.

## verification and maintenance

the first Windows migration run passed 22 Python tests and 277 native assertions, including every module help/settings page. follow-up ownership checks cover discarded stretch/restore history. the normal workflow now tests the actual committed files with read-only repository permissions; it does not regenerate or push source.

the temporary migration workflow and new one-time transformation scripts were removed after materialization. their reviewed transformations remain in Git history. edit `core/` and `modules/` directly; the older initial migration helpers are historical reference, not runtime dependencies.

this is not a stable release. use the manual acceptance checks in `integration-status.md`, particularly physical keyboard layers, multi-monitor behavior and real Notepad3 saves. original repositories, standalone startup entries and personal files have not been modified by this repository patch.
