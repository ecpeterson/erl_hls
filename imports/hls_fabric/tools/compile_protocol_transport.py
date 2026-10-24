"""Compile an emitted DSLX transport with its required single-clock schedule; retain commands and hashes."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from compiler_paths import PUBLIC
from backend_paths import ROOT


def digest(path: Path) -> str:
    """Bind exact compiler inputs and products without claiming hardware equivalence."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_clock(xls: Path, source: Path, stage: Path, top: str, module: str,
                  imports: list[Path]) -> None:
    """Lower a sampled proc once; preserve its exact one-stage schedule and failed diagnostics."""
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


def compile_transport(xls: Path, directory: Path) -> None:
    """Compile one fresh generated proc; reject existing products and retain failed diagnostics."""
    stage = directory / 'dslx'
    compile_clock(xls, stage/'transport.x', stage, 'protocol_clock', 'protocol_fabric_core',
                  [stage, ROOT/'priv/xls/lib', PUBLIC/'priv/xls/lib'])
    rtl = [stage/'core.v', stage/'protocol_fabric.sv']
    with (directory/'files.f').open('x') as listing:
        listing.write(''.join(str(p.resolve())+'\n' for p in rtl))
    summary_path = directory/'summary.json'
    summary = json.loads(summary_path.read_text())
    summary['rtl'] = [{'file':str(p.resolve()), 'sha256':digest(p)} for p in rtl]
    summary['dslx_inputs'] = [{'file':str(p.resolve()), 'sha256':digest(p)} for p in
        [stage/'transport.x', *sorted(stage.glob('remote_*_codec_*.x')),
         ROOT/'priv/xls/lib/protocol_partition.x', ROOT/'priv/xls/lib/protocol_transport.x',
         PUBLIC/'priv/xls/lib/axis.x']]
    summary['xls_tools'] = [{'file':str((xls/n).resolve()), 'sha256':digest(xls/n)}
                            for n in ['ir_converter_main','opt_main','codegen_main']]
    summary['schedule'] = {'pipeline_stages':1, 'flop_inputs':False, 'flop_outputs':False,
                           'channel_handshakes':'always_enabled_clock_samples'}
    summary_path.write_text(json.dumps(summary, indent=2)+'\n')


def main() -> None:
    """Use the caller-selected XLS distribution and the checkout's pinned compiler dependency."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    compile_transport(args.xls.resolve(), args.directory.resolve())


if __name__ == '__main__':
    main()
