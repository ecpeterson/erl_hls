"""Check compiled OTP package ownership, including type-only edges and deployed release contents."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ARCHITECTURE_FORBIDDEN = {
    'hls_compile': {'erl_hls', 'hls_fabric', 'hls_target', 'hls_spacetime',
                    'hls_spacetime_observer'},
    'hls_fabric': {'erl_hls', 'hls_target', 'hls_spacetime', 'hls_spacetime_observer'},
    'hls_target': {'erl_hls', 'hls_spacetime', 'hls_spacetime_observer'},
}

# hls_gs retains the public callback/type-provider identity. Compilation may call only its
# process-free retained-handle descriptor; every live runtime entry point remains forbidden.
COMPILE_RUNTIME_ALLOWED_CALLS = {('xls_provider_gs', 'hls_gs', 'from', 0)}

RUNTIME_PROJECT_DIRECTORIES = {'ebin', 'include'}
RUNTIME_PROJECT_SUFFIXES = {
    'ebin': {'.app', '.appup', '.beam'},
    'include': {'.hrl', '.md'},
}
RUNTIME_LIBRARY_DIRECTORIES = {'ebin', 'include', 'priv'}
RUNTIME_RELEASE_DIRECTORIES = {'bin', 'lib', 'releases'}
BUILD_LAUNCHERS = {
    'compile-source-build', 'compile_xls.py', 'hls-fabric', 'hls-repetition', 'hlsc'
}
RUNTIME_FORBIDDEN_SUFFIXES = {
    '.bash', '.c', '.cc', '.cmake', '.cpp', '.erl', '.escript', '.ex', '.exs', '.h',
    '.hpp', '.ir', '.m', '.mk', '.mm', '.py', '.sh', '.sv', '.tcl', '.v', '.vhd',
    '.vhdl', '.x', '.xdc', '.zsh',
}
RELEASE_APPLICATION = re.compile(r'\{\s*([a-z][a-zA-Z0-9_@]*),\s*"[^"]+"(?:\s*,[^{}]*)?\}')

# Inspect inert BEAM tables; no application or project module is started or called.
ERLANG_AUDIT = r'''
[Request] = init:get_plain_arguments(),
{ok, Bytes} = file:read_file(Request), #{<<"applications">> := Paths, <<"runtime">> := Runtime} = json:decode(Bytes),
ReadApp = fun(Path) ->
    {ok, [{application, Name, Props}]} = file:consult(unicode:characters_to_list(Path)),
    #{name => Name, file => Path, modules => proplists:get_value(modules, Props, []),
      dependencies => proplists:get_value(applications, Props, [])}
end,
Compiler = filename:join([code:lib_dir(compiler), "ebin", "compiler.app"]),
Apps = [ReadApp(P) || P <- Paths] ++ [ReadApp(unicode:characters_to_binary(Compiler))],
Remote = fun Walk({remote_type, _, [{atom, _, Module} | Rest]}) -> [Module | Walk(Rest)];
             Walk(Tuple) when is_tuple(Tuple) -> Walk(tuple_to_list(Tuple));
             Walk(List) when is_list(List) -> lists:append([Walk(Item) || Item <- List]);
             Walk(_) -> []
         end,
Inspect = fun(Module, App) ->
    Beam = filename:join(filename:dirname(maps:get(file, App)), atom_to_list(Module) ++ ".beam"),
    {ok, {Module, [{imports, Imports}, {abstract_code, {raw_abstract_v1, Forms}}]}} =
        beam_lib:chunks(unicode:characters_to_list(Beam), [imports, abstract_code]),
    #{module => Module, application => maps:get(name, App),
      imports => lists:usort([M || {M, _, _} <- Imports]),
      calls => lists:usort([[M, F, A] || {M, F, A} <- Imports]),
      types => lists:usort(Remote(Forms))}
end,
Modules = [Inspect(M, App) || App <- Apps,
    lists:member(atom_to_binary(maps:get(name, App)), Runtime), M <- maps:get(modules, App)],
io:put_chars(json:encode(#{applications => Apps, runtime_modules => Modules})), halt().
'''


def application_files(root: Path, profile: str) -> list[Path]:
    """Select built application metadata, with Git subdirectories and checkout precedence."""
    applications: dict[str, Path] = {}
    for kind in ('lib', 'checkouts'):
        for dependency in sorted((root/'_build'/profile/kind).glob('*')):
            candidates = [dependency/'ebin', *sorted(dependency.glob('apps/*/ebin'))]
            for directory in candidates:
                for path in sorted(directory.glob('*.app')):
                    applications[path.stem] = path
    return list(applications.values())


def project_applications(root: Path) -> set[str]:
    """Return OTP application names owned by this umbrella, excluding fetched dependencies."""
    suffix = '.app.src'
    paths = [
        path
        for application_root in ('apps', 'workloads')
        for path in (root/application_root).glob('*/src/*.app.src')
    ]
    return {path.name[:-len(suffix)] for path in paths}


def undeclared_application_dependencies(snapshot: dict,
                                        applications: set[str]) -> list[dict[str, str]]:
    """Reject direct project imports and remote types absent from the caller's app manifest."""
    owners = {module: app['name'] for app in snapshot['applications'] for module in app['modules']}
    declared = {app['name']: set(app['dependencies']) for app in snapshot['applications']}
    errors: list[dict[str, str]] = []
    for module in snapshot['runtime_modules']:
        application = module['application']
        if application not in applications:
            continue
        for reference in ('imports', 'types'):
            for target_module in module[reference]:
                target = owners.get(target_module)
                if (target in applications and target != application and
                        target not in declared.get(application, set())):
                    errors.append(dict(kind='undeclared_application_dependency',
                                       reference=reference, application=application,
                                       module=module['module'], target=target,
                                       target_module=target_module))
    return errors


def duplicate_module_ownership(snapshot: dict) -> list[dict[str, str]]:
    """Reject one BEAM module claimed by more than one inspected OTP application."""
    owners: dict[str, set[str]] = {}
    for application in snapshot['applications']:
        for module in application['modules']:
            owners.setdefault(module, set()).add(application['name'])
    return [dict(kind='duplicate_module_ownership', module=module,
                 applications=sorted(applications))
            for module, applications in sorted(owners.items()) if len(applications) > 1]


def release_manifest_applications(path: Path) -> set[str]:
    """Read application names from one generated OTP release manifest."""
    return set(RELEASE_APPLICATION.findall(path.read_text())) - {'erts'}


def runtime_release_violations(snapshot: dict, runtimes: set[str],
                               release: Path) -> list[dict[str, str]]:
    """Require an exact runtime closure and reject build assets in every packaged library."""
    if not release.is_dir():
        return []
    errors: list[dict[str, str]] = []
    project = set(snapshot.get(
        'project_applications', (app['name'] for app in snapshot['applications'])))
    expected_modules = {
        app['name']: set(app['modules']) for app in snapshot['applications']
    }
    library = release/'lib'
    roots = sorted(library.iterdir()) if library.is_dir() else []
    app_files: list[Path] = []
    for root in roots:
        if root.is_symlink() or not root.is_dir():
            errors.append(dict(kind='release_library_root',
                               path=str(root.relative_to(release))))
            continue
        applications = sorted((root/'ebin').glob('*.app'))
        app_files.extend(applications)
        if len(applications) != 1:
            errors.append(dict(kind='release_library_application_count',
                               path=str(root.relative_to(release)),
                               count=str(len(applications))))
        elif not root.name.startswith(applications[0].stem + '-'):
            errors.append(dict(kind='release_library_application_name',
                               path=str(root.relative_to(release)),
                               application=applications[0].stem))
        for entry in sorted(root.iterdir()):
            if (entry.is_symlink() or not entry.is_dir() or
                    entry.name not in RUNTIME_LIBRARY_DIRECTORIES):
                errors.append(dict(kind='release_library_asset',
                                   path=str(entry.relative_to(release))))
        for asset in sorted(root.rglob('*')):
            if asset.is_symlink():
                errors.append(dict(kind='release_library_symlink',
                                   path=str(asset.relative_to(release))))
                continue
            if asset.is_dir():
                continue
            if (asset.name in BUILD_LAUNCHERS or
                    asset.suffix.lower() in RUNTIME_FORBIDDEN_SUFFIXES):
                errors.append(dict(kind='release_forbidden_asset',
                                   path=str(asset.relative_to(release))))
    application_copies: dict[str, int] = {}
    for app_file in app_files:
        application_copies[app_file.stem] = application_copies.get(app_file.stem, 0) + 1
    for application, count in sorted(application_copies.items()):
        if count != 1:
            errors.append(dict(kind='release_application_library_count',
                               application=application, count=str(count)))
    released = {path.stem for path in app_files}
    for entry in sorted(release.iterdir()):
        if entry.name not in RUNTIME_RELEASE_DIRECTORIES:
            errors.append(dict(kind='release_overlay_asset', path=entry.name))
        elif entry.is_symlink() or not entry.is_dir():
            errors.append(dict(kind='release_root_entry', path=entry.name))
    for asset in sorted(release.rglob('*')):
        relative = asset.relative_to(release)
        if asset.is_symlink():
            errors.append(dict(kind='release_symlink', path=str(relative)))
        elif (not asset.is_dir() and relative.parts[0] not in {'bin', 'lib'} and
              (asset.name in BUILD_LAUNCHERS or
               asset.suffix.lower() in RUNTIME_FORBIDDEN_SUFFIXES)):
            errors.append(dict(kind='release_forbidden_asset', path=str(relative)))
    for name in sorted((released & project) - runtimes):
        errors.append(dict(kind='unexpected_release_application', application=name))

    manifests = sorted((release/'releases').glob('*/*.rel'))
    if len(manifests) != 1:
        errors.append(dict(kind='release_manifest_count', path=str(release),
                           count=str(len(manifests))))
    else:
        manifest = release_manifest_applications(manifests[0])
        for name in sorted(released - manifest):
            errors.append(dict(kind='unlisted_release_application', application=name))
        for name in sorted(manifest - released):
            errors.append(dict(kind='missing_release_library', application=name))
        for name in sorted((manifest & project) - runtimes):
            errors.append(dict(kind='unexpected_release_manifest_application', application=name))
        for name in sorted(runtimes - manifest):
            errors.append(dict(kind='missing_release_manifest_application', application=name))
        allowed_bin = {
            manifests[0].stem,
            f'{manifests[0].stem}-{manifests[0].parent.name}',
            'install_upgrade.escript',
            'no_dot_erlang.boot',
            'nodetool',
        }
        for entry in sorted((release/'bin').iterdir() if (release/'bin').is_dir() else []):
            if entry.name not in allowed_bin:
                errors.append(dict(kind='release_build_launcher',
                                   path=str(entry.relative_to(release))))

    for app_file in app_files:
        if app_file.stem not in runtimes:
            continue
        root = app_file.parent.parent
        released_modules = {path.stem for path in (root/'ebin').glob('*.beam')}
        for module in sorted(released_modules - expected_modules.get(app_file.stem, set())):
            errors.append(dict(kind='unexpected_release_beam', application=app_file.stem,
                               module=module))
        for module in sorted(expected_modules.get(app_file.stem, set()) - released_modules):
            errors.append(dict(kind='missing_release_beam', application=app_file.stem,
                               module=module))
        for entry in sorted(root.iterdir()):
            if entry.name not in RUNTIME_PROJECT_DIRECTORIES:
                errors.append(dict(kind='release_project_asset', application=app_file.stem,
                                   path=str(entry.relative_to(release))))
                continue
            for asset in sorted(entry.rglob('*')):
                if (asset.is_symlink() or asset.is_dir() or
                        asset.suffix not in RUNTIME_PROJECT_SUFFIXES[entry.name]):
                    errors.append(dict(kind='release_project_asset', application=app_file.stem,
                                       path=str(asset.relative_to(release))))

    if len(manifests) != 1:
        for name in sorted(BUILD_LAUNCHERS):
            launcher = release/'bin'/name
            if launcher.exists():
                errors.append(dict(kind='release_build_launcher',
                                   path=str(launcher.relative_to(release))))
    return errors


def violations(snapshot: dict, runtimes: set[str], forbidden: set[str],
               release: Path | None = None) -> list[dict[str, str]]:
    """Reject declared dependencies, calls or remote types crossing the runtime/build boundary."""
    owners = {module: app['name'] for app in snapshot['applications'] for module in app['modules']}
    found = {app['name'] for app in snapshot['applications']}
    errors: list[dict[str, str]] = [dict(kind='missing_application', application=name)
                                 for name in sorted(runtimes - found)]
    for app in snapshot['applications']:
        if app['name'] in runtimes:
            for dependency in sorted(set(app['dependencies']) & forbidden):
                errors.append(dict(kind='application_dependency', application=app['name'], target=dependency))
    for module in snapshot['runtime_modules']:
        if module['application'] not in runtimes:
            continue
        for kind in ('imports', 'types'):
            for target in module[kind]:
                if owners.get(target) in forbidden:
                    errors.append(dict(kind=kind, module=module['module'], target=target,
                                       application=owners[target]))
    if release is not None:
        applications = list((release/'lib').glob('*/ebin/*.app'))
        if not applications:
            errors.append(dict(kind='missing_release', path=str(release)))
        for app in applications:
            if app.stem in forbidden:
                errors.append(dict(kind='release_application', application=app.stem))
        for beam in (release/'lib').glob('*/ebin/*.beam'):
            if owners.get(beam.stem) in forbidden:
                errors.append(dict(kind='release_module', module=beam.stem, application=owners[beam.stem]))
        released = {app.stem for app in applications}
        for name in sorted(runtimes - released):
            errors.append(dict(kind='missing_release_application', application=name))
        errors.extend(runtime_release_violations(snapshot, runtimes, release))
    return errors


def policy_violations(snapshot: dict, runtimes: set[str], forbidden: set[str],
                      release: Path | None = None) -> list[dict[str, str]]:
    """Apply the requested boundary and keep core independent of every other inspected app."""
    errors = violations(snapshot, runtimes, forbidden, release)
    found = {app['name'] for app in snapshot['applications']}
    if 'hls_core' in runtimes & found:
        core_forbidden = found - {'hls_core'} - forbidden
        errors.extend(violations(snapshot, {'hls_core'}, core_forbidden, None))
    return errors


def architecture_violations(snapshot: dict) -> list[dict[str, str]]:
    """Reject reverse dependencies from synthesis and target layers into their consumers."""
    found = {app['name'] for app in snapshot['applications']}
    errors: list[dict[str, str]] = []
    for application, forbidden in ARCHITECTURE_FORBIDDEN.items():
        if application in found:
            errors.extend(violations(snapshot, {application}, forbidden & found, None))
    owners = {module: app['name'] for app in snapshot['applications'] for module in app['modules']}
    for module in snapshot['runtime_modules']:
        if module['application'] != 'hls_compile':
            continue
        for target in module['types']:
            if owners.get(target) == 'hls_runtime':
                errors.append(dict(kind='compile_runtime_boundary', reference='types',
                                   module=module['module'], target=target))
        for target, function, arity in module.get('calls', []):
            edge = (module['module'], target, function, arity)
            if (owners.get(target) == 'hls_runtime' and
                    edge not in COMPILE_RUNTIME_ALLOWED_CALLS):
                errors.append(dict(kind='compile_runtime_boundary', reference='call',
                                   module=module['module'], target=target,
                                   function=function, arity=str(arity)))
    return errors


def main(argv: list[str] | None = None) -> int:
    """Inspect one already-built profile and optionally its runtime-only release; never compile."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--profile', default='default')
    parser.add_argument('--runtime', action='append', required=True, help='runtime OTP application (repeatable)')
    parser.add_argument('--forbid', action='append', default=[
        'erl_hls', 'hls_compile', 'hls_fabric', 'hls_target',
        'hls_spacetime', 'hls_spacetime_observer', 'compiler'])
    parser.add_argument('--release', type=Path)
    parser.add_argument('--report', type=Path, default=Path('_build/package-boundaries.json'))
    args = parser.parse_args(argv)
    paths = application_files(args.root.resolve(), args.profile)
    with tempfile.TemporaryDirectory(prefix='package-boundaries-') as temporary:
        request = Path(temporary)/'request.json'
        request.write_text(json.dumps({'applications': list(map(str, paths)), 'runtime': args.runtime}))
        result = subprocess.run(['erl', '+S', '2', '-noshell', '-eval', ERLANG_AUDIT,
                                 '-extra', str(request)], capture_output=True, text=True, timeout=60)
    if result.returncode:
        sys.stderr.write(result.stdout + result.stderr)
        return 1
    snapshot = json.loads(result.stdout)
    snapshot['project_applications'] = sorted(project_applications(args.root.resolve()))
    errors = duplicate_module_ownership(snapshot)
    errors.extend(policy_violations(snapshot, set(args.runtime), set(args.forbid), args.release))
    errors.extend(architecture_violations(snapshot))
    report = snapshot | {'violations': errors, 'release': str(args.release) if args.release else None}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    for error in errors:
        print(json.dumps(error, sort_keys=True))
    print(f"Checked {len(snapshot['runtime_modules'])} runtime modules; {len(errors)} package violations")
    return int(bool(errors))
