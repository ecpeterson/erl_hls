#!/usr/bin/env python3
"""Map and route one retained XLS FIFO between preserved stimulus/capture registers."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
from fifo_experiment import MODULE, ports, sha
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phi_timing import critical_paths
from timing_coverage.check import check


def run(args: argparse.Namespace) -> None:
    """Measure a selected FIFO with matched harness/constraints and register coverage."""
    selected = [m for m in MODULE.finditer(args.rtl.read_text())
                if m[1].startswith(f'fifo_for_depth_{args.depth}_')
                and ports(m[0]).get('push_data') == f'input[{args.width-1}:0]']
    if not selected:
        raise ValueError('no matching FIFO')
    module = selected[0]
    required = {'clk', 'reset', 'push_valid', 'push_ready', 'push_data', 'pop_valid', 'pop_ready', 'pop_data'}
    if set(ports(module[0])) != required:
        raise ValueError('unsupported FIFO ports')
    root = args.stage
    root.mkdir(parents=True, exist_ok=False)
    (root/'fifo.v').write_text(module[0]+'\n')
    width = args.width
    (root/'harness.v').write_text(f'''module fifo_probe(input wire clock, output wire activity);
  (* keep = "true" *) reg [{width+2}:0] stimulus = 1;
  (* keep = "true" *) reg [{width+1}:0] captured = 0;
  wire [{width-1}:0] data;
  wire valid, ready;
  always @(posedge clock) begin
    stimulus <= {{stimulus[{width+1}:0], stimulus[{width+2}] ^ stimulus[{width}] ^ stimulus[1] ^ stimulus[0]}};
    captured <= {{ready, valid, data}};
  end
  assign activity = captured[0];
  {module[1]} fifo(.clk(clock), .reset(stimulus[{width+2}]),
    .push_valid(stimulus[{width}]), .pop_ready(stimulus[{width+1}]),
    .push_data(stimulus[{width-1}:0]), .pop_data(data), .pop_valid(valid), .push_ready(ready));
endmodule
''')
    (root/'map.ys').write_text('read_verilog -sv fifo.v harness.v\nsynth_xilinx -flatten -abc9 -family xc7 -top fifo_probe\ncheck -assert\nscc -expect 0\nwrite_json mapped.json\n')
    here = Path(__file__).resolve().parents[1]
    (root/'timing.xdc').write_text((here/'xc7z030sbg485.xdc').read_text()+'create_clock -period 5 [get_ports clock]\n')
    commands = [
        [str(args.yosys), '-Q', '-q', '-s', 'map.ys'],
        [str(args.nextpnr), '--chipdb', str(args.chipdb), '--json', 'mapped.json',
         '--xdc', 'timing.xdc', '--seed', str(args.seed), '--freq', '200', '--timing-allow-fail',
         '--report', 'timing.json', '--log', 'route.log', '--timing-coverage', 'coverage.json']]
    for label, command in zip(('map', 'route'), commands):
        with (root/(label+'.console')).open('w') as out:
            subprocess.run(command,cwd=root,stdout=out,stderr=subprocess.STDOUT,check=True,timeout=600)
    counts = Counter(c['type'] for c in json.loads((root/'mapped.json').read_text())['modules']['fifo_probe']['cells'].values())
    coverage = check(json.loads((root/'coverage.json').read_text()),[
        {'type':'SLICE_FFX','port':'D','class':'register_input'},
        {'type':'SLICE_FFX','port':'Q','class':'register_output'}])
    if not coverage['endpoint_requirements_met'] or any(k.startswith(('RAM','SRL','DSP')) for k in counts):
        raise ValueError('unexpected or unmodeled sequential primitive')
    result = {'module':module[1], 'width':width, 'depth':args.depth, 'seed':args.seed,
        'counts':dict(counts),'LUT':sum(v for k,v in counts.items() if re.fullmatch('LUT[1-6]',k)),
        'FF':sum(v for k,v in counts.items() if k.startswith('FD')),
        'fmax':json.loads((root/'timing.json').read_text())['fmax'],
        'critical_paths':critical_paths((root/'route.log').read_text()),'coverage':coverage,
        'inputs':{str(p):sha(p) for p in [args.rtl,args.yosys,args.nextpnr,args.chipdb,Path(__file__)]},
        'commands':commands, 'scope':'Isolated FIFO plus preserved fabric registers; partial native timing, not a board clock.'}
    (root/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ['width','depth','LUT','FF','fmax']}),flush=True)


def main() -> None:
    """Require retained RTL, pinned physical tools and a fresh output directory."""
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('rtl','yosys','nextpnr','chipdb','stage'):
        parser.add_argument('--'+name,type=lambda p:Path(p).resolve(),required=True)
    parser.add_argument('--width',type=int,default=424)
    parser.add_argument('--depth',type=int,default=1)
    parser.add_argument('--seed',type=int,default=1)
    args=parser.parse_args()
    if min(args.width,args.depth,args.seed)<1: parser.error('width, depth and seed must be positive')
    run(args)


if __name__=='__main__':
    main()
