"""Windows Terminal shortcut guard tests using disposable JSON fixtures."""
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

    def test_known_defaults(self):
        self.assertEqual(self.check()[1].splitlines(), ['OK', 'CLEAR=1', 'COPY=1', 'SELECT=1'])
        self.assertEqual(self.check('1.23.10353.0')[1].splitlines(),
                         ['OK', 'CLEAR=0', 'COPY=1', 'SELECT=1'])

    def test_existing_explicit_user_binding(self):
        code, output = self.check(settings={'keybindings': [
            {'id': 'Terminal.ClearBuffer', 'keys': 'ctrl+shift+k'},
            {'id': 'Terminal.CopyToClipboard', 'keys': 'ctrl+c'}]})
        self.assertEqual(code, 0)
        self.assertEqual(output.splitlines(), ['OK', 'CLEAR=1', 'COPY=1', 'SELECT=1'])

    def test_removed_and_reassigned_defaults(self):
        for identifier in ('', 'Terminal.PasteFromClipboard'):
            with self.subTest(identifier=identifier):
                code, output = self.check(settings={'keybindings': [
                    {'id': identifier, 'keys': 'ctrl+shift+c'}]})
                self.assertEqual(code, 0)
                self.assertIn('COPY=0', output)
                self.assertIn('CLEAR=1', output)

    def test_ui_generated_clear_action(self):
        # Windows Terminal creates a User.* ID when editing Actions in its UI.
        settings = {'actions': [{'id': 'User.clearBuffer.87C324ED',
                                 'command': {'action': 'clearBuffer', 'clear': 'all'}}],
                    'keybindings': [{'id': 'User.clearBuffer.87C324ED',
                                     'keys': 'ctrl+shift+k'}]}
        code, output = self.check(settings=settings)
        self.assertEqual(code, 0)
        self.assertEqual(output.splitlines(), ['OK', 'CLEAR=1', 'COPY=1', 'SELECT=1'])
        code, output = self.check('1.23.10353.0', settings)
        self.assertEqual(code, 0)
        self.assertIn('CLEAR=1', output)

    def test_custom_action_equivalence(self):
        settings = {'actions': [
            {'id': 'User.copy', 'command': {'action': 'copy', 'singleLine': False}},
            {'id': 'User.selectAll', 'command': 'selectAll'}],
            'keybindings': [
                {'id': 'User.copy', 'keys': 'ctrl+shift+c'},
                {'id': 'User.selectAll', 'keys': 'ctrl+shift+a'}]}
        code, output = self.check(settings=settings)
        self.assertEqual(code, 0)
        self.assertEqual(output.splitlines(), ['OK', 'CLEAR=1', 'COPY=1', 'SELECT=1'])

    def test_incompatible_custom_actions_fail_closed(self):
        for definition in (
            {'action': 'clearBuffer', 'clear': 'screen'},
            {'action': 'clearBuffer'},
            {'action': 'clearBuffer', 'clear': 'all', 'unexpected': True},
            'paste',
        ):
            with self.subTest(definition=definition):
                settings = {'actions': [{'id': 'User.clear', 'command': definition}],
                            'keybindings': [{'id': 'User.clear', 'keys': 'ctrl+shift+k'}]}
                code, output = self.check(settings=settings)
                self.assertEqual(code, 0)
                self.assertIn('CLEAR=0', output)
        settings = {'actions': [{'id': 'User.copy', 'command': {'action': 'copy', 'singleLine': True}}],
                    'keybindings': [{'id': 'User.copy', 'keys': 'ctrl+shift+c'}]}
        self.assertIn('COPY=0', self.check(settings=settings)[1])

    def test_missing_and_duplicate_custom_actions(self):
        settings = {'keybindings': [{'id': 'User.unknown', 'keys': 'ctrl+shift+k'}]}
        self.assertIn('CLEAR=0', self.check(settings=settings)[1])
        settings = {'actions': [
            {'id': 'User.copy', 'command': 'copy'},
            {'id': 'User.copy', 'command': 'selectAll'}]}
        code, output = self.check(settings=settings)
        self.assertNotEqual(code, 0)
        self.assertTrue(output.startswith('ERROR:'), output)

    def test_old_version_with_manual_clear(self):
        code, output = self.check('1.23.10353.0', {'keybindings': [
            {'id': 'Terminal.ClearBuffer', 'keys': 'ctrl+shift+k'}]})
        self.assertEqual(code, 0)
        self.assertIn('CLEAR=1', output)

    def test_comments_and_trailing_commas(self):
        code, output = self.check(raw='''{
           // Terminal preferences
           "keybindings": [{"id":"Terminal.ClearBuffer", "keys":"ctrl+shift+k",},],
           "profiles":{"defaults":{"icon":"https://example.com/icon.png"}},
        }''' )
        self.assertEqual(code, 0)
        self.assertIn('CLEAR=1', output)

    def test_imports_and_custom_actions_fail_closed(self):
        for settings in ({'import': ['other.json']},
                         {'actions': [{'id': 'Terminal.ClearBuffer', 'command': 'paste'}]}):
            with self.subTest(settings=settings):
                code, output = self.check(settings=settings)
                self.assertNotEqual(code, 0)
                self.assertTrue(output.startswith('ERROR:'), output)

    def test_malformed_json_fails_closed(self):
        code, output = self.check(raw='{broken')
        self.assertNotEqual(code, 0)
        self.assertTrue(output.startswith('ERROR:'), output)


if __name__ == '__main__':
    unittest.main()
