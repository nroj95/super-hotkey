"""One-time reviewed five-module migration. Runtime files, not this script, are the product.

Read the pinned original runtime and Win Key Overhaul snapshot; stage all transforms
before writing repository files. Never read or alter the user's application data.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = '8a23f74ead746e422186071e87d3065de1bf27d8'
UI_BASE = 'fbb3da3ed9ba737b552675a6b2d1332b0eabfd7a'
WW_COMMIT = '02a28d906868a883a33d3081c1bd4bd7ad0e0274'
spec = importlib.util.spec_from_file_location('old_migration', ROOT / 'migration/integrate.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
OUTPUTS: dict[str, bytes] = {}
BASE_DIRECTORY: Path | None = None
UI_DIRECTORY: Path | None = None


def baseline(name: str, ui: bool = False) -> str:
    directory = UI_DIRECTORY if ui else BASE_DIRECTORY
    data = (directory / name).read_bytes() if directory else subprocess.run(
        ['git', 'show', f'{UI_BASE if ui else BASE}:{name}'], cwd=ROOT,
        check=True, stdout=subprocess.PIPE).stdout
    return data.decode('utf-8-sig').replace('\r\n', '\n')


def emit(name: str, text: str) -> None:
    OUTPUTS[name] = (text.rstrip() + '\n').encode('utf-8')


def body(text: str, name: str, indent: int = 0) -> str:
    start, end = old.method_span(text, name, indent)
    return text[start:end]


def patch_method(text: str, name: str, transform, indent: int = 0) -> str:
    return old.method(text, name, transform(body(text, name, indent)), indent)


def rewrite(text: str, identifiers: dict[str, str] | None = None, labels: bool = False) -> str:
    """Replace AHK tokens without touching native names, strings, comments or object fields."""
    identifiers = identifiers or {}
    pattern = re.compile(r'''(?P<comment>/\*[\s\S]*?\*/|(?<!\S);[^\n]*)|(?P<string>"(?:`[\s\S]|[^"`])*"|'(?:`[\s\S]|[^'`])*')|(?P<identifier>[A-Za-z_]\w*)''')
    def replace(match):
        token = match.group()
        if match.lastgroup == 'identifier' and (match.start() == 0 or text[match.start()-1] != '.'):
            return identifiers.get(token, token)
        if labels and match.lastgroup == 'string' and '\\' not in token and 'nroj.' not in token:
            for original, renamed in [('Window Cascade', 'Cascade Kingdom'), ('Win Key Overhaul', 'Wonder Windows'),
                ('Power Hotkey', 'Power-Up Utilities'), ('Scratchpad', 'Paper Pad'), ('Caps + Pause Layers', 'Secret Keys')]:
                token = token.replace(original, renamed)
        return token
    return pattern.sub(replace, text)


def strip_debug_globals(text: str) -> str:
    def remaining(match):
        names = [value.strip() for value in match[2].split(',')]
        names = [name for name in names if name not in {'debug_enabled', 'debug_verbose_enabled'}]
        return match[1] + 'global ' + ', '.join(names) if names else ''
    text = re.sub(r'(?m)^(\s*)global ([\w, ]+)$', remaining, text)
    text = re.sub(r'(?m)^\s*debug_(?:verbose_)?enabled := (?:true|false)\s*$', '', text)
    return rewrite(text, {'debug_enabled': 'SuiteState.Log.verbose', 'debug_verbose_enabled': 'SuiteState.Log.verbose'})


def keybindings() -> None:
    text = baseline('core/keybindings.ahk')
    text = old.replace_once(text, '        this.actions := Map()',
        '        this.scopes := Map()\n        this.observerGroups := Map()\n        this.actions := Map()')
    text = old.replace_once(text, '        this.actions[actionId] := {',
        '        scope := Keybindings.Option(options, "scope", "")\n'
        '        scopeName := SubStr(scope, 1, 1) = "!" ? SubStr(scope, 2) : scope\n'
        '        if scope != "" && !this.scopes.Has(scopeName)\n'
        '            throw ValueError("Unknown input scope: " scope)\n'
        '        this.actions[actionId] := {scope: scope,')
    text = old.replace_definitions(text, (ROOT / 'migration/ui-replacements/keybindings.ahk').read_text(encoding='utf-8'))
    text = old.replace_once(text, '            this.routeMap[binding.signature] := route',
        '            if !this.routeMap.Has(binding.signature)\n'
        '                this.routeMap[binding.signature] := []\n'
        '            this.routeMap[binding.signature].Push(route)')
    text = old.replace_once(text, 'route.action.repeat, route.action.context)',
        'route.action.repeat, ObjBindMethod(this, "ContextActive", route.action))')
    text = old.replace_once(text, '            route := this.routeMap[signature]',
        '            route := this._SelectedRoute(signature)\n            if !IsObject(route)\n                return')
    text = text.replace(' && this.client.bindings.Length', '')
    text = old.replace_once(text, '        this.observers := []\n        if IsObject(this.client)',
        '        this.observers := []\n        this.observerGroups.Clear()\n        if IsObject(this.client)')
    emit('core/keybindings.ahk', rewrite(text, {'Gui': 'SuiteGui'}))


def layers() -> None:
    text = baseline('modules/keyboard-layers/state-machine.ahk')
    text = old.replace_once(text, 'if !CPL.enabled || CPL.stopping || CPL.blockedPrefixes.Has(physicalKey)',
        'if !CPL.enabled || CPL.stopping || !CPL.enabledLayers[layerName] || CPL.blockedPrefixes.Has(physicalKey)')
    text = old.replace_once(text, '    if !CPL.routes.Has(routeKey) || !CPL_RouteEligible(CPL.routes[routeKey])',
        '    if !IsObject(CPL_SelectRoute(routeKey))')
    text = old.method(text, 'CPL_RoutePredicate',
        'CPL_RoutePredicate(routeKey, *) => IsObject(CPL_SelectRoute(routeKey))', 0)
    text = old.replace_once(text, '    route := CPL.routes[routeKey]',
        '    route := CPL_SelectRoute(routeKey)\n    if !IsObject(route)\n        return')
    text = old.replace_once(text, 'if vk = 0x14 || vk = 0x13 || vk = 0x03\n        || vk = 0x10',
        'if (vk = 0x14 && CPL.enabledLayers["caps"])\n'
        '        || ((vk = 0x13 || vk = 0x03) && CPL.enabledLayers["pause"])\n        || vk = 0x10')
    text = old.replace_once(text, 'if !press.finished && (!CPL.enabled || !press.route.enabled\n',
        'if !press.finished && (!CPL.enabled || !press.route.enabled\n'
        '            || (HasMethod(press.route.context, "Call") && !press.route.context.Call())\n')
    emit('modules/keyboard-layers/state-machine.ahk', text)


def application() -> None:
    text = baseline('core/application.ahk')
    legacy = body(text, 'ImportLegacyModuleSettings', 4)
    text = text.replace('    static CascadeMenu := 0\n', '').replace('    static ScratchpadMenu := 0\n', '')
    text = text.replace('        SuiteState.CascadeMenu := Menu()\n', '').replace('        SuiteState.ScratchpadMenu := Menu()\n', '')
    text = text.replace('0.1.0-preview.1', '0.2.0-preview.1')
    text = old.replace_once(text, '        this.activeModules := this.Settings.modules.Clone()',
        '        this.activeModules := this.Settings.modules.Clone()\n'
        '        this.activeLayers := this.Settings.layers.Clone()\n'
        '        this.wonder := 0\n        this.wonderStarted := false')
    text = old.replace_once(text, '        SuiteState.Log := SuiteLog(directory)',
        '        SuiteState.Log := SuiteLog(directory, 2097152, this.Settings.verbose)\n        SuiteIcons.Initialize()')
    text = old.replace_once(text, '            if this.ModuleActive("scratchpad") {',
        '            if this.ModuleActive("win-key-overhaul") {\n'
        '                this.wonderStarted := true\n                this.wonder.Start()\n            }\n'
        '            if this.ModuleActive("scratchpad") {')
    text = old.replace_once(text, '        InitializeCascadeState()',
        '        InitializeCascadeState()\n        WW_InitializeState()')
    text = old.replace_once(text, '        if this.ModuleActive("keyboard-layers")\n'
        '            options.layerFactory := (name, status) => LocalKeyboardLayers(name, status)',
        '        if this.ModuleActive("keyboard-layers") && (this.activeLayers["caps"] || this.activeLayers["pause"])\n'
        '            options.layerFactory := (name, status) => LocalKeyboardLayers(name, status, this.activeLayers)')
    text = old.replace_once(text, '        this.manager.AddAction("core.keybindings",',
        '        this.manager.RegisterScope("paper-pad", PaperPadWindowActive)\n        this.manager.AddAction("core.keybindings",')
    text = old.replace_once(text, '        ScratchpadModule.Register(this.manager)',
        '        ScratchpadModule.Register(this.manager)\n        this.wonder := WonderWindowsModule(this.manager, this.dryRun)')
    text = old.replace_once(text, '    CancelInputs() {',
        '    CancelInputs() {\n        if IsObject(this.wonder)\n            this.wonder.CancelWork()')
    text = old.replace_once(text, '        modulesOpen := IsObject(this.ui) && IsObject(this.ui.modulesWindow)',
        '        modulesOpen := IsObject(this.ui) && this.ui.HasSettingsOpen()\n'
        '        if !IsObject(this.manager) || this.manager.disposed\n            return')
    text = old.replace_once(text, '        if this.cascadeStarted\n            this.Cleanup',
        '        if IsObject(this.ui)\n            this.Cleanup("Core / interfaces", ObjBindMethod(this.ui, "CloseAll"))\n'
        '        if this.wonderStarted\n            this.Cleanup("Wonder Windows", (*) => this.wonder.Stop(reason, code))\n'
        '        if this.cascadeStarted\n            this.Cleanup')
    text = old.replace_once(text, '        OnMessage(0x0218, this.powerCallback, 0)',
        '        SuiteWindowOwnership.Clear()\n        OnMessage(0x0218, this.powerCallback, 0)')
    text = text.replace('window-cascade|power-hotkey|scratchpad|caps-pause-layers|',
        'window-cascade|win-key-overhaul|windows-key-overhaul|window-hotkeys|power-hotkey|scratchpad|caps-pause-layers|')
    text = rewrite(text, labels=True)
    text = old.method(text, 'ImportLegacyModuleSettings', legacy, 4)
    emit('core/application.ahk', text)
    launcher = baseline('super-hotkey-world.ahk')
    launcher = old.replace_once(launcher, '#Include "%A_ScriptDir%\\core\\application.ahk"',
        '#Include "%A_ScriptDir%\\core\\windows.ahk"\n#Include "%A_ScriptDir%\\core\\help.ahk"\n#Include "%A_ScriptDir%\\core\\application.ahk"')
    launcher = old.replace_once(launcher, '#Include "%A_ScriptDir%\\modules\\scratchpad\\adapter.ahk"',
        '#Include "%A_ScriptDir%\\modules\\scratchpad\\adapter.ahk"\n#Include "%A_ScriptDir%\\modules\\wonder-windows\\include.ahk"\n'
        '#Include "%A_ScriptDir%\\modules\\wonder-windows\\adapter.ahk"')
    emit('super-hotkey-world.ahk', launcher)


def cascade() -> None:
    folder = ROOT / 'modules/window-cascade'
    for path in folder.glob('*.ahk'):
        name = path.name
        text = baseline('modules/window-cascade/' + name)
        if name == 'interface.ahk':
            parts = [body(text, item) for item in ['ShowCascadeStatusTip', 'HideCascadeStatusTip', 'CheckCompatibilitySettings']]
            text = '; Cascade Kingdom navigation is owned by the suite interface.\n\n' + '\n\n'.join(parts)
            text += '''

UpdateTrayMenu() {
    global cascade_auto_placement_paused
    SuiteState.CascadeStatus := cascade_auto_placement_paused ? "Cascade Kingdom (placement paused)" : "Cascade Kingdom"
}

ToggleWindowCascadeHelp(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.ShowHelp("window-cascade")
}

CloseWindowCascadeHelp(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.CloseWindow("help:window-cascade")
}

RefreshCascadeHelpBindings(*) {
    if IsObject(SuiteState.App.ui)
        SuiteState.App.ui.RefreshHelp()
}
'''
        elif name == 'adapter.ahk':
            text = text.replace('        BuildTrayMenu()\n', '').replace('        SetTimer(CheckCompatibilitySettings, -500)\n', '')
        elif name == 'debug.ahk':
            text = old.method(text, 'ToggleVerboseDebugLogging', '', 0)
            text = old.method(text, 'DebugLog',
                'DebugLog(message) => SuiteState.Log.Debug("Cascade Kingdom", message)', 0)
        elif name == 'settings.ahk':
            text = old.replace_once(text, 'settings_path := settings_directory "\\settings.ini"',
                'settings_path := settings_directory "\\settings.ini"\n'
                'focus_corner_visible := IniRead(settings_path, "FocusTabs", "Visible", "1") = "1"')
            text = old.replace_once(text, 'cascade_auto_placement_paused := false',
                'cascade_auto_placement_paused := IniRead(settings_path, "Controls", "AutoPlacementPaused", "0") = "1"')
        elif name == 'windows.ahk':
            text = old.replace_once(text,
                '    return !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.WindowCascade.Ignore", "ptr")',
                '    return SuiteWindowOwnership.IsManual(hwnd)\n'
                '        || !!DllCall("GetPropW", "ptr", hwnd, "str", "nroj.WindowCascade.Ignore", "ptr")')
        elif name == 'commands.ahk':
            text = old.replace_once(text, '    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor)\n        return',
                '    was_manual := SuiteWindowOwnership.Release(hwnd)\n'
                '    if undo_snapshot\n        undo_snapshot["was_manual"] := was_manual\n'
                '    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor) {\n'
                '        if was_manual\n            SuiteWindowOwnership.Claim(hwnd)\n        return\n    }')
            text = patch_method(text, 'UndoPendingAdoption', lambda part: old.replace_once(part,
                '    QueueFocusCornerUpdate()\n    return true',
                '    if snapshot.Has("was_manual") && snapshot["was_manual"]\n'
                '        SuiteWindowOwnership.Claim(hwnd)\n    QueueFocusCornerUpdate()\n    return true'))
        elif name == 'keybindings.ahk':
            text = old.replace_once(text, '[binding], {category: "Window Cascade",\n'
                '            available: (*) => SuiteState.App.ModuleActive("window-cascade")})',
                '[binding], {category: commandId < 0 ? "Super Hotkey World" : "Cascade Kingdom",\n'
                '            available: (*) => commandId < 0 || SuiteState.App.ModuleActive("window-cascade")})')
            text = old.method(text, 'CascadeResetLogFromBinding',
                'CascadeResetLogFromBinding(*) => SuiteState.App.ui.ClearLog()', 0)
            text = old.method(text, 'CascadeCopyLogFromBinding',
                'CascadeCopyLogFromBinding(*) => SuiteState.App.ui.CopyLog()', 0)
        text = strip_debug_globals(text)
        text = rewrite(text, {'Gui': 'SuiteGui'}, labels=True)
        emit('modules/window-cascade/' + name, text)


def paper_and_utilities() -> None:
    text = baseline('modules/scratchpad/adapter.ahk')
    text = old.replace_once(text, '                    context: ScratchpadEditorFocused})',
        '                    scope: "paper-pad", context: ScratchpadEditorFocused})')
    emit('modules/scratchpad/adapter.ahk', rewrite(text, labels=True))
    text = baseline('modules/scratchpad/scratchpad.ahk')
    text = text.replace('        this.BuildTrayMenu()\n', '')
    for name in ['BuildTrayMenu', 'BuildMonitorMenu', 'MonitorMenuLabel', 'SetMonitorTarget', 'UpdateMonitorMenu',
        'SetWindowSizePercent', 'UpdateWindowSizeMenu', 'UpdateTrayChecks']:
        text = old.method(text, name)
    text = old.method(text, 'WelcomeText', '''    WelcomeText() {
        return "# Welcome to Paper Pad`n`n"
            . "Open Paper Pad from the Super Hotkey World tray for instructions.`n"
            . "Use Keybindings to see and change the current shortcuts.`n`n"
            . "Your pages are ordinary files. Start typing below.`n`n"
    }''')
    text = old.method(text, 'ShowHelp',
        '    ShowHelp(*) => SuiteState.App.ui.ShowHelp("scratchpad")')
    # These fields existed only to back tray submenus; keep the save/controller code intact.
    first = text.index('        this.startup_shortcut := ')
    last = text.index('        this.mutex_handle := 0', first)
    text = text[:first] + text[last:]
    emit('modules/scratchpad/scratchpad.ahk', rewrite(text, {'Gui': 'SuiteGui'}, labels=True))
    for name in ['power-hotkey.ahk', 'modules.ahk', 'keyboard.ahk', 'terminal.ahk', 'utilities.ahk']:
        text = baseline('modules/power-hotkey/' + name)
        if name == 'power-hotkey.ahk':
            for line in ['        this.modulesWindow := 0\n', '        this.statusWindow := 0\n', '        this.log := []\n',
                         '        PH_Modules.CloseStatus(this)\n']:
                text = text.replace(line, '')
            text = old.replace_once(text, 'case "interface": this.OpenKeybindings()',
                'case "interface": SuiteState.App.ui.ShowHelp("power-hotkey")')
            text = old.method(text, 'OpenKeybindings')
            text = old.method(text, 'Report',
                '    Report(text) => SuiteState.Log.Write("Power-Up Utilities", text)')
        elif name == 'modules.ahk':
            for method in ['ShowStatus', 'RefreshStatus', 'CloseStatus']:
                text = old.method(text, method)
            text = text.replace('"open Power Hotkey"', '"show Power-Up Utilities help"')
        emit('modules/power-hotkey/' + name, rewrite(text, labels=True))


def wonder_windows() -> None:
    source = ROOT / 'migration/upstream/win-key-overhaul/win-key-overhaul'
    files = {path.name: path.read_text(encoding='utf-8-sig').replace('\r\n', '\n') for path in source.glob('*.ahk')}
    symbols = set()
    for text in files.values():
        symbols.update(re.findall(r'(?m)^([A-Za-z_]\w*)\(', text))
        for names in re.findall(r'(?m)^\s*global ([\w, ]+)$', text):
            symbols.update(name.strip() for name in names.split(','))
    symbols.update(re.findall(r'(?m)^([a-z_]\w*) :=', files['settings.ahk']))
    namespaced = {name: 'WW_' + name for name in symbols}
    namespaced['Gui'] = 'SuiteGui'
    files.pop('controls.ahk')
    files.pop('interface.ahk')
    settings = files['settings.ahk']
    settings = settings[:settings.index('startup_shortcut_path :=')] + settings[settings.index('screengrid_releases_url :='):]
    settings = settings[:settings.index('debug_enabled :=')]
    files['settings.ahk'] = 'WW_InitializeState() {\n    global\n' + rewrite(settings, namespaced) + '\n}'
    startup = files['startup.ahk']
    files['startup.ahk'] = '\n\n'.join(body(startup, name) for name in ['GetNativeWindowsSnapState',
        'PromptToDisableNativeWindowsSnap', 'OpenWindowsSnapSettings', 'IsScreenGridRunning', 'OpenScreenGridReleases'])
    files['startup.ahk'] = files['startup.ahk'].replace('Open Recommended setup from the tray', 'Open Wonder Windows Settings')
    debug = files['debug.ahk']
    files['debug.ahk'] = '''DebugLog(message) => SuiteState.Log.Debug("Wonder Windows", message)

DebugError(context, failure) => SuiteState.Log.Error("Wonder Windows / " context, failure)

''' + body(debug, 'DebugDescribeWindow')
    files['debug.ahk'] = strip_debug_globals(files['debug.ahk'])
    files['fancyzones.ahk'] = patch_method(files['fancyzones.ahk'], 'CheckFancyZonesStartup',
        lambda part: old.replace_once(part, '    CheckFancyZonesIntegration()',
            '    fancyzones_integration_state := ReadFancyZonesIntegrationState()'))
    files['fancyzones.ahk'] = files['fancyzones.ahk'].replace('        KeyWait(direction)\n', '')
    files['fancyzones.ahk'] = files['fancyzones.ahk'].replace('"\\win-key-overhaul\\fancyzones-settings.ps1"',
        '"\\modules\\wonder-windows\\fancyzones-settings.ps1"')
    # Input actions may be reassigned; helper comparisons must not depend on label casing.
    files['fancyzones.ahk'] = files['fancyzones.ahk'].replace('direction = "Up" || direction = "Down"',
        'StrLower(direction) = "up" || StrLower(direction) = "down"')
    files['windows.ahk'] = patch_method(files['windows.ahk'], 'RunWindowCommand', lambda part: old.replace_once(
        old.replace_once(part, '    previous_dpi_context := 0',
            '    previous_dpi_context := 0\n    previous_win_delay := A_WinDelay\n    SetWinDelay 10'),
        '        Critical previous_critical', '        SetWinDelay previous_win_delay\n        Critical previous_critical'))
    for filename, function_names in {'windows.ahk': ['IsWindowToggleCandidate'],
        'swapping.ahk': ['IsWindowSwapCandidate']}.items():
        for name in function_names:
            files[filename] = patch_method(files[filename], name, lambda part: old.replace_once(part,
                '    if !hwnd\n', '    if !hwnd || SuiteWindowOwnership.IsSuiteSurface(hwnd)\n'))
    files['window-state.ahk'] = patch_method(files['window-state.ahk'], 'GetWindowControlTarget',
        lambda part: old.replace_once(part, '    return WinExist("A")',
            '    hwnd := WinExist("A")\n'
            '    if !hwnd || SuiteWindowOwnership.IsSuiteSurface(hwnd)\n        return 0\n'
            '    try return IsWinKeyOverhaulShellClass(WinGetClass(hwnd)) ? 0 : hwnd\n    catch\n        return 0'))
    # Claim before the first geometry mutation, including both sides of swaps.
    claims = {'layouts.ahk': ['PrepareWindowForPlacement', 'MoveWindowToVisibleHorizontalBounds',
        'MoveWindowToVisibleVerticalBounds'], 'windows.ahk': ['MoveWindowToVisibleRectangle', 'ApplyWindowPlacement'],
        'borderless.ahk': ['EnterBorderlessFullscreen']}
    for filename, function_names in claims.items():
        for name in function_names:
            def insert_claim(part):
                paren = old.block_end(part, part.index('('), '(', ')')
                opening = part.index('{', paren)
                return part[:opening+1] + '\n    SuiteWindowOwnership.Claim(hwnd)' + part[opening+1:]
            files[filename] = patch_method(files[filename], name, insert_claim)
    for name in ['MaximizeWindowTarget', 'RestoreWindowTarget']:
        files['window-state.ahk'] = patch_method(files['window-state.ahk'], name,
            lambda part: old.replace_once(part, '    if !hwnd\n        return',
                '    if !hwnd\n        return\n    SuiteWindowOwnership.Claim(hwnd)'))
    for name, text in files.items():
        transformed = rewrite(text, namespaced, labels=True) if name != 'settings.ahk' else rewrite(text, labels=True)
        transformed = re.sub(r'^; Internal Win Key Overhaul module[^\n]*\n',
            '; Wonder Windows implementation. Launch the suite, not this file.\n', transformed)
        emit('modules/wonder-windows/' + name, transformed)
    helper = source / 'fancyzones-settings.ps1'
    OUTPUTS['modules/wonder-windows/fancyzones-settings.ps1'] = helper.read_bytes()
    includes = ['settings.ahk', 'window-state.ahk', 'layout-geometry.ahk', 'layouts.ahk', 'swapping.ahk',
        'focus.ahk', 'window-switcher.ahk', 'borderless.ahk', 'fancyzones.ahk', 'windows.ahk', 'startup.ahk', 'debug.ahk']
    emit('modules/wonder-windows/include.ahk', '; Explicit includes; no auto-execution or plugin discovery.\n' +
        '\n'.join('#Include "%A_ScriptDir%\\modules\\wonder-windows\\' + name + '"' for name in includes))
    manifest = json.loads(baseline('migration/source-manifest.json'))
    manifest['sources'].append({'name': 'win-key-overhaul', 'url': 'https://github.com/nroj95/win-key-overhaul.git',
        'commit': WW_COMMIT})
    manifest['tracked_file_counts']['win-key-overhaul'] = sum(path.is_file() for path in source.parent.rglob('*'))
    emit('migration/source-manifest.json', json.dumps(manifest, indent=2))


def interfaces_and_tests() -> None:
    text = baseline('core/windows.ahk', True)
    text = old.replace_once(text, '    static Claim(hwnd) {',
        '    static Claim(hwnd) {\n        if IsObject(SuiteState.App) && SuiteState.App.stopping\n            return')
    emit('core/windows.ahk', text)
    text = baseline('core/tray.ahk', True)
    text = text.replace('w760 h390 ReadOnly +VScroll"', 'w760 h390 ReadOnly +VScroll vhelpText"')
    text = text.replace('["Edit1"]', '["helpText"]')
    emit('core/tray.ahk', text)
    text = baseline('tests/runtime-check.ahk')
    text = text.replace('enabled = 4', 'enabled = 5').replace('all four modules', 'all five modules')
    text = old.replace_once(text, '        this.CheckDryRunLifecycle()',
        '        this.CheckDryRunLifecycle()\n        SuiteUpgradeChecks.Run()')
    emit('tests/runtime-check.ahk', text)
    text = baseline('tests/check.py')
    text = old.replace_once(text, "    run([sys.executable, 'migration/integrate.py', '--check'])\n", '')
    text = old.replace_once(text, '        stream.write(\'#Include "%A_ScriptDir%\\\\tests\\\\runtime-check.ahk"',
        '        stream.write(\'#Include "%A_ScriptDir%\\\\tests\\\\upgrade-check.ahk"\\n\')\n'
        '        stream.write(\'#Include "%A_ScriptDir%\\\\tests\\\\runtime-check.ahk"')
    emit('tests/check.py', text)
    OUTPUTS['assets/super-hotkey-world.ico'] = (ROOT / 'migration/upstream/keybindings/icons/keybindings.ico').read_bytes()
    attribution = (ROOT / 'migration/upstream/keybindings/icons/ATTRIBUTION.md').read_text(encoding='utf-8')
    emit('assets/ATTRIBUTION.md', attribution.replace('keybindings.ico', 'super-hotkey-world.ico'))


def main() -> None:
    global BASE_DIRECTORY, UI_DIRECTORY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-directory', type=Path)
    parser.add_argument('--ui-directory', type=Path)
    args = parser.parse_args()
    BASE_DIRECTORY, UI_DIRECTORY = args.baseline_directory, args.ui_directory
    keybindings()
    layers()
    application()
    cascade()
    paper_and_utilities()
    wonder_windows()
    interfaces_and_tests()
    for name, content in OUTPUTS.items():
        path = ROOT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for name in ['keybindings.ico', 'scratchpad.ico', 'window-cascade.ico', 'keybindings-ATTRIBUTION.md', 'window-cascade-ATTRIBUTION.md']:
        (ROOT / 'assets' / name).unlink(missing_ok=True)
    print(f'Materialized {len(OUTPUTS)} reviewed runtime and test files. No user settings were accessed.')


if __name__ == '__main__':
    main()
