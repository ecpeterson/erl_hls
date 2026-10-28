"""Check compiled OTP package ownership, including type-only edges and deployed release contents."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

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
      imports => lists:usort([M || {M, _, _} <- Imports]), types => lists:usort(Remote(Forms))}
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
    return errors


def main(argv: list[str] | None = None) -> int:
    """Inspect one already-built profile and optionally its runtime-only release; never compile."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--profile', default='default')
    parser.add_argument('--runtime', action='append', required=True, help='runtime OTP application (repeatable)')
    parser.add_argument('--forbid', action='append', default=['erl_hls', 'hls_lowering', 'compiler'])
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
    errors = violations(snapshot, set(args.runtime), set(args.forbid), args.release)
    report = snapshot | {'violations': errors, 'release': str(args.release) if args.release else None}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    for error in errors:
        print(json.dumps(error, sort_keys=True))
    print(f"Checked {len(snapshot['runtime_modules'])} runtime modules; {len(errors)} package violations")
    return int(bool(errors))
