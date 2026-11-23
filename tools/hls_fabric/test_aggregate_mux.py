#!/usr/bin/env python3
"""Check the production aggregate selector's ordering, polling, stalls, reset and forwarding latency."""
import argparse
import json
from pathlib import Path
import re

from backend_paths import ROOT
from backend_commands import digest, execute
from transport_codegen import specialize


def probe(stage: Path, xls: Path, count: int, shortened: bool) -> None:
    """Compile the unchanged production mux and check every accepted request through real RTL."""
    stage.mkdir(parents=True, exist_ok=False)
    source = ROOT/'apps/hls_lowering/priv/xls/partition_reduction.x.in'
    body, = re.findall(r'proc ReductionMux<.*?^}', source.read_text(), re.M | re.S)
    (stage/'actor.x').write_text('pub struct ReductionAggregateRequest { slot: u32, aggregate: bits[186] }\n')
    (stage/'top.x').write_text('import actor;\n'+body+f'''
pub proc Top {{
  config(incoming: chan<actor::ReductionAggregateRequest>[u32:{count}] in,
      outgoing: chan<actor::ReductionAggregateRequest> out) {{
    spawn ReductionMux<u32:{count}>(incoming, outgoing); ()
  }}
  init {{ () }}
  next(state: ()) {{ state }}
}}
''')
    commands = [
        ([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false',
          f'--dslx_path={stage}', f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', str(stage/'top.x')], 'convert', 'top.ir'),
        ([str(xls/'opt_main'), str(stage/'top.ir')], 'optimize', 'top.opt.ir'),
        ([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
          '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
          '--module_name=aggregate_mux', str(stage/'top.opt.ir')], 'codegen', 'top.v')]
    for command, label, output in commands:
        execute(command, stage, label, output=stage/output)
    if shortened:
        result = specialize(xls/'codegen_main', stage/'top.opt.ir', stage/'top.v', stage/'adapters')
        if len(result['adapters']) != 1:
            raise ValueError('aggregate probe did not specialize exactly one mux')
    connections = ',\n'.join(f'._incoming__{i}(frames[{i}]), ._incoming__{i}_vld(valid[{i}]), ._incoming__{i}_rdy(ready[{i}])'
                            for i in range(count))
    bench = ROOT/'apps/hls_fabric/test/rtl/aggregate_mux_tb.sv'
    (stage/'test.sv').write_text(bench.read_text().replace('@@CONNECTIONS@@', connections))
    execute(['iverilog', '-g2012', '-s', 'aggregate_mux_tb', f'-Paggregate_mux_tb.N={count}',
             f'-Paggregate_mux_tb.EXPECTED_NS={0 if shortened else 8}', '-o', str(stage/'test.vvp'),
             str(stage/'test.sv'), str(stage/'top.v')], stage, 'iverilog')
    execute(['vvp', str(stage/'test.vvp')], stage, 'simulate')
    output = (stage/'simulate.log').read_text()
    if output.count('PASS: aggregate mux') != 2:
        raise ValueError('aggregate probe did not complete both reset epochs')
    (stage/'provenance.json').write_text(json.dumps({'count': count, 'shortened': shortened, 'commands': [c for c,_,_ in commands],
        'template_sha256': digest(source), 'bench_sha256': digest(bench), 'rtl_sha256': digest(stage/'top.v')}, indent=2)+'\n')
    print(output, end='', flush=True)


def main() -> None:
    """Exercise power-of-two and irregular fan-in, plus the preceding schedule as a latency control."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    for count in (1, 2, 3, 4, 8):
        probe(args.stage.resolve()/f'inputs-{count}', args.xls.resolve(), count, True)
    probe(args.stage.resolve()/'reference-2', args.xls.resolve(), 2, False)


if __name__ == '__main__':
    main()
