"""Materialize the reviewed runtime from pinned source snapshots, without Git writes.

This is a one-time migration tool, not an application dependency or plugin loader.
Only generated runtime paths are written; upstream snapshots and user data are read-only.
Run with --check to verify that the committed runtime matches these transformations.
"""
from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'migration' / 'upstream'
OUTPUTS: dict[str, bytes] = {}


def source(project: str, name: str, expected: str | None = None) -> str:
    data = (UPSTREAM / project / name).read_bytes()
    if expected and hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() != expected:
        raise ValueError(f'Pinned source changed: {project}/{name}; review before migrating.')
    return data.decode('utf-8-sig').replace('\r\n', '\n')


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f'Expected exactly one migration anchor: {old[:100]!r}')
    return text.replace(old, new, 1)


def block_end(text: str, start: int, opening: str = "{", closing: str = "}") -> int:
    """Skip AHK quoted strings, escaped characters and comments while counting braces."""
    depth, index = 0, start
    quote = ''
    while index < len(text):
        char = text[index]
        if quote:
            if char == '`':
                index += 2
                continue
            if char == quote:
                quote = ''
        elif char in '\"\'':
            quote = char
        elif char == ';' and (index == 0 or text[index - 1].isspace()):
            end = text.find('\n', index)
            index = len(text) if end < 0 else end
            continue
        elif text.startswith('/*', index):
            end = text.find('*/', index + 2)
            if end < 0:
                raise ValueError('Unclosed block comment')
            index = end + 2
            continue
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise ValueError('Unclosed AHK block')


def method_span(text: str, name: str, indent: int = 4) -> tuple[int, int]:
    matches = list(re.finditer(r'(?m)^' + ' ' * indent + r'(?:static )?' + re.escape(name) + r'\(', text))
    if len(matches) != 1:
        raise ValueError(f'Expected one definition of {name}, found {len(matches)}')
    start = matches[0].start()
    parameters = text.index('(', matches[0].start())
    parameters_end = block_end(text, parameters, '(', ')')
    body_start = parameters_end
    while body_start < len(text) and text[body_start].isspace():
        body_start += 1
    if text.startswith('=>', body_start):
        end = text.find('\n', body_start)
        return start, len(text) if end < 0 else end
    brace = text.find('{', parameters_end)
    if brace < 0:
        raise ValueError(f'Missing function body: {name}')
    return start, block_end(text, brace)


def method(text: str, name: str, replacement: str = '', indent: int = 4) -> str:
    start, end = method_span(text, name, indent)
    return text[:start] + replacement.rstrip() + text[end:]


def between(text: str, first: str, last: str, replacement: str) -> str:
    if text.count(first) != 1 or text.count(last) != 1:
        raise ValueError(f'Ambiguous migration range: {first!r}, {last!r}')
    start, end = text.index(first), text.index(last)
    if start >= end:
        raise ValueError('Reversed migration range')
    return text[:start] + replacement + text[end:]


def emit(path: str, text: str) -> None:
    OUTPUTS[path] = (text.rstrip() + '\n').encode('utf-8')


def replacement_file(name: str) -> str:
    return (ROOT / 'migration' / 'replacements' / name).read_text(encoding='utf-8')


def replace_definitions(text: str, replacements: str, indent: int = 4) -> str:
    names = re.findall(r'(?m)^' + ' ' * indent + r'(?:static )?(\w+)\(', replacements)
    for name in names:
        start, end = method_span(replacements, name, indent)
        body = replacements[start:end]
        if re.search(r'(?m)^' + ' ' * indent + r'(?:static )?' + re.escape(name) + r'\(', text):
            text = method(text, name, body, indent)
        else:
            opening = text.index('{', re.search(r'(?m)^class \w+', text).start())
            closing = block_end(text, opening) - 1
            text = text[:closing] + '\n' + body + '\n' + text[closing:]
    return text


def keybindings() -> None:
    text = source('keybindings', 'lib/keybindings.ahk', 'eb6ab85765e0ee904dbbb17161315f2eb1ddf10f')
    text = text[text.index('class Keybindings {'):]
    text = between(text, '    DiscoverParticipants() {', '    static DisplayRows(', '')
    for name in ['_PublishedCatalogSnapshot', '_OwnerMutexName', '_OwnerAlive', '_Lock', '_Unlock',
                 '_Owners', '_Maintain', '_Notice', '_TellPeer', 'WasExplicitlyEdited']:
        text = method(text, name)
    text = replace_definitions(text, replacement_file('keybindings.ahk'))
    text = text.replace('static Version := "0.2.0-preview.6"', 'static Version := "suite-preview.1"')
    text = replace_once(text, '        key := Keybindings._BaseKey(keyName)',
        '        key := Keybindings._BaseKey(keyName)\n'
        '        if layer != "normal" && key.activation\n'
        '            throw ValueError("A layer activation key cannot also be its suffix.")')
    text = replace_once(text, 'return {layer: layer, modifiers: mask, key: key.code, mouse: key.mouse,',
        'return {layer: layer, modifiers: mask, key: key.code, mouse: key.mouse, activationKey: key.activation,')
    text = replace_once(text, '        this.externalCapture := DllCall("FindWindowW", "ptr", 0,\n'
        '            "str", this.captureTitle, "ptr") != 0',
        '        this.externalCapture := IsObject(this.recording)')
    text = replace_once(text,
        'if InStr(route.state, "conflict:") = 1 || route.state = "unavailable: no layer adapter"',
        'if InStr(route.state, "unavailable:") = 1')
    text = replace_once(text, '                        route.action.repeat)',
        '                        route.action.repeat, route.action.context)')
    text = replace_once(text, '        if vk = 0x1B {',
        '        bare := this._CaptureLayer() = "normal" && Keybindings.ModifierMask() = 0\n'
        '        if vk = 0x1B && bare {')
    text = replace_once(text, '        if vk = 0x08 || vk = 0x2E {',
        '        if (vk = 0x08 || vk = 0x2E) && bare {')
    text = text.replace('"reset mine"', '"Reset all shortcuts"')
    text = text.replace('"x268 y" footerY " w140 h31"', '"x244 y" footerY " w180 h31"')
    text = text.replace('"x422 y" footerY " w130 h31"', '"x438 y" footerY " w130 h31"')
    text = replace_once(text, '        window.OnEvent("Close", ObjBindMethod(this, "_RequestCloseSettings"))',
        '        window.OnEvent("ContextMenu", ObjBindMethod(this, "_EditBindingText"))\n'
        '        window.OnEvent("Close", ObjBindMethod(this, "_RequestCloseSettings"))')
    text = text.replace('"search..."', '"search... (right-click a shortcut to type it)"')
    # Cancel held normal outputs when their explicit context or a local layer takes over.
    text = replace_once(text, '                || Keybindings.ModifierMask() != route.binding.modifiers {',
        '                || Keybindings.ModifierMask() != route.binding.modifiers\n'
        '                || !this.ContextActive(route.action)\n'
        '                || (IsObject(this.client) && this.client.OwnsInput(key)) {')
    text = replace_once(text,
        '                    || this.applying || Keybindings.ModifierMask() != press.route.binding.modifiers) {',
        '                    || this.applying || Keybindings.ModifierMask() != press.route.binding.modifiers\n'
        '                    || !this.ContextActive(press.route.action)\n'
        '                    || (IsObject(this.client) && this.client.OwnsInput(key))) {')
    text = text.replace('libraryDirectory "\\..\\icons\\keybindings.ico"',
                        'A_ScriptDir "\\assets\\keybindings.ico"')
    # Remove comments tied to the retired independent-process design.
    lines = text.splitlines()
    text = '\n'.join(line for line in lines if not (line.lstrip().startswith(';') and
        re.search(r'(?i)peer|remote|protocol 1|cross-process|registry lock|participating|owning script', line)))
    for forbidden in ['SendMessageTimeoutW', 'CreateMutexW', 'RegisterWindowMessageW', 'this._Owners(',
                      'this.ownerControl', 'this._Maintain(', 'RequestRemoteSlotEdit']:
        if forbidden in text:
            raise ValueError(f'Retired Keybindings infrastructure remains: {forbidden}')
    emit('core/keybindings.ahk', '#Requires AutoHotkey v2.0\n\n'
         '; Shared in-process manager. Parser, recorder, GUI and data codec retain upstream behavior.\n'
         '; Runtime availability and explicit contexts do not overwrite saved assignments.\n\n' + text)


def layers() -> None:
    text = source('caps-pause-layers', 'caps-pause-layers.ahk', 'a887abe5fa5f3c51001f33ddc9510a213663e1c0')
    names = ['CPL_PrefixDown', 'CPL_PrefixUp', 'CPL_FinishPrefix', 'CPL_Disarm', 'CPL_ExpireArm',
             'CPL_StartObserver', 'CPL_UpdateObserver', 'CPL_ObserveKey', 'CPL_ObserveRelease',
             'CPL_ModifierMask', 'CPL_ModifierSymbols', 'CPL_RouteKey', 'CPL_RoutePredicate',
             'CPL_GuardPredicate', 'CPL_EnsureKeyGroup', 'CPL_EnsureRouteVariant', 'CPL_KeyDown',
             'CPL_KeyGuardDown', 'CPL_KeyUp', 'CPL_FinishPress', 'CPL_CancelLayerPresses',
             'CPL_UpdateReleaseTimer', 'CPL_CheckReleases', 'CPL_Reset', 'CPL_Indicator',
             'CPL_ForegroundHidesIndicator']
    parts = []
    for name in names:
        start, end = method_span(text, name, 0)
        parts.append(text[start:end])
    result = '\n\n'.join(parts)
    result = replace_once(result, 'if !press.finished && (!CPL_ClientAlive(press.route.client)\n'
        '            || !press.route.enabled',
        'if !press.finished && (!CPL.enabled || !press.route.enabled')
    # Pointer-sized direct callbacks replace delivery/lease checks in the local adapter.
    result = result.replace('before posting an event', 'before delivering an event')
    result = result.replace('while the service is idle', 'while the layer is idle')
    emit('modules/keyboard-layers/state-machine.ahk',
         '; Preserved held/one-shot state machine; lifecycle and dispatch are in keyboard-layers.ahk.\n\n' + result)


def power_hotkey() -> None:
    text = source('power-hotkey', 'power-hotkey.ahk', '9e2e6afcf6d7e5fea02a9467e7daf6bad8126a4a')
    text = text[text.index('class PowerHotkeys {'):]
    for name in ['PowerEvent', 'ResumeInputs', 'UpdatePause', 'BuildTray', 'OfferClassicFKeys',
                 'ApplyClassicFKeysManually', 'ToggleStartup', 'UpdateStartupMenu', 'FindLegacyLayers']:
        text = method(text, name)
    text = replace_definitions(text, replacement_file('power-hotkey.ahk'))
    text = replace_once(text, '        catch Error as commandError {',
        '        catch Error as commandError {\n            SuiteState.Log.Error("Power Hotkey", commandError)')
    text = text.replace('static Version := "0.1.0-preview.2"', 'static Version := "suite-preview.1"')
    emit('modules/power-hotkey/power-hotkey.ahk',
         '; Existing command dispatch and safety checks, using the suite-owned manager.\n\n' + text)
    for name in ['modules.ahk', 'keyboard.ahk', 'terminal.ahk', 'utilities.ahk']:
        helper = source('power-hotkey', 'power-hotkey/' + name)
        helper = helper.replace('The layer service owns suppressed inputs.', 'The local layer owns suppressed inputs.')
        emit('modules/power-hotkey/' + name, helper)


def window_cascade() -> None:
    folder = UPSTREAM / 'window-cascade' / 'window-cascade'
    names = sorted(path.name for path in folder.glob('*.ahk'))
    for name in names:
        text = source('window-cascade', 'window-cascade/' + name)
        text = text.replace('A_TrayMenu', 'SuiteState.CascadeMenu')
        text = text.replace('\\icons\\', '\\assets\\')
        text = text.replace('separate Caps + Pause Layers service', 'enabled Caps + Pause Layers module')
        text = text.replace('A_IconTip :=', 'SuiteState.CascadeStatus :=')
        if name == 'settings.ahk':
            text = replace_once(text, 'settings_directory := EnvGet("LOCALAPPDATA") "\\Window Cascade"',
                'settings_directory := SuiteState.App.Settings.directory "\\window-cascade"')
            text = replace_once(text, 'debug_log_path := settings_directory "\\window-cascade-debug.log"',
                                'debug_log_path := SuiteState.Log.path')
            text = 'InitializeCascadeState()\n{\n    global\n' + text + '\n}\n'
        elif name == 'keybindings.ahk':
            text = replace_once(text, 'InitializeCascadeKeybindings()', 'InitializeCascadeKeybindings(manager)')
            text = between(text, '    manager := Keybindings(',
                           "    ; Preserve the user's previous", '')
            text = replace_once(text, '    CascadeAddAction(manager, "keybindings", "open Keybindings",\n'
                                '        -3, "Caps + K")', '')
            text = replace_once(text, 'manager.AddAction(id, label,',
                                'manager.AddAction("window-cascade." id, label,')
            text = replace_once(text, '[binding], {category: "Window Cascade"})',
                '[binding], {category: "Window Cascade",\n'
                '            available: (*) => SuiteState.App.ModuleActive("window-cascade")})')
            text = replace_once(text, '    try manager.Start()\n    catch Error as failure {\n'
                '        try manager.Stop()\n        cascade_keybindings := 0\n        throw failure\n    }', '')
            text = method(text, 'ShutdownCascadeKeybindings', '', 0)
            # Dry-run callbacks terminate before window, clipboard or log-reset actions.
            anchor = '    if event.phase != "down"\n        return'
            text = replace_once(text, anchor, anchor + '\n    if SuiteState.App.dryRun {\n'
                '        SuiteState.Log.Write("Window Cascade", "dry run: " event.actionId)\n'
                '        return\n    }')
        elif name == 'controls.ahk':
            start = text.index('\nIsExplorerSpaceReshowIntentContext()\n')
            text = '; Native mouse observations are registered by the shared manager.\n' + text[start:]
        elif name == 'interface.ahk':
            text = method(text, 'ToggleStartup', '', 0)
            text = text.replace('    SuiteState.CascadeMenu.Add("Run at startup", ToggleStartup)\n', '')
            text = text.replace('    SuiteState.CascadeMenu.AddStandard()\n', '')
            text = text.replace('    SuiteState.CascadeMenu.Delete("&Pause Script")\n', '')
            text = text.replace('    SuiteState.CascadeMenu.Delete("&Suspend Hotkeys")\n', '')
            text = replace_once(text, '    if FileExist(startup_shortcut_path)\n'
                '        SuiteState.CascadeMenu.Check("Run at startup")\n    else\n'
                '        SuiteState.CascadeMenu.Uncheck("Run at startup")', '')
            text = replace_once(text, '    for actionId, action in cascade_keybindings.actions {',
                '    for actionId, action in cascade_keybindings.actions {\n'
                '        if !InStr(actionId, "window-cascade.")\n            continue')
        elif name == 'debug.ahk':
            text = method(text, 'InitializeDebugLogging',
                'InitializeDebugLogging() {\n    DebugLogSession("enabled")\n}', 0)
            text = method(text, 'RotateDebugLogIfNeeded', '', 0)
            text = method(text, 'LogUnhandledError', '', 0)
            text = method(text, 'DebugLog', 'DebugLog(message) {\n'
                '    SuiteState.Log.Write("Window Cascade", message)\n}', 0)
            text = method(text, 'DebugError', 'DebugError(context, failure) {\n'
                '    SuiteState.Log.Error("Window Cascade / " context, failure)\n}', 0)
            text = method(text, 'ResetDebugLog', 'ResetDebugLog() {\n'
                '    SuiteState.Log.Clear()\n    return true\n}', 0)
        if re.search(r'(?m)^IsCascadeEnabled\(', text):
            text = method(text, 'IsCascadeEnabled', 'IsCascadeEnabled() {\n'
                '    return SuiteState.App.ModuleActive("window-cascade") && !SuiteState.App.dryRun\n}', 0)
        if re.search(r'(?m)^[^;\n]*::', text):
            raise ValueError(f'Unmigrated Window Cascade hotkey: {name}')
        emit('modules/window-cascade/' + name, text)
    emit('modules/window-cascade/include.ahk', '\n'.join(
        '#Include "%A_ScriptDir%\\modules\\window-cascade\\' + name + '"' for name in names))


def scratchpad() -> None:
    text = source('scratchpad', 'scratchpad.ahk', '073042871cced0bfd6ac7f4478b44dd30b10f239')
    text = text[text.index('\nScratchpadEditorFocused()\n') + 1:]
    text = replace_once(text, '    if !IsSet(scratchpad) || !scratchpad.HasWindow()',
        '    if !IsSet(scratchpad) || !IsObject(scratchpad) || !scratchpad.HasWindow()')
    boundary = text.index('class ScratchpadTextChangedError')
    controller, bridge = text[:boundary], text[boundary:]
    controller = replace_once(controller, '    __New()\n', '    __New(dataDirectory)\n')
    controller = replace_once(controller, 'this.data_directory := EnvGet("LOCALAPPDATA") "\\Scratchpad"',
        'this.data_directory := dataDirectory')
    controller = replace_once(controller, 'this.error_log := this.data_directory "\\errors.log"',
        'this.error_log := SuiteState.Log.path')
    controller = replace_once(controller, '        OnExit ObjBindMethod(this, "OnScriptExit")', '')
    controller = replace_once(controller,
        '        configured_hotkey := IniRead(this.settings_path, "Controls", "ToggleHotkey", "Win+F12")\n'
        '        this.SetToggleHotkey(configured_hotkey, false)', '')
    controller = replace_definitions(controller, replacement_file('scratchpad.ahk'))
    controller = replace_once(controller, '        try FileAppend detail, this.error_log, "UTF-8-RAW"',
        '        SuiteState.Log.Error("Scratchpad", failure)')
    controller = controller.replace('A_TrayMenu', 'SuiteState.ScratchpadMenu')
    controller = controller.replace('A_IconTip :=', 'SuiteState.ScratchpadStatus :=')
    # Retire the separate toggle editor and per-module startup controls.
    for name in ['HandleToggleHotkey', 'SetToggleHotkey', 'ParseToggleHotkey', 'CanonicalKeyName',
                 'FriendlyFromHotkeyControl', 'ChooseToggleHotkey', 'ShowCustomHotkeyDialog',
                 'UpdateToggleHotkeyMenu', 'DisplayHotkeyName', 'ToggleStartup']:
        if re.search(r'(?m)^    ' + name + r'\(', controller):
            controller = method(controller, name)
    controller = controller.replace('this.toggle_hotkey_callback := ObjBindMethod(this, "HandleToggleHotkey")',
                                    'this.toggle_hotkey_callback := 0')
    # A failed constructor must not retain the original controller mutex or timers.
    start, end = method_span(controller, '__New')
    constructor = controller[start:end]
    opening = constructor.index('{')
    body = constructor[opening + 1:-1]
    wrapped = constructor[:opening + 1] + '\n        this.mutex_handle := 0\n        try {\n' + body + '\n        }\n'
    wrapped += '''        catch Error as failure {
            for name in ["autosave_callback", "page_lock_sync_callback", "process_commands_callback"]
                if HasProp(this, name)
                    SetTimer(this.%name%, 0)
            if HasProp(this, "page_lock_handle")
                try this.ReleasePageLock()
            if HasProp(this, "controller_window")
                try this.controller_window.Destroy()
            if this.mutex_handle {
                DllCall("CloseHandle", "ptr", this.mutex_handle)
                this.mutex_handle := 0
            }
            throw failure
        }
    }'''
    controller = controller[:start] + wrapped + controller[end:]
    text = (controller + bridge).replace('\\icons\\', '\\assets\\')
    emit('modules/scratchpad/scratchpad.ahk',
         '; Preserved Notepad3 controller; shared shortcuts, logging and save-aware suite lifecycle.\n\n' + text)


def assets() -> None:
    for project, name in [('keybindings', 'keybindings.ico'), ('scratchpad', 'scratchpad.ico'),
                          ('window-cascade', 'window-cascade.ico')]:
        OUTPUTS['assets/' + name] = (UPSTREAM / project / 'icons' / name).read_bytes()
    for project, name, target in [
        ('keybindings', 'ATTRIBUTION.md', 'keybindings-ATTRIBUTION.md'),
        ('window-cascade', 'ATTRIBUTION.md', 'window-cascade-ATTRIBUTION.md'),
        ('window-cascade', 'fatcow-readme.txt', 'fatcow-readme.txt')]:
        OUTPUTS['assets/' + target] = (UPSTREAM / project / 'icons' / name).read_bytes()
    OUTPUTS['LICENSE'] = (UPSTREAM / 'keybindings' / 'LICENSE').read_bytes()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify generated files without writing.')
    args = parser.parse_args()
    keybindings()
    layers()
    power_hotkey()
    window_cascade()
    scratchpad()
    assets()
    # All transformations finish before any output is written.
    changed = [name for name, content in OUTPUTS.items()
               if not (ROOT / name).is_file() or (ROOT / name).read_bytes() != content]
    if args.check and changed:
        raise SystemExit('Runtime needs materialization: ' + ', '.join(changed))
    if not args.check:
        for name in changed:
            path = ROOT / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(OUTPUTS[name])
    print(f'{len(OUTPUTS)} runtime/source-attribution files verified; {len(changed)} changed.')


if __name__ == '__main__':
    main()
