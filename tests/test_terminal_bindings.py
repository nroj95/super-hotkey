"""Windows Terminal binding resolution using disposable settings fixtures."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'modules/power-up-utilities/terminal-bindings.ps1'


@unittest.skipUnless(sys.platform == 'win32', 'requires Windows PowerShell 5.1')
class TerminalBindingsTests(unittest.TestCase):
    def check(self, version='1.24.12741.0', settings=None, raw=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, result = root / 'settings.json', root / 'result.txt'
            if settings is not None or raw is not None:
                path.write_text(raw if raw is not None else json.dumps(settings), encoding='utf-8')
            process = subprocess.run([
                str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'),
                '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(HELPER),
                '-TerminalVersion', version, '-SettingsPath', str(path), '-ResultPath', str(result)
            ], capture_output=True, text=True, timeout=20)
            return process.returncode, result.read_text(encoding='utf-8-sig')

    def bindings(self, settings=None, version='1.24.12741.0', raw=None):
        code, output = self.check(version, settings, raw)
        self.assertEqual(code, 0, output)
        lines = output.splitlines()
        self.assertEqual(lines[0], 'OK', output)
        return dict(line.split('=', 1) for line in lines[1:])

    def test_defaults(self):
        self.assertEqual(self.bindings(), {
            'CLEAR': '^+k', 'COPY': '^+c', 'SELECT': '^+a', 'SAFE_CLEAR_STEPS': '1'})
        self.assertEqual(self.bindings(version='1.23.10353.0')['CLEAR'], '')
        self.assertEqual(self.bindings(version='1.22.11141.0')['COPY'], '^+c')

    def test_alt_bindings_override_defaults(self):
        settings = {'keybindings': [
            {'id': '', 'keys': 'ctrl+shift+k'},
            {'id': 'Terminal.ClearBuffer', 'keys': 'ctrl+shift+l'},
            {'id': '', 'keys': 'ctrl+shift+c'},
            {'id': 'Terminal.CopyToClipboard', 'keys': 'alt+shift+c'},
            {'id': '', 'keys': 'ctrl+shift+a'},
            {'id': 'Terminal.SelectAll', 'keys': 'ctrl+alt+a'}]}
        self.assertEqual(self.bindings(settings), {
            'CLEAR': '^+l', 'COPY': '!+c', 'SELECT': '^!a', 'SAFE_CLEAR_STEPS': '1'})

    def test_ui_generated_custom_action(self):
        settings = {'actions': [{'id': 'User.clearBuffer.87C324ED',
                                 'command': {'action': 'clearBuffer', 'clear': 'all'}}],
                    'keybindings': [
                        {'id': '', 'keys': 'ctrl+shift+k'},
                        {'id': 'User.clearBuffer.87C324ED', 'keys': 'ctrl+shift+l'}]}
        self.assertEqual(self.bindings(settings)['CLEAR'], '^+l')
        self.assertEqual(self.bindings(settings, version='1.23.10353.0')['CLEAR'], '^+l')

    def test_custom_equivalent_actions(self):
        settings = {'actions': [
            {'id': 'User.copy', 'command': {'action': 'copy', 'singleLine': False}},
            {'id': 'User.select', 'command': 'selectAll'}],
            'keybindings': [
                {'id': '', 'keys': 'ctrl+shift+c'},
                {'id': '', 'keys': 'ctrl+shift+a'},
                {'id': 'User.copy', 'keys': 'alt+shift+c'},
                {'id': 'User.select', 'keys': 'ctrl+alt+a'}]}
        self.assertEqual(self.bindings(settings)['COPY'], '!+c')
        self.assertEqual(self.bindings(settings)['SELECT'], '^!a')

    def test_legacy_inline_command(self):
        settings = {'actions': [{'command': {'action': 'clearBuffer', 'clear': 'all'},
                                 'keys': 'ctrl+shift+l'}],
                    'keybindings': [{'id': '', 'keys': 'ctrl+shift+k'}]}
        self.assertEqual(self.bindings(settings)['CLEAR'], '^+l')

    def test_prefer_still_active_default(self):
        settings = {'keybindings': [{'id': 'Terminal.ClearBuffer', 'keys': 'ctrl+shift+l'}]}
        self.assertEqual(self.bindings(settings)['CLEAR'], '^+k')

    def test_missing_copy_uses_ctrl_c(self):
        settings = {'keybindings': [{'id': '', 'keys': 'ctrl+shift+c'}]}
        self.assertEqual(self.bindings(settings)['COPY'], '^c')

    def test_unknown_actions_do_not_steal_default(self):
        settings = {'keybindings': [
            {'id': 'User.unknown', 'keys': 'ctrl+shift+k'},
            {'id': '', 'keys': 'ctrl+shift+a'}]}
        result = self.bindings(settings)
        self.assertEqual(result['CLEAR'], '')
        self.assertEqual(result['SELECT'], '')
        self.assertEqual(result['COPY'], '^+c')

    def test_unsupported_shortcut_is_not_selected(self):
        settings = {'keybindings': [
            {'id': '', 'keys': 'ctrl+shift+k'},
            {'id': 'Terminal.ClearBuffer', 'keys': 'win+shift+l'}]}
        self.assertEqual(self.bindings(settings)['CLEAR'], '')

    def test_function_key_shortcuts(self):
        settings = {'keybindings': [
            {'id': '', 'keys': 'ctrl+shift+k'},
            {'id': 'Terminal.ClearBuffer', 'keys': 'ctrl+f12'}]}
        self.assertEqual(self.bindings(settings)['CLEAR'], '^{F12}')

    def test_clear_step_shortcuts_are_guarded(self):
        for shortcut in ('ctrl+c', 'enter'):
            with self.subTest(shortcut=shortcut):
                settings = {'keybindings': [
                    {'id': 'Terminal.PasteFromClipboard', 'keys': shortcut}]}
                self.assertEqual(self.bindings(settings)['SAFE_CLEAR_STEPS'], '0')
        settings = {'keybindings': [{'id': '', 'keys': 'ctrl+c'}]}
        self.assertEqual(self.bindings(settings)['SAFE_CLEAR_STEPS'], '1')

    def test_incompatible_custom_action_is_not_used(self):
        for definition in (
            {'action': 'clearBuffer', 'clear': 'screen'},
            {'action': 'clearBuffer'},
            {'action': 'clearBuffer', 'clear': 'all', 'unexpected': True},
            'paste',
        ):
            with self.subTest(definition=definition):
                settings = {'actions': [{'id': 'User.clear', 'command': definition}],
                            'keybindings': [
                                {'id': '', 'keys': 'ctrl+shift+k'},
                                {'id': 'User.clear', 'keys': 'ctrl+shift+l'}]}
                self.assertEqual(self.bindings(settings)['CLEAR'], '')

    def test_duplicate_and_imported_fail_closed(self):
        for settings in (
            {'actions': [{'id': 'User.copy', 'command': 'copy'},
                         {'id': 'User.copy', 'command': 'selectAll'}]},
            {'import': ['other.json']},
            {'actions': [{'id': 'Terminal.ClearBuffer', 'command': 'paste'}]},
            {'keybindings': [{'keys': ['ctrl+shift+k', 'ctrl+shift+l'],
                              'id': 'Terminal.ClearBuffer'}]},
        ):
            with self.subTest(settings=settings):
                code, output = self.check(settings=settings)
                self.assertNotEqual(code, 0)
                self.assertTrue(output.startswith('ERROR:'), output)

    def test_unknown_version_fails_closed(self):
        code, output = self.check(version='1.25.0.0')
        self.assertNotEqual(code, 0)
        self.assertIn('Unsupported Windows Terminal version', output)

    def test_comments_and_trailing_commas(self):
        output = self.bindings(raw='''{
           // custom terminal shortcuts
           "keybindings": [{"id":"Terminal.ClearBuffer", "keys":"ctrl+shift+l",},],
           "profiles":{"defaults":{"icon":"https://example.com/icon.png"}},
        }''')
        self.assertEqual(output['CLEAR'], '^+k')

    def test_malformed_json_fails_closed(self):
        code, output = self.check(raw='{broken')
        self.assertNotEqual(code, 0)
        self.assertTrue(output.startswith('ERROR:'), output)


if __name__ == '__main__':
    unittest.main()
