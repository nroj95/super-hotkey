"""Regression tests for the one-time, source-preserving migration helpers."""
import importlib.util
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('integration', root / 'migration/integrate.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTests(unittest.TestCase):
    def test_default_object_does_not_become_function_body(self):
        text = 'class Example {\n    __New(options := {}) {\n        this.value := {}\n    }\n}\n'
        start, end = migration.method_span(text, '__New')
        self.assertEqual(text[start:end], '    __New(options := {}) {\n        this.value := {}\n    }')

    def test_multiline_parameters_and_strings(self):
        text = '    Work(options := {},\n        label := "({})")\n    {\n        output := "}"\n    }\n'
        self.assertEqual(migration.method_span(text, 'Work'), (0, len(text) - 1))

    def test_comments_and_escaped_quotes(self):
        text = '{\n ; }\n /* } */\n value := "a`\"}"\n nested := {}\n}'
        self.assertEqual(migration.block_end(text, 0), len(text))

    def test_arrow_function(self):
        text = '    Run(value := {}) => value\n    Other() {\n    }\n'
        self.assertEqual(migration.method(text, 'Run'), '\n    Other() {\n    }\n')

    def test_global_function(self):
        text = 'Function(options := {}) {\n}\n'
        self.assertEqual(migration.method_span(text, 'Function', 0), (0, len(text) - 1))

    def test_ambiguous_definition_rejected(self):
        with self.assertRaises(ValueError):
            migration.method_span('    Run() {}\n    Run() {}', 'Run')

    def test_missing_and_duplicate_anchors_rejected(self):
        for text in ['missing', 'anchor anchor']:
            with self.assertRaises(ValueError):
                migration.replace_once(text, 'anchor', 'new')

    def test_replace_and_insert_methods(self):
        original = 'class Example {\n    Run(options := {}) {\n        return 1\n    }\n}\n'
        replacements = 'class Migration {\n    Run(options := {}) {\n        return 2\n    }\n    Added() => 3\n}\n'
        changed = migration.replace_definitions(original, replacements)
        self.assertIn('return 2', changed)
        self.assertIn('    Added() => 3\n}', changed)
        self.assertNotIn('return 1', changed)

    def test_reversed_range_rejected(self):
        with self.assertRaises(ValueError):
            migration.between('last first', 'first', 'last', '')

    def test_replacement_fragments_are_well_formed(self):
        for path in (root / 'migration/replacements').glob('*.ahk'):
            text = path.read_text(encoding='utf-8')
            opening = text.index('{')
            self.assertEqual(migration.block_end(text, opening), len(text.rstrip()))
            for name in migration.re.findall(r'(?m)^    (?:static )?(\w+)\(', text):
                start, end = migration.method_span(text, name)
                self.assertGreater(end, start)


if __name__ == '__main__':
    unittest.main()
