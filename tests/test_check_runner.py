"""Exercise runner failure paths without launching AutoHotkey or native actions."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import check


class CheckRunnerTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.output))

    def process(self, stdout='', stderr='', returncode=0):
        process = MagicMock(pid=12345, returncode=returncode)
        process.communicate.return_value = (stdout, stderr)
        factory = self.enterContext(patch.object(check.subprocess, 'Popen'))
        factory.return_value.__enter__.return_value = process
        return process

    def test_success_returns_both_streams(self):
        process = self.process('output\n', 'diagnostic\n')
        self.assertEqual(check.run(['fixture']), 'output\ndiagnostic\n')
        process.kill.assert_not_called()

    def test_nonzero_exit_and_warning_fail(self):
        for returncode, output in [(2, ''), (0, 'Warning: fixture')]:
            with self.subTest(returncode=returncode):
                self.process(output, returncode=returncode)
                with self.assertRaisesRegex(RuntimeError, 'Check failed'):
                    check.run(['fixture'])

    def test_diagnostics_failure_still_kills_timed_out_process(self):
        process = self.process()
        process.communicate.side_effect = [subprocess.TimeoutExpired('fixture', 1), ('tail', '')]
        with patch.object(check.sys, 'platform', 'win32'), \
                patch.object(check, 'window_diagnostics', side_effect=OSError('diagnostics failed')):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                check.run(['fixture'], timeout=1)
        process.kill.assert_called_once_with()
        self.assertEqual(process.communicate.call_count, 2)
        self.assertIn('diagnostics failed', self.output.getvalue())
        self.assertIn('tail', self.output.getvalue())

    def test_timeout_collects_captions_only_for_child_process(self):
        process = self.process()
        process.communicate.side_effect = [subprocess.TimeoutExpired('fixture', 1), ('tail', '')]
        with patch.object(check.sys, 'platform', 'win32'), \
                patch.object(check, 'window_diagnostics', return_value=['fixture window']) as diagnostics:
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                check.run(['fixture'], timeout=1)
        diagnostics.assert_called_once_with(process.pid)
        process.kill.assert_called_once_with()
        self.assertIn('fixture window', self.output.getvalue())

    def test_non_windows_timeout_skips_native_diagnostics(self):
        process = self.process()
        process.communicate.side_effect = [subprocess.TimeoutExpired('fixture', 1), ('', '')]
        with patch.object(check.sys, 'platform', 'linux'), \
                patch.object(check, 'window_diagnostics') as diagnostics:
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                check.run(['fixture'], timeout=1)
        diagnostics.assert_not_called()
        process.kill.assert_called_once_with()

    def run_main(self, native_failure=False, parse_output='PASS: Super Hotkey and every module parsed.'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'AutoHotkey64.exe'
            calls = []
            harness_text = []

            def run(arguments):
                calls.append(arguments)
                if len(calls) == 1:
                    return ''
                if len(calls) == 2:
                    return parse_output
                harness_text.append(Path(arguments[-1]).read_text(encoding='utf-8'))
                if native_failure:
                    raise RuntimeError('native fixture failure')
                return 'PASS: native suite checks completed: 1'

            # Preserve the host's concrete Path class while exercising Windows dispatch.
            with patch.object(check, 'ROOT', root), patch.object(check, 'Path', type(root)), \
                    patch.object(check, 'find_autohotkey', return_value=executable), \
                    patch.object(check, 'run', side_effect=run), \
                    patch.object(check.sys, 'argv', ['check.py']), \
                    patch.object(check.sys, 'platform', 'win32'):
                if native_failure:
                    with self.assertRaisesRegex(RuntimeError, 'native fixture failure'):
                        check.main()
                elif not parse_output:
                    with self.assertRaisesRegex(RuntimeError, 'successful parse'):
                        check.main()
                else:
                    check.main()
            self.assertEqual(list(root.glob('.super-hotkey-check-*.ahk')), [])
            return calls, harness_text

    def test_parse_cannot_replace_a_running_suite(self):
        calls, harness = self.run_main()
        parse = calls[1]
        self.assertIn('/force', parse)
        self.assertLess(parse.index('/force'), len(parse) - 2)
        self.assertEqual(parse[-1], '--check')
        self.assertIn('tests\\checks.ahk', harness[0])

    def test_failed_native_check_removes_harness(self):
        calls, harness = self.run_main(native_failure=True)
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(harness), 1)

    def test_missing_parse_confirmation_stops_before_native_check(self):
        calls, harness = self.run_main(parse_output='')
        self.assertEqual(len(calls), 2)
        self.assertEqual(harness, [])


if __name__ == '__main__':
    unittest.main()
