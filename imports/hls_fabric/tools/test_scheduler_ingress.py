#!/usr/bin/env python3
"""Check generated alternating ingress ordering, sparse lanes, stalls and reset in RTL."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root

from backend_paths import ROOT, erl_command
from backend_commands import digest, execute


def compile_ingress(stage: Path, xls: Path, public: Path, count: int, reference: bool = False) -> None:
    """Compile the actual Erlang-generated selector with a minimal scheduled-request type."""
    stage.mkdir(parents=True, exist_ok=False)
    expression = f'''[Stage] = init:get_plain_arguments(),
      A = #{{identity => probe, index => 0}},
      Local = #{{schedulers => [#{{stem => "probe", module_name => "ingress_types",
        actors => [#{{identity => probe, slot => 3}}]}}]}},
      Source = hls_partition_shared_dslx:ingress_support(A, Local, lists:seq(1, {count})),
      ok = file:write_file(filename:join(Stage, "selector.x"), Source), halt().'''
    execute(erl_command(public, expression, stage, profile="test"), stage, 'generate')
    (stage/'ingress_types.x').write_text('''import axis;
pub struct ScheduledRequest { slot: u32, frame: axis::Frame, credit: u1 }
''')
    arguments = ', '.join(f'frame_{i}: chan<axis::Frame> in' for i in range(count))
    names = ', '.join(f'frame_{i}' for i in range(count))
    selector = (stage/'selector.x').read_text()
    if reference:
        (stage/'scheduler_ingress_reference.x').write_bytes((ROOT/'test/xls/scheduler_ingress_reference.x').read_bytes())
        selector = 'import scheduler_ingress_reference;\n'
    proc = 'scheduler_ingress_reference::Reference' if reference else 'SchedulerIngress0'
    (stage/'top.x').write_text('import axis;\nimport ingress_types;\n'+selector+f'''
pub proc Top {{
  config({arguments}, request_out: chan<ingress_types::ScheduledRequest> out) {{
    spawn {proc}<u32:3>({names}, request_out); ()
  }}
  init {{ () }}
  next(state: ()) {{ state }}
}}
''')
    commands = [
        ([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false',
          f'--dslx_path={stage}:{public/"priv/xls/lib"}', f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}',
          str(stage/'top.x')], 'convert', 'ingress.ir'),
        ([str(xls/'opt_main'), str(stage/'ingress.ir')], 'optimize', 'ingress.opt.ir'),
        ([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit',
          '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
          '--reset=reset', '--fifo_module=', '--module_name=ingress', str(stage/'ingress.opt.ir')],
         'codegen', 'ingress.v')]
    for command, label, output in commands:
        execute(command, stage, label, output=stage/output)
    (stage/'build.json').write_text(json.dumps({'count': count, 'reference': reference, 'commands': [c for c,_,_ in commands],
        'rtl_sha256': digest(stage/'ingress.v'), 'emitter_sha256': digest(ROOT/'src/hls_partition_shared_dslx.erl'),
        'template_sha256': digest(ROOT/'priv/xls/scheduler_ingress.x.in')}, indent=2)+'\n')


def simulate(stage: Path, count: int, expected_ns: int = 8) -> None:
    """Compare every accepted frame and grant against a fair ordered scoreboard."""
    connections = ',\n'.join(f'._frame_{i}(frames[{i}]), ._frame_{i}_vld(valid[{i}]), ._frame_{i}_rdy(ready[{i}])'
                             for i in range(count))
    source = (ROOT/'test/rtl/scheduler_ingress_tb.sv').read_text().replace('@@CONNECTIONS@@', connections)
    (stage/'test.sv').write_text(source)
    execute(['iverilog', '-g2012', '-s', 'scheduler_ingress_tb', f'-Pscheduler_ingress_tb.N={count}', f'-Pscheduler_ingress_tb.EXPECTED_NS={expected_ns}',
             '-o', str(stage/'test.vvp'), str(stage/'test.sv'), str(stage/'ingress.v')], stage, 'compile-test')
    execute(['vvp', str(stage/'test.vvp')], stage, 'simulate')
    output = (stage/'simulate.log').read_text()
    if 'PASS:' not in output:
        raise ValueError('ingress test did not finish')
    print(output, end='', flush=True)


def main() -> None:
    """Exercise both the one-producer boundary and the final two-way merger."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--erl-hls', type=Path, default=None)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--counts', type=int, nargs='+', default=[1, 2])
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    for count in args.counts:
        if count not in (1, 2):
            parser.error('input count must be one or two')
        stage = args.stage.resolve()/f'inputs-{count}'
        compile_ingress(stage, args.xls.resolve(), args.erl_hls.resolve(), count)
        simulate(stage, count)
    if 2 in args.counts:
        stage = args.stage.resolve()/'reference-2'
        compile_ingress(stage, args.xls.resolve(), args.erl_hls.resolve(), 2, reference=True)
        simulate(stage, 2, expected_ns=16)


if __name__ == '__main__':
    main()
