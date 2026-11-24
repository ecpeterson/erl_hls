"""Exercise package policy without building applications or invoking external hardware tools."""
from pathlib import Path
import tempfile
import unittest
from erl_hls_tools.package_boundaries import (
    application_files,
    policy_violations,
    undeclared_application_dependencies,
    violations,
)


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

    def test_undeclared_project_imports_and_remote_types(self) -> None:
        """Every direct project-app import or remote type requires a manifest dependency."""
        for reference in ('imports', 'types'):
            snapshot = self.snapshot()
            snapshot['runtime_modules'][0][reference] = ['lower']
            self.assertEqual(
                undeclared_application_dependencies(snapshot, {'hls_runtime', 'erl_hls'}),
                [{'kind': 'undeclared_application_dependency', 'reference': reference,
                  'application': 'hls_runtime', 'module': 'codec', 'target': 'erl_hls',
                  'target_module': 'lower'}])
            snapshot['applications'][0]['dependencies'].append('erl_hls')
            self.assertEqual(
                undeclared_application_dependencies(snapshot, {'hls_runtime', 'erl_hls'}), [])

    def test_forbidden_scan_ignores_unrequested_callers(self) -> None:
        """A broad snapshot does not apply one package's reverse-edge rule to another package."""
        snapshot = self.snapshot()
        snapshot['runtime_modules'].append(
            {'module': 'lower', 'application': 'erl_hls', 'imports': ['lower'], 'types': []})
        self.assertEqual(violations(snapshot, {'hls_runtime'}, {'erl_hls'}), [])

    def test_core_forbids_every_project_app_without_reclassifying_other_callers(self) -> None:
        """Core cannot import another inspected app, while that app may call its own modules."""
        snapshot = {'applications': [
            {'name': 'hls_core', 'modules': ['core_codec'],
             'dependencies': ['kernel', 'stdlib']},
            {'name': 'hls_runtime', 'modules': ['runtime_codec'],
             'dependencies': ['kernel', 'stdlib', 'hls_core']}],
            'runtime_modules': [
                {'module': 'core_codec', 'application': 'hls_core',
                 'imports': ['runtime_codec'], 'types': []},
                {'module': 'runtime_codec', 'application': 'hls_runtime',
                 'imports': ['runtime_codec'], 'types': []}]}
        self.assertEqual(
            policy_violations(snapshot, {'hls_core', 'hls_runtime'}, {'erl_hls'}),
            [{'kind': 'imports', 'module': 'core_codec', 'target': 'runtime_codec',
              'application': 'hls_runtime'}])
        snapshot['runtime_modules'][0]['imports'] = []
        snapshot['applications'][0]['dependencies'].append('hls_runtime')
        self.assertEqual(
            policy_violations(snapshot, {'hls_core', 'hls_runtime'}, {'erl_hls'})[0],
            {'kind': 'application_dependency', 'application': 'hls_core',
             'target': 'hls_runtime'})

    def test_observer_declares_dynamic_resource_owners(self) -> None:
        """The observer declares core, runtime and compiler owners used by computed paths."""
        manifest = (Path(__file__).resolve().parents[1] /
                    'apps/hls_spacetime_observer/src/hls_spacetime_observer.app.src').read_text()
        dependency_text = manifest.split('{applications, [', 1)[1].split(']}', 1)[0]
        dependencies = {name.strip() for name in dependency_text.split(',')}
        self.assertTrue({'erl_hls', 'hls_core', 'hls_runtime'} <= dependencies)

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
