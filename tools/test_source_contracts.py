"""Regression tests for documentation coverage, including preprocessor edge cases."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("contracts", ROOT / "tools/check_source_contracts.py")
CONTRACTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACTS)


class SourceContractsTests(unittest.TestCase):
    """Exercise declarations without compiling the source under examination."""

    @classmethod
    def setUpClass(cls) -> None:
        """Compile only the checker, once for the test suite."""
        cls.stage = tempfile.TemporaryDirectory(prefix="source-contract-tests-")
        subprocess.run(["erlc", "-Werror", "-o", cls.stage.name,
                        str(ROOT / "tools/source_contracts.erl")], check=True)

    @classmethod
    def tearDownClass(cls) -> None:
        """Remove the checker and source fixtures."""
        cls.stage.cleanup()

    def audit(self, source: str) -> list[dict[str, object]]:
        """Return diagnostics for inert, possibly non-compilable source."""
        path = Path(self.stage.name) / "example.erl"
        path.write_text('-module(example).\n' + source)
        return CONTRACTS.findings(self.stage.name, [path.name], self.stage.name)

    def test_public_docs_must_be_nonempty_and_formal(self) -> None:
        """A source comment, false, empty text and metadata are not API prose."""
        for doc in ['', '-doc false.', '-doc "".', '-doc #{since => "1"}.']:
            with self.subTest(doc=doc):
                gaps = self.audit('-export([f/0]).\n%% Explains f.\n' + doc +
                                  '\n-spec f() -> ok.\nf() -> ok.')
                self.assertEqual([g['rule'] for g in gaps], ['public_doc'])
        self.assertEqual(self.audit('-export([f/0]).\n-doc "Returns ok.".\n'
                                    '-spec f() -> ok.\nf() -> ok.'), [])

    def test_private_comments_and_specs_are_separate(self) -> None:
        """Private declarations need both a description and a specification."""
        self.assertEqual({g['rule'] for g in self.audit('f() -> ok.')},
                         {'private_comment', 'spec'})
        self.assertEqual(self.audit('%% Returns ok.\n-spec f() -> ok.\nf() -> ok.'), [])
        self.assertEqual(self.audit('-spec f() -> ok.\n%% Returns ok.\nf() -> ok.'), [])

    def test_types_and_export_all(self) -> None:
        """Opaque and parameterized types have the same visibility rules as aliases."""
        gaps = self.audit('-export_type([value/1]).\n-opaque value(T) :: {value, T}.\n'
                          '-type private() :: atom().\n-compile([export_all]).\nf() -> ok.')
        self.assertEqual({(g['id'], g['rule']) for g in gaps}, {
            ('type:value/1', 'public_doc'), ('type:private/0', 'private_comment'),
            ('function:f/0', 'public_doc'), ('function:f/0', 'spec')})

    def test_callbacks_are_public_contracts(self) -> None:
        """A behavior callback requires prose even without a function export."""
        gaps = self.audit('-callback run(atom()) -> ok.')
        self.assertEqual([(g['id'], g['rule']) for g in gaps],
                         [('callback:run/1', 'public_doc')])
        self.assertEqual(self.audit('-doc "Runs the operation.".\n-callback run(atom()) -> ok.'), [])

    def test_dispatch_clauses(self) -> None:
        """Each message class needs its own explanation beyond the callback spec."""
        gaps = self.audit('%% Dispatches calls.\n-spec handle_call(term(), term(), term()) -> term().\n'
                          '%% Returns the state.\nhandle_call(info, _, S) -> {reply, S, S};\n'
                          'handle_call(_, _, S) -> {reply, error, S}.')
        self.assertEqual([(g['id'], g['rule']) for g in gaps],
                         [('function:handle_call/3:clause:2', 'clause_comment')])

    def test_conditionals_and_macros_are_not_executed(self) -> None:
        """Inspect both conditional branches and tolerate record-field splices."""
        gaps = self.audit('-define(FIELD, x = 0).\n-record(r, {?FIELD}).\n'
                          '-ifdef(ONE).\nf() -> ?UNDEFINED_MACRO.\n-else.\nf() -> two.\n-endif.')
        self.assertEqual(len(gaps), 4)
        self.assertEqual({g['rule'] for g in gaps}, {'spec', 'private_comment'})
        self.assertEqual(len({g['fingerprint'] for g in gaps}), 2)

    def test_guarded_macro_arguments_keep_body_fingerprints(self) -> None:
        """Fallback parsing must retain changes inside legal assertion macros."""
        source = 'f() -> ?assertMatch(#{n := N} when N > 2, value()).'
        gaps = self.audit(source)
        self.assertEqual({g['rule'] for g in gaps}, {'spec', 'private_comment'})
        changed = self.audit(source.replace('N > 2', 'N > 3'))
        self.assertNotEqual(gaps[0]['fingerprint'], changed[0]['fingerprint'])
        self.assertEqual(gaps[0]['fingerprint'], self.audit('\n' + source)[0]['fingerprint'])

    def test_parse_errors_are_not_hidden(self) -> None:
        """A malformed function cannot disappear behind the record macro exception."""
        gaps = self.audit('-record(r, {x}).\nf() -> .')
        self.assertIn('parse', [g['rule'] for g in gaps])

    def test_fingerprints_ignore_lines_but_track_code_and_specs(self) -> None:
        """Editing a declaration requires completing it; moving it does not."""
        original = self.audit('-spec f() -> atom().\nf() -> ok.')[0]['fingerprint']
        moved = self.audit('\n\n-spec f() -> atom().\n\nf()  ->\n ok.')[0]['fingerprint']
        self.assertEqual(original, moved)
        self.assertNotEqual(original, self.audit('-spec f() -> atom().\nf() -> no.')[0]['fingerprint'])
        self.assertNotEqual(original, self.audit('-spec f() -> ok.\nf() -> ok.')[0]['fingerprint'])

    def test_debt_cannot_grow_or_return(self) -> None:
        """Both conditional definitions may remain, but changed or restored debt fails."""
        prior = self.audit('-ifdef(ONE).\nf() -> one.\n-else.\nf() -> two.\n-endif.')
        self.assertEqual(CONTRACTS.regressions(prior, prior), [])
        changed = self.audit('-ifdef(ONE).\nf() -> changed.\n-else.\nf() -> two.\n-endif.')
        self.assertEqual(len(CONTRACTS.regressions(changed, prior)), 2)
        self.assertEqual(CONTRACTS.regressions(prior, []), prior)
        malformed = self.audit('f() -> .')
        self.assertEqual(CONTRACTS.regressions(malformed, malformed), malformed)

    def audit_files(self, sources: dict[str, str]) -> list[dict[str, object]]:
        """Audit a complete inert inventory, including files with no contract gaps."""
        with tempfile.TemporaryDirectory(dir=self.stage.name) as directory:
            for name, source in sources.items():
                path = Path(directory, name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            return CONTRACTS.findings(self.stage.name, sorted(sources), directory)

    def test_module_move_retains_only_unchanged_debt(self) -> None:
        """A unique module survives a path move; body, spec and visibility edits do not."""
        source = '-module(example).\n-spec f() -> atom().\nf() -> ok.'
        prior = self.audit_files({'old/example.erl': source})
        moved = self.audit_files({'new/renamed_file.erl': source})
        self.assertEqual(CONTRACTS.regressions(moved, prior), [])
        for changed in [source.replace('-> ok.', '-> changed.'),
                        source.replace('-> atom().', '-> ok.'),
                        source.replace('-module(example).', '-module(other).')]:
            with self.subTest(source=changed):
                current = self.audit_files({'new/example.erl': changed})
                self.assertEqual(CONTRACTS.regressions(current, prior), current)
        # A formal doc satisfies either visibility, isolating the missing-spec debt.
        private = '-module(example).\n-doc "Returns ok.".\nf() -> ok.'
        prior = self.audit_files({'old/example.erl': private})
        public = self.audit_files({'new/example.erl': private.replace(
            '-module(example).', '-module(example).\n-export([f/0]).')})
        self.assertEqual([g['rule'] for g in public], ['spec'])
        self.assertEqual(CONTRACTS.regressions(public, prior), public)

    def test_module_copies_are_ambiguous_even_when_documented(self) -> None:
        """The whole inventory detects copies that a findings-only index would miss."""
        missing = '-module(example).\nf() -> ok.'
        clean = '-module(example).\n%% Returns ok.\n-spec f() -> ok.\nf() -> ok.'
        prior = self.audit_files({'old/example.erl': missing})
        for original, copied in [(missing, missing), (missing, clean), (clean, clean)]:
            with self.subTest(original=original, copied=copied):
                current = self.audit_files({'old/example.erl': original, 'copy/example.erl': copied})
                ambiguity = [g for g in current if g['rule'] == 'module_identity']
                self.assertEqual(len(ambiguity), 2)
                self.assertTrue(all(g in CONTRACTS.regressions(current, prior) for g in ambiguity))
                self.assertTrue(all(g in CONTRACTS.regressions(current, current) for g in ambiguity))
        ambiguous_prior = self.audit_files({'a/example.erl': missing, 'b/example.erl': clean})
        unique = self.audit_files({'new/example.erl': missing})
        self.assertEqual(CONTRACTS.regressions(unique, ambiguous_prior), unique)

    def test_conditional_module_identity_is_not_guessed(self) -> None:
        """Multiple module declarations fail closed even when they spell the same name."""
        source = '-ifdef(ONE).\n-module(example).\n-else.\n-module(example).\n-endif.'
        gaps = self.audit_files({'example.erl': source})
        self.assertEqual([g['rule'] for g in gaps], ['module_identity'])
        self.assertEqual(CONTRACTS.regressions(gaps, gaps), gaps)

    def test_module_move_preserves_conditional_declarations(self) -> None:
        """Each conditional function keeps its own strict declaration fingerprint."""
        source = '-module(example).\n-ifdef(ONE).\nf() -> one.\n-else.\nf() -> two.\n-endif.'
        prior = self.audit_files({'old/example.erl': source})
        current = self.audit_files({'new/example.erl': source})
        self.assertEqual(CONTRACTS.regressions(current, prior), [])
        changed = self.audit_files({'new/example.erl': source.replace('-> two.', '-> three.')})
        self.assertEqual(len(CONTRACTS.regressions(changed, prior)), 2)

    def test_headers_and_unidentified_files_remain_path_bound(self) -> None:
        """Neither a common basename nor a header's module spelling grants move credit."""
        for name, source in [('same.hrl', '-type value() :: atom().'),
                             ('same.hrl', '-module(example).\n-type value() :: atom().'),
                             ('same.erl', 'f() -> ok.')]:
            with self.subTest(name=name, source=source):
                prior = self.audit_files({'old/' + name: source})
                moved = self.audit_files({'new/' + name: source})
                self.assertTrue(moved)
                self.assertEqual(CONTRACTS.regressions(moved, prior), moved)

    def test_moved_parse_failures_are_never_inherited(self) -> None:
        """A matching module and unchanged malformed source cannot waive a parse error."""
        source = '-module(example).\nf() -> .'
        prior = self.audit_files({'old/example.erl': source})
        moved = self.audit_files({'new/example.erl': source})
        self.assertIn('parse', [g['rule'] for g in moved])
        self.assertEqual(CONTRACTS.regressions(moved, prior), moved)

    def test_cli_move_and_narrowed_inventory(self) -> None:
        """Resolve physical aliases without hiding distinct in-tree or external copies."""
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'tools/source_contracts.erl').write_text(
                (ROOT / 'tools/source_contracts.erl').read_text())
            (root / 'source-contracts.json').write_text(json.dumps(
                {'include': ['src/*.erl'], 'base_ref': 'HEAD'}))
            original = root / 'src/old/example.erl'
            original.parent.mkdir(parents=True)
            original.write_text('-module(example).\nf() -> ok.')
            for args in [('init', '-q'), ('add', '.'),
                         ('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                          'commit', '-qm', 'baseline')]:
                subprocess.run(['git', '-C', directory, *args], check=True)
            moved = root / 'src/new/example.erl'
            moved.parent.mkdir(parents=True)
            original.rename(moved)
            command = [sys.executable, str(ROOT / 'tools/check_source_contracts.py'),
                       '--base', 'HEAD', '--report', 'report.json']
            alias = root / 'source-alias'
            alias.symlink_to(root / 'src', target_is_directory=True)
            result = subprocess.run(command + [str(moved), str(alias / 'new/example.erl')],
                                    cwd=directory, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((root / 'report.json').read_text())
            self.assertEqual(report['new'], [])
            copy = root / 'src/copy/example.erl'
            copy.parent.mkdir(parents=True)
            copy.write_text('-module(example).\n%% Returns ok.\n-spec f() -> ok.\nf() -> ok.')
            result = subprocess.run(command + ['./src/new/example.erl'], cwd=directory,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            report = json.loads((root / 'report.json').read_text())
            self.assertEqual({g['path'] for g in report['new'] if g['rule'] == 'module_identity'},
                             {'src/new/example.erl', 'src/copy/example.erl'})
            copy.unlink()
            external = Path(outside, 'outside.erl')
            external.write_text('-module(outside).\n%% Returns ok.\n-spec f() -> ok.\nf() -> ok.')
            result = subprocess.run(command + [str(external)], cwd=directory,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((root / 'report.json').read_text())
            self.assertEqual(report['new'], [])
            external.write_text(external.read_text().replace('-module(outside).', '-module(example).'))
            result = subprocess.run(command + [str(external)], cwd=directory,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            report = json.loads((root / 'report.json').read_text())
            ambiguous = {g['path'] for g in report['new'] if g['rule'] == 'module_identity'}
            self.assertIn('src/new/example.erl', ambiguous)
            self.assertEqual(len(ambiguous), 2)
            external_path = (ambiguous - {'src/new/example.erl'}).pop()
            self.assertFalse(Path(external_path).is_absolute())
            self.assertEqual((root / external_path).resolve(), external.resolve())

    def test_scope_includes_root_modules(self) -> None:
        """Owned modules and headers are checked at every directory depth."""
        self.assertEqual(CONTRACTS.selected(['root.erl', 'src/sub/deep.erl', 'include/t.hrl',
                                             '_build/generated.erl', 'notes/a.md'],
                                            {'include': ['*.erl', '*.hrl'], 'exclude': ['_build/*']}),
                         ['include/t.hrl', 'root.erl', 'src/sub/deep.erl'])


class DslxContractsTests(unittest.TestCase):
    """Protect DSLX coverage against syntax, visibility and baseline mistakes."""

    def audit(self, source: str) -> list[dict[str, object]]:
        """Inspect inert DSLX without requiring the XLS binaries."""
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'example.x').write_text(source)
            return CONTRACTS.dslx_source_contracts.findings(['example.x'], directory)

    def test_public_and_private_declarations(self) -> None:
        """Comments cover functions, aliases, records and enums at both visibilities."""
        for declaration in ['fn f() { () }', 'type T = u32;',
                            'struct S<N: u32> { x: uN[N] }', 'enum E: u1 { A = 0 }']:
            for public in [False, True]:
                with self.subTest(declaration=declaration, public=public):
                    source = ('pub ' if public else '') + declaration
                    gaps = self.audit(source)
                    self.assertEqual([g['rule'] for g in gaps],
                                     ['public_doc' if public else 'private_comment'])
                    self.assertEqual(self.audit('// Describes the contract.\n' + source), [])
                    self.assertEqual(len(self.audit('// ----\n' + source)), 1)

    def test_comments_belong_to_one_declaration(self) -> None:
        """File banners, trailing notes and body comments do not document later APIs."""
        source = ('// File overview.\n\npub fn f() {\n // Implementation detail.\n ()\n}\n'
                  '// Explains g.\nfn g() { () } // Describes g only.\nfn h() { () }')
        self.assertEqual([g['id'] for g in self.audit(source)], ['function:f', 'function:h'])
        self.assertEqual(len(self.audit('// Explains f.\nfn f() { () } fn g() { () }')), 1)

    def test_literals_and_parametric_defaults(self) -> None:
        """Braces and keywords inside defaults, strings and character literals stay inert."""
        source = r'''// Pads a value.
pub fn f<N: u32, M: u32 = {if N > u32:0 { N } else { u32:1 }}>(x: uN[N]) -> uN[M] {
  trace_fmt!("fake fn hidden() {{ }} // pub proc Fake", x);
  let quote = '\'';
  let brace = '{';
  x as uN[M]
}
// Wraps a payload.
pub type Wrapped = (u32, u8[2]);
'''
        self.assertEqual(self.audit(source), [])

    def test_attributes_and_proc_lifecycle(self) -> None:
        """Test attributes retain comments and every lifecycle body has its own contract."""
        source = '''// Drives a finite sequence.
#[test_proc]
proc Example<N: u32> {
  input: chan<uN[N]> in;
  config(input: chan<uN[N]> in) { (input,) }
  // Starts empty.
  init { () }
  next(state: ()) { state }
}
#[test]
// Exercises the empty case.
fn empty_test() { () }
'''
        self.assertEqual([g['id'] for g in self.audit(source)],
                         ['function:Example.config', 'function:Example.next'])
        self.assertEqual(self.audit('// Adds no state.\n#[quickcheck(test_count=12)]\nfn p() { true }'), [])

    def test_unsupported_or_incomplete_syntax_fails_closed(self) -> None:
        """The audit cannot silently pass a lost declaration or malformed boundary."""
        for source in ['pub fn f() {', 'pub fn f() { ] }', 'pub fn f() { "unterminated }',
                       'pub fn f<N: u32() { () }', 'pub fn f() -> u32;',
                       'pub struct { x: u32 }', 'impl S { fn f() { () } }',
                       'type T = u32', 'proc P {', 'proc P { unsupported {} }']:
            with self.subTest(source=source):
                gaps = self.audit(source)
                self.assertEqual([g['rule'] for g in gaps], ['parse'])
                self.assertEqual(CONTRACTS.regressions(gaps, gaps), gaps)

    def test_fingerprints_and_completed_debt(self) -> None:
        """Code/type/visibility changes need prose; formatting and line shifts do not."""
        before = self.audit('pub fn f(x: u32) -> u32 { x + u32:1 }')
        moved = self.audit('\n\npub fn f ( x : u32 ) -> u32 {\n x + u32:1\n}')
        self.assertEqual(CONTRACTS.regressions(moved, before), [])
        for source in ['pub fn f(x: u32) -> u32 { x + u32:2 }',
                       'pub fn f(x: u16) -> u16 { x + u16:1 }',
                       'fn f(x: u32) -> u32 { x + u32:1 }']:
            self.assertEqual(len(CONTRACTS.regressions(self.audit(source), before)), 1)
        documented = self.audit('// Adds one.\npub fn f(x: u32) -> u32 { x + u32:1 }')
        self.assertEqual(CONTRACTS.regressions(before, documented), before)

    def test_only_handwritten_dslx_is_selected(self) -> None:
        """The scope includes static libraries without treating generated outputs as owned APIs."""
        config = json.loads((ROOT / 'source-contracts.json').read_text())
        self.assertEqual(CONTRACTS.selected([
            'priv/xls/lib/mailbox.x', 'priv/xls/debug/server.x', 'priv/xls/direct.x',
            'priv/xls/deep/sub/library.x',
            'examples/generated.erl.x', 'test_data/generated.x', '_build/out.x'], config),
            ['priv/xls/debug/server.x', 'priv/xls/deep/sub/library.x',
             'priv/xls/direct.x', 'priv/xls/lib/mailbox.x'])

    def test_git_baseline_uses_current_dslx_scope(self) -> None:
        """Adding DSLX coverage must audit old source, not classify every old gap as new."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / 'priv/xls/lib'
            library.mkdir(parents=True)
            source = library / 'f.x'
            source.write_text('pub fn f() -> u32 { u32:1 }')
            for args in [('init', '-q'), ('add', '.'),
                         ('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                          'commit', '-qm', 'baseline')]:
                subprocess.run(['git', '-C', directory, *args], check=True)
            config = {'include': ['priv/xls/*.x']}
            # Keep every Git subprocess in the fixture without changing global cwd.
            check_output = subprocess.check_output
            with patch.object(CONTRACTS.subprocess, 'check_output',
                              side_effect=lambda *a, **kw: check_output(*a, cwd=directory, **kw)):
                prior = CONTRACTS.baseline('', 'HEAD', config)
            path = 'priv/xls/lib/f.x'
            self.assertEqual(CONTRACTS.regressions(CONTRACTS.findings('', [path], directory), prior), [])
            source.write_text('pub fn f() -> u32 { u32:2 }')
            self.assertEqual(len(CONTRACTS.regressions(CONTRACTS.findings('', [path], directory), prior)), 1)


if __name__ == '__main__':
    unittest.main()
