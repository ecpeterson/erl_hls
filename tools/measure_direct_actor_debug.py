#!/usr/bin/env python3
"""Compare complete direct-actor fixtures with physical and semantic diagnostics.

Run test_actor_debug.sh ... direct_reduction first. The baseline and observed
fixtures share application ports, reset, codegen options, and workload. This
maps complete designs; it does not infer placed timing or power.
Use --baseline to compare two already instrumented fixture/p2 builds.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from measure_topology_debug import cell_counts, distribution
import topology_debug

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--seeds', type=int, default=2)
    parser.add_argument('--baseline', type=Path, help='previous fixture directory containing p2')
    parser.add_argument('--scope', help='workload and comparison recorded in the report')
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error('--seeds must be positive')
    fixture, stage = args.fixture.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    # Keep physical queries enabled in both measurements so the increment
    # includes actor publication, retention and query selection, rather than
    # charging the existing transport/probe controller entirely to actors.
    if args.baseline:
        modes = {'baseline': args.baseline.resolve()/'p2', 'candidate': fixture/'p2'}
        scope = 'complete instrumented fixture, pipeline stages 2, XC7 ABC9; baseline versus candidate'
    else:
        production = fixture / 'production'
        topology_debug.instrument(argparse.Namespace(
            rtl=[production / 'actor_debug_2.v', production / 'actor_debug_wrapper.v'],
            yosys=args.yosys, top='actor_debug_production_wrapper', clock='clk', reset='reset',
            output_top='hls_application', reset_active_low=False, stage=stage/'baseline',
            actor_projection=None, actor_root=''))
        modes = {'physical_queries': stage/'baseline', 'actor_queries': fixture/'p2'}
        scope = ('complete five-actor reduction fixture, pipeline stages 2, XC7 ABC9; '
                 'physical queries versus physical plus committed actor queries')
    rows, inputs = [], {}
    rtl = ROOT/'priv/rtl/debug'
    for mode, instrumented in modes.items():
        # Use the preserved Yosys representation; Verilog export may omit
        # application memory-mapping attributes.
        sources = [instrumented/'instrumented.json', instrumented/'debug_top.v',
                   rtl/'hls_topology_debug.v', rtl/'hls_debug_frame_rx.v', rtl/'hls_debug_route.v',
                   rtl/'hls_actor_snapshot.v']
        inputs[mode] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        for seed in range(1, args.seeds+1):
            prefix = stage/f'{mode}-{seed}'
            script = f'read_json {topology_debug.quote(sources[0])}\n'
            script += 'read_verilog -sv ' + ' '.join(map(topology_debug.quote, sources[1:])) + '\n'
            script += ('hierarchy -check -top hls_debug_application\nproc\nflatten\nopt\n'
                       f'rename -scramble-name -seed {seed}\n'
                       'synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top hls_debug_application\n'
                       'check -assert\nscc -expect 0\n'
                       f'tee -o {topology_debug.quote(prefix.with_suffix(".json"))} stat -json -tech xilinx\n')
            prefix.with_suffix('.ys').write_text(script)
            with prefix.with_suffix('.log').open('w') as log:
                subprocess.run([args.yosys, '-Q', '-s', str(prefix.with_suffix('.ys'))],
                               stdout=log, stderr=log, check=True)
            cells = json.loads(prefix.with_suffix('.json').read_text())['design']['num_cells_by_type']
            row = {'mode': mode, 'seed': seed, **cell_counts(cells), 'DSP': cells.get('DSP48E1', 0)}
            rows.append(row)
            print(row, flush=True)
    report = {'scope': (args.scope or scope) + '; no placed timing or power',
              'yosys': subprocess.check_output([args.yosys, '-V'], text=True).strip(),
              'inputs': inputs, 'runs': rows,
              'summary': {mode: {metric: distribution([row[metric] for row in rows if row['mode'] == mode])
                                 for metric in ('LUT','LUT_logic','LUT_RAM','FF','RAMB18','RAMB36','DSP')}
                          for mode in modes}}
    (stage/'results.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
