"""Portable checks of the source layout and the architecture's boundaries."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = sorted((ROOT / 'core').glob('*.ahk'))
MODULES = sorted((ROOT / 'modules').rglob('*.ahk'))
RUNTIME = [ROOT / 'super-hotkey.ahk', *CORE, *MODULES]
MODULE_CLASSES = {'CascadeKingdomModule', 'WonderWindowsModule', 'PowerUpUtilities',
                  'PaperPadModule', 'SecretLayersModule'}


def source(path):
    return path.read_text(encoding='utf-8')


def code(path):
    """Source without ; comments, so prose never trips a structural rule."""
    return re.sub(r'(?m)(^|\s);.*$', r'\1', source(path))


class SuiteStructureTests(unittest.TestCase):
    def test_explicit_include_tree_is_complete(self):
        visited = set()

        def walk(path):
            if path in visited:
                return
            visited.add(path)
            for name in re.findall(r'(?m)^#Include\s+"([^"]+)"', source(path)):
                relative = name.replace('%A_ScriptDir%\\', '').replace('\\', '/')
                target = (ROOT / relative).resolve()
                self.assertTrue(target.is_relative_to(ROOT), name)
                self.assertTrue(target.is_file(), name)
                walk(target)

        walk(ROOT / 'super-hotkey.ahk')
        self.assertEqual(visited, {path.resolve() for path in RUNTIME})

    def test_global_names_do_not_collide(self):
        # Everything shares one AutoHotkey namespace across all files.
        definitions = {}
        for path in RUNTIME:
            for name in re.findall(r'(?m)^(?:class\s+)?([A-Za-z_]\w*)(?:\(|\s+(?:extends\s+\w+\s*)?\{)', source(path)):
                self.assertNotIn(name, definitions, f'{name}: {definitions.get(name)} and {path}')
                definitions[name] = path
        self.assertGreater(len(definitions), 300)

    def test_core_does_not_reach_into_modules(self):
        # Core may construct the module classes, nothing else from modules.
        owned = set()
        for path in MODULES:
            text = source(path)
            owned.update(re.findall(r'(?m)^([A-Za-z_]\w*)\(', text))
            owned.update(re.findall(r'(?m)^class\s+(\w+)', text))
            if path.name == 'settings.ahk':
                owned.update(re.findall(r'(?m)^([A-Za-z_]\w*)\s*:=', text))
        owned -= MODULE_CLASSES
        for path in CORE:
            used = set(re.findall(r'[A-Za-z_]\w*', code(path))) & owned
            self.assertEqual(used, set(), f'{path.name} uses module internals')

    def test_modules_do_not_reach_into_each_other(self):
        # Modules share behavior through core, such as SuiteManagedWindows.
        owned, declared = {}, {}
        for path in MODULES:
            text = source(path)
            module = path.parent.name
            owned.setdefault(module, set()).update(re.findall(r'(?m)^([A-Za-z_]\w*)\(', text),
                                                   re.findall(r'(?m)^class\s+(\w+)', text))
            for names in re.findall(r'(?m)^\s*global\s+(.+)$', code(path)):
                declared.setdefault(module, set()).update(
                    re.findall(r'([A-Za-z_]\w*)\s*(?::=[^,]*)?(?:,|$)', names))
        for path in MODULES:
            module = path.parent.name
            others = set().union(*(names for other, names in owned.items() if other != module))
            used = set(re.findall(r'[A-Za-z_]\w*', code(path))) & others
            self.assertEqual(used, set(), f'{path.relative_to(ROOT)} uses another module')
        for module, names in declared.items():
            for other, other_names in declared.items():
                if other != module:
                    self.assertEqual(names & other_names, set(), f'{module} and {other} share globals')

    def test_only_core_owns_the_tray(self):
        for path in RUNTIME:
            text = code(path)
            if path.name != 'tray.ahk':
                self.assertNotIn('A_TrayMenu', text, str(path))
            if path.parent.name != 'core':
                self.assertIsNone(re.search(r'(?<![\w.])Menu\(', text), str(path))

    def test_gui_construction_uses_one_icon_factory(self):
        for path in RUNTIME:
            if path.name == 'ui.ahk':
                continue
            self.assertIsNone(re.search(r'(?<![\w.])Gui\(', code(path)), str(path))
        self.assertEqual([path.name for path in (ROOT / 'assets').glob('*.ico')], ['super-hotkey.ico'])
        self.assertIn('CC BY 3.0', (ROOT / 'assets/ATTRIBUTION.md').read_text(encoding='utf-8'))

    def test_hotkeys_are_registered_by_the_input_layer(self):
        # Feature modules declare actions; only the input layer installs hooks.
        for path in MODULES:
            if path.parent.name == 'secret-layers':
                continue
            text = code(path)
            self.assertIsNone(re.search(r'(?<![\w.])Hotkey\(', text), str(path))
            self.assertNotRegex(text, r'(?m)^#HotIf\b')
            self.assertNotRegex(text, r'(?m)^#SingleInstance\b')

    def test_wonder_has_no_automatic_setup_writes(self):
        text = source(ROOT / 'modules/wonder-windows/module.ahk')
        # Snap and FancyZones changes are reachable only from the Settings page.
        lifecycle = text[text.index('    Start() {'):text.index('    ShowSettings(ui) {')]
        self.assertNotIn('WW_PromptToDisableNativeWindowsSnap()', lifecycle)
        self.assertNotIn('WW_CheckFancyZonesIntegration()', lifecycle)

    def test_sources_are_utf8_with_lf(self):
        for path in [*RUNTIME, *ROOT.glob('tests/*'), *ROOT.glob('modules/*/*.ps1')]:
            if path.is_dir():
                continue
            data = path.read_bytes()
            self.assertFalse(data.startswith(b'\xef\xbb\xbf'), f'{path}: BOM')
            self.assertNotIn(b'\r', data, f'{path}: CR')
            data.decode('utf-8')


if __name__ == '__main__':
    unittest.main()
