#!/usr/bin/env python3
"""Check embedded generated-source attribution and unchanged external-tool logs."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

from erl_hls_tools import compile_xls as compiler
from erl_hls_tools.testing import BuildFixture


def annotated(code: str, source: str, line: int, columns: tuple[int, int] | None = None) -> str:
    """Write the emitter's reserved right-column marker without computing any expected origins."""
    span = '' if columns is None else f'{columns[0]}:{columns[1]} '
    return code + ' ' * max(2, 80 - len(code.encode())) + f'// @erl {span}{json.dumps(source)}:{line}\n'


def continuation(source: str, line: int, columns: tuple[int, int]) -> str:
    """Align an explicit continuation with the usual column-84 @ marker."""
    return ' ' * 80 + f'// @erl+ {columns[0]}:{columns[1]} {json.dumps(source)}:{line}\n'


class SourceDiagnosticsTests(unittest.TestCase):
    """Attribution uses explicit line comments and byte columns, not symbol guesses."""

    def setUp(self) -> None:
        """Create a nested generated module under a path containing spaces."""
        temporary = tempfile.TemporaryDirectory(prefix='source diagnostic ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.module = self.root / 'actor_helpers' / 'policy.x'
        self.module.parent.mkdir()
        self.module.write_text('pub fn choose(value: u32) -> u32 {\n' +
            annotated('  let next = value + u32:1;', 'include/policy_body.hrl', 42) +
            '  next\n}\n')

    def test_exact_nested_module_and_no_origin_inheritance(self) -> None:
        """Only code on the annotated physical line receives its source association."""
        diagnostic = 'TypeInferenceError: actor_helpers/policy.x:2:16-2:18: incompatible widths\n'
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])
        self.assertIsNone(compiler.mapped_source(self.module, 1, 1))
        self.assertIsNone(compiler.mapped_source(self.module, 3, 3))
        self.assertIsNone(compiler.mapped_source(self.module, 2, 84))

    def test_absolute_path_and_ansi_preserve_identity(self) -> None:
        """Tool-rendered absolute paths and terminal color codes name the same module."""
        diagnostic = f'\x1b[31mTypeInferenceError: {self.module}:2:16-2:18\x1b[0m\n'
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])

    def test_duplicate_locations_and_distinct_modules(self) -> None:
        """Repeated excerpts produce one note, and equal basenames never alias."""
        other = self.root / 'other' / 'policy.x'
        other.parent.mkdir()
        other.write_text('\n' + annotated('pub fn other() { u32:1 }', 'other.erl', 90))
        diagnostic = ('actor_helpers/policy.x:2:16\n' * 2 + 'other/policy.x:2:16\n' +
                      'policy.x:2:16\n')
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)',
             'Erlang source: other.erl:90 (generated other/policy.x:2:16)'])

    def test_multiple_origins_and_continuation_line_offsets(self) -> None:
        """Disjoint ranges apply to one code line; following diagnostics retain physical row numbers."""
        self.module.write_text(annotated('  abc def ghi', 'a.erl', 10, (3, 6)) +
            continuation('b.erl', 20, (7, 10)) + continuation('c.erl', 30, (11, 14)) +
            annotated('  next', 'next.erl', 40))
        self.assertEqual(compiler.mapped_source(self.module, 1, 3), ('a.erl', 10))
        self.assertEqual(compiler.mapped_source(self.module, 1, 8), ('b.erl', 20))
        self.assertEqual(compiler.mapped_source(self.module, 1, 13), ('c.erl', 30))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 6))
        self.assertIsNone(compiler.mapped_source(self.module, 2, 84))
        self.assertEqual(compiler.mapped_source(self.module, 4, 4), ('next.erl', 40))

    def test_existing_comment_and_long_code_alignment(self) -> None:
        """An existing comment keeps its position while @ markers align with their continuations."""
        code = '  abc def // L23'
        self.module.write_text(code + ' ' * (83 - len(code)) + '@erl 3:6 "a.erl":23\n' +
            continuation('b.erl', 24, (7, 10)))
        self.assertEqual(compiler.mapped_source(self.module, 1, 8), ('b.erl', 24))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 13))
        long = 'x' * 100
        self.module.write_text(annotated(long, 'long.erl', 12))
        self.assertEqual(compiler.mapped_source(self.module, 1, 100), ('long.erl', 12))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 101))

    def test_utf8_byte_columns_and_escaped_filename(self) -> None:
        """JSON filenames preserve quotes/Unicode, and ranges count generated bytes, not characters."""
        name = 'include/a"b\\λ.hrl'
        self.module.write_text(annotated('  "λ" + value', name, 7, (10, 15)))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 9))
        self.assertEqual(compiler.mapped_source(self.module, 1, 10), (name, 7))
        self.assertEqual(compiler.mapped_source(self.module, 1, 14), (name, 7))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 15))

    def test_malformed_annotations_and_code_bounds(self) -> None:
        """Malformed, prose, comment-only, overlapping and out-of-code origins fail closed."""
        invalid = [
            '  abc // @erl "bad.erl":0\n',
            '  abc // @erl "bad.erl":1 trailing text\n',
            '  abc // mentions @erl "bad.erl":1\n',
            '  abc // @erlang "bad.erl":1\n',
            '  abc // @erl "bad\\q.erl":1\n',
            '  abc // @erl "bad\\n.erl":1\n',
            '  abc // @erl "":1\n',
            '  abc // @erl 3:99 "bad.erl":1\n',
            '  abc // @erl 1:4 "bad.erl":1\n',
            '  abc // @erl 5:3 "bad.erl":1\n',
            '  abc // @erl 3:3 "bad.erl":1\n',
            '  // @erl "bad.erl":1\n',
            '  abc\n// @erl "bad.erl":1\n',
            annotated('  abc def', 'a.erl', 1, (3, 6)) + continuation('b.erl', 2, (5, 10)),
            annotated('  abc def', 'a.erl', 1, (3, 6)) + continuation('a.erl', 1, (3, 6)),
            annotated('  abc def', 'a.erl', 1) + continuation('b.erl', 2, (7, 10)),
            annotated('  abc def', 'a.erl', 1, (3, 6)) + ' // @erl+ 7:10 "b.erl":2\n',
            annotated('  abc def', 'a.erl', 1, (3, 6)) + ' ' * 80 + '// @erl+ "b.erl":2\n',
            annotated('  abc def', 'a.erl', 1, (3, 6)) + ' ' * 80 + '// @erl+broken\n',
            annotated('  abc def', 'a.erl', 1, (3, 6)) + 'x' + ' ' * 79 + '// @erl+ 7:10 "b.erl":2\n',
        ]
        for text in invalid:
            with self.subTest(text=text):
                self.module.write_text(text)
                self.assertIsNone(compiler.mapped_source(self.module, 1, 4))
        self.module.write_text(annotated('  abc def', 'a.erl', 1, (3, 6)) + '\n' +
            continuation('b.erl', 2, (7, 10)))
        self.assertEqual(compiler.mapped_source(self.module, 1, 4), ('a.erl', 1))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 8))

    def test_quoted_markers_characters_identifiers_and_labels(self) -> None:
        """Only real comments count; XLS apostrophe suffixes and labels are not open strings."""
        for quote in ('"', '`'):
            self.module.write_text(f'let text = {quote}// @erl \\"fake.erl\\":1{quote};\n')
            self.assertIsNone(compiler.mapped_source(self.module, 1, 5))
            self.module.write_text(f'let text = {quote}multiline\n// @erl "fake.erl":1\nend{quote};\n' +
                annotated('  next', 'real.erl', 4))
            self.assertIsNone(compiler.mapped_source(self.module, 2, 5))
            self.assertEqual(compiler.mapped_source(self.module, 4, 4), ('real.erl', 4))
        for code in ("  '/' + u8:1", "  '\\'' + u8:1", "  state'' + next'", "  'outer: for (i, ())"):
            self.module.write_text(annotated(code, 'lexical.erl', 5))
            self.assertEqual(compiler.mapped_source(self.module, 1, 4), ('lexical.erl', 5))

    def test_relocation_keeps_source_names_descriptive(self) -> None:
        """Origins move with code and do not resolve against generated helper directories."""
        relocated = self.root / 'moved bundle'
        relocated.mkdir()
        shutil.move(self.module.parent, relocated)
        self.assertEqual(compiler.source_diagnostics('actor_helpers/policy.x:2:16', relocated),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])
        self.assertFalse((relocated / 'include/policy_body.hrl').exists())

    def test_external_paths_and_legacy_sidecars_are_not_consulted(self) -> None:
        """No basename fallback, outside-tree reads, or obsolete sidecar fallback can invent an origin."""
        inside = self.root / 'command-directory'
        inside.mkdir()
        self.assertEqual(compiler.source_diagnostics(f'{self.module}:2:16', inside), [])
        self.assertEqual(compiler.source_diagnostics('bad\0path.x:1:1', self.root), [])
        link = self.root / 'alias.x'
        link.symlink_to(self.module)
        self.assertEqual(compiler.source_diagnostics('alias.x:2:16', self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])
        self.module.write_text('abc\n')
        self.module.with_suffix('.x.map.json').write_text('{"version":1,"ranges":[]}')
        self.assertIsNone(compiler.mapped_source(self.module, 1, 2))

    def test_failure_keeps_raw_diagnostic_and_adds_source_note(self) -> None:
        """A real child failure retains original bytes and adds the generated span's source note."""
        text = 'TypeInferenceError: actor_helpers/policy.x:2:16-2:18: incompatible widths\n'
        program = 'import sys; sys.stderr.write(' + repr(text) + '); sys.exit(7)'
        with self.assertRaises(RuntimeError) as caught:
            compiler.run([sys.executable, '-c', program], self.root, 'failed.ir', 10)
        self.assertIn('compiler exited 7', str(caught.exception))
        self.assertIn(text, str(caught.exception))
        self.assertIn('Erlang source: include/policy_body.hrl:42', str(caught.exception))
        self.assertEqual((self.root / 'stderr.log').read_bytes(), text.encode())
        self.assertEqual(json.loads((self.root / 'time.json').read_text())['returncode'], 7)


class FlatBuildSourceAnnotationTests(BuildFixture):
    """The flat adapter transports annotations as ordinary generated source bytes."""

    def test_annotation_relocation_and_publication(self) -> None:
        """Published source retains embedded origins without packaging obsolete sidecars."""
        self.source.write_text(annotated('pub fn counter() { u32:1 }', 'counter.erl', 12))
        self.source.with_suffix('.x.map.json').write_text('obsolete sidecar')
        moved = self.root / 'relocated input'
        self.inputs.rename(moved)
        release = compiler.build(moved / self.source.name, self.xls, self.output, cache=self.cache)
        self.assertFalse((release / 'sources/counter.x.map.json').exists())
        self.assertEqual((release / 'sources/counter.x').read_bytes(), (moved / 'counter.x').read_bytes())
        self.assertEqual(compiler.source_diagnostics('counter.x:1:2', release / 'sources'),
                         ['Erlang source: counter.erl:12 (generated counter.x:1:2)'])


if __name__ == '__main__':
    unittest.main()
