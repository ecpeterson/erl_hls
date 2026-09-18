"""Regression tests for documentation coverage, including preprocessor edge cases."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
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


if __name__ == '__main__':
    unittest.main()
