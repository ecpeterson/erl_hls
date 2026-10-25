#!/usr/bin/env python3
"""Fault-inject incremental XLS builds; optionally compare real regsvc RTL."""
import argparse
from collections.abc import Callable, Mapping
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from erl_hls_tools import compile_xls as compiler
from erl_hls_tools.testing import BuildFixture

ROOT = Path(__file__).resolve().parents[1]


class ToolPackageTests(unittest.TestCase):
    """Package imports are inert and retain compiler-relative observation assets."""

    def test_imports_do_not_select_environment(self) -> None:
        """Transitive helper imports leave environment/search paths unchanged without executing tools."""
        probe = """import importlib, os, sys
before_env, before_path = dict(os.environ), list(sys.path)
for name in ['compile_xls', 'hls_profile', 'topology_debug', 'topology_debug_report', 'measure_topology_debug']:
    importlib.import_module('erl_hls_tools.' + name)
assert dict(os.environ) == before_env
assert sys.path == before_path
assert not any(name.startswith('test_') for name in sys.modules)
from erl_hls_tools.topology_debug_services import rtl_files
assert all(path.is_file() for path in rtl_files(monitor=True))
"""
        subprocess.run([sys.executable, '-c', probe], cwd=ROOT/'tools', check=True,
                       env={**os.environ, 'ERL_HLS_ROOT': '/missing/compiler', 'ERL_AFLAGS': 'sentinel'}, timeout=10)
NATIVE_XLS = None


class Builds(BuildFixture):
    """Check incremental compiler publication and failure recovery."""
    def test_cold_warm_and_relocated_build(self):
        release = self.build()
        self.assertEqual(self.statuses(), dict(ir=False, opt=False, codegen=False))
        self.assertEqual(self.build(), release)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        relocated = self.root / 'relocated'
        shutil.copytree(self.inputs, relocated)
        other = self.root / 'other'
        compiler.build(relocated / self.source.name, self.xls, other, cache=self.cache)
        self.assertEqual(self.statuses(other), dict(ir=True, opt=True, codegen=True))
        self.assertEqual((other / 'counter.v').read_bytes(), (release / 'counter.v').read_bytes())
        self.assertEqual(self.calls.read_text().splitlines(), ['ir', 'opt', 'codegen'])

    def test_output_name_does_not_confuse_shared_conversion_cache(self):
        old = self.build()
        new = self.build(name='renamed')
        self.assertEqual(self.statuses(), dict(ir=True, opt=False, codegen=False))
        self.assertEqual((new / 'renamed.ir').read_bytes(), (old / 'counter.ir').read_bytes())
        self.assertTrue((new / 'renamed.build.json').is_file())

    def test_codegen_options_reuse_conversion_and_optimization(self):
        old = self.build()
        new = self.build(pipeline_stages=3, initiation_interval=2, ram_configurations='test-ram')
        self.assertNotEqual(old, new)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=False))
        self.assertNotEqual((old / 'counter.v').read_bytes(), (new / 'counter.v').read_bytes())
        self.assertTrue(old.is_dir())

    def test_delay_table_changes_only_invalidate_codegen(self) -> None:
        """A changed table cannot silently reuse RTL scheduled with older costs."""
        table = self.root / 'costs.tsv'
        table.write_text('add 8 2 100 200\n')
        old = self.build(delay_model='xc7_7030', delay_table=table)
        self.build(delay_model='xc7_7030', delay_table=table)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        table.write_text('add 8 2 200 400\n')
        new = self.build(delay_model='xc7_7030', delay_table=table)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=False))
        self.assertEqual((old / 'xc7_delay_table.tsv').read_text(), 'add 8 2 100 200\n')
        self.assertEqual((new / 'xc7_delay_table.tsv').read_text(), table.read_text())
        manifest = json.loads((new / 'counter.build.json').read_text())
        self.assertEqual(manifest['assets']['xc7_delay_table.tsv'], compiler.sha(table))
        with self.assertRaisesRegex(ValueError, 'requires a delay table'):
            self.build(delay_model='xc7_7030')

    def test_channel_delays_invalidate_codegen_only(self) -> None:
        """Scheduling budgets survive publication and cannot reuse an older RTL schedule."""
        original = self.build()
        delayed = self.build(channel_delays={'output:send': 6, 'input:recv': 0})
        self.assertNotEqual(original, delayed)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=False))
        manifest = json.loads((delayed / 'counter.build.json').read_text())
        self.assertIn('--additional_channel_delay_ps=input:recv=0,output:send=6',
                      manifest['options']['codegen'])
        self.assertEqual(self.build(channel_delays={'input:recv': 0, 'output:send': 6}), delayed)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        self.assertNotEqual(self.build(channel_delays={'output:send': 7}), delayed)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=False))
        self.assertEqual(self.build(channel_delays={}), original)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))

    def test_invalid_channel_delays_do_not_launch_tools(self) -> None:
        """Reject malformed names and costs before publishing or invoking the compiler."""
        for delays in ({'output:other': 1}, {'output=1': 2}, {'output': -1},
                       {'output': True}, {'output': 1.5}):
            with self.subTest(delays=delays), self.assertRaisesRegex(ValueError, 'channel delays'):
                self.build(channel_delays=delays)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.output.exists())

    def test_import_and_stdlib_edits_invalidate_conversion(self):
        self.build()
        for dependency in [self.inputs / 'helper.x', self.xls / 'xls/dslx/stdlib/std.x']:
            dependency.write_text(dependency.read_text() + '// changed\n')
            self.build()
            self.assertEqual(self.statuses(), dict(ir=False, opt=False, codegen=False))

    def test_compiler_edit_invalidates_only_its_stage_when_output_is_unchanged(self):
        self.build()
        tool = self.xls / 'opt_main'
        tool.write_text(tool.read_text() + '\n# new compiler build\n')
        self.build()
        self.assertEqual(self.statuses(), dict(ir=True, opt=False, codegen=True))

    def test_assets_and_metadata_republish_without_recompilation(self):
        asset = self.inputs / 'wrapper.v'
        asset.write_text('// first wrapper\n')
        old = self.build(assets=[asset], metadata={'profile': {'count': 1}})
        asset.write_text('// changed wrapper\n')
        new = self.build(assets=[asset], metadata={'profile': {'count': 2}})
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        self.assertNotEqual(old, new)
        self.assertEqual((old / 'wrapper.v').read_text(), '// first wrapper\n')
        self.assertEqual((new / 'wrapper.v').read_text(), '// changed wrapper\n')

    def test_failed_rebuild_retains_release_and_resumes_completed_stages(self):
        old = self.build()
        (self.inputs / 'helper.x').write_text('// requires new conversion\n')
        with patch.dict(os.environ, {'XLS_TEST_FAIL': 'opt'}):
            with self.assertRaisesRegex(RuntimeError, 'exited 7'):
                self.build()
        self.assertEqual(self.output.resolve(), old)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        attempt = Path(report['attempt'])
        self.assertEqual(report['status'], 'failed')
        self.assertIn('injected failure', (attempt / 'stderr.log').read_text())
        self.assertIn('partial output', (attempt / 'counter.opt.ir').read_text())
        self.assertTrue((attempt / 'helper.x').is_file())
        self.assertEqual(json.loads((attempt / 'time.json').read_text())['returncode'], 7)
        self.build()
        self.assertEqual(self.statuses(), dict(ir=True, opt=False, codegen=False))

    def test_corrupt_cache_and_release_are_not_reused(self):
        old = self.build()
        run = json.loads(self.output.with_suffix('.run.json').read_text())
        key = run['stages']['ir']['key']
        (self.cache / 'ir' / key / 'counter.ir').write_text('corrupted cached IR')
        (old / 'counter.v').write_text('corrupted published RTL')
        new = self.build()
        self.assertEqual(self.statuses(), dict(ir=False, opt=True, codegen=True))
        self.assertNotEqual((new / 'counter.v').read_text(), 'corrupted published RTL')
        self.assertTrue(list(self.cache.glob('ir/*.damaged-*')))
        self.assertTrue(list(new.parent.glob('*.damaged-*')))

    def test_timeout_kills_compiler_and_preserves_release(self):
        old = self.build()
        self.source.write_text('import helper; // changed\n')
        ready = self.root / 'ready'
        with patch.dict(os.environ, {'XLS_TEST_PAUSE': 'ir', 'XLS_TEST_READY': str(ready)}):
            with self.assertRaises(TimeoutError):
                self.build(timeout=0.2)
        self.assertEqual(self.output.resolve(), old)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(ready.read_text()), 0)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        timing = json.loads((Path(report['attempt']) / 'time.json').read_text())
        self.assertIn('exceeded', timing['error'])

    def spawn_build(self, output, extra_env=None):
        log = (self.root / f'{output.name}.log').open('w')
        self.addCleanup(log.close)
        process = subprocess.Popen([sys.executable, str(ROOT / 'tools/compile_xls.py'),
            str(self.source), str(self.xls), '--output', str(output), '--cache', str(self.cache)],
            stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, **(extra_env or {})))
        self.addCleanup(lambda: process.poll() is None and process.kill())
        return process

    def wait_ready(self, path):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(path.exists())

    def test_two_publishers_share_cache_without_partial_results(self):
        first, second = self.root / 'first', self.root / 'second'
        processes = [self.spawn_build(path) for path in (first, second)]
        for process in processes:
            self.assertEqual(process.wait(timeout=10), 0)
        self.assertEqual((first / 'counter.v').read_bytes(), (second / 'counter.v').read_bytes())
        for output in (first, second):
            manifest = json.loads((output / 'counter.build.json').read_text())
            self.assertEqual(compiler.sha(output / 'counter.v'), manifest['rtl']['counter.v'])

    def test_concurrent_nondeterministic_outputs_use_one_checked_result(self):
        first, second = self.root / 'first', self.root / 'second'
        processes = [self.spawn_build(output, {'XLS_TEST_NONDETERMINISTIC': 'opt', 'XLS_TEST_PAUSE': 'opt',
                     'XLS_TEST_READY': str(self.root / (output.name + '.ready'))}) for output in (first, second)]
        for process in processes:
            self.assertEqual(process.wait(timeout=10), 0)
        for artifact in ['counter.opt.ir', 'counter.v']:
            self.assertEqual((first / artifact).read_bytes(), (second / artifact).read_bytes())
        reports = [json.loads(path.with_suffix('.run.json').read_text()) for path in (first, second)]
        self.assertTrue(any(report['stages']['opt']['adopted'] for report in reports))
        self.assertTrue(all(not report['stages']['opt']['reused'] for report in reports))

    def test_same_output_has_one_writer_and_input_snapshot_is_stable(self):
        ready = self.root / 'ready'
        first = self.spawn_build(self.output, {'XLS_TEST_PAUSE': 'ir', 'XLS_TEST_READY': str(ready)})
        self.wait_ready(ready)
        with self.assertRaisesRegex(ValueError, 'already active'):
            self.build()
        self.source.write_text('// edited while the compiler was running\n')
        # The first compiler reads its frozen snapshot after the pause.
        self.assertEqual(first.wait(timeout=15), 0)
        manifest = json.loads((self.output / 'counter.build.json').read_text())
        self.assertNotEqual(manifest['sources']['counter.x'], compiler.sha(self.source))
        self.assertEqual((self.output / 'sources/counter.x').read_text(), 'import helper;\n')

    def test_signal_cancellation_preserves_release_and_stops_child(self):
        old = self.build()
        self.source.write_text('import helper; // invalidate conversion\n')
        ready = self.root / 'ready'
        process = self.spawn_build(self.output, {'XLS_TEST_PAUSE': 'ir', 'XLS_TEST_READY': str(ready),
                                                'XLS_TEST_SLEEP': '10'})
        self.wait_ready(ready)
        process.send_signal(signal.SIGTERM)
        self.assertNotEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.output.resolve(), old)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(ready.read_text()), 0)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(report['status'], 'failed')
        self.assertIn('interrupted', report['error'])

    def test_preflight_preserves_existing_output(self):
        old = self.build()
        (self.xls / 'codegen_main').unlink()
        with self.assertRaisesRegex(ValueError, 'missing executable'):
            self.build()
        self.assertEqual(self.output.resolve(), old)
        with self.assertRaisesRegex(ValueError, 'positive'):
            self.build(pipeline_stages=0)
        unmanaged = self.root / 'directory'
        unmanaged.mkdir()
        with self.assertRaisesRegex(ValueError, 'managed symlink'):
            compiler.build(self.source, self.xls, unmanaged)

    def test_duration(self):
        self.assertEqual(compiler.duration('2h'), 7200)
        self.assertEqual(compiler.duration('0.5m'), 30)
        for invalid in ('0', '-1', 'nan', 'inf', '1d', '1;echo nope'):
            with self.assertRaises(argparse.ArgumentTypeError):
                compiler.duration(invalid)


class Recipes(BuildFixture):
    """Exercise multiple exact schedules and finalization through the common transaction."""

    def recipe(self, snapshot: Path) -> list[compiler.StageSpec]:
        """Two units share frozen inputs while keeping distinct tops and sampled/pipelined schedules."""
        result = []
        for index in range(2):
            unit = f"unit{index}"
            raw, optimized, rtl = (f"{unit}/{name}" for name in ('raw.ir', 'optimized.ir', 'actor.v'))
            flags = [f"--pipeline_stages={1 if index == 0 else 3}",
                     f"--flop_outputs={'false' if index == 0 else 'true'}", f"--module_name={unit}"]
            result.extend([
                {'id': f'{unit}/convert', 'cache': 'ir', 'tool': 'ir_converter_main',
                 'arguments': ['--dslx_path=.', '--dslx_stdlib_path=_stdlib', f'--top={unit}', 'counter.x'],
                 'output': raw, 'inputs': {'sources': {'counter.x': 'counter.x', 'helper.x': 'helper.x'},
                                           'stdlib': {'std.x': '_stdlib/std.x'}}},
                {'id': f'{unit}/opt', 'cache': 'opt', 'tool': 'opt_main', 'arguments': [raw],
                 'output': optimized, 'inputs': {raw: raw}},
                {'id': f'{unit}/codegen', 'cache': 'codegen', 'tool': 'codegen_main',
                 'arguments': [*flags, optimized], 'output': rtl, 'inputs': {optimized: optimized}}])
        return result

    def publication(self, snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
        """Select both units together and retain stable recipe/cache provenance."""
        return {'manifest_name': 'build.json',
                'manifest': {'stages': {key: row['key'] for key, row in runs.items()}},
                'files': {row['output']: row['output'] for row in runs.values()}}

    def execute(self, *, source_root: Path | None = None, output: Path | None = None,
                finalize: Callable[[Path, Mapping[str, compiler.StageRun]], compiler.Publication] | None = None,
                prepare: Callable[[Path], list[compiler.StageSpec]] | None = None) -> Path:
        """Construct the same explicit snapshot mapping after source or output relocation."""
        source_root = source_root or self.inputs
        files = {**compiler.tree_files(source_root),
                 **compiler.tree_files(self.xls/'xls/dslx/stdlib', '_stdlib')}
        return compiler.execute(files, {name: self.xls/name for name in compiler.TOOLS}, output or self.output,
                                prepare=prepare or self.recipe, finalize=finalize or self.publication,
                                directories=['empty-import'], name='two_units', cache=self.cache)

    def test_multiunit_cold_warm_and_relocated(self) -> None:
        """Every stage reuses after relocation and one-stage/no-output-flop flags are unchanged."""
        release = self.execute()
        self.assertEqual(len(self.calls.read_text().splitlines()), 6)
        for index in range(2):
            command = json.loads((release/f'unit{index}/codegen.command.json').read_text())
            self.assertIn(f"--flop_outputs={'false' if index == 0 else 'true'}", command)
            self.assertIn(f"--pipeline_stages={1 if index == 0 else 3}", command)
        self.assertEqual(self.execute(), release)
        self.assertTrue(all(self.statuses().values()))
        moved = self.root/'moved sources'
        shutil.copytree(self.inputs, moved)
        second = self.root/'other output'
        other_release = self.execute(source_root=moved, output=second)
        self.assertTrue(all(self.statuses(second).values()))
        self.assertEqual(compiler.sha(other_release/'unit1/actor.v'), compiler.sha(release/'unit1/actor.v'))
        self.assertEqual(len(self.calls.read_text().splitlines()), 6)

    def test_second_unit_failure_retains_release_and_retry_reuses_completed_work(self) -> None:
        """A failed last unit cannot expose a mixture of old and new successful products."""
        old = self.execute()
        (self.inputs/'helper.x').write_text('// new dependency\n')
        with patch.dict(os.environ, {'XLS_TEST_FAIL': 'codegen', 'XLS_TEST_FAIL_MATCH': '--module_name=unit1'}):
            with self.assertRaisesRegex(RuntimeError, 'exited 7'):
                self.execute()
        self.assertEqual(self.output.resolve(), old)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(report['active_stage'], 'unit1/codegen')
        attempt = Path(report['attempt'])
        self.assertTrue((attempt/'unit0/actor.v').is_file())
        self.assertIn('partial output', (attempt/'unit1/actor.v').read_text())
        self.execute()
        self.assertEqual(self.statuses(), {'unit0/convert': True, 'unit0/opt': True, 'unit0/codegen': True,
                                          'unit1/convert': True, 'unit1/opt': True, 'unit1/codegen': False})

    def test_finalization_failure_and_transformation_remain_atomic(self) -> None:
        """Final reports and transformed RTL participate in publication identity without new XLS work."""
        old = self.execute()

        def fail(snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
            """Fail after producing a partial final report to test the transaction boundary."""
            (snapshot/'partial-report.json').write_text('{}')
            raise ValueError('rejected final policy')

        with self.assertRaisesRegex(ValueError, 'rejected final policy'):
            self.execute(finalize=fail)
        self.assertEqual(self.output.resolve(), old)
        self.assertTrue(all(self.statuses().values()))
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(report['active_stage'], 'finalize')
        self.assertTrue((Path(report['attempt'])/'partial-report.json').is_file())

        def transform(snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
            """Change a product without changing the client manifest to test executor file identity."""
            path = snapshot/'unit1/actor.v'
            path.write_text(path.read_text()+'// legalized\n')
            return self.publication(snapshot, runs)

        new = self.execute(finalize=transform)
        self.assertNotEqual(new, old)
        self.assertTrue(all(self.statuses().values()))
        self.assertTrue((new/'unit1/actor.v').read_text().endswith('// legalized\n'))
        self.assertEqual(self.execute(), old)

    def test_frozen_input_mutation_rejected_before_publication(self) -> None:
        """A postprocessor may change products, never the source snapshot behind their provenance."""
        old = self.execute()

        def mutate(snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
            """Inject a source mutation as a rejecting control for the finalization contract."""
            (snapshot/'counter.x').write_text('mutated')
            return self.publication(snapshot, runs)

        with self.assertRaisesRegex(ValueError, 'frozen build input'):
            self.execute(finalize=mutate)
        self.assertEqual(self.output.resolve(), old)

    def test_invalid_recipe_runs_no_tools(self) -> None:
        """Duplicate products and paths escaping the snapshot fail before tool execution."""
        def duplicate(snapshot: Path) -> list[compiler.StageSpec]:
            """Return two owners of the same product to exercise preparation validation."""
            specs = self.recipe(snapshot)
            specs[-1]['output'] = specs[0]['output']
            return specs

        with self.assertRaisesRegex(ValueError, 'duplicate or reserved'):
            self.execute(prepare=duplicate)
        self.assertFalse(self.calls.exists())
        with self.assertRaisesRegex(ValueError, 'normalized relative path'):
            compiler.execute({'../escaped.x': self.source}, {'ir_converter_main': self.xls/'ir_converter_main'},
                             self.output, prepare=self.recipe, finalize=self.publication)
        self.assertFalse(self.calls.exists())

    def test_finalizer_cannot_replace_logs_or_change_tool_identity(self) -> None:
        """A late client mistake or compiler replacement cannot publish false provenance."""
        old = self.execute()

        def replace_log(snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
            """Select an owned diagnostic filename as the manifest as a rejecting control."""
            result = self.publication(snapshot, runs)
            return {**result, 'manifest_name': 'unit0/convert.command.json'}

        with self.assertRaisesRegex(ValueError, 'shadows'):
            self.execute(finalize=replace_log)
        self.assertEqual(self.output.resolve(), old)

        def change_tool(snapshot: Path, runs: Mapping[str, compiler.StageRun]) -> compiler.Publication:
            """Replace a tool after all stages finish to exercise the last identity check."""
            tool = self.xls/'codegen_main'
            tool.write_text(tool.read_text()+'\n# replacement during finalization\n')
            return self.publication(snapshot, runs)

        with self.assertRaisesRegex(ValueError, 'changed during finalization'):
            self.execute(finalize=change_tool)
        self.assertEqual(self.output.resolve(), old)

    def test_input_tree_keeps_nested_and_linked_imports(self) -> None:
        """Dependency inventory preserves import hierarchy and detects link cycles explicitly."""
        nested = self.inputs/'subdir'
        nested.mkdir()
        (nested/'module.x').write_text('pub const A = u1:1;')
        (self.inputs/'alias').symlink_to(nested, target_is_directory=True)
        files = compiler.tree_files(self.inputs, '_imports/0')
        self.assertIn('_imports/0/subdir/module.x', files)
        self.assertIn('_imports/0/alias/module.x', files)
        self.assertEqual(compiler.sha(files['_imports/0/subdir/module.x']),
                         compiler.sha(files['_imports/0/alias/module.x']))
        (nested/'loop').symlink_to(self.inputs, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'cyclic input directory'):
            compiler.tree_files(self.inputs)

    def test_flat_finalizer_and_signal_policy(self) -> None:
        """The flat adapter refreshes transformed product hashes and restores embedding signal policy."""
        prior = signal.getsignal(signal.SIGTERM)
        old = self.build()

        def transform(snapshot: Path, manifest: dict) -> dict:
            """Model a fabric-owned postprocessor without owning its release directory."""
            path = snapshot/'counter.v'
            path.write_text(path.read_text()+'// backend result\n')
            return {**manifest, 'backend': {'policy': 'test'}}

        new = self.build(finalize=transform)
        self.assertEqual(signal.getsignal(signal.SIGTERM), prior)
        self.assertEqual(self.statuses(), dict(ir=True, opt=True, codegen=True))
        manifest = json.loads((new/'counter.build.json').read_text())
        self.assertEqual(manifest['rtl']['counter.v'], compiler.sha(new/'counter.v'))
        self.assertEqual(manifest['artifacts']['counter.v'], compiler.sha(new/'counter.v'))
        self.assertEqual(manifest['backend'], {'policy': 'test'})
        self.assertNotEqual(old, new)



class NativeBuild(unittest.TestCase):
    def test_regsvc_matches_direct_compilation_and_reuses(self):
        if NATIVE_XLS is None:
            self.skipTest('pass --xls-root to compare real regsvc compilation')
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            for source in (ROOT / 'priv/xls/lib').glob('*.x'):
                shutil.copyfile(source, stage / source.name)
            shutil.copyfile(ROOT / 'src/examples/regsvc/regsvc.erl.x', stage / 'regsvc.x')
            stdlib = NATIVE_XLS / 'xls/dslx/stdlib'
            commands = [
                ('regsvc.ir', [NATIVE_XLS / 'ir_converter_main', '--warnings_as_errors=false', '--dslx_path=.',
                               f'--dslx_stdlib_path={stdlib}', '--top=Top', 'regsvc.x']),
                ('regsvc.opt.ir', [NATIVE_XLS / 'opt_main', 'regsvc.ir']),
                ('regsvc.v', [NATIVE_XLS / 'codegen_main', '--pipeline_stages=1', '--delay_model=unit',
                              '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
                              '--reset=reset', '--fifo_module=', 'regsvc.opt.ir'])]
            for output, command in commands:
                with (stage / output).open('w') as stream:
                    subprocess.run(list(map(str, command)), cwd=stage, stdout=stream, check=True)
            release = compiler.build(stage / 'regsvc.x', NATIVE_XLS, stage / 'compiled')
            self.assertEqual((stage / 'regsvc.v').read_bytes(), (release / 'regsvc.v').read_bytes())
            self.assertEqual(compiler.build(stage / 'regsvc.x', NATIVE_XLS, stage / 'compiled'), release)
            report = json.loads((stage / 'compiled.run.json').read_text())
            self.assertTrue(all(row['reused'] for row in report['stages'].values()))
            subprocess.run(['iverilog', '-g2012', '-tnull', str(release / 'regsvc.v')], check=True)
            changed = compiler.build(stage / 'regsvc.x', NATIVE_XLS, stage / 'compiled', pipeline_stages=2)
            changed_report = json.loads((stage / 'compiled.run.json').read_text())
            self.assertEqual({k: v['reused'] for k, v in changed_report['stages'].items()},
                             dict(ir=True, opt=True, codegen=False))
            self.assertNotEqual((changed / 'regsvc.v').read_bytes(), (release / 'regsvc.v').read_bytes())
            subprocess.run(['iverilog', '-g2012', '-tnull', str(changed / 'regsvc.v')], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--xls-root', type=Path)
    arguments, rest = parser.parse_known_args()
    NATIVE_XLS = arguments.xls_root.resolve() if arguments.xls_root else None
    unittest.main(argv=[sys.argv[0], *rest])
