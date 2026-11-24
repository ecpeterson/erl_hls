"""Mock external XLS stages to check multi-unit publication and cache identity, not hardware semantics."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('source_build_executor', ROOT/'apps/hls_target/priv/tools/compile_source_build.py')
driver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(driver)

# Each stub retains exactly the requested source/import closure, so shadowed imports have distinct witnesses.
STUB = r'''import json, os, pathlib, re, sys
stage = {'ir_converter_main': 'convert', 'opt_main': 'opt', 'codegen_main': 'codegen'}[pathlib.Path(sys.argv[0]).name]
source = pathlib.Path(sys.argv[-1])
unit = source.parts[0]
with open(os.environ['XLS_SOURCE_CALLS'], 'a') as calls:
    calls.write(json.dumps({'stage': stage, 'unit': unit, 'command': sys.argv}) + '\n')
if os.environ.get('XLS_SOURCE_FAIL') == unit + ':' + stage:
    print('partial failed product')
    print('injected source-build failure', file=sys.stderr)
    raise SystemExit(7)
if stage == 'convert':
    roots = next(arg.split('=', 1)[1].split(':') for arg in sys.argv if arg.startswith('--dslx_path='))
    stdlib = next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--dslx_stdlib_path='))
    files = {}
    def visit(path):
        key = path.as_posix()
        if key in files:
            return
        text = path.read_text()
        files[key] = text
        for name in re.findall(r'^\s*import\s+([\w.]+);', text, re.MULTILINE):
            relative = pathlib.Path(*name.split('.')).with_suffix('.x')
            resolved = next((pathlib.Path(root)/relative for root in [*roots, stdlib]
                             if (pathlib.Path(root)/relative).is_file()), None)
            if resolved is None:
                raise RuntimeError('unresolved fixture import: ' + name)
            visit(resolved)
    visit(source)
    inputs = files
else:
    inputs = json.loads(source.read_text())
print(json.dumps({'stage': stage, 'arguments': sys.argv[1:], 'inputs': inputs}, sort_keys=True))
'''


class SourceBuildExecutorTests(unittest.TestCase):
    """Use two independent units and hierarchical imports to exercise executor boundaries."""

    def setUp(self) -> None:
        """Create deterministic, distinct source units and executable stand-ins for the three XLS stages."""
        self.temporary = tempfile.TemporaryDirectory(prefix='source executor ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bundle = self.root/'source bundle'
        self.bundle.mkdir()
        self.xls = self.root/'tool bundle'
        (self.xls/'xls/dslx/stdlib').mkdir(parents=True)
        (self.xls/'xls/dslx/stdlib/std.x').write_text('pub const STANDARD = u32:7;\n')
        for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
            tool = self.xls/name
            tool.write_text('#!' + sys.executable + '\n' + STUB)
            tool.chmod(0o755)
        self.calls = self.root/'calls.jsonl'
        self.environment = patch.dict(os.environ, {'XLS_SOURCE_CALLS': str(self.calls), 'XLS_SOURCE_FAIL': ''})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.cache = self.root/'cache'
        self.output = self.root/'published'
        units = []
        for index in range(2):
            role = f'role{index}'
            for relative in (f'{role}/core', f'{role}/imports/libs'):
                (self.bundle/relative).mkdir(parents=True)
            (self.bundle/role/'core/main.x').write_text('import libs.helper;\n'
                f'pub fn main() -> u32 {{ helper::VALUE + u32:{index} }}\n')
            (self.bundle/role/'imports/libs/helper.x').write_text('import libs.leaf;\n'
                f'pub const VALUE = leaf::LEAF + u32:{index + 1};\n')
            (self.bundle/role/'adapter.sv').write_text(f'module adapter_{index}; endmodule\n')
            flags = [f'--pipeline_stages={index + 1}', '--flop_inputs=false',
                     '--flop_outputs=' + ('false' if index == 0 else 'true'), '--reset=rst']
            units.append({'directory': f'{role}/core', 'role': role, 'source': f'{role}/core/main.x',
                          'top': 'main', 'module': f'unit_{index}', 'output': f'{role}/core/design.v',
                          'dslx_path': [f'{role}/imports', 'shared'], 'codegen_flags': flags,
                          'rtl': [f'{role}/core/design.v', f'{role}/adapter.sv']})
        (self.bundle/'shared/libs').mkdir(parents=True)
        (self.bundle/'shared/libs/helper.x').write_text('pub const VALUE = u32:999;\n')
        (self.bundle/'shared/libs/leaf.x').write_text('pub const LEAF = u32:23;\n')
        self.manifest: dict[str, Any] = {'version': 2, 'provenance': {'kind': 'unplanned'},
            'metadata': {'kind': 'mock deployment', 'hardware_profile': {
                'backend': 'fixture', 'options': {'storage': 'local', 'pipeline_stages': 99}}},
            'units': units, 'inputs': [], 'rtl': {unit['role']: unit['rtl'] for unit in units}}
        self.freeze()

    def freeze(self) -> None:
        """Regenerate the trusted manifest after a deliberate source edit, without including products."""
        self.manifest['inputs'] = [{'file': str(path.relative_to(self.bundle)),
                                   'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                                  for path in sorted(self.bundle.rglob('*'))
                                  if path.is_file() and path.suffix in ('.x', '.sv')]
        (self.bundle/'source-build.json').write_text(json.dumps(self.manifest, sort_keys=True) + '\n')

    def bound_snapshot(self) -> dict[str, tuple[bytes, int]]:
        """Record only frozen source files and their manifest, excluding external compilation products."""
        names = ['source-build.json', *(row['file'] for row in self.manifest['inputs'])]
        return {name: ((self.bundle/name).read_bytes(), (self.bundle/name).stat().st_mtime_ns) for name in names}

    def invocations(self) -> list[dict[str, Any]]:
        """Return the ordered external calls, which also distinguish cache hits from executions."""
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def compile(self, *, directory: Path | None = None, output: Path | None = None) -> Path:
        """Compile a selected immutable input bundle through the shared cache into a managed output."""
        return driver.compile_build(self.xls, directory or self.bundle, output=output or self.output,
                                    cache=self.cache, timeout=10)

    def test_preview_and_execution_use_identical_relative_commands(self) -> None:
        """Preview is read-only; cold execution preserves explicit schedules and relative product listings."""
        before = self.bound_snapshot()
        with patch('subprocess.Popen', side_effect=AssertionError('preview launched a process')):
            plan = driver.plan_build(self.xls, self.bundle)
        self.assertEqual(self.bound_snapshot(), before)
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.output.exists())
        self.assertEqual(self.invocations(), [])
        self.assertEqual(plan['metadata'], self.manifest['metadata'])
        for index, unit in enumerate(plan['units']):
            self.assertEqual(unit['codegen_flags'], self.manifest['units'][index]['codegen_flags'])
            self.assertEqual(unit['commands'][-1]['command'][1:1 + len(unit['codegen_flags'])],
                             unit['codegen_flags'])
            for command in unit['commands']:
                self.assertFalse(Path(command['output']).is_absolute())
                self.assertFalse(Path(command['log']).is_absolute())
                self.assertFalse(Path(command['command'][-1]).is_absolute())
        release = self.compile()
        self.assertEqual(release, self.output.resolve())
        self.assertTrue(self.output.is_symlink())
        self.assertFalse(release.is_symlink())
        compiled = json.loads((release/'compiled.json').read_text())
        self.assertEqual(compiled['version'], 2)
        self.assertFalse(compiled['native_measured'])
        self.assertFalse(compiled['eligible'])
        self.assertEqual(compiled['metadata'], self.manifest['metadata'])
        self.assertEqual(compiled['xls_tools'],
                         {name: tool['sha256'] for name, tool in plan['xls_tools'].items()})
        self.assertEqual(compiled['build_request']['sha256'], plan['request_sha256'])
        self.assertEqual(compiled['build_request']['descriptor'], plan['request'])
        self.assertEqual(compiled['implementation']['request_sha256'], plan['request_sha256'])
        self.assertEqual(compiled['implementation']['product_sha256'], compiled['products']['sha256'])
        self.assertEqual(compiled['implementation']['provenance'], {'kind': 'unplanned'})
        for name, (contents, _) in before.items():
            self.assertEqual((release/name).read_bytes(), contents)
        self.assertEqual([call['command'] for call in self.invocations()],
                         [command['command'] for unit in plan['units'] for command in unit['commands']])
        for unit, result in zip(plan['units'], compiled['units'], strict=True):
            planned = [command['command'] for command in unit['commands']]
            self.assertEqual([command['command'] for command in result['commands']], planned)
            self.assertEqual(json.loads((release/unit['directory']/'commands.json').read_text()), result['commands'])
            listing = release/unit['role']/'files.f'
            paths = listing.read_text().splitlines()
            self.assertTrue(all(not Path(path).is_absolute() for path in paths))
            self.assertEqual([(listing.parent/path).resolve() for path in paths],
                             [(release/row['file']).resolve() for row in compiled['rtl'][unit['role']]])
            for row in compiled['rtl'][unit['role']]:
                self.assertFalse(Path(row['file']).is_absolute())
                self.assertEqual(hashlib.sha256((release/row['file']).read_bytes()).hexdigest(), row['sha256'])
        self.assertEqual(self.bound_snapshot(), before)
        report = json.loads((self.output.parent/(self.output.name + '.run.json')).read_text())
        for index, unit in enumerate(plan['units']):
            for command in unit['commands']:
                self.assertEqual(report['stages'][f'unit{index}.{command["stage"]}']['planned_command'],
                                 command['command'])
        self.assertEqual(self.compile(), release)
        self.assertEqual(len(self.invocations()), 6)
        self.assertEqual(self.bound_snapshot(), before)

    def test_compiled_release_rejects_self_consistent_inventory_edits(self) -> None:
        """Recomputed identities cannot omit required products or add unrelated files and RTL."""
        plan = driver.plan_build(self.xls, self.bundle)
        release = self.compile()
        original = json.loads((release/'compiled.json').read_text())

        def reidentify(value: dict[str, Any], rows: list[dict[str, str]]) -> None:
            """Replace product rows and recompute both dependent receipt identities."""
            products = {'schema': 1, 'files': rows}
            product_identity = driver.executor().identity(products)
            value['products'] = products | {'sha256': product_identity}
            realization = {key: value['implementation'][key]
                           for key in ('schema', 'request_sha256', 'provenance')}
            realization['product_sha256'] = product_identity
            value['implementation'] = realization | {
                'sha256': driver.executor().identity(realization),
            }
            (release/'compiled.json').write_text(json.dumps(value) + '\n')

        omitted = json.loads(json.dumps(original))
        reidentify(omitted, omitted['products']['files'][1:])
        with self.assertRaisesRegex(ValueError, 'product inventory mismatch'):
            driver.checked_compiled_release(release, plan)

        added = json.loads(json.dumps(original))
        unexpected = release/'unexpected.bin'
        unexpected.write_bytes(b'unrelated product\n')
        rows = added['products']['files'] + [
            {'file': unexpected.name, 'sha256': hashlib.sha256(unexpected.read_bytes()).hexdigest()}
        ]
        reidentify(added, sorted(rows, key=lambda row: row['file']))
        with self.assertRaisesRegex(ValueError, 'product inventory mismatch'):
            driver.checked_compiled_release(release, plan)

        changed_rtl = json.loads(json.dumps(original))
        role = sorted(changed_rtl['rtl'])[0]
        changed_rtl['rtl'][role] = changed_rtl['rtl'][role][1:]
        (release/'compiled.json').write_text(json.dumps(changed_rtl) + '\n')
        with self.assertRaisesRegex(ValueError, 'RTL inventory mismatch'):
            driver.checked_compiled_release(release, plan)

    def test_metadata_only_change_preserves_cached_stages_and_new_provenance(self) -> None:
        """Descriptive policy cannot change schedules, but every publication retains its own metadata."""
        first_plan = driver.plan_build(self.xls, self.bundle)
        first = self.compile()
        first_manifest = json.loads((first/'compiled.json').read_text())
        first_inputs = self.manifest['inputs']
        self.manifest['metadata']['hardware_profile']['options']['storage'] = 'shared'
        self.freeze()
        plan = driver.plan_build(self.xls, self.bundle)
        self.assertEqual(self.manifest['inputs'], first_inputs)
        self.assertEqual(plan['units'], first_plan['units'])
        self.assertEqual(plan['xls_tools'], first_plan['xls_tools'])
        count = len(self.invocations())
        second = self.compile()
        compiled = json.loads((second/'compiled.json').read_text())
        report = json.loads((self.root/'published.run.json').read_text())
        self.assertNotEqual(first, second)
        self.assertEqual(len(self.invocations()), count)
        self.assertTrue(all(command['reused'] for command in report['stages'].values()))
        self.assertEqual(compiled['metadata'], self.manifest['metadata'])
        self.assertEqual(compiled['units'], first_manifest['units'])
        self.assertEqual(compiled['xls_tools'], first_manifest['xls_tools'])
        self.assertEqual(compiled['products'], first_manifest['products'])
        self.assertNotEqual(compiled['build_request']['sha256'],
                            first_manifest['build_request']['sha256'])
        self.assertNotEqual(compiled['implementation']['sha256'],
                            first_manifest['implementation']['sha256'])
        self.assertEqual(json.loads((first/'compiled.json').read_text()), first_manifest)
        self.assertNotEqual(compiled['source_build_sha256'], first_manifest['source_build_sha256'])

    def test_metadata_must_be_an_object_before_execution(self) -> None:
        """Reject malformed metadata before launching tools or creating any output/cache state."""
        for value in (None, 'profile', [], 7):
            with self.subTest(metadata=value):
                self.manifest['metadata'] = value
                self.freeze()
                before = self.bound_snapshot()
                with patch('subprocess.Popen', side_effect=AssertionError('invalid metadata executed a tool')):
                    with self.assertRaisesRegex(ValueError, 'metadata must be an object'):
                        driver.plan_build(self.xls, self.bundle)
                    with self.assertRaisesRegex(ValueError, 'metadata must be an object'):
                        self.compile()
                self.assertEqual(self.bound_snapshot(), before)
                self.assertFalse(self.cache.exists())
                self.assertFalse(self.output.exists())
                self.assertEqual(self.invocations(), [])
        del self.manifest['metadata']
        self.freeze()
        self.assertEqual(driver.plan_build(self.xls, self.bundle)['metadata'], {})

    def test_later_unit_failure_keeps_previous_release_and_retry_uses_cache(self) -> None:
        """Publication is all-or-nothing and a retry reuses both complete units and completed earlier stages."""
        previous = self.compile()
        previous_metadata = (previous/'compiled.json').read_bytes()
        for index in range(2):
            path = self.bundle/f'role{index}/core/main.x'
            path.write_text(path.read_text() + '// changed frozen source\n')
        self.freeze()
        before = self.bound_snapshot()
        with patch.dict(os.environ, {'XLS_SOURCE_FAIL': 'role1:codegen'}):
            with self.assertRaises(RuntimeError):
                self.compile()
        self.assertEqual(self.output.resolve(), previous)
        self.assertEqual((previous/'compiled.json').read_bytes(), previous_metadata)
        failure = json.loads((self.output.parent/(self.output.name + '.run.json')).read_text())
        self.assertEqual(failure['status'], 'failed')
        self.assertIn('codegen', failure['active_stage'])
        attempt = Path(failure['attempt'])
        self.assertTrue(attempt.is_dir())
        self.assertTrue(any('injected source-build failure' in path.read_text()
                            for path in attempt.rglob('*.log')))
        count = len(self.invocations())
        release = self.compile()
        self.assertNotEqual(release, previous)
        self.assertEqual([(call['unit'], call['stage']) for call in self.invocations()[count:]],
                         [('role1', 'codegen')])
        self.assertEqual(self.bound_snapshot(), before)

    def test_hierarchical_imports_preserve_shadowing_and_dependency_identity(self) -> None:
        """Ordered import roots select each role's helper and transitive shared input; changed inputs invalidate conversion."""
        release = self.compile()
        for index in range(2):
            files = json.loads((release/f'role{index}/core/raw.ir').read_text())['inputs']
            self.assertIn(f'role{index}/imports/libs/helper.x', files)
            self.assertIn('shared/libs/leaf.x', files)
            self.assertNotIn('shared/libs/helper.x', files)
        count = len(self.invocations())
        (self.bundle/'shared/libs/leaf.x').write_text('pub const LEAF = u32:47;\n')
        self.freeze()
        changed = self.compile()
        self.assertNotEqual(changed, release)
        self.assertEqual([call['unit'] for call in self.invocations()[count:] if call['stage'] == 'convert'],
                         ['role0', 'role1'])
        for index in range(2):
            files = json.loads((changed/f'role{index}/core/raw.ir').read_text())['inputs']
            self.assertEqual(files['shared/libs/leaf.x'], 'pub const LEAF = u32:47;\n')

    def test_frozen_input_drift_rejects_before_tools_or_publication(self) -> None:
        """A source edit without a refreshed manifest cannot poison caches or replace a valid release."""
        previous = self.compile()
        count = len(self.invocations())
        (self.bundle/'shared/libs/leaf.x').write_text('unfrozen edit\n')
        changed = self.bound_snapshot()
        with self.assertRaisesRegex(ValueError, 'changed source build input'):
            self.compile()
        with self.assertRaisesRegex(ValueError, 'changed source build input'):
            driver.plan_build(self.xls, self.bundle)
        self.assertEqual(self.output.resolve(), previous)
        self.assertEqual(len(self.invocations()), count)
        self.assertEqual(self.bound_snapshot(), changed)

    def test_relocation_reuses_cache_without_absolute_input_paths(self) -> None:
        """Moving source and tools reuses the whole implementation in an output-local release."""
        first = self.compile()
        relocated = self.root/'relocated source bundle'
        relocated_xls = self.root/'relocated tool bundle'
        shutil.copytree(self.bundle, relocated)
        shutil.copytree(self.xls, relocated_xls)
        count = len(self.invocations())
        relocated_output = self.root/'relocated output'
        with patch.object(driver.executor(), 'execute',
                          side_effect=AssertionError('whole hit entered the stage executor')):
            second = driver.compile_build(relocated_xls, relocated, output=relocated_output,
                                          cache=self.cache, timeout=10)
        self.assertEqual(len(self.invocations()), count)
        self.assertNotEqual(first, second)
        self.assertEqual(second.parent, self.root/'.relocated output-releases')
        self.assertEqual(relocated_output.resolve(), second)
        for relative in ('role0/core/raw.ir', 'role0/core/optimized.ir', 'role0/core/design.v',
                         'role1/core/raw.ir', 'role1/core/optimized.ir', 'role1/core/design.v'):
            self.assertEqual((first/relative).read_bytes(), (second/relative).read_bytes())
        compiled = json.loads((second/'compiled.json').read_text())
        original = json.loads((first/'compiled.json').read_text())
        report = json.loads((self.root/'relocated output.run.json').read_text())
        self.assertTrue(report['implementation_reused'])
        self.assertEqual(report['stages'], {})
        self.assertEqual(compiled['rtl'], original['rtl'])
        self.assertEqual(compiled['build_request'], original['build_request'])
        self.assertEqual(compiled['products'], original['products'])
        self.assertEqual(compiled['implementation'], original['implementation'])
        for role in ('role0', 'role1'):
            listing = second/role/'files.f'
            self.assertTrue(all((listing.parent/line).is_file() for line in listing.read_text().splitlines()))

    def test_whole_implementation_warm_hit_uses_checked_selection(self) -> None:
        """A warm request bypasses every external stage and copies the checked release locally."""
        plan = driver.plan_build(self.xls, self.bundle)
        first = self.compile()
        compiled = json.loads((first/'compiled.json').read_text())
        implementation = compiled['implementation']['sha256']
        selection = driver.selection_path(self.cache, plan['request_sha256'])
        self.assertEqual(json.loads(selection.read_text())['implementation_sha256'], implementation)
        stored = driver.implementation_path(self.cache, implementation)
        self.assertTrue((stored/'record.json').is_file())
        count = len(self.invocations())
        warm_output = self.root/'warm output'
        with patch.object(driver.executor(), 'execute',
                          side_effect=AssertionError('warm hit entered the stage executor')):
            warm = self.compile(output=warm_output)
        self.assertEqual(len(self.invocations()), count)
        self.assertEqual(warm.parent, self.root/'.warm output-releases')
        self.assertEqual(warm_output.resolve(), warm)
        self.assertFalse(warm.is_symlink())
        self.assertFalse(warm.is_relative_to(stored))
        self.assertEqual(driver.release_hashes(warm), driver.release_hashes(first))
        report = json.loads((self.root/'warm output.run.json').read_text())
        self.assertTrue(report['implementation_reused'])
        self.assertEqual(report['implementation_sha256'], implementation)
        self.assertEqual(report['stages'], {})

    def test_warm_hit_rejects_linked_release_roots_and_namespaces(self) -> None:
        """Whole-release reuse never accepts a linked store/output root as owned cache data."""
        plan = driver.plan_build(self.xls, self.bundle)
        first = self.compile()
        implementation = json.loads(
            (first/'compiled.json').read_text()
        )['implementation']['sha256']
        entry = driver.implementation_path(self.cache, implementation)
        record = json.loads((entry/'record.json').read_text())
        stored_release = entry/'release'

        linked_release = self.root/'linked release'
        linked_release.symlink_to(stored_release, target_is_directory=True)
        self.assertFalse(driver.exact_release(linked_release, record['files']))

        linked_cache_target = self.root/'linked cache target'
        linked_cache_target.mkdir()
        linked_cache = self.root/'linked cache'
        linked_cache.symlink_to(linked_cache_target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'linked owned directory'):
            driver.compile_build(
                self.xls,
                self.bundle,
                output=self.root/'linked cache output',
                cache=linked_cache,
                timeout=10,
            )

        output = self.root/'linked namespace output'
        namespace = self.root/'.linked namespace output-releases'
        outside = self.root/'outside releases'
        outside.mkdir()
        namespace.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'linked owned directory'):
            self.compile(output=output)
        self.assertFalse(output.exists())

        namespace.unlink()
        namespace.mkdir()
        local = namespace/record['release_id']
        local.symlink_to(stored_release, target_is_directory=True)
        repaired = self.compile(output=output)
        self.assertEqual(output.resolve(), repaired)
        self.assertEqual(repaired, local)
        self.assertTrue(local.is_dir())
        self.assertFalse(local.is_symlink())
        damaged = list(namespace.glob(local.name + '.damaged-*'))
        self.assertEqual(len(damaged), 1)
        self.assertTrue(damaged[0].is_symlink())
        self.assertEqual(driver.release_hashes(local), record['files'])
        self.assertEqual(
            json.loads(driver.selection_path(self.cache, plan['request_sha256']).read_text())[
                'implementation_sha256'
            ],
            implementation,
        )

    def test_cross_linked_selection_preserves_other_request_and_reselects(self) -> None:
        """A selector cannot borrow another request's implementation or damage its valid store entry."""
        original_metadata = json.loads(json.dumps(self.manifest['metadata']))
        first_plan = driver.plan_build(self.xls, self.bundle)
        first = self.compile()
        first_implementation = json.loads(
            (first/'compiled.json').read_text()
        )['implementation']['sha256']

        self.manifest['metadata']['hardware_profile']['options']['storage'] = 'shared'
        self.freeze()
        second = self.compile(output=self.root/'second request')
        second_implementation = json.loads(
            (second/'compiled.json').read_text()
        )['implementation']['sha256']
        second_entry = driver.implementation_path(self.cache, second_implementation)
        second_hashes = driver.release_hashes(second_entry/'release')

        self.manifest['metadata'] = original_metadata
        self.freeze()
        restored = driver.plan_build(self.xls, self.bundle)
        self.assertEqual(restored['request_sha256'], first_plan['request_sha256'])
        selection = driver.selection_path(self.cache, first_plan['request_sha256'])
        value = json.loads(selection.read_text())
        value['implementation_sha256'] = second_implementation
        selection.write_text(json.dumps(value) + '\n')

        count = len(self.invocations())
        repaired = self.compile(output=self.root/'cross link repaired')
        self.assertEqual(len(self.invocations()), count)
        self.assertEqual(
            json.loads((repaired/'compiled.json').read_text())['implementation']['sha256'],
            first_implementation,
        )
        self.assertEqual(
            json.loads(selection.read_text())['implementation_sha256'], first_implementation
        )
        self.assertEqual(
            len(list(selection.parent.glob(selection.name + '.damaged-*'))), 1
        )
        self.assertEqual(driver.release_hashes(second_entry/'release'), second_hashes)
        self.assertEqual(
            list(second_entry.parent.glob(second_entry.name + '.damaged-*')), []
        )

    def test_corrupt_implementation_is_quarantined_and_rebuilt(self) -> None:
        """A changed store file cannot be reused and remains quarantined beside a clean rebuild."""
        first = self.compile()
        compiled = json.loads((first/'compiled.json').read_text())
        implementation = compiled['implementation']['sha256']
        entry = driver.implementation_path(self.cache, implementation)
        product = entry/'release/role0/core/design.v'
        product.write_text('corrupt cached implementation\n')
        for stage in ('ir', 'opt', 'codegen'):
            shutil.rmtree(self.cache/stage)
        count = len(self.invocations())
        rebuilt = self.compile(output=self.root/'rebuilt output')
        self.assertEqual(len(self.invocations()) - count, 6)
        self.assertEqual((rebuilt/'role0/core/design.v').read_bytes(),
                         (first/'role0/core/design.v').read_bytes())
        damaged = list(entry.parent.glob(entry.name + '.damaged-*'))
        self.assertEqual(len(damaged), 1)
        self.assertEqual((damaged[0]/'release/role0/core/design.v').read_text(),
                         'corrupt cached implementation\n')
        self.assertNotEqual((entry/'release/role0/core/design.v').read_text(),
                            'corrupt cached implementation\n')

    def test_warm_hit_revalidates_current_tools_before_selection(self) -> None:
        """Tool drift after lookup cannot publish an otherwise valid stored implementation."""
        self.compile()
        original = driver.checked_implementation
        changed = False

        def change_tool(*args: Any, **kwargs: Any) -> Any:
            """Change one selected executable after store validation to exercise the final check."""
            nonlocal changed
            result = original(*args, **kwargs)
            if not changed:
                changed = True
                tool = self.xls/'opt_main'
                tool.write_text(tool.read_text() + '\n# changed after selection\n')
                tool.chmod(0o755)
            return result

        output = self.root/'drifted warm output'
        with patch.object(driver, 'checked_implementation', side_effect=change_tool), \
             patch.object(driver.executor(), 'execute',
                          side_effect=AssertionError('warm hit entered the stage executor')):
            with self.assertRaisesRegex(ValueError, 'changed before implementation reuse'):
                self.compile(output=output)
        self.assertFalse(output.exists())
        report = json.loads((self.root/'drifted warm output.run.json').read_text())
        self.assertEqual(report['status'], 'failed')

    def test_concurrent_request_has_one_external_first_writer(self) -> None:
        """Concurrent outputs serialize request selection and only the first runs external tools."""
        outputs = [self.root/'concurrent a', self.root/'concurrent b']
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(self.compile, output=output) for output in outputs]
            releases = [future.result(timeout=20) for future in futures]
        self.assertEqual(len(self.invocations()), 6)
        for output, release in zip(outputs, releases, strict=True):
            self.assertEqual(output.resolve(), release)
            self.assertEqual(release.parent, self.root/f'.{output.name}-releases')
        reports = [json.loads((output.parent/(output.name + '.run.json')).read_text())
                   for output in outputs]
        self.assertEqual(sum(report.get('implementation_reused', False) for report in reports), 1)
        selections = list((self.cache/'source-build/requests').glob('*.json'))
        implementations = [path for path in (self.cache/'source-build/implementations').iterdir()
                           if path.is_dir() and '.damaged-' not in path.name]
        self.assertEqual(len(selections), 1)
        self.assertEqual(len(implementations), 1)

    def test_plan_provenance_requires_exact_lowercase_sha256_identities(self) -> None:
        """Plan correlation is closed and exact before an external tool or cache path is touched."""
        valid = {'kind': 'implementation_plan', 'logical_system_sha256': '1' * 64,
                 'implementation_plan_sha256': 'a' * 64, 'target_projection_sha256': 'f' * 64}
        self.manifest['provenance'] = valid
        self.freeze()
        self.assertEqual(driver.plan_build(self.xls, self.bundle)['provenance'], valid)
        invalid = [None, {}, {'kind': 'unplanned', 'extra': 'x'}, valid | {'extra': 'x'},
                   valid | {'implementation_plan_sha256': 'A' * 64},
                   valid | {'logical_system_sha256': '1' * 63}]
        for value in invalid:
            with self.subTest(provenance=value):
                self.manifest['provenance'] = value
                self.freeze()
                with patch('subprocess.Popen', side_effect=AssertionError('bad provenance ran a tool')):
                    with self.assertRaisesRegex(ValueError, 'source build provenance'):
                        driver.plan_build(self.xls, self.bundle)
                self.assertFalse(self.output.exists())

    def test_linked_standard_library_is_snapshotted(self) -> None:
        """Preserve valid imports through linked library subdirectories in the isolated source tree."""
        stdlib = self.xls/'xls/dslx/stdlib'
        (stdlib/'numbers').mkdir()
        (stdlib/'numbers/value.x').write_text('pub const VALUE = u32:19;\n')
        (stdlib/'alias').symlink_to(stdlib/'numbers', target_is_directory=True)
        main = self.bundle/'role0/core/main.x'
        main.write_text('import alias.value;\n' + main.read_text())
        self.freeze()
        planned = driver.plan_build(self.xls, self.bundle)
        self.assertIn('alias/value.x', {row['file'] for row in planned['stdlib_inputs']})
        release = self.compile()
        self.assertEqual((release/'_stdlib/alias/value.x').read_bytes(), (stdlib/'numbers/value.x').read_bytes())
        inputs = json.loads((release/'role0/core/raw.ir').read_text())['inputs']
        self.assertIn('_stdlib/alias/value.x', inputs)


if __name__ == '__main__':
    unittest.main()
