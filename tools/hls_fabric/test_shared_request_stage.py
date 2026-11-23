#!/usr/bin/env python3
"""Exercise the production request register at II=1, under stalls and across reset."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(argv: list[str | Path], stage: Path, log: str, output: str | None = None) -> None:
    """Retain compiler/simulation diagnostics and bound each small invocation."""
    with (stage / log).open('w') as err, (stage / (output or log + '.out')).open('w') as out:
        subprocess.run(list(map(str, argv)), cwd=stage, stdout=out, stderr=err,
                       check=True, timeout=120)


def main() -> None:
    """Compile the actual stage with a narrow test payload and several schedules."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(),
                        default=ROOT / '_build/shared-request-stage')
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=True)
    template = (ROOT / 'apps/hls_lowering/priv/xls/templates/shared_loader.x.in').read_text()
    stage = template[template.index('proc SharedRequestStage {'):]
    (args.stage / 'request_stage.x').write_text(stage.replace('SharedDispatchTicket', 'u16'))
    run([args.xls / 'ir_converter_main', '--top=SharedRequestStage',
         '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), 'request_stage.x'],
        args.stage, 'convert.log', 'request.ir')
    run([args.xls / 'opt_main', 'request.ir'], args.stage, 'opt.log', 'request.opt.ir')
    for stages in (1, 2, 3):
        rtl = f'request_{stages}.v'
        run([args.xls / 'codegen_main', f'--pipeline_stages={stages}',
             '--worst_case_throughput=1', '--delay_model=unit', '--flop_inputs=false',
             '--flop_outputs=false', '--reset=reset', '--module_name=request_stage',
             '--use_system_verilog=false', '--fifo_module=', 'request.opt.ir'],
            args.stage, f'codegen-{stages}.log', rtl)
        run(['iverilog', '-g2012', '-s', 'shared_request_stage_tb', '-o', 'sim.vvp',
             ROOT / 'apps/hls_fabric/test/rtl/shared_request_stage_tb.sv', rtl], args.stage, 'compile.log')
        run(['vvp', 'sim.vvp'], args.stage, f'simulate-{stages}.log')
        if 'PASS:' not in (args.stage / f'simulate-{stages}.log.out').read_text():
            raise AssertionError('request-stage witness did not finish')
    print('PASS: request stage: II=1, ordered stalls, reset; 1/2/3 XLS stages')


if __name__ == '__main__':
    main()
