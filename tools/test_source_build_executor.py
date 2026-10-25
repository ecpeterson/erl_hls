"""Mock external XLS stages to check multi-unit publication and cache identity, not hardware semantics."""
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
SPEC = importlib.util.spec_from_file_location('source_build_executor', ROOT/'priv/tools/compile_source_build.py')
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
        self.manifest: dict[str, Any] = {'version': 1,
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
        self.assertFalse(compiled['native_measured'])
        self.assertFalse(compiled['eligible'])
        self.assertEqual(compiled['metadata'], self.manifest['metadata'])
        self.assertEqual(compiled['xls_tools'],
                         {name: tool['sha256'] for name, tool in plan['xls_tools'].items()})
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
        """Moving identical emitted bytes preserves stage identities while each publication stays self-contained."""
        first = self.compile()
        relocated = self.root/'relocated source bundle'
        shutil.copytree(self.bundle, relocated)
        count = len(self.invocations())
        second = self.compile(directory=relocated, output=self.root/'relocated output')
        self.assertEqual(len(self.invocations()), count)
        self.assertNotEqual(first, second)
        for relative in ('role0/core/raw.ir', 'role0/core/optimized.ir', 'role0/core/design.v',
                         'role1/core/raw.ir', 'role1/core/optimized.ir', 'role1/core/design.v'):
            self.assertEqual((first/relative).read_bytes(), (second/relative).read_bytes())
        compiled = json.loads((second/'compiled.json').read_text())
        report = json.loads((self.root/'relocated output.run.json').read_text())
        self.assertTrue(all(command['reused'] for command in report['stages'].values()))
        self.assertEqual(compiled['rtl'], json.loads((first/'compiled.json').read_text())['rtl'])
        for role in ('role0', 'role1'):
            listing = second/role/'files.f'
            self.assertTrue(all((listing.parent/line).is_file() for line in listing.read_text().splitlines()))

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
