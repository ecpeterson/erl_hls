"""Regression tests for documentation coverage, including preprocessor edge cases."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
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
