#!/usr/bin/env python3
"""Check ready-lane service and fairness with twelve data lanes and three return lanes."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root
import shutil

from backend_paths import ROOT
from backend_commands import digest, execute


def check(xls: Path, public: Path, stage: Path, source: Path, sparse_limit: int) -> None:
    """Compile the static transmitter and validate opaque traffic under sparse/saturated loads."""
    stage.mkdir(parents=True, exist_ok=False)
    sources = [source, ROOT / 'test/xls/credit_arbitration.x',
               public / 'priv/xls/lib/axis.x', public / 'priv/xls/lib/frame_config.x']
    template = ROOT / 'test/rtl/credit_arbitration_tb.sv'
    tracked = [*sources, template, Path(__file__), ROOT / 'tools/backend_commands.py',
               *[xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')],
               *(xls / 'xls/dslx/stdlib').rglob('*.x')]
    inputs = {str(p): digest(p) for p in tracked}
    for original, name in zip(sources, ['hls_credit_link.x', 'credit_arbitration.x', 'axis.x', 'frame_config.x']):
        shutil.copy(original, stage / name)
    ports = []
    for i in range(12):
        ports += [f'._frames_in__{i}(frames[{i}]), ._frames_in__{i}_vld(frame_valid[{i}]), ._frames_in__{i}_rdy(frame_ready[{i}])',
                  f'._credits_in__{i}(1\'b1), ._credits_in__{i}_vld(credit_valid[{i}]), ._credits_in__{i}_rdy(credit_ready[{i}])']
    for i in range(3):
        ports += [f'._returned_in__{i}(1\'b1), ._returned_in__{i}_vld(return_valid[{i}]), ._returned_in__{i}_rdy(return_ready[{i}])']
    (stage / 'test.sv').write_text(template.read_text().replace('@@CONNECTIONS@@', ',\n    '.join(ports)))
    commands = [
        ([str(xls / 'ir_converter_main'), '--top=Top', '--warnings_as_errors=false', '--dslx_path=.',
          f'--dslx_stdlib_path={xls / "xls/dslx/stdlib"}', 'credit_arbitration.x'], 'convert', 'arbiter.ir'),
        ([str(xls / 'opt_main'), 'arbiter.ir'], 'optimize', 'arbiter.opt.ir'),
        ([str(xls / 'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
          '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
          '--module_name=arbiter', 'arbiter.opt.ir'], 'codegen', 'arbiter.v')]
    for command, label, output in commands:
        execute(command, stage, label, timeout=600, output=stage / output)
    execute(['iverilog', '-g2012', '-s', 'credit_arbitration_tb',
         f'-Pcredit_arbitration_tb.SPARSE_LIMIT={sparse_limit}', '-o', 'test.vvp', 'test.sv', 'arbiter.v'], stage, 'compile', timeout=600)
    execute(['vvp', 'test.vvp'], stage, 'simulation', timeout=600)
    print((stage / 'simulation.log').read_text(), end='')
    if inputs != {str(p): digest(p) for p in tracked}:
        raise ValueError('arbitration inputs changed during validation')
    (stage / 'provenance.json').write_text(json.dumps({'inputs': inputs,
        'commands': [c for c, _, _ in commands], 'sparse_cycle_limit': sparse_limit, 'rtl_sha256': digest(stage / 'arbiter.v')}, indent=2)+'\n')


def main() -> None:
    """Select the pinned XLS installation, public libraries and a fresh artifact directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--erl-hls', type=Path, default=None)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT / 'apps/hls_lowering/priv/xls/hls_credit_link.x', help='explicit historical source for matched comparisons')
    parser.add_argument('--sparse-limit', type=int, default=400, help='maximum cycles for the sparse workload')
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    if args.sparse_limit < 1:
        parser.error('sparse cycle limit must be positive')
    check(args.xls.resolve(), args.erl_hls.resolve(), args.stage.resolve(), args.source.resolve(), args.sparse_limit)


if __name__ == '__main__':
    main()
