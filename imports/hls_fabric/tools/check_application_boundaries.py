#!/usr/bin/env python3
"""Reject example dependencies in generic compiler, lowering and runtime libraries."""
import json
from pathlib import Path
import subprocess
import tempfile

from compiler_paths import compiler_root, compiler_tool


def main() -> int:
    """Inspect the default build and require examples to remain outside library call/type dependencies."""
    auditor = compiler_tool(compiler_root('default'), 'package_boundaries')
    generic = {'erl_hls', 'hls_runtime', 'hls_lowering', 'hls_fabric', 'router'}
    paths = auditor.application_files(Path.cwd(), 'default')
    with tempfile.TemporaryDirectory(prefix='application-boundaries-') as temporary:
        request = Path(temporary) / 'request.json'
        request.write_text(json.dumps({'applications': list(map(str, paths)), 'runtime': sorted(generic)}))
        result = subprocess.run(['erl', '+S', '2', '-noshell', '-eval', auditor.ERLANG_AUDIT,
                                 '-extra', str(request)], capture_output=True, text=True, check=True, timeout=60)
    snapshot = json.loads(result.stdout)
    errors = auditor.violations(snapshot, generic, {'hls_phi', 'hls_snowflake'}, None)
    report = Path('_build/application-boundaries.json')
    report.write_text(json.dumps(snapshot | {'violations': errors}, indent=2, sort_keys=True) + '\n')
    for error in errors:
        print(json.dumps(error, sort_keys=True))
    print(f"Checked {len(snapshot['runtime_modules'])} library modules; {len(errors)} example dependencies")
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
