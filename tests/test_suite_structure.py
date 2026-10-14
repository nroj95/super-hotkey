"""Portable checks for the shipped source layout, not regeneration of runtime code."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = [ROOT / 'super-hotkey-world.ahk', *sorted((ROOT / 'core').glob('*.ahk')),
           *sorted((ROOT / 'modules').rglob('*.ahk'))]


class SuiteStructureTests(unittest.TestCase):
    def test_explicit_include_tree_is_complete(self):
        visited = set()
        def walk(path):
            if path in visited:
                return
            visited.add(path)
            for name in re.findall(r'(?m)^#Include\s+"([^"]+)"', path.read_text(encoding='utf-8-sig')):
                relative = name.replace('%A_ScriptDir%\\', '').replace('\\', '/')
                target = (ROOT / relative).resolve()
                self.assertTrue(target.is_relative_to(ROOT), name)
                self.assertTrue(target.is_file(), name)
                walk(target)
        walk(ROOT / 'super-hotkey-world.ahk')
        self.assertEqual(visited, {path.resolve() for path in RUNTIME})

    def test_global_function_names_do_not_collide(self):
        definitions = {}
        for path in RUNTIME:
            for name in re.findall(r'(?m)^([A-Za-z_]\w*)\(', path.read_text(encoding='utf-8-sig')):
                self.assertNotIn(name, definitions, f'{name}: {definitions.get(name)} and {path}')
                definitions[name] = path
        self.assertGreater(len(definitions), 300)

    def test_only_core_owns_the_tray(self):
        for path in RUNTIME:
            if path.name == 'tray.ahk':
                continue
            self.assertNotIn('A_TrayMenu.', path.read_text(encoding='utf-8-sig'), str(path))

    def test_modules_have_no_tray_submenus(self):
        for path in (ROOT / 'modules').rglob('*.ahk'):
            self.assertIsNone(re.search(r'(?<!\w)Menu\(', path.read_text(encoding='utf-8-sig')), str(path))

    def test_gui_construction_uses_one_icon_factory(self):
        for path in RUNTIME:
            if path.name == 'windows.ahk' and path.parent.name == 'core':
                continue
            self.assertIsNone(re.search(r'(?<!\w)Gui\(', path.read_text(encoding='utf-8-sig')), str(path))
        self.assertEqual([path.name for path in (ROOT / 'assets').glob('*.ico')], ['super-hotkey-world.ico'])
        self.assertIn('CC BY 3.0', (ROOT / 'assets/ATTRIBUTION.md').read_text())

    def test_debug_switches_are_not_owned_by_modules(self):
        for path in (ROOT / 'modules').rglob('*.ahk'):
            text = path.read_text(encoding='utf-8-sig')
            self.assertNotRegex(text, r'(?m)^\s*(?:WW_)?Toggle(?:Verbose)?DebugLogging\(')
            self.assertNotRegex(text, r'(?m)^\s*(?:WW_)?debug_(?:verbose_)?enabled\s*:=')

    def test_feature_modules_do_not_register_unmanaged_actions(self):
        for path in (ROOT / 'modules').rglob('*.ahk'):
            if path.parent.name == 'keyboard-layers':
                continue
            text = path.read_text(encoding='utf-8-sig')
            self.assertNotRegex(text, r'(?<!\w)Hotkey\(')
            self.assertNotRegex(text, r'(?m)^#HotIf\b')
            self.assertNotRegex(text, r'(?m)^#SingleInstance\b')

    def test_names_and_original_ids_are_preserved(self):
        text = (ROOT / 'core/settings.ahk').read_text()
        for name in ['Cascade Kingdom', 'Wonder Windows', 'Power-Up Utilities', 'Paper Pad', 'Secret Keys']:
            self.assertIn(name, text)
        for identifier in ['window-cascade', 'win-key-overhaul', 'power-hotkey', 'scratchpad', 'keyboard-layers']:
            self.assertIn(f'"{identifier}"', text)

    def test_wonder_source_is_pinned(self):
        manifest = json.loads((ROOT / 'migration/source-manifest.json').read_text())
        sources = {entry['name']: entry['commit'] for entry in manifest['sources']}
        self.assertEqual(sources['win-key-overhaul'], '02a28d906868a883a33d3081c1bd4bd7ad0e0274')
        path = ROOT / 'migration/upstream/win-key-overhaul/win-key-overhaul/layout-geometry.ahk'
        data = path.read_bytes()
        digest = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        self.assertEqual(digest, 'aaf242ab4bd7cd0a397a2e9d592a939a37c0410b')

    def test_wonder_has_no_automatic_setup_writes(self):
        text = (ROOT / 'modules/wonder-windows/adapter.ahk').read_text()
        self.assertNotIn('WW_PromptToDisableNativeWindowsSnap()', text)
        self.assertNotIn('WW_CheckFancyZonesIntegration()', text)
        text = (ROOT / 'modules/wonder-windows/fancyzones.ahk').read_text()
        startup = text[:text.index('WW_ReassertFancyZonesKeyboardHook(*)')]
        self.assertNotIn('WW_CheckFancyZonesIntegration()', startup)
        self.assertNotIn('KeyWait(direction)', text)

    def test_old_source_generators_are_not_part_of_normal_checks(self):
        text = (ROOT / 'tests/check.py').read_text()
        self.assertNotIn("'migration/integrate.py'", text)
        self.assertNotIn("'migration/upgrade-ui.py'", text)

    def test_legacy_paper_paths_and_window_markers_remain(self):
        text = (ROOT / 'modules/scratchpad/scratchpad.ahk').read_text()
        self.assertIn('nroj.Scratchpad.Notepad3Window', text)
        self.assertIn('nroj.Scratchpad.Controller', text)
        self.assertIn('"\\Scratchpad"', text)
        self.assertNotIn('this.toggle_hotkey_name', text)
        self.assertIn('SuiteState.App.ui.ShowHelp("scratchpad")', text)


if __name__ == '__main__':
    unittest.main()
