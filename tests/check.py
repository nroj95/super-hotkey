"""Run the migration and isolated AutoHotkey checks; never run real feature actions."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(arguments: list[str], timeout: int = 60) -> str:
    result = subprocess.run(arguments, cwd=ROOT, capture_output=True, timeout=timeout,
                            encoding='utf-8-sig', errors='replace')
    output = result.stdout + result.stderr
    print(output, end='' if output.endswith('\n') else '\n')
    if result.returncode:
        raise RuntimeError(f'Check exited with code {result.returncode}.')
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
        raise RuntimeError('Native checks require Windows; use unittest for migration helper checks elsewhere.')
    executable = find_autohotkey(args.autohotkey)
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'])
    run([sys.executable, 'migration/integrate.py', '--check'])
    parsed = run([str(executable), '/ErrorStdOut=UTF-8', str(ROOT / 'super-hotkey-world.ahk'), '--check'])
    if 'PASS: Super Hotkey World and every module parsed.' not in parsed:
        raise RuntimeError('The launcher did not report a successful parse.')
    # A_ScriptDir stays at the repository root, matching the real launcher includes.
    with tempfile.NamedTemporaryFile(prefix='.shw-check-', suffix='.ahk', dir=ROOT,
                                     mode='w', encoding='utf-8', delete=False) as stream:
        harness = Path(stream.name)
        stream.write('#Include "super-hotkey-world.ahk"\n')
        stream.write('#Include "%A_ScriptDir%\\tests\\runtime-check.ahk"\n#Warn All, StdOut\n')
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
