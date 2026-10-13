# integration status

## implemented in this preview

one launcher, one AutoHotkey manager/process/tray, four default-enabled modules, restart-based module choices, local Caps/Pause routing, editable inactive assignments, reconciled factory shortcuts, central rotating logging, and separate confirmed reset operations. Power Hotkey dispatch and Window Cascade algorithms are adapted from the pinned implementations. Scratchpad retains its Notepad3 save/ownership code with shared contextual shortcuts and save-aware shutdown.

no old repository, startup entry or original settings file is deleted. the suite intentionally starts a new shortcut configuration rather than silently interpreting the old independent owners' files.

## automated checks

`python tests/check.py` runs migration helper tests, verifies materialized files against the pinned transformations, parses every included AutoHotkey module, and runs isolated native assertions. these cover the factory catalog, disabled assignments, conflict rejection without overwriting, explicit contexts, ordinary CapsLock/Pause assignments with layers disabled, parser safety rules, log rotation, reset scope and a busy Scratchpad restart veto.

tests use temporary data and dry-run callbacks. they do **not** prove physical keyboard-hook behavior, real window placement, Notepad3 saves, suspend/resume, or multi-monitor correctness. no real sleep, audio or text-insertion action is invoked.

## manual acceptance before daily use

- confirm one AutoHotkey process/tray; all four module combinations should start or produce an actionable error. test a fresh configuration and the copied Scratchpad/Window Cascade preferences.
- test Caps/Pause held chords, one-shot timeout/cancellation, modifier changes and release order on the actual Norwegian keyboard. check synthesized F13–F24/numpad releases, pause/unlock/resume, and no stuck input after opening settings.
- disable layers, restart, and verify native CapsLock/Pause. replace an inactive layer assignment with an ordinary shortcut, including an explicitly assigned CapsLock/Pause key. disable a feature module and reuse its shortcut; re-enabling must reject a conflict without overwriting assignments.
- compare Window Cascade placement, monitor switching, focus tabs, drag/drop, minimize/restore and exit recovery with the standalone version. confirm the suite's own windows are not cascaded. retain the existing ScreenGrid/FancyZones compatibility precautions.
- test Scratchpad toggle, editor-only commands, emoji-picker Escape, checked saves, page switching, disk-conflict refusal, reload/undo retention and an exit with a pending Notepad3 dialog. test a disposable notes folder first.
- confirm both reset dialogs default to cancellation. verify disabled assignments reset as intended, while note files, notes/editor paths, editor profile, page state and backups remain intact.

## release boundary

this branch is a migration preview, not a declaration of behavior parity. phase 5 remains open until manual acceptance is complete. phase 6 (stable release and retirement of the original repositories) has not started.
