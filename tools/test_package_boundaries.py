"""Exercise package policy without building applications or invoking external hardware tools."""
from pathlib import Path
import tempfile
import unittest
from erl_hls_tools.package_boundaries import application_files, violations


class PackageBoundariesTests(unittest.TestCase):
    """Direct calls, type-only imports and release membership all enforce the same boundary."""

    def snapshot(self) -> dict:
        """Return independently owned runtime/build modules with no initial crossing."""
        return {'applications': [
            {'name': 'hls_runtime', 'modules': ['codec'], 'dependencies': ['kernel', 'stdlib']},
            {'name': 'erl_hls', 'modules': ['lower'], 'dependencies': ['hls_runtime']}],
            'runtime_modules': [{'module': 'codec', 'application': 'hls_runtime',
                                 'imports': ['lists'], 'types': []}]}

    def test_import_and_remote_type_crossings(self) -> None:
        """A type-only compiler reference must fail even when no executable import exists."""
        for kind in ('imports', 'types'):
            snapshot = self.snapshot()
            snapshot['runtime_modules'][0][kind] = ['lower']
            self.assertEqual(violations(snapshot, {'hls_runtime'}, {'erl_hls'}), [
                {'kind': kind, 'module': 'codec', 'target': 'lower', 'application': 'erl_hls'}])
        self.assertEqual(violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}), [])

    def test_application_dependency(self) -> None:
        """A declared build dependency fails even if currently no code calls it."""
        snapshot = self.snapshot()
        snapshot['applications'][0]['dependencies'].append('erl_hls')
        self.assertEqual(violations(snapshot, {'hls_runtime'}, {'erl_hls'})[0]['kind'],
                         'application_dependency')

    def test_release_cannot_smuggle_build_module_into_runtime_app(self) -> None:
        """Both app manifests and individual BEAM ownership are checked after packaging."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            ebin = release/'lib/hls_runtime-0.1/ebin';ebin.mkdir(parents=True)
            (ebin/'hls_runtime.app').write_text('fixture')
            (ebin/'lower.beam').write_bytes(b'fixture')
            self.assertEqual(violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release), [
                {'kind': 'release_module', 'module': 'lower', 'application': 'erl_hls'}])

    def test_nested_git_application_and_checkout(self) -> None:
        """git_subdir metadata is found, then replaced by an explicit checkout of the same app."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root/'_build/test/lib/hls_runtime/apps/hls_runtime/ebin/hls_runtime.app'
            nested.parent.mkdir(parents=True);nested.write_text('fixture')
            self.assertEqual(application_files(root, 'test'), [nested])
            checkout = root/'_build/test/checkouts/hls_runtime/ebin/hls_runtime.app'
            checkout.parent.mkdir(parents=True);checkout.write_text('fixture')
            self.assertEqual(application_files(root, 'test'), [checkout])


if __name__ == '__main__':
    unittest.main()
