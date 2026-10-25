#!/usr/bin/env python3
"""Exercise production-generated parallel outboxes with aliased and independent lanes."""
import argparse
from pathlib import Path
from compiler_paths import compiler_root
import shutil

from backend_paths import erl_command
from backend_commands import execute

ROOT = Path(__file__).resolve().parents[1]


def check(xls: Path, public: Path, stage: Path, lanes: int) -> None:
    """Compile the real private drainer, then check all accepted effects and credits in RTL."""
    stage.mkdir(parents=True, exist_ok=False)
    execute(erl_command(public, f'[Path] = init:get_plain_arguments(), ok = hls_partition_outbox_tests:write(Path, {lanes}), halt().', stage/'top.x', profile="test"), stage, 'generate')
    shutil.copy(public/'priv/xls/lib/axis.x', stage/'axis.x')
    shutil.copy(ROOT/'test/rtl/parallel_outbox_actor.x', stage/'parallel_outbox_actor.x')
    for command, name, output in [
        ([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false', '--dslx_path=.',
          f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', 'top.x'], 'convert', 'top.ir'),
        ([str(xls/'opt_main'), 'top.ir'], 'optimize', 'top.opt.ir'),
        ([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
          '--flop_outputs=true', '--reset=reset', '--fifo_module=', '--use_system_verilog=false',
          '--module_name=parallel_outbox', 'top.opt.ir'], 'codegen', 'top.v')]:
        execute(command, stage, name, timeout=600, output=stage / output)
    ports = [f'._fragment_{i}(fragments[{i}]), ._fragment_{i}_vld(fragment_valid[{i}]), ._fragment_{i}_rdy(fragment_ready[{i}])' for i in range(lanes)]
    (stage/'test.sv').write_text((ROOT/'test/rtl/parallel_outbox_tb.sv').read_text().replace('@@CONNECTIONS@@', ',\n    '.join(ports)))
    execute(['iverilog', '-g2012', '-s', 'parallel_outbox_tb', f'-Pparallel_outbox_tb.LANES={lanes}', '-o', 'test.vvp', 'test.sv', 'top.v'], stage, 'compile', timeout=600)
    execute(['vvp', 'test.vvp'], stage, 'simulate', timeout=600)
    log = (stage/'simulate.log').read_text()
    if 'PASS parallel prefix' not in log:
        raise ValueError('incomplete parallel-outbox test')
    print(log, flush=True)


def main() -> None:
    """Test distinct, balanced-alias and uneven-alias destination geometries with a caller-selected native compiler."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--erl-hls', type=Path, default=None)
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    for lanes in (4, 2, 3):
        check(args.xls.resolve(), args.erl_hls.resolve(), args.stage.resolve()/f'lanes-{lanes}', lanes)


if __name__ == '__main__':
    main()
