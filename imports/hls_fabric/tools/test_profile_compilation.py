"""Check emitted profile inputs and publication metadata using compiler stubs."""
from compiler_paths import PUBLIC
from backend_paths import ROOT
import json
from pathlib import Path
import shutil
import subprocess
import unittest
import compile_xls as compiler
from test_compile_xls import BuildFixture


class ProfileBuilds(BuildFixture):
    """Keep external compilation bound to the profile emitted by Erlang."""

    def setUp(self) -> None:
        """Prepare opaque DSLX and independently emitted profile/RAM metadata."""
        super().setUp()
        self.topology = 'phi_decoder_profile_topology.x'
        self.wrapper = 'phi_decoder_profile_top.v'
        self.config_name = 'phi_decoder_profile.json'
        self.manifest_path = self.inputs / 'phi_decoder_profile.inputs.json'
        # Geometry, plane names and scheduler declarations are deliberately absent.
        (self.inputs / self.topology).write_text('import actor;\nproc Top {}\n')
        (self.inputs / 'actor.x').write_text('pub const VALUE = u32:7;\n')
        self.config = dict(width=3, height=3, planes=['x', 'z'], shards_per_plane=3,
                           scheduler_count=8, source_scheduler_count=2,
                           phi_actor_count=18, source_actor_count=18)
        (self.inputs / self.config_name).write_text(json.dumps(self.config))
        for asset in ('hls_1r1w_ram.v', self.wrapper):
            (self.inputs / asset).write_text('// ' + asset)
        self.ram = 'profile_bank:1R1W:request:response:completion'
        self.recipe = '0123456789abcdef' * 4
        self.input_manifest = dict(version=1, ram_configurations=self.ram,
            ram_configuration=self.recipe,
            inputs={name: compiler.sha(self.inputs / name) for name in
                    (self.topology, self.wrapper, self.config_name, 'actor.x')})
        self.manifest_path.write_text(json.dumps(self.input_manifest))
        # Prepared stages retain standalone helpers and may run from any cwd.
        for helper in ('compile_xls.py', 'compile_phi_decoder_profile.py',
                       'compile_phi_decoder_profile.sh'):
            source = (PUBLIC if helper == 'compile_xls.py' else ROOT) / 'tools' / helper
            shutil.copyfile(source, self.inputs / helper)
        self.command = ['bash', str(self.inputs / 'compile_phi_decoder_profile.sh'),
                        str(self.inputs), str(self.xls)]

    def run_profile(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        """Run only isolated compiler stubs and retain diagnostics on assertion failure."""
        return subprocess.run([*self.command, *arguments], cwd=self.root,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def publish(self, *arguments: str) -> Path:
        """Require a successful compiler run and return its immutable release."""
        result = self.run_profile(*arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        return (self.inputs / 'compiled').resolve()

    def reject(self, release: Path, *arguments: str) -> None:
        """Reject changed inputs before tool execution while retaining the old release."""
        calls = self.calls.read_text()
        result = self.run_profile(*arguments)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.inputs / 'compiled').resolve(), release)
        self.assertEqual(self.calls.read_text(), calls)

    def test_profile_metadata_ram_configuration_and_cache(self) -> None:
        """Trust emitted metadata without rediscovering DSLX geometry or RAM ports."""
        options = ('7200', '3', '4', '2', '--delay-model', 'test-model')
        release = self.publish(*options)
        manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
        self.assertEqual(manifest['profile'], {**self.config, 'pipeline_stages': 4,
                         'initiation_interval': 2, 'delay_model': 'test-model',
                         'flop_inputs': False, 'flop_outputs': True})
        self.assertEqual(manifest['ram_configuration'], self.recipe)
        codegen = manifest['options']['codegen']
        self.assertIn('--worst_case_throughput=2', codegen)
        self.assertIn('--pipeline_stages=4', codegen)
        self.assertIn('--delay_model=test-model', codegen)
        self.assertIn('--ram_configurations=' + self.ram, codegen)
        for asset in ('hls_1r1w_ram.v', self.wrapper):
            self.assertEqual(manifest['rtl'][asset], compiler.sha(release / asset))
        self.assertEqual(manifest['assets'][self.manifest_path.name],
                         compiler.sha(self.manifest_path))
        self.assertFalse((release / 'phi_scheduler_rams.sh').exists())
        self.assertEqual(self.publish(*options), release)
        self.assertEqual(self.statuses(self.inputs / 'compiled'),
                         dict(ir=True, opt=True, codegen=True))

    def test_regenerated_actor_retains_recipe_identity_and_invalidates_cache(self) -> None:
        """Rebinding changed actor bytes changes compilation, not the RAM recipe identity."""
        original = self.publish()
        actor = self.inputs / 'actor.x'
        actor.write_text('pub const VALUE = u32:8;\n')
        self.input_manifest['inputs']['actor.x'] = compiler.sha(actor)
        self.manifest_path.write_text(json.dumps(self.input_manifest))
        changed = self.publish()
        self.assertNotEqual(changed, original)
        self.assertEqual(self.statuses(self.inputs / 'compiled'),
                         dict(ir=False, opt=False, codegen=False))
        for release in (original, changed):
            manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
            self.assertEqual(manifest['ram_configuration'], self.recipe)

    def test_bound_input_mutations_retain_release(self) -> None:
        """Check every bound file, including actor modules outside the primary topology."""
        release = self.publish()
        for name in self.input_manifest['inputs']:
            with self.subTest(input=name):
                path = self.inputs / name
                original = path.read_bytes()
                path.write_bytes(original + b'\n')
                try:
                    self.reject(release)
                finally:
                    path.write_bytes(original)

    def test_manifest_is_mandatory_and_rejects_malformed_contracts(self) -> None:
        """Reject absent, incomplete or unsupported input contracts before compiling."""
        release = self.publish()
        original = self.manifest_path.read_bytes()
        self.manifest_path.unlink()
        self.reject(release)
        self.manifest_path.write_bytes(original)
        invalid = [
            {**self.input_manifest, 'version': 2},
            {**self.input_manifest, 'version': True},
            {**self.input_manifest, 'inputs': []},
            {**self.input_manifest, 'ram_configurations': []},
            {key: value for key, value in self.input_manifest.items() if key != 'version'},
            {key: value for key, value in self.input_manifest.items() if key != 'ram_configuration'},
            *[{**self.input_manifest, 'ram_configuration': value} for value in
              (None, 7, '0' * 63, 'g' * 64, self.recipe.upper())],
        ]
        for required in (self.topology, self.wrapper, self.config_name):
            invalid.append({**self.input_manifest, 'inputs': {
                key: value for key, value in self.input_manifest['inputs'].items()
                if key != required}})
        for value in invalid:
            with self.subTest(manifest=value):
                self.manifest_path.write_text(json.dumps(value))
                self.reject(release)
        self.manifest_path.write_bytes(original)

    def test_manifest_rejects_unbound_paths_and_bad_digests(self) -> None:
        """Keep input bindings inside the snapshot and require full lowercase SHA-256."""
        release = self.publish()
        inputs = self.input_manifest['inputs']
        digest = inputs[self.topology]
        invalid = [
            {**inputs, self.topology: '0' * 63},
            {**inputs, self.topology: 'G' * 64},
            {**inputs, self.topology: digest.upper()},
            {**inputs, '../outside.x': digest},
            {**inputs, '/outside.x': digest},
            {**inputs, 'nested/actor.x': inputs['actor.x']},
            {**inputs, 'unknown.json': digest},
        ]
        for bindings in invalid:
            with self.subTest(bindings=bindings):
                self.manifest_path.write_text(json.dumps({**self.input_manifest,
                                                        'inputs': bindings}))
                self.reject(release)

    def test_requested_shards_must_match_emitted_profile(self) -> None:
        """Do not reinterpret a valid emitted topology for a different shard count."""
        release = self.publish()
        self.reject(release, '7200', '2')


if __name__ == '__main__':
    unittest.main()
