"""Keep Super Hotkey's language files in step with the code.

Visible text is written in English inside T("...") in the AutoHotkey sources,
and each module's guide one sentence per line in its HelpText() block. This
script collects both, in include-file order and without repeats, and:

  python tools/lang.py             reports every language's missing and stale lines
  python tools/lang.py nb          reports one language
  python tools/lang.py --update    rewrites lang/template.lang and every lang/<code>.lang

--update never loses a translation. Text that is new in the code gets an empty
"=" line; a translation whose English is gone moves below "; stale" so its
wording can be reused, and is dropped once its own "=" line is emptied.
Comments other than "; language:" are regenerated, one "; <file>" line before
each source file's group of texts.

The file format, read the same way by core/language.ahk:
  ; language: Norsk bokmål    the name the Language page lists
  English text                exactly as written in the code, escapes included
  = Norsk tekst               nothing after "=" means not translated yet
Other lines starting with ";" are comments; blank lines separate entries.
Files are UTF-8 without a BOM, with LF line endings.

tests/test_language.py imports this module: it fails when --update would change
a file, when T() is given anything but a quoted literal, and when a translated
file shows English text outside T().
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LANG = ROOT / 'lang'
TEMPLATE = LANG / 'template.lang'
STALE = '; stale'
CODE = re.compile(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$')  # as SuiteSettings.ValidLanguage
CALL = re.compile(r'(?<![\w.])[Tt]\(')
LITERAL_CALL = re.compile(r'(?<![\w.])[Tt]\("((?:[^"`]|`.)*)"')
GUIDE = re.compile(r'HelpText\(\)\s*=>\s*"\s*$')


def sources() -> list[Path]:
    """The runtime files in the order tests/test_suite_structure.py lists them."""
    return [ROOT / 'super-hotkey.ahk', *sorted((ROOT / 'core').glob('*.ahk')),
            *sorted((ROOT / 'modules').rglob('*.ahk'))]


def strip_comment(line: str) -> str:
    """The line without a trailing ; comment, ignoring semicolons inside quotes."""
    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if char == '`':
            index += 2
            continue
        if quote:
            if char == quote:
                quote = None
        elif char in '"\'':
            quote = char
        elif char == ';' and (index == 0 or line[index - 1] in ' \t'):
            return line[:index]
        index += 1
    return line


def scan(path: Path) -> tuple[list[str], list[str], list[str]]:
    """(code lines without comments or guides, T() literals, guide lines) of one file."""
    code, texts, guide = [], [], []
    lines = path.read_text(encoding='utf-8').split('\n')
    in_guide = False
    for number, line in enumerate(lines):
        if in_guide:
            if line.strip().startswith(')'):
                in_guide = False
            elif line.strip():
                guide.append(line.strip())
            code.append('')
            continue
        if line.strip() == '(' and number and GUIDE.search(lines[number - 1]):
            in_guide = True
            code.append('')
            continue
        line = strip_comment(line)
        code.append(line)
        texts.extend(LITERAL_CALL.findall(line))
    return code, texts, guide


def bare_calls() -> list[str]:
    """'file:line' for each T( that does not start with a quoted literal."""
    found = []
    for path in sources():
        for number, line in enumerate(scan(path)[0], 1):
            for match in CALL.finditer(line):
                definition = match.start() == 0 and line.rstrip().endswith('{')
                if not definition and not line.startswith('"', match.end()):
                    found.append(f'{path.relative_to(ROOT).as_posix()}:{number}')
    return found


def collect() -> list[tuple[str, list[str]]]:
    """[(file, texts)] of every translatable text, each listed once, under its first file."""
    seen, groups = set(), []
    for path in sources():
        _, texts, guide = scan(path)
        fresh = []
        for text in texts + guide:
            if text not in seen:
                if not text or text[0] in ';=':
                    raise ValueError(f'{path.name}: text cannot start with ; or =: {text!r}')
                seen.add(text)
                fresh.append(text)
        if fresh:
            groups.append((path.relative_to(ROOT).as_posix(), fresh))
    return groups


def parse(text: str) -> tuple[str, dict[str, str]]:
    """(language name, {English: translation}) of a .lang file; empty translations included."""
    name, entries, source = '', {}, None
    for number, line in enumerate(text.split('\n'), 1):
        match = re.match(r'^;\s*language:\s*(.*?)\s*$', line)
        if match:
            name = match[1]
        elif line.startswith('='):
            if source is None:
                raise ValueError(f'line {number}: "=" without an English line above it')
            if source in entries:
                raise ValueError(f'line {number}: {source!r} is listed twice')
            entries[source] = re.sub(r'^ ', '', line[1:])
            source = None
        elif not line or line.startswith(';'):
            if source is not None:
                raise ValueError(f'line {number - 1}: {source!r} has no "=" line')
        elif source is not None:
            raise ValueError(f'line {number - 1}: {source!r} has no "=" line')
        else:
            source = line
    if source is not None:
        raise ValueError(f'{source!r} has no "=" line')
    return name, entries


def render(name: str, entries: dict[str, str], groups: list[tuple[str, list[str]]]) -> str:
    """A complete .lang file: every current text, then stale translations."""
    lines = [f'; language: {name}'.rstrip(),
             '; Super Hotkey translation; see lang/README.md. Keep each = line;',
             '; python tools/lang.py --update adds new text and rewrites these comments.']
    current = set()
    for file, texts in groups:
        lines += ['', f'; {file}']
        for text in texts:
            current.add(text)
            translation = entries.get(text, '')
            lines += ['', text, f'= {translation}'.rstrip()]
    stale = [(text, value) for text, value in entries.items() if text not in current and value]
    if stale:
        lines += ['', STALE]
        for text, value in stale:
            lines += ['', text, f'= {value}']
    return '\n'.join(lines) + '\n'


def languages() -> list[Path]:
    return sorted(path for path in LANG.glob('*.lang') if path != TEMPLATE)


def expected() -> dict[Path, str]:
    """Every language file, the template included, as --update would write it."""
    groups = collect()
    files = {TEMPLATE: render('', {}, groups)}
    for path in languages():
        if not CODE.match(path.stem):
            raise ValueError(f'{path.name}: name it after a language code, such as nb or pt-BR')
        try:
            name, entries = parse(path.read_text(encoding='utf-8'))
        except ValueError as error:
            raise ValueError(f'{path.name}: {error}') from None
        files[path] = render(name, entries, groups)
    return files


def report(paths: list[Path]) -> None:
    groups = collect()
    current = {text for _, texts in groups for text in texts}
    for path in paths:
        name, entries = parse(path.read_text(encoding='utf-8'))
        missing = [text for text in sorted(current) if not entries.get(text)]
        stale = [text for text, value in entries.items() if text not in current and value]
        print(f'{name or path.stem} ({path.stem}): {len(current) - len(missing)} of {len(current)} '
              f'translated, {len(missing)} missing, {len(stale)} stale')
        for text in stale:
            print(f'  stale: {text}')


def main() -> None:
    parser = argparse.ArgumentParser(description='Keep lang/*.lang in step with the code.')
    parser.add_argument('code', nargs='?', help='report only this language, such as nb')
    parser.add_argument('--update', action='store_true', help='rewrite the template and every language file')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')  # language names, also when piped
    if bare_calls():
        raise ValueError('T() takes a quoted literal: ' + ', '.join(bare_calls()))
    if args.update:
        LANG.mkdir(exist_ok=True)
        for path, text in expected().items():
            if not path.exists() or path.read_text(encoding='utf-8') != text:
                path.write_text(text, encoding='utf-8', newline='\n')
                print(f'updated {path.relative_to(ROOT).as_posix()}')
        return
    paths = [LANG / f'{args.code}.lang'] if args.code else languages()
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(f'{path.relative_to(ROOT).as_posix()} does not exist; copy the template')
    report(paths)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
