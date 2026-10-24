"""Check profile-specific RAM settings and publication metadata using compiler stubs."""
from compiler_paths import PUBLIC
from backend_paths import ROOT
import json
import shutil
import subprocess
import unittest
import compile_xls as compiler
from test_compile_xls import BuildFixture

class ProfileBuilds(BuildFixture):
    """Keep profile input validation coupled to the generated RAM interface."""
    def test_profile_wrapper_publishes_metadata_ram_configuration_and_assets(self):
        (self.inputs / 'phi_decoder_profile_topology.x').write_text('const WIDTH = u16:3;\nconst HEIGHT = u16:3;\nproc Phi_xReductionPlane {}\nproc Phi_zReductionPlane {}\n' + ''.join(f'proc SchedulerRouter{i} {{}}\n' for i in range(8)))
        (self.inputs / 'phi_decoder_profile.json').write_text(json.dumps(dict(width=3, height=3, planes=['x', 'z'], shards_per_plane=3, scheduler_count=8, source_scheduler_count=2, phi_actor_count=18, source_actor_count=18)))
        shutil.copyfile(ROOT / 'tools/phi_scheduler_rams.sh', self.inputs / 'phi_scheduler_rams.sh')
        for asset in ('hls_1r1w_ram.v', 'phi_decoder_profile_top.v'):
            (self.inputs / asset).write_text('// ' + asset)
        # Exercise the helpers as copied into a prepared stage, from another cwd.
        for helper in ('compile_xls.py', 'compile_phi_decoder_profile.py', 'compile_phi_decoder_profile.sh'):
            shutil.copyfile((PUBLIC if helper == 'compile_xls.py' else ROOT) / 'tools' / helper, self.inputs / helper)
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
        config_path = self.inputs / 'phi_decoder_profile.json'
        valid_config = json.loads(config_path.read_text())
        for changes in ({'width': 2}, {'planes': ['x']}, {'scheduler_count': 7}, {'shards_per_plane': 2}, {'phi_actor_count': 1}):
            config_path.write_text(json.dumps({**valid_config, **changes}))
            rejected = subprocess.run(command, cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual((self.inputs / 'compiled').resolve(), release)


if __name__ == '__main__':
    unittest.main()
