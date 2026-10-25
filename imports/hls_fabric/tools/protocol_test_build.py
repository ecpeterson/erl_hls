"""Test-only adapters to the public source builder and isolated sampled-clock circuits."""
from pathlib import Path
import json
import subprocess
import sys

from backend_commands import digest, run
from backend_paths import application_directory


def emit_command(kind: str, config: Path, output: Path) -> list[str | Path]:
    """Invoke the public CLI from a built profile; callers supply erlang_environment explicitly."""
    return ['erl', '+S', '2:2', '-noshell', '-s', 'hls_fabric_cli', 'main', '-extra',
            'emit', '--kind', kind, '--config', config, '--output', output]


def compile_build(xls: Path, directory: Path, *, profile: str = 'default') -> Path:
    """Compile an emitted bundle and return its resolved immutable release; retain logs on failure.

    Schedules, imports, input verification and provenance come from the production
    source-build boundary. No fixture-specific compiler implementation is selected.
    """
    compiler = application_directory('erl_hls', profile)
    run([sys.executable, compiler/'priv/tools/compile_source_build.py', xls, directory],
        directory, 'compile-source-build', timeout=None)
    return (directory/'compiled').resolve()


def compile_clock(xls: Path, source: Path, stage: Path, top: str, module: str,
                  imports: list[Path]) -> None:
    """Lower a standalone component or deliberately corrupted test circuit, retaining diagnostics.

    This bypasses source-bundle identity checks only for explicit test circuits.
    Positive source builds use compile_build; this helper makes no admission claim.
    """
    commands = [
        ('convert', [xls/'ir_converter_main', '--warnings_as_errors=false', '--top='+top,
                     '--dslx_path='+':'.join(map(str, imports)),
                     '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'), source], stage/'raw.ir'),
        ('opt', [xls/'opt_main', stage/'raw.ir'], stage/'optimized.ir'),
        ('codegen', [xls/'codegen_main', '--pipeline_stages=1', '--delay_model=unit',
                     '--flop_inputs=false', '--flop_outputs=false', '--use_system_verilog=false',
                     '--reset=reset', '--module_name='+module, stage/'optimized.ir'], stage/'core.v'),
    ]
    records = []
    for name, command, target in commands:
        with (stage/(name+'.log')).open('x') as log, target.open('x') as output:
            result = subprocess.run(list(map(str, command)), stdout=output, stderr=log, timeout=300)
        records.append({'command':list(map(str, command)), 'exit':result.returncode, 'output':str(target),
                        'sha256':digest(target)})
        (stage/'commands.json').write_text(json.dumps(records, indent=2)+'\n')
        if result.returncode:
            raise RuntimeError(f'{name} failed: ' + (stage/(name+'.log')).read_text()[-4000:])
