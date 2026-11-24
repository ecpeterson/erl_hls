"""Check local/CI coverage composition, selection safety and read-only previews."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check
from regression_inventory import load_inventory
from regression_steps import Command, Rows


class CheckTests(unittest.TestCase):
    """Keep complete qualification distinct from EUnit and the narrower feature runner."""
    def test_default_covers_every_routine_feature_and_ci_layer(self) -> None:
        """Default groups retain packaging, compiler, RTL, debugging, quality and both placements."""
        inventory = load_inventory()
        cases = check.feature_cases(None)
        self.assertEqual(cases, sorted(name for name, row in inventory['cases'].items()
                                      if row['group'] == 'test'))
        self.assertNotIn('telemetry', cases)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plans = {group: check.recipe(group, root/'xls', root/group, cases,
                     ('direct', 'ingress_direct'), None) for group in check.GROUPS}
            steps = {step.name: step for plan in plans.values() for step in plan.steps if isinstance(step, Command)}
            for name in ('eunit', 'release-compiler', 'release-facade', 'release-workloads',
                         'installed-toolchain', 'source-maps', 'DSLX-golden',
                         'function-differential', 'actor-differential',
                         'test_sim_bridge', 'test_debug_memories', 'test_actor_snapshot_formal',
                         'incremental-build', 'arbitration', 'fabric-router', 'RTL-and-bridge',
                         'test_debug_sampling', 'topology-debug',
                         'dialyzer', 'source-contracts', 'runtime-boundaries'):
                self.assertIn(name, steps)
            self.assertEqual(steps['release-compiler'].argv,
                             ['rebar3', 'release', '-n', 'erl_hls'])
            self.assertEqual(steps['release-facade'].argv,
                             ['rebar3', 'release', '-n', 'hls'])
            self.assertEqual(steps['release-workloads'].argv,
                             ['rebar3', 'release', '-n', 'hls_workloads'])
            ordered = [step.name for step in plans['test'].steps if isinstance(step, Command)]
            self.assertLess(ordered.index('release-workloads'), ordered.index('installed-toolchain'))
            self.assertTrue(set(cases) <= {name.split('/')[0] for name in steps})
            topology = str([step.argv for step in plans['topology'].steps if isinstance(step, Command)])
            self.assertIn(', direct)', topology)
            self.assertIn(', ingress_direct)', topology)
            self.assertFalse(any('run_regression.py' in str(step.argv) for step in steps.values()))
            self.assertEqual(list(root.iterdir()), [])

    def test_ci_subset_does_not_remove_base_checks(self) -> None:
        """Narrowing features leaves packaging and other independent checks in the job."""
        cases = check.feature_cases('["serial", "serial", "control_failures"]')
        self.assertEqual(cases, ['serial', 'control_failures'])
        plan = check.recipe('test', Path('/xls'), Path('/stage'), [], ('direct',), None)
        names = {step.name for step in plan.steps if isinstance(step, Command)}
        self.assertIn('installed-toolchain', names)
        self.assertIn('RTL-and-bridge', names)
        release_names = {'release-compiler', 'release-facade', 'release-workloads'}
        self.assertTrue(release_names <= names)
        for raw in ('{}', '[1]', '["absent"]', '["mixed_topology"]', '["telemetry"]'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                check.feature_cases(raw)

    def test_preview_has_no_side_effects_or_tool_requirement(self) -> None:
        """A dry run works before tools are installed and prints all three groups."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)/'output with spaces'
            output = io.StringIO()
            with contextlib.redirect_stdout(output), patch.object(check, 'preflight') as preflight:
                check.main(['/missing/xls', '--stage', str(stage), '--dry-run'])
            self.assertEqual([p['group'] for p in json.loads(output.getvalue())], list(check.GROUPS))
            self.assertFalse(stage.exists())
            preflight.assert_not_called()

    def test_missing_tools_and_failed_group_stop_execution(self) -> None:
        """Reject missing prerequisites, and never start later groups after a failure."""
        with patch.object(check.shutil, 'which', return_value=None), self.assertRaisesRegex(ValueError, 'missing tools'):
            check.preflight(['quality'], None)
        with self.assertRaisesRegex(ValueError, 'XLS_ROOT is required'):
            check.preflight(['test'], None)
        with tempfile.TemporaryDirectory() as directory, patch.object(check, 'preflight'), \
             patch.object(check, 'run_case', side_effect=RuntimeError('fixture failure')) as run, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as exit:
                check.main(['/xls', '--stage', directory])
            self.assertEqual(exit.exception.code, 1)
            self.assertEqual(run.call_count, 1)

    def test_feature_composition_preserves_lazy_rows_and_timeouts(self) -> None:
        """Wrapping feature recipes must neither execute their generators nor add a group deadline."""
        command = Command('probe', ['tool'], timeout=7, rejection='expected')
        with tempfile.TemporaryDirectory() as directory:
            table = Path(directory)/'not-generated-yet'
            rows = Rows(table, 1, lambda row: [command])
            wrapped = check.prefix_steps('feature', [command, rows])
            self.assertEqual(wrapped[0].name, 'feature/probe')
            self.assertEqual(wrapped[0].timeout, 7)
            self.assertEqual(wrapped[0].rejection, 'expected')
            self.assertFalse(table.exists())
            self.assertEqual(wrapped[1].expand(['value']), [wrapped[0]])

    def test_repeated_local_runs_allocate_distinct_tool_stages(self) -> None:
        """Tools with fixed default output directories must receive fresh per-run locations."""
        for stage in (Path('/first'), Path('/second')):
            plan = check.recipe('test', Path('/xls'), stage, [], ('direct',), None)
            steps = {step.name: step for step in plan.steps if isinstance(step, Command)}
            for name in ('function-differential-native', 'function-differential', 'actor-differential',
                         'test_debug_memories', 'test_actor_snapshot_formal', 'arbitration',
                         'fabric-router', 'test_fabric_services', 'test_debug_trace_integration',
                         'test_debug_sampling', 'topology-debug'):
                with self.subTest(stage=stage, name=name):
                    argv = steps[name].argv
                    output = Path(argv[argv.index('--stage') + 1])
                    self.assertEqual(output.parent, stage)

    def test_source_map_fixture_compiles_umbrella_test_beam_first(self) -> None:
        """The fixture must not depend on disposable umbrella EUnit projection artifacts."""
        plan = check.recipe('test', Path('/xls'), Path('/stage'), [], ('direct',), None)
        commands = [step for step in plan.steps if isinstance(step, Command)]
        fixture_index = next(index for index, step in enumerate(commands)
                             if step.name == 'source-map-fixtures')
        self.assertEqual(commands[fixture_index - 1].name, 'beam-compile')
        self.assertEqual(commands[fixture_index - 1].argv,
                         ['rebar3', 'as', 'test', 'compile'])
        fixture = commands[fixture_index]
        self.assertIn('xls_source_map_dslx:write', fixture.argv[fixture.argv.index('-eval') + 1])
        self.assertIn(str(check.ROOT / '_build/test/lib/erl_hls/test'), fixture.argv)

    def test_ci_uses_shared_recipes(self) -> None:
        """Workflows delegate qualification instead of maintaining separate test command lists."""
        ci = (check.ROOT/'.github/workflows/ci.yml').read_text()
        quality = (check.ROOT/'.github/workflows/source-quality.yml').read_text()
        for group, workflow in (('test', ci), ('topology', ci), ('quality', quality)):
            self.assertIn('tools/check.py', workflow)
            self.assertIn('--group ' + group, workflow)
        for workflow in (ci, quality):
            for duplicate in ('run: rebar3 eunit', 'run: rebar3 dialyzer',
                              'tools/test_source_toolchain.py', 'tools/run_regression.py'):
                self.assertNotIn(duplicate, workflow)
        self.assertEqual(ci.count('uses: ./.github/actions/rtl-tools'), 2)
        self.assertNotIn('sudo apt-get', ci)


if __name__ == '__main__':
    unittest.main()
