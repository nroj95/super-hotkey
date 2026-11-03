"""Portable checks that every language file matches the code's visible text."""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import lang  # noqa: E402

# Files whose visible text all goes through T(); the list grows module by module.
TRANSLATED = ['modules/secret-layers']
# Literals that look like prose but are not shown as text: log areas and categories.
NOT_SHOWN = re.compile(r'(\.(Error|Write)|Report)\([^()]*$|category:\s*$')


class LanguageTests(unittest.TestCase):
    def test_language_files_are_current(self):
        for path, text in lang.expected().items():
            name = path.relative_to(ROOT).as_posix()
            self.assertTrue(path.is_file(), f'{name} is missing; run python tools/lang.py --update')
            self.assertEqual(path.read_text(encoding='utf-8'), text,
                             f'{name} is out of date; run python tools/lang.py --update')

    def test_translations_take_quoted_literals(self):
        # tools/lang.py finds text only where it is written in quotes inside T().
        self.assertEqual(lang.bare_calls(), [])

    def test_translated_files_show_no_bare_english(self):
        # A heuristic: a literal that starts with two words, such as "Enable Pause", is
        # prose unless it is a log area or a category; option strings start with one.
        for folder in TRANSLATED:
            for path in sorted((ROOT / folder).glob('*.ahk')):
                for number, line in enumerate(lang.scan(path)[0], 1):
                    line = lang.LITERAL_CALL.sub('T()', line)
                    for match in re.finditer(r'"[A-Z][a-z]+\s+[A-Za-z][a-z]+[^"`]*"', line):
                        if not NOT_SHOWN.search(line[:match.start()]):
                            self.fail(f'{path.relative_to(ROOT).as_posix()}:{number} shows '
                                      f'{match[0]} without T()')

    def test_reader_round_trips_the_format(self):
        name, entries = lang.parse('; language: Test\n\nHello `n world\n= Hei\n\nUntranslated\n=\n')
        self.assertEqual((name, entries), ('Test', {'Hello `n world': 'Hei', 'Untranslated': ''}))
        for broken in ['= orphan\n', 'One\nTwo\n= x\n', 'One\n= a\n\nOne\n= b\n', 'Dangling\n']:
            with self.assertRaises(ValueError, msg=broken):
                lang.parse(broken)


if __name__ == '__main__':
    unittest.main()
