#!/usr/bin/env python3
"""Measure aggregate-channel stalls and transfers in the retained 2x1 profile."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from architecture import sha

ROOT = Path(__file__).resolve().parents[3]
SCOPE = 'dut.application.__phi_decoder_profile_topology__SchedulerGrid_0_next_inst'


def main() -> None:
    """Run the existing application testbench with passive channel observers."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=lambda p: Path(p).resolve())
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=False)
    rtl = args.rtl / 'phi_decoder_profile.v'
    text = rtl.read_text()
    instances = re.findall(r'\w+ (materialized_fifo_fifo__scheduler_\d+_aggregate_) \(', text)
    if len(instances) != 2:
        raise ValueError('expected exactly two aggregate delivery channels in the 2x1 fixture')
    source = (ROOT / 'test/rtl/phi_decoder_profile_tb.sv').read_text()
    observers = ['integer observed_cycle=0; always @(negedge clk) observed_cycle=observed_cycle+1;']
    for i, instance in enumerate(instances):
        endpoint = f'{SCOPE}.{instance}'
        observers.append(f'''
    integer offered_{i}=0, transfers_{i}=0, stalls_{i}=0, burst_{i}=0, max_stall_{i}=0;
    integer last_{i}=-1, gap_{i}=1000000, adjacent_{i}=0;
    always @(posedge clk) if(resetn) begin
      if({endpoint}.push_valid) offered_{i}=offered_{i}+1;
      if({endpoint}.push_valid && !{endpoint}.push_ready) begin
        stalls_{i}=stalls_{i}+1; burst_{i}=burst_{i}+1;
        if(burst_{i}>max_stall_{i}) max_stall_{i}=burst_{i};
      end else burst_{i}=0;
      if({endpoint}.pop_valid && {endpoint}.pop_ready) begin
        transfers_{i}=transfers_{i}+1;
        if(last_{i}>=0 && observed_cycle-last_{i}<gap_{i}) gap_{i}=observed_cycle-last_{i};
        if(last_{i}>=0 && observed_cycle-last_{i}==1) adjacent_{i}=adjacent_{i}+1;
        last_{i}=observed_cycle;
      end
    end
    final $display("AGGREGATE channel={i} offered=%0d delivered=%0d blocked=%0d longest_block=%0d minimum_gap=%0d adjacent=%0d",
      offered_{i},transfers_{i},stalls_{i},max_stall_{i},gap_{i},adjacent_{i});
''')
    source = source.removesuffix('endmodule\n') + '\n'.join(observers) + '\nendmodule\n'
    tb = args.stage / 'traffic.sv'
    tb.write_text(source)
    summary = {'rtl_sha256': sha(rtl), 'scope': SCOPE, 'channels': instances, 'runs': []}
    for stalled in (0, 1):
        command = ['iverilog', '-g2012', '-s', 'phi_decoder_profile_tb', '-o', 'sim.vvp',
                   '-Pphi_decoder_profile_tb.WIDTH=2', '-Pphi_decoder_profile_tb.HEIGHT=1',
                   f'-Pphi_decoder_profile_tb.STALL_OUTPUTS={stalled}', str(tb),
                   *[str(args.rtl / n) for n in ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')]]
        for label, cmd in [('compile', command), ('simulation', ['vvp', 'sim.vvp'])]:
            with (args.stage / f'{stalled}-{label}.log').open('w') as out:
                subprocess.run(cmd, cwd=args.stage, stdout=out, stderr=subprocess.STDOUT,
                               check=True, timeout=300)
        log = (args.stage / f'{stalled}-simulation.log').read_text()
        rows = [dict((key, int(value)) for key, value in re.findall(r'(\w+)=(\d+)', line))
                for line in log.splitlines() if line.startswith('AGGREGATE ')]
        if len(rows) != 2 or 'PASS: decoder-only' not in log:
            raise ValueError('missing application/observer results')
        summary['runs'].append({'stalled': bool(stalled), 'channels': rows,
                                'cycles_per_step': float(re.search(r'cycles_per_step=([\d.]+)', log)[1])})
    (args.stage / 'sim.vvp').unlink()
    (args.stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
