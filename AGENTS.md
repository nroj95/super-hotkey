# implementation constraints

- target AutoHotkey v2, 64-bit Windows. preserve working behavior before adding features.
- this checkpoint is a source baseline, not a working suite. do not claim otherwise.
- start with `docs/initial-audit.md` and inspect complete implementations before changing their lifecycle.
- use one launcher, one process, one tray, one shared Keybindings manager, and simple modules.
- keep module action IDs globally unique. check the whole effective binding set before registration.
- disabled feature modules release inputs but retain editable assignments and personal data.
- disabling layers leaves native CapsLock/Pause behavior unless explicitly rebound; normal bindings still work.
- an unavailable layer binding is not the same thing as a disabled action.
- support contextual editor shortcuts explicitly; never turn Scratchpad navigation into accidental global hotkeys.
- module toggles may require a restart. do not implement dynamic plugin loading or profiles.
- route errors into a single rotating log. preserve actionable errors rather than swallowing them.
- reset shortcuts separately from factory settings. confirm both; neither may delete notes or other personal data.
- do not rewrite the existing source repositories, migrate Git history, or add submodules.
- retain source licenses and icon attribution. keep `migration/upstream` as reference until each migration is reviewed.
- never launch real power/sleep/text actions from automated checks. use isolated settings directories and dry-run actions.
- preserve LF, descriptive names, and the existing comment style; keep added documentation concise.
