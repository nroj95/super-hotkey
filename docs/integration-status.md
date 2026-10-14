# integration status

## five-module preview

- Cascade Kingdom: automatic window management.
- Wonder Windows: manual Windows shortcuts, layouts, stretching, swapping and navigation.
- Power-Up Utilities: extra keyboard, text and system actions.
- Paper Pad: the preserved Notepad3 notes controller.
- Secret Keys: independently configurable CapsLock and Pause layers.

one launcher, process, tray and application icon. the flat tray opens each module's How to use page; lower-right buttons link to settings and the single shared Keybindings editor. disabled modules retain help and saved assignments. errors are always logged; verbose diagnostics have one global switch.

Wonder Windows uses the pinned Win Key Overhaul implementation with namespaced state. only explicit complementary input scopes may share a shortcut. Paper Pad retains its editor navigation while active. manual window geometry leaves the cascade until explicitly adopted; focus-only navigation does not claim geometry. Windows Snap and FancyZones configuration require explicit user actions and confirmation.

## validation boundaries

`python tests/check.py` checks the committed source, runs portable structural tests, parses every included AutoHotkey module and executes isolated native/GUI assertions. no migration generator runs during normal checks. native tests use temporary settings, dry-run callbacks and owned test windows, not real note documents or the user's workspace.

automated checks cannot establish physical keyboard-hook behavior, real Notepad3 save parity, multi-monitor placement, or suspend/resume reliability. no real sleep, audio or text-insertion action is invoked. this remains a preview until manual acceptance is complete.

## manual acceptance

1. verify the flat tray, five How to use pages, lower-right navigation, one shared Keybindings window and matching application icons. check all pages with modules disabled too.
2. test all four Caps/Pause combinations after restart. enabled prefixes provide held and one-shot shortcuts; disabled prefixes behave natively or follow explicit ordinary assignments. Ctrl + Alt + K must remain available with factory shortcuts.
3. compare Wonder Windows layouts, stretch, swap, fullscreen and spatial focus on real monitors. test interaction with Cascade Kingdom, manual ownership and explicit adoption. test one drag-snapping tool at a time.
4. use disposable Paper Pad notes first: new/switch/save/hide, disk conflicts, emoji-picker Escape, reload and pending editor dialogs. verify page shortcuts take precedence over Wonder Windows only in the pad context.
5. test module conflicts, both confirmed reset operations, save-aware exit/restart, global verbose logging, startup and suspend/resume. verify original notes, paths, profiles and standalone settings remain intact.

`main` and the standalone repositories remain migration checkpoints. do not delete or retire them before acceptance. no stable release has been published.
