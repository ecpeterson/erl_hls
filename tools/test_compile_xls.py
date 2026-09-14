#!/usr/bin/env python3
"""Fault-inject incremental XLS builds; optionally compare real regsvc RTL."""
import argparse
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

import compile_xls as compiler

ROOT = Path(__file__).resolve().parents[1]
NATIVE_XLS = None
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
p = pathlib.Path
stage = {'ir_converter_main': 'ir', 'opt_main': 'opt', 'codegen_main': 'codegen'}[p(sys.argv[0]).name]
with open(os.environ['XLS_TEST_CALLS'], 'a') as log:
    log.write(stage + '\n')
if os.environ.get('XLS_TEST_PAUSE') == stage:
    p(os.environ['XLS_TEST_READY']).write_text(str(os.getpid()))
    time.sleep(float(os.environ.get("XLS_TEST_SLEEP", "1")))
if os.environ.get('XLS_TEST_FAIL') == stage:
    print('partial output')
    print('injected failure', file=sys.stderr)
    sys.exit(7)
if stage == 'ir':
    inputs = {str(f): f.read_text() for pattern in ['*.x', '_stdlib/**/*.x'] for f in sorted(p('.').glob(pattern))}
else:
    inputs = p(sys.argv[-1]).read_text()
result = {'stage': stage, 'args': sys.argv[1:], 'inputs': inputs}
if os.environ.get('XLS_TEST_NONDETERMINISTIC') == stage:
    result['node_id'] = os.getpid()
print(json.dumps(result, sort_keys=True))
'''


class Builds(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inputs = self.root / 'input with spaces'
        self.inputs.mkdir()
        self.source = self.inputs / 'counter.x'
        self.source.write_text('import helper;\n')
        (self.inputs / 'helper.x').write_text('pub const VALUE = u32:1;\n')
        self.xls = self.root / 'xls'
        self.xls.mkdir()
        for tool in compiler.TOOLS:
            path = self.xls / tool
            path.write_text(STUB)
            path.chmod(0o755)
        stdlib = self.xls / 'xls/dslx/stdlib'
        stdlib.mkdir(parents=True)
        (stdlib / 'std.x').write_text('// test standard library\n')
        self.calls = self.root / 'calls'
        environment = patch.dict(os.environ, {'XLS_TEST_CALLS': str(self.calls)})
        environment.start()
        self.addCleanup(environment.stop)
        self.output = self.root / 'published'
        self.cache = self.root / 'cache'

    def build(self, **options):
        return compiler.build(self.source, self.xls, self.output, cache=self.cache, **options)

    def statuses(self, output=None):
        report = json.loads((output or self.output).with_suffix('.run.json').read_text())
        return {name: row['reused'] for name, row in report['stages'].items()}

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

    def test_profile_wrapper_publishes_metadata_ram_configuration_and_assets(self):
        (self.inputs / 'phi_decoder_profile_topology.x').write_text('const WIDTH = u16:3;\nconst HEIGHT = u16:3;\n')
        shutil.copyfile(ROOT / 'tools/phi_scheduler_rams.sh', self.inputs / 'phi_scheduler_rams.sh')
        for asset in ('hls_1r1w_ram.v', 'phi_decoder_profile_top.v'):
            (self.inputs / asset).write_text('// ' + asset)
        # Exercise the helpers as copied into a prepared stage, from another cwd.
        for helper in ('compile_xls.py', 'compile_phi_decoder_profile.py', 'compile_phi_decoder_profile.sh'):
            shutil.copyfile(ROOT / 'tools' / helper, self.inputs / helper)
        command = ['bash', str(self.inputs / 'compile_phi_decoder_profile.sh'), str(self.inputs), str(self.xls)]
        subprocess.run(command, cwd=self.root, check=True, stdout=subprocess.DEVNULL)
        release = (self.inputs / 'compiled').resolve()
        manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
        self.assertEqual(manifest['profile']['shards_per_plane'], 3)
        self.assertEqual(manifest['profile']['initiation_interval'], 1)
        self.assertIn('--worst_case_throughput=1', manifest['options']['codegen'])
        ram = next(arg for arg in manifest['options']['codegen'] if arg.startswith('--ram_configurations='))
        self.assertIn('scheduler_7_mailbox:1R1W:', ram)
        self.assertNotIn('scheduler_8_', ram)
        for asset in ('hls_1r1w_ram.v', 'phi_decoder_profile_top.v'):
            self.assertEqual(manifest['rtl'][asset], compiler.sha(release / asset))
        subprocess.run(command, cwd=self.root, check=True, stdout=subprocess.DEVNULL)
        self.assertEqual(self.statuses(self.inputs / 'compiled'), dict(ir=True, opt=True, codegen=True))

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
