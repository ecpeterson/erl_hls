"""Exercise package policy without building applications or invoking external hardware tools."""
from pathlib import Path
import tempfile
import unittest
from erl_hls_tools.package_boundaries import (
    application_files,
    architecture_violations,
    duplicate_module_ownership,
    policy_violations,
    project_applications,
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

    def release(self, root: Path, applications: list[str],
                manifest: list[str] | None = None) -> None:
        """Write the minimal generated layout needed by the release-content audit."""
        modules = {'hls_runtime': ['codec'], 'erl_hls': ['lower'],
                   'new_builder': ['new_lower']}
        for application in applications:
            ebin = root/f'lib/{application}-0.1/ebin'
            ebin.mkdir(parents=True)
            (ebin/f'{application}.app').write_text('fixture')
            for module in modules.get(application, []):
                (ebin/f'{module}.beam').write_bytes(b'fixture')
        release = root/'releases/0.1/fixture.rel'
        release.parent.mkdir(parents=True)
        names = applications if manifest is None else manifest
        entries = ','.join(f'{{{name},"0.1"}}' for name in names)
        release.write_text(f'{{release,{{"fixture","0.1"}},{{erts,"1"}},[{entries}]}}.\n')

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

    def test_duplicate_module_ownership(self) -> None:
        """A stale application cannot silently replace the owner used by edge checks."""
        snapshot = self.snapshot()
        snapshot['applications'][1]['modules'].append('codec')
        self.assertEqual(duplicate_module_ownership(snapshot), [
            {'kind': 'duplicate_module_ownership', 'module': 'codec',
             'applications': ['erl_hls', 'hls_runtime']}])

    def test_project_applications_include_workloads(self) -> None:
        """Package policy owns descriptors in both architectural and workload roots."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative, name in (("apps/core/src", "core"),
                                   ("workloads/example/src", "example")):
                directory = root / relative
                directory.mkdir(parents=True)
                (directory / f"{name}.app.src").write_text("fixture")
            self.assertEqual(project_applications(root), {"core", "example"})

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

    def test_synthesis_layers_cannot_depend_on_optimizer_or_facade(self) -> None:
        """Compile, communication and target layers keep the Stage 3 graph acyclic."""
        snapshot = {'applications': [
            {'name': 'hls_compile', 'modules': ['lower'], 'dependencies': ['hls_core']},
            {'name': 'hls_fabric', 'modules': ['route'], 'dependencies': ['hls_compile']},
            {'name': 'hls_target', 'modules': ['emit'], 'dependencies': ['hls_fabric']},
            {'name': 'hls_spacetime', 'modules': ['plan'], 'dependencies': ['hls_core']}],
            'runtime_modules': [
                {'module': 'lower', 'application': 'hls_compile', 'imports': [], 'types': []},
                {'module': 'route', 'application': 'hls_fabric', 'imports': ['lower'], 'types': []},
                {'module': 'emit', 'application': 'hls_target', 'imports': ['route'], 'types': []},
                {'module': 'plan', 'application': 'hls_spacetime', 'imports': [], 'types': []}]}
        self.assertEqual(architecture_violations(snapshot), [])
        snapshot['runtime_modules'][2]['types'] = ['plan']
        self.assertEqual(architecture_violations(snapshot), [
            {'kind': 'types', 'module': 'emit', 'target': 'plan',
             'application': 'hls_spacetime'}])

    def test_compiler_runtime_edge_is_limited_to_the_value_provider(self) -> None:
        """Compiler code may load the retained-handle provider but cannot call live services."""
        snapshot = {'applications': [
            {'name': 'hls_compile', 'modules': ['lower', 'xls_provider_gs'],
             'dependencies': ['hls_core', 'hls_runtime']},
            {'name': 'hls_runtime', 'modules': ['hls_gs', 'live_session'],
             'dependencies': ['hls_core']}],
            'runtime_modules': [
                {'module': 'lower', 'application': 'hls_compile',
                 'imports': [], 'calls': [], 'types': []},
                {'module': 'xls_provider_gs', 'application': 'hls_compile',
                 'imports': ['hls_gs'], 'calls': [['hls_gs', 'from', 0]], 'types': []},
                {'module': 'hls_gs', 'application': 'hls_runtime',
                 'imports': [], 'calls': [], 'types': []},
                {'module': 'live_session', 'application': 'hls_runtime',
                 'imports': [], 'calls': [], 'types': []}]}
        self.assertEqual(architecture_violations(snapshot), [])
        snapshot['runtime_modules'][0]['calls'] = [['live_session', 'start_link', 0]]
        self.assertEqual(architecture_violations(snapshot), [
            {'kind': 'compile_runtime_boundary', 'reference': 'call',
             'module': 'lower', 'target': 'live_session',
             'function': 'start_link', 'arity': '0'}])
        snapshot['runtime_modules'][0]['calls'] = []
        snapshot['runtime_modules'][1]['calls'] = [['hls_gs', 'start_link', 2]]
        self.assertEqual(architecture_violations(snapshot), [
            {'kind': 'compile_runtime_boundary', 'reference': 'call',
             'module': 'xls_provider_gs', 'target': 'hls_gs',
             'function': 'start_link', 'arity': '2'}])

    def test_release_cannot_smuggle_build_module_into_runtime_app(self) -> None:
        """Both app manifests and individual BEAM ownership are checked after packaging."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            ebin = release/'lib/hls_runtime-0.1/ebin'
            (ebin/'lower.beam').write_bytes(b'fixture')
            self.assertCountEqual(
                violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release), [
                    {'kind': 'release_module', 'module': 'lower', 'application': 'erl_hls'},
                    {'kind': 'unexpected_release_beam', 'application': 'hls_runtime',
                     'module': 'lower'}])

    def test_release_beams_match_the_application_module_inventory(self) -> None:
        """A foreign or omitted BEAM cannot hide inside an otherwise allowed runtime app."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            ebin = release/'lib/hls_runtime-0.1/ebin'
            (ebin/'codec.beam').unlink()
            (ebin/'orphan.beam').write_bytes(b'fixture')
            self.assertCountEqual(
                violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release), [
                    {'kind': 'unexpected_release_beam', 'application': 'hls_runtime',
                     'module': 'orphan'},
                    {'kind': 'missing_release_beam', 'application': 'hls_runtime',
                     'module': 'codec'}])

    def test_release_project_application_set_is_exact(self) -> None:
        """A future project application cannot bypass an outdated forbidden-app list."""
        snapshot = self.snapshot()
        snapshot['applications'].append(
            {'name': 'new_builder', 'modules': ['new_lower'], 'dependencies': []})
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime', 'new_builder'])
            self.assertEqual(violations(snapshot, {'hls_runtime'}, {'erl_hls'}, release)[-2:], [
                {'kind': 'unexpected_release_application', 'application': 'new_builder'},
                {'kind': 'unexpected_release_manifest_application',
                 'application': 'new_builder'}])

    def test_release_rejects_source_assets_and_build_launchers(self) -> None:
        """Runtime applications retain interfaces but never source templates or build entry points."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            source = release/'lib/hls_runtime-0.1/src/template.x'
            source.parent.mkdir()
            source.write_text('fixture')
            launcher = release/'bin/hlsc'
            launcher.parent.mkdir()
            launcher.write_text('fixture')
            overlay = release/'build.config'
            overlay.write_text('fixture')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_overlay_asset', 'path': 'build.config'}, errors)
            self.assertIn({'kind': 'release_project_asset', 'application': 'hls_runtime',
                           'path': 'lib/hls_runtime-0.1/src'}, errors)
            self.assertIn({'kind': 'release_forbidden_asset',
                           'path': 'lib/hls_runtime-0.1/src/template.x'}, errors)
            self.assertIn({'kind': 'release_build_launcher', 'path': 'bin/hlsc'}, errors)

    def test_release_rejects_orphan_library_root(self) -> None:
        """A library root cannot evade the manifest audit by omitting its application file."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            native = release/'lib/orphan-0.1/priv/orphan.so'
            native.parent.mkdir(parents=True)
            native.write_bytes(b'fixture')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_library_application_count',
                           'path': 'lib/orphan-0.1', 'count': '0'}, errors)
            self.assertNotIn({'kind': 'release_forbidden_asset',
                              'path': 'lib/orphan-0.1/priv/orphan.so'}, errors)

    def test_release_library_name_matches_its_application(self) -> None:
        """A manifest cannot be hidden under a differently named release library root."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            (release/'lib/hls_runtime-0.1').rename(release/'lib/disguised-0.1')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_library_application_name',
                           'path': 'lib/disguised-0.1',
                           'application': 'hls_runtime'}, errors)

    def test_release_rejects_duplicate_application_libraries(self) -> None:
        """Two version roots for one application cannot collapse into one manifest-set entry."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'])
            ebin = release/'lib/hls_runtime-0.2/ebin'
            ebin.mkdir(parents=True)
            (ebin/'hls_runtime.app').write_text('fixture')
            (ebin/'codec.beam').write_bytes(b'fixture')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_application_library_count',
                           'application': 'hls_runtime', 'count': '2'}, errors)

    def test_release_rejects_library_symlinks(self) -> None:
        """A dependency cannot hide external files or directories behind release symlinks."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime', 'kernel'])
            priv = release/'lib/kernel-0.1/priv'
            priv.mkdir()
            (priv/'external').symlink_to(release.parent, target_is_directory=True)
            (priv/'native.so').symlink_to('/dev/null')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_library_symlink',
                           'path': 'lib/kernel-0.1/priv/external'}, errors)
            self.assertIn({'kind': 'release_library_symlink',
                           'path': 'lib/kernel-0.1/priv/native.so'}, errors)

    def test_release_rejects_top_level_symlinks(self) -> None:
        """The release control directories cannot redirect the audit outside the package."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)/'release'
            release.mkdir()
            self.release(release, ['hls_runtime'])
            external = Path(temporary)/'external-bin'
            external.mkdir()
            (release/'bin').symlink_to(external, target_is_directory=True)
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_root_entry', 'path': 'bin'}, errors)
            self.assertIn({'kind': 'release_symlink', 'path': 'bin'}, errors)

    def test_release_rejects_control_tree_assets_and_symlinks(self) -> None:
        """Release metadata and allowed bin names cannot hide source or external targets."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)/'release'
            release.mkdir()
            self.release(release, ['hls_runtime'])
            hidden = release/'releases/0.1/build.py'
            hidden.write_text('fixture')
            target = Path(temporary)/'external-nodetool'
            target.write_text('fixture')
            binary = release/'bin'
            binary.mkdir()
            (binary/'nodetool').symlink_to(target)
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_forbidden_asset',
                           'path': 'releases/0.1/build.py'}, errors)
            self.assertIn({'kind': 'release_symlink', 'path': 'bin/nodetool'}, errors)

    def test_release_scans_dependency_libraries_for_build_assets(self) -> None:
        """Target sources and build launchers cannot hide inside an OTP dependency's priv tree."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime', 'kernel'])
            priv = release/'lib/kernel-0.1/priv'
            priv.mkdir()
            (priv/'template.x').write_text('fixture')
            (priv/'hlsc').write_text('fixture')
            (priv/'kernel_helper.so').write_bytes(b'fixture')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_forbidden_asset',
                           'path': 'lib/kernel-0.1/priv/template.x'}, errors)
            self.assertIn({'kind': 'release_forbidden_asset',
                           'path': 'lib/kernel-0.1/priv/hlsc'}, errors)
            self.assertNotIn({'kind': 'release_forbidden_asset',
                              'path': 'lib/kernel-0.1/priv/kernel_helper.so'}, errors)

    def test_release_rejects_dependency_source_directories(self) -> None:
        """An unrecognized source tree cannot hide files with otherwise innocuous suffixes."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime', 'kernel'])
            source = release/'lib/kernel-0.1/src/README.txt'
            source.parent.mkdir()
            source.write_text('fixture')
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'release_library_asset',
                           'path': 'lib/kernel-0.1/src'}, errors)

    def test_release_manifest_must_match_packaged_libraries(self) -> None:
        """The boot manifest and copied application directories describe the same closure."""
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            self.release(release, ['hls_runtime'], ['erl_hls'])
            errors = violations(self.snapshot(), {'hls_runtime'}, {'erl_hls'}, release)
            self.assertIn({'kind': 'unlisted_release_application',
                           'application': 'hls_runtime'}, errors)
            self.assertIn({'kind': 'missing_release_library', 'application': 'erl_hls'}, errors)
            self.assertIn({'kind': 'missing_release_manifest_application',
                           'application': 'hls_runtime'}, errors)

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
