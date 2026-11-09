#!/usr/bin/env python3
"""Check hash-bound generated-source attribution and unchanged external-tool logs."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

from erl_hls_tools import compile_xls as compiler
from erl_hls_tools.testing import BuildFixture


def write_map(path: Path, ranges: list[dict]) -> Path:
    """Bind fixture origins to the exact adjacent generated source bytes."""
    sidecar = path.with_name(path.name + '.map.json')
    sidecar.write_text(json.dumps({'version': 1,
        'generated_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'ranges': ranges}))
    return sidecar


def origin(start: list[int], end: list[int], file: str, line: int) -> dict:
    """Describe one half-open emitted range with its source-level location."""
    return {'start': start, 'end': end, 'source': {'file': file, 'line': line}}


class SourceDiagnosticsTests(unittest.TestCase):
    """Attribution uses generated positions and verified bytes, not symbol guesses."""

    def setUp(self) -> None:
        """Create a nested generated module under a path containing spaces."""
        temporary = tempfile.TemporaryDirectory(prefix='source diagnostic ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.module = self.root / 'actor_helpers' / 'policy.x'
        self.module.parent.mkdir()
        self.module.write_text('pub fn choose(value: u32) -> u32 {\n'
                               '  let next = value + u32:1;\n'
                               '  next\n' '}\n')
        self.ranges = [origin([1, 1], [5, 1], 'policy.erl', 8),
                       origin([2, 14], [2, 27], 'include/policy_body.hrl', 42)]
        self.sidecar = write_map(self.module, self.ranges)

    def test_exact_nested_module_and_narrowest_origin(self) -> None:
        """A nested source range overrides its enclosing function without guessing a filename."""
        diagnostic = 'TypeInferenceError: actor_helpers/policy.x:2:16-2:18: incompatible widths\n'
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])
        self.assertEqual(compiler.mapped_source(self.module, 3, 3), ('policy.erl', 8))

    def test_absolute_path_and_ansi_preserve_identity(self) -> None:
        """Tool-rendered absolute paths and terminal color codes map to the same module."""
        diagnostic = f'\x1b[31mTypeInferenceError: {self.module}:2:16-2:18\x1b[0m\n'
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])

    def test_duplicate_locations_and_distinct_modules(self) -> None:
        """Repeated tool excerpts produce one note, and equal basenames never alias."""
        other = self.root / 'other' / 'policy.x'
        other.parent.mkdir()
        other.write_bytes(self.module.read_bytes())
        write_map(other, [origin([1, 1], [5, 1], 'other.erl', 90)])
        diagnostic = ('actor_helpers/policy.x:2:16\n' * 2 + 'other/policy.x:2:16\n'
                      'policy.x:2:16\n')
        self.assertEqual(compiler.source_diagnostics(diagnostic, self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)',
             'Erlang source: other.erl:90 (generated other/policy.x:2:16)'])

    def test_utf8_byte_columns_and_half_open_ranges(self) -> None:
        """Columns count generated UTF-8 bytes and never include the range's end."""
        self.module.write_text('// λ\nabcdef\n')
        write_map(self.module, [origin([1, 4], [1, 6], 'unicode.erl', 1),
                                origin([2, 2], [2, 4], 'unicode.erl', 2)])
        self.assertEqual(compiler.mapped_source(self.module, 1, 5), ('unicode.erl', 1))
        self.assertIsNone(compiler.mapped_source(self.module, 1, 6))
        self.assertEqual(compiler.mapped_source(self.module, 2, 3), ('unicode.erl', 2))
        self.assertIsNone(compiler.mapped_source(self.module, 2, 4))
        self.assertIsNone(compiler.mapped_source(self.module, 2, 8))

    def test_missing_stale_malformed_and_ambiguous_maps(self) -> None:
        """Untrusted attribution cannot replace an external failure with a guessed origin."""
        good = self.sidecar.read_bytes()
        cases = [b'not json', b'[]', b'{"version": 2}',
                 json.dumps({'version': True, 'generated_sha256': compiler.sha(self.module),
                             'ranges': self.ranges}).encode(),
                 json.dumps({'version': 1, 'generated_sha256': '0'*64, 'ranges': self.ranges}).encode()]
        for content in cases:
            with self.subTest(content=content):
                self.sidecar.write_bytes(content)
                self.assertIsNone(compiler.mapped_source(self.module, 2, 16))
        for invalid in [origin([0, 1], [2, 2], 'bad.erl', 1),
                        origin([2, 16], [2, 10], 'bad.erl', 1),
                        origin([2, 1], [2, 999], 'bad.erl', 1),
                        origin([2, 1], [3, 1], 'bad.erl', False)]:
            with self.subTest(invalid=invalid):
                write_map(self.module, [*self.ranges, invalid])
                self.assertIsNone(compiler.mapped_source(self.module, 2, 16))
        write_map(self.module, [self.ranges[1], origin([2, 14], [2, 27], 'different.erl', 99)])
        self.assertIsNone(compiler.mapped_source(self.module, 2, 16))
        self.sidecar.write_bytes(good)
        self.module.write_bytes(self.module.read_bytes() + b'// edited\n')
        self.assertIsNone(compiler.mapped_source(self.module, 2, 16))
        self.sidecar.unlink()
        self.assertIsNone(compiler.mapped_source(self.module, 2, 16))

    def test_relocation_keeps_source_names_descriptive(self) -> None:
        """The map does not resolve source locations against a generated helper directory."""
        relocated = self.root / 'moved bundle'
        relocated.mkdir()
        shutil.move(self.module.parent, relocated)
        self.assertEqual(compiler.source_diagnostics('actor_helpers/policy.x:2:16', relocated),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])
        self.assertFalse((relocated / 'include/policy_body.hrl').exists())

    def test_external_paths_are_not_read_as_bundle_maps(self) -> None:
        """A diagnostic outside the command's input tree receives no source attribution."""
        inside = self.root / 'command-directory'
        inside.mkdir()
        self.assertEqual(compiler.source_diagnostics(f'{self.module}:2:16', inside), [])
        self.assertEqual(compiler.source_diagnostics('bad\0path.x:1:1', self.root), [])
        link = self.root / 'outside.x'
        link.symlink_to(self.module)
        self.assertEqual(compiler.source_diagnostics('outside.x:2:16', self.root),
            ['Erlang source: include/policy_body.hrl:42 (generated actor_helpers/policy.x:2:16)'])

    def test_failure_keeps_raw_diagnostic_and_adds_source_note(self) -> None:
        """A real child failure is retained byte-for-byte, including the original generated span."""
        text = 'TypeInferenceError: actor_helpers/policy.x:2:16-2:18: incompatible widths\n'
        program = 'import sys; sys.stderr.write(' + repr(text) + '); sys.exit(7)'
        with self.assertRaises(RuntimeError) as caught:
            compiler.run([sys.executable, '-c', program], self.root, 'failed.ir', 10)
        self.assertIn('compiler exited 7', str(caught.exception))
        self.assertIn(text, str(caught.exception))
        self.assertIn('Erlang source: include/policy_body.hrl:42', str(caught.exception))
        self.assertEqual((self.root / 'stderr.log').read_bytes(), text.encode())
        self.assertEqual(json.loads((self.root / 'time.json').read_text())['returncode'], 7)


class FlatBuildSourceMapTests(BuildFixture):
    """The flat adapter freezes and publishes diagnostic inputs without changing RTL cache keys."""

    def test_map_relocation_and_publication(self) -> None:
        """Sidecars follow generated sources through a moved input stage and managed release."""
        write_map(self.source, [origin([1, 1], [2, 1], 'counter.erl', 12)])
        moved = self.root / 'relocated input'
        self.inputs.rename(moved)
        release = compiler.build(moved / self.source.name, self.xls, self.output, cache=self.cache)
        self.assertTrue((release / 'sources/counter.x.map.json').is_file())
        self.assertEqual(compiler.source_diagnostics('counter.x:1:2', release / 'sources'),
                         ['Erlang source: counter.erl:12 (generated counter.x:1:2)'])
        write_map(moved / self.source.name, [origin([1, 1], [2, 1], 'counter.erl', 13)])
        updated = compiler.build(moved / self.source.name, self.xls, self.output, cache=self.cache)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        self.assertNotEqual(release, updated)
        self.assertEqual(compiler.source_diagnostics('counter.x:1:2', updated / 'sources'),
                         ['Erlang source: counter.erl:13 (generated counter.x:1:2)'])


if __name__ == '__main__':
    unittest.main()
