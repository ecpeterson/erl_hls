#!/usr/bin/env python3
"""Fast checks for the differential runner's evidence and reduction contracts."""
import argparse
import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest

import compiler_differential as differential
import compiler_differential_cases as cases


class GeneratorTest(unittest.TestCase):
    def test_shifts_bound_counts_independently_of_value_width(self):
        for t in cases.TYPES:
            for c in ['s8', 'u8']:
                source = cases.Emitter(t, 'helper').emit(
                    ['shift', 'bsl', ['var', 'X'], ['var', 'Y'], c])
                self.assertIn(f'X bsl hls_nums:wrap(hls_nums:{c}(), Y)', source)
                self.assertTrue(source.startswith(f'hls_nums:wrap(hls_nums:{t}(),'))
        coverage = cases.coverage([cases.generate(751, i) for i in range(100)])
        self.assertGreater(coverage.get('operator:bsl', 0), 0)
        self.assertGreater(coverage.get('operator:bsr', 0), 0)

    def test_replay_is_independent_of_generation_order(self):
        forward = {i: cases.generate(751, i) for i in range(40)}
        reverse = {i: cases.generate(751, i) for i in reversed(range(40))}
        self.assertEqual(forward, reverse)
        self.assertNotEqual(forward[0], cases.generate(752, 0))

    def test_inputs_include_signed_division_boundaries_and_zero_divisors(self):
        for i in range(4):
            program = cases.generate(17, i)
            width, _ = cases.TYPES[program['type']]
            pairs = [row[:2] for row in program['inputs']]
            self.assertIn([1 << (width - 1), (1 << width) - 1], pairs)
            self.assertIn([1, 0], pairs)
            self.assertIn([0, 0], pairs)

    def test_reductions_preserve_scope_type_and_progress(self):
        for i in range(100):
            program = cases.generate(193, i, depth=4)
            self.assertTrue(cases.valid(program['expression']))
            self.assertTrue(cases.valid(program['helper'], calls=False))
            for small in cases.program_reductions(program):
                self.assertLess(cases.program_cost(small), cases.program_cost(program))
                self.assertTrue(cases.valid(small['expression']))
                self.assertTrue(cases.valid(small['helper'], calls=False))
                self.assertEqual(cases.node_type(small['expression']), 'word')
                self.assertEqual(cases.node_type(small['helper']), 'word')

    def test_reducer_cannot_move_a_bound_variable_out_of_scope(self):
        program = {**cases.generate(1, 0), 'expression':
                   ['let', ['const', 7], ['binary', '+', ['bound', 0], ['var', 'X']]]}
        reduced = list(cases.program_reductions(program))
        self.assertTrue(reduced)
        self.assertTrue(all(cases.valid(p['expression']) for p in reduced))
        self.assertNotIn(['bound', 0], [p['expression'] for p in reduced])


class RunnerTest(unittest.TestCase):
    def test_timeout_retains_command_and_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            result = differential.execute([sys.executable, '-c',
                'import time; print("started", flush=True); time.sleep(60)'],
                stage, 'timeout', .3)
            self.assertTrue(result['timeout'])
            self.assertEqual(result['returncode'], -signal.SIGKILL)
            self.assertIn('started', (stage / 'timeout.stdout').read_text())
            self.assertEqual(json.loads((stage / 'timeout.command.json').read_text()), result)

    def test_tool_failure_is_not_a_semantic_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            runner = differential.Runner(stage, stage)
            failure = runner.command('dslx', [sys.executable, '-c',
                                     'raise SystemExit(17)'], stage)
            self.assertEqual(failure['category'], 'tool_error')
            self.assertEqual(failure['phase'], 'dslx')

    def test_failure_signatures_distinguish_lowerer_locations(self):
        first = {'phase': 'lower', 'category': 'error', 'reason': 'function_clause',
                 'location': ['xls_parse', 'one', 3]}
        second = {**first, 'location': ['xls_pattern_lower', 'two', 3]}
        self.assertNotEqual(differential.signature(first), differential.signature(second))

    def test_shrinker_isolates_failure_without_switching_to_another_bug(self):
        # A synthetic predicate tests the reducer independently of compiler behavior.
        failure = {'status': 'failed', 'phase': 'lower', 'category': 'error',
                   'reason': 'bad_expression', 'location': ['target', 'lower', 1], 'rtl': False}

        class Probe:
            def __init__(self, stage):
                self.stage = stage

            def run(self, programs, name, rtl):
                text = cases.canonical([p['expression'] for p in programs])
                if '["const",7]' in text:
                    return {**failure, 'stage': name}
                # An unrelated bug must not count as preserving the original failure.
                return {**failure, 'stage': name, 'location': ['other', 'lower', 1]}

        with tempfile.TemporaryDirectory() as directory:
            probe = Probe(Path(directory))
            irrelevant = {**cases.generate(1, 0), 'expression': ['const', 2]}
            target = {**cases.generate(1, 1), 'expression':
                      ['binary', '+', ['const', 7], ['var', 'X']]}
            small = differential.minimize(probe, [irrelevant, target], failure, 120)
            self.assertEqual(len(small), 1)
            self.assertEqual(small[0]['expression'], ['const', 7])
            self.assertEqual(small[0]['inputs'], [[0, 0, 0, 0, 0]])
            self.assertEqual(json.loads((probe.stage / 'minimized.json').read_text()), small)
            history = json.loads((probe.stage / 'shrink.json').read_text())
            self.assertLessEqual(history['attempts'], 120)
            self.assertTrue(any(not step['accepted'] for step in history['history']))

    def test_shrink_budget_is_hard_limit(self):
        class Probe:
            def __init__(self, stage):
                self.stage = stage
                self.calls = 0

            def run(self, programs, name, rtl):
                self.calls += 1
                return {'status': 'ok', 'stage': name}

        with tempfile.TemporaryDirectory() as directory:
            probe = Probe(Path(directory))
            programs = [cases.generate(1, i) for i in range(5)]
            differential.minimize(probe, programs, {'phase': 'lower', 'rtl': False}, 2)
            self.assertEqual(probe.calls, 2)


def integration(xls, stage):
    """Prove detection and shrinking with a corrupted DSLX literal, then replay cleanly."""
    class CorruptLiteral(differential.Runner):
        def command(self, phase, argv, directory):
            if phase == 'dslx':
                source = directory / 'probe.x'
                source.write_text(source.read_text().replace('u8:7;', 'u8:6;'))
            return super().command(phase, argv, directory)

    runner = CorruptLiteral(xls, stage)
    runner.prepare()
    program = {**cases.generate(1, 0),
               'expression': ['binary', '+', ['const', 7], ['var', 'X']],
               'helper': ['const', 0], 'inputs': [[0, 0, 0, 0, 0], [1, 0, 0, 0, 0]]}
    failure = runner.run([program], 'injected')
    assert failure.get('category') == 'result_mismatch', failure
    small = differential.minimize(runner, [program], failure, 40)
    assert small[0]['expression'] == ['const', 7], small
    assert small[0]['inputs'] == [[0, 0, 0, 0, 0]], small
    clean = differential.Runner(xls, stage / 'clean-replay')
    clean.prepare(compile=False)
    replay = clean.run(small, 'batch', rtl=True)
    assert replay['status'] == 'ok', replay
    deep_expression = ['const', 7]
    for _ in range(96):
        deep_expression = ['match', 0, ['const', 0], deep_expression]
    deep = {**program, 'expression': deep_expression, 'inputs': [[0, 0, 0, 0, 0]]}
    deep_replay = clean.run([deep], 'deep-failure-list')
    assert deep_replay['status'] == 'ok', deep_replay
    deep_source = (clean.stage / 'deep-failure-list' / 'probe.x').read_text()
    assert 'hls_failure::first_all([' in deep_source
    print('PASS: discrepancy minimization, clean RTL replay, and flat failure selection agree')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xls-root', type=Path)
    parser.add_argument('--stage', type=Path, default=differential.ROOT / '_build/differential-self-test')
    args = parser.parse_args()
    if args.xls_root:
        if args.stage.exists():
            parser.error('self-test stage already exists; choose a fresh directory')
        integration(args.xls_root, args.stage)
    else:
        unittest.main(argv=[sys.argv[0]])
