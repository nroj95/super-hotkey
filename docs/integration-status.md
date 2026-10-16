# release checks

## automated checks

on Windows with AutoHotkey v2 64-bit and Python:

```powershell
python tests/check.py
```

use `--autohotkey 'C:\path\to\AutoHotkey64.exe'` for a nonstandard installation. portable structural checks can also run separately:

```powershell
python -m unittest discover -s tests -p 'test_*.py'
```

CI runs on pull requests and pushes to `main`. it checks the committed source: portable structure tests, a complete launcher parse, and isolated native/GUI regressions. temporary preferences, test-owned windows and inert command callbacks keep these checks away from personal notes and real sleep, audio or text-output actions.

regressions cover module/layer availability, scoped conflicts, staged editing, geometry ownership, GUI layout, cancelled/deferred commands, lock/resume state and Paper Pad request expiry. check the actual CI result for the revision being released; a successful parse alone is not a passing test suite.

## desktop acceptance before tagging

these require a real desktop and are not replaced by CI:

1. test held, one-shot and double-tap CapsLock/Pause input; disable each layer and confirm native keys return. record, apply and cancel assignments. suspend with a key held and check for stuck output or delayed actions after resuming.
2. test Cascade Kingdom and Wonder Windows together: new windows, adoption, drag placement, stretch/restore, constrained-window swaps, focus tabs and minimize/restore. hold CapsLock while opening a new window; change the hold-to-skip setting to Pause and Disabled; check queued windows never cascade after release. verify this works with each keyboard layer disabled. include mixed DPI, negative monitor coordinates, a disconnected display and virtual desktops.
3. use disposable Paper Pad pages: new, save, rename, switch, hide, delete to Recycle Bin and exit/restart. test external file changes, pending Notepad3 dialogs and a missing or unresponsive editor. verify that real notes remain untouched by resets.
4. test startup-link creation/removal, module settings, verbose logging and confirmed resets. verify settings persist in the intended folder. keep old standalone scripts stopped.
5. test actual sleep/unlock and tray suspension together. inspect input recovery and automatic placement, including windows opened while paused. test system utilities deliberately, not as part of the automated harness.

also inspect Help, Settings and Keybindings on the intended display scaling. Keybindings needs room for an 820 × 520 logical-pixel layout; text-only Help pages grow to fit their guides. CI's small desktop does not certify every high-DPI display configuration.

publish a release tag only after desktop acceptance. no cleanup or reset should delete standalone repositories or personal files.
