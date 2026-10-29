"""Run portable and isolated AutoHotkey checks; never run real feature actions."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def window_diagnostics(process_id: int) -> list[str]:
    """Read captions only from the test process, never from unrelated applications."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.EnumChildWindows.argtypes = [wintypes.HWND, callback_type, wintypes.LPARAM]
    output = []

    @callback_type
    def caption(hwnd, unused):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == process_id:
            text = ctypes.create_unicode_buffer(4096)
            if user32.GetWindowTextW(hwnd, text, len(text)):
                output.append(text.value)
        return True

    @callback_type
    def window(hwnd, unused):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == process_id:
            caption(hwnd, 0)
            user32.EnumChildWindows(hwnd, caption, 0)
        return True

    user32.EnumWindows(window, 0)
    return output


def run(arguments: list[str], timeout: int = 45) -> str:
    with subprocess.Popen(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          encoding='utf-8-sig', errors='replace') as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                if sys.platform == 'win32':
                    print('Test process windows:', *window_diagnostics(process.pid), sep='\n')
            except Exception as error:
                print(f'Test window diagnostics failed: {error}')
            finally:
                # Diagnostics must never prevent cleanup of our timed-out process.
                process.kill()
            stdout, stderr = process.communicate()
            print(stdout + stderr)
            raise RuntimeError(f'Check timed out after {timeout} seconds.')
        output = stdout + stderr
        print(output, end='' if output.endswith('\n') else '\n')
        if process.returncode or 'Warning:' in output:
            raise RuntimeError(f'Check failed or emitted a warning (exit {process.returncode}).')
        return output


def find_autohotkey(argument: str | None) -> Path:
    if argument:
        candidate = Path(argument).resolve()
        if not candidate.is_file():
            raise FileNotFoundError(candidate)
        return candidate
    candidates = []
    for variable, suffix in [('ProgramFiles', 'AutoHotkey/v2/AutoHotkey64.exe'),
                             ('LOCALAPPDATA', 'Programs/AutoHotkey/v2/AutoHotkey64.exe')]:
        if os.getenv(variable):
            candidates.append(Path(os.environ[variable]) / suffix)
    command = shutil.which('AutoHotkey64.exe')
    if command:
        candidates.append(Path(command))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError('AutoHotkey v2 64-bit was not found. Pass --autohotkey PATH.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--autohotkey', help='Path to AutoHotkey64.exe.')
    args = parser.parse_args()
    if sys.platform != 'win32':
        raise RuntimeError('Native checks require Windows; portable structural checks can run elsewhere.')
    executable = find_autohotkey(args.autohotkey)
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'])
    # /force means SingleInstance Off, not replacement of the running suite.
    parsed = run([str(executable), '/force', '/ErrorStdOut=UTF-8',
                  str(ROOT / 'super-hotkey.ahk'), '--check'])
    if 'PASS: Super Hotkey and every module parsed.' not in parsed:
        raise RuntimeError('The launcher did not report a successful parse.')
    # A_ScriptDir stays at the repository root, matching the real launcher includes.
    with tempfile.NamedTemporaryFile(prefix='.super-hotkey-check-', suffix='.ahk', dir=ROOT,
                                     mode='w', encoding='utf-8', delete=False) as stream:
        harness = Path(stream.name)
        stream.write('#Include "super-hotkey.ahk"\n')
        stream.write('#Include "%A_ScriptDir%\\tests\\checks.ahk"\n#Warn All, StdOut\n')
    try:
        result = run([str(executable), '/ErrorStdOut=UTF-8', str(harness)])
        if 'PASS: native suite checks completed:' not in result:
            raise RuntimeError('The native test harness did not finish.')
    finally:
        harness.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
