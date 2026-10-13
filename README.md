# Super Hotkey World

a modular Windows productivity suite built from the existing AutoHotkey utilities.

**status: integration preview, not a stable release.** the shared runtime is implemented; physical keyboard, window-management and Notepad3 acceptance testing remains necessary before replacing the originals. see `docs/integration-status.md`.

## run

requires Windows and **64-bit AutoHotkey v2**. Scratchpad additionally uses the existing dedicated Notepad3 editor; its bridge was originally written for Notepad3 7.26.602.1. one AutoHotkey process does not mean eliminating the Notepad3 process.

close the original Window Cascade, Power Hotkey, Scratchpad and keyboard-layer scripts before launching `super-hotkey-world.ahk`. the suite does not stop them or remove their startup entries automatically.

```powershell
python .\tests\check.py
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' .\super-hotkey-world.ahk --dry-run
```

`--dry-run` opens the shared editor with isolated temporary settings, no active shortcuts, no window management and no Notepad3 launch. omit it for normal operation. `--check` only parses the entire suite and exits. pass `--autohotkey PATH` to the test runner when AutoHotkey is installed elsewhere.

## controls

all four modules are enabled initially. **Modules → Apply and restart** changes their availability. Keybindings is always available from the tray; its defaults are **Caps + K** and **Ctrl + Alt + K**. terminal clearing now defaults to **Caps + Ctrl + K**, avoiding the old collision.

click either shortcut slot to record. right-click a slot to enter a key name, including bare Escape, CapsLock or Pause. disabled modules keep their editable assignments without reserving inputs. disabled layers leave their assignments inactive; normal replacements still work. an enabled layer owns its prefix keys, so ordinary CapsLock/Pause assignments remain inactive until layers are disabled.

Scratchpad's global toggle defaults to **Win + F12**. its save, navigation, new-page, delete and hide commands are contextual: they only intercept input inside its owned editor. Caps/Pause retains held chords and short-tap one-shot behavior.

## settings and data

suite settings and the rotating `debug.log` live in `%LOCALAPPDATA%\nroj\SuperHotkeyWorld`. the first normal start copies existing Window Cascade and Scratchpad preferences/state/editor-profile files when the suite copies do not exist. original files are not modified. Scratchpad continues using its configured notes folder.

**old standalone shortcut assignments are not imported automatically.** the suite starts with the reconciled factory catalog; the original keybinding files remain intact.

**Reset all shortcuts** restores assignments, including disabled modules, without changing module choices. **Restore factory defaults** also re-enables modules and resets a whitelist of preferences, with a settings backup. neither deletes notes, changes their folder/editor path, or deletes the Notepad3 profile. both require confirmation. a Scratchpad save failure can veto exit or restart.

## development

`core/` owns lifecycle, settings, logging and the shared manager. `modules/` contains in-process feature implementations. `migration/upstream/` retains the pinned references and their licenses; Shell Folders is not part of this repository.

`migration/integrate.py` is a one-time source migration, not a runtime dependency or plugin loader. it verifies major source hashes and materializes the adapted files; `--check` verifies the committed result. the development-branch Windows workflow checks the migration and native runtime before committing generated outputs. do not run the original entry points as part of the suite.

retain the original installations and repositories until the manual acceptance checks pass. source licenses and icon attribution are retained under `LICENSE`, `assets/` and the reference snapshots.
