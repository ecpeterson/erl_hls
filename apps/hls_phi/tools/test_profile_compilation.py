"""Check emitted profile inputs and publication metadata using compiler stubs."""
import phi_tool_paths  # Resolve shared tooling for this application.
from compiler_paths import compiler_root, compiler_source, compiler_tool
from backend_paths import ROOT
from compile_phi_decoder_profile import BUILD_PROFILE
import json
from pathlib import Path
import shutil
import subprocess
import unittest
compiler = compiler_tool(compiler_root("test"), "compile_xls")
BuildFixture = compiler_tool(compiler_root("test"), "testing").BuildFixture


def policy(stages: int = 2, interval: int = 1, model: str = "unit") -> dict:
    """Represent a retained emitter result; CLI/EUnit tests qualify its Erlang producer separately."""
    return {"version": 1, "profile": {
        "backend": "channel_scheduler", "placement": "prepared_source",
        "frame_abi": {"name": "canonical_actor_v1", "header_bits": 32,
                      "payload_bits": 96, "frame_bits": 128, "payload_words": 3,
                      "parameterized": False},
        "schedules": {"channel": {"pipeline_stages": stages, "initiation_interval": interval,
            "delay_model": model, "executor_result_delay": 0, "flop_inputs": False,
            "flop_outputs": True, "fifo_module": "none"}},
        "tools": {"provider": "xls", "identity": "external_compilation"},
        "postprocess": {"completion_storage": "registers"}},
        "codegen_flags": [f"--pipeline_stages={stages}", f"--delay_model={model}",
            "--flop_inputs=false", "--flop_outputs=true", "--use_system_verilog=false",
            "--reset=reset", "--fifo_module=", f"--worst_case_throughput={interval}"]}


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
        (self.inputs / BUILD_PROFILE).write_text(json.dumps(policy()))
        self.ram = 'profile_bank:1R1W:request:response:completion'
        self.recipe = '0123456789abcdef' * 4
        self.input_manifest = dict(version=1, ram_configurations=self.ram,
            ram_configuration=self.recipe,
            inputs={name: compiler.sha(self.inputs / name) for name in
                    (self.topology, self.wrapper, self.config_name, BUILD_PROFILE, 'actor.x')})
        self.manifest_path.write_text(json.dumps(self.input_manifest))
        # Prepared stages retain standalone helpers and may run from any cwd.
        for helper in ('compile_xls.py', 'compile_phi_decoder_profile.py',
                       'compile_phi_decoder_profile.sh', 'backend_build_profile.py', 'phi_tool_paths.py'):
            source = (compiler_source(compiler_root('test'), 'compile_xls') if helper == 'compile_xls.py'
                      else ROOT / 'tools/hls_fabric' / helper if helper == 'backend_build_profile.py' else Path(__file__).with_name(helper))
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
        selected = self.root / 'selected-build-profile.json'
        selected.write_text(json.dumps(policy(4, 2, 'test-model')))
        options = ('--timeout', '7200', '--build-profile', str(selected))
        release = self.publish(*options)
        manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
        self.assertEqual(manifest['profile'], self.config)
        self.assertEqual(manifest['build_profile'], policy(4, 2, 'test-model'))
        self.assertEqual(manifest['assets'][selected.name], compiler.sha(selected))
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
        self.assertFalse((release / 'scheduler_ram_configurations.sh').exists())
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
        for required in (self.topology, self.wrapper, self.config_name, BUILD_PROFILE):
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

    def test_schedule_is_not_reconstructed_by_the_external_adapter(self) -> None:
        """A literal extra flag survives, while removed schedule CLI arguments are rejected."""
        selected = self.root / 'selected-build-profile.json'
        value = policy()
        value['codegen_flags'].append('--test_emitted_policy=preserved')
        selected.write_text(json.dumps(value))
        release = self.publish('--build-profile', str(selected))
        manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
        self.assertIn('--test_emitted_policy=preserved', manifest['options']['codegen'])
        self.assertEqual(manifest['build_profile'], value)
        self.reject(release, '--pipeline-stages', '3')

    def test_selected_policy_is_required_and_checked_before_tools(self) -> None:
        """Invalid or unsupported selected policies cannot change the chosen release."""
        release = self.publish()
        selected = self.root / 'selected-build-profile.json'
        self.reject(release, '--build-profile', str(selected))
        value = policy()
        value['profile']['postprocess']['completion_storage'] = 'lutram'
        selected.write_text(json.dumps(value))
        self.reject(release, '--build-profile', str(selected))
        selected.write_text('{}')
        self.reject(release, '--build-profile', str(selected))
        collision = self.root / BUILD_PROFILE
        collision.write_text(json.dumps(policy()))
        self.reject(release, '--build-profile', str(collision))

    def test_delay_table_follows_the_selected_emitted_model(self) -> None:
        """Freeze custom timing input without introducing a parallel schedule selector."""
        selected = self.root / 'selected-build-profile.json'
        selected.write_text(json.dumps(policy(model='xc7_7030')))
        table = self.root / 'delay.tsv'
        table.write_text('op\tdelay\nadd\t1\n')
        release = self.publish('--build-profile', str(selected), '--delay-table', str(table))
        manifest = json.loads((release / 'phi_decoder_profile.build.json').read_text())
        self.assertIn('--xc7_delay_table=assets/xc7_delay_table.tsv', manifest['options']['codegen'])
        self.assertEqual(manifest['assets']['xc7_delay_table.tsv'], compiler.sha(table))
        self.reject(release, '--build-profile', str(selected))


if __name__ == '__main__':
    unittest.main()
