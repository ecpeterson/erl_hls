#!/usr/bin/env python3
"""Audit declared OTP edges and keep generic libraries independent of examples."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from compiler_paths import compiler_root, compiler_tool


GENERIC_APPLICATIONS = {'erl_hls', 'hls_runtime', 'hls_lowering', 'hls_fabric', 'router'}
EXAMPLE_APPLICATIONS = {'hls_phi', 'hls_snowflake'}
DEFAULT_APPLICATIONS = GENERIC_APPLICATIONS | EXAMPLE_APPLICATIONS
PROFILE_APPLICATIONS = {
    'default': DEFAULT_APPLICATIONS,
    'spacetime': DEFAULT_APPLICATIONS | {'hls_spacetime', 'hls_spacetime_observer'},
}


def audit_profile(profile: str) -> tuple[dict, list[dict[str, str]]]:
    """Inspect one built profile for missing apps, undeclared edges and reverse example edges."""
    expected = PROFILE_APPLICATIONS[profile]
    auditor = compiler_tool(compiler_root(profile), 'package_boundaries')
    paths = auditor.application_files(Path.cwd(), profile)
    with tempfile.TemporaryDirectory(prefix='application-boundaries-') as temporary:
        request = Path(temporary) / 'request.json'
        request.write_text(json.dumps({'applications': list(map(str, paths)),
                                       'runtime': sorted(expected)}))
        result = subprocess.run(['erl', '+S', '2', '-noshell', '-eval', auditor.ERLANG_AUDIT,
                                 '-extra', str(request)], capture_output=True, text=True,
                                check=True, timeout=60)
    snapshot = json.loads(result.stdout)
    found = {app['name'] for app in snapshot['applications']}
    errors = auditor.violations(snapshot, expected, set(), None)
    errors.extend(auditor.violations(snapshot, GENERIC_APPLICATIONS & found,
                                     EXAMPLE_APPLICATIONS, None))
    errors.extend(auditor.undeclared_application_dependencies(snapshot, expected))
    return snapshot, errors


def main(argv: list[str] | None = None) -> int:
    """Audit requested profiles and write one profile-keyed report; default to the ordinary build."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', action='append', choices=PROFILE_APPLICATIONS,
                        help='already-built rebar profile (repeatable; default: default)')
    args = parser.parse_args(argv)
    profiles = list(dict.fromkeys(args.profile or ['default']))
    snapshots: dict[str, dict] = {}
    errors: list[dict[str, str]] = []
    modules = 0
    for profile in profiles:
        snapshot, profile_errors = audit_profile(profile)
        snapshots[profile] = snapshot | {'violations': profile_errors}
        modules += len(snapshot['runtime_modules'])
        errors.extend([dict(profile=profile) | error for error in profile_errors])
    report = Path('_build/application-boundaries.json')
    report.write_text(json.dumps({'profiles': snapshots, 'violations': errors},
                                 indent=2, sort_keys=True) + '\n')
    for error in errors:
        print(json.dumps(error, sort_keys=True))
    print(f"Checked {modules} project modules across {', '.join(profiles)}; "
          f"{len(errors)} application-boundary violations")
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
