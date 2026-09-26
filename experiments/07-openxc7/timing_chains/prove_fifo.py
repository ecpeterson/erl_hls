#!/usr/bin/env python3
"""Check live FIFO data and handshakes for all inputs over a bounded reset history."""
import argparse
import json
from pathlib import Path
import subprocess
from fifo_experiment import MODULE, ports, sha


def run(args: argparse.Namespace) -> None:
    """Exhaustively compare a selected generated FIFO for twelve symbolic cycles."""
    modules = [{m[1]:m[0] for m in MODULE.finditer(path.read_text())}
               for path in (args.baseline,args.candidate)]
    names = [n for n in modules[0] if n.startswith(f'fifo_for_depth_{args.depth}_')
             and ports(modules[0][n]).get('push_data')==f'input[{args.width-1}:0]']
    if not names or names[0] not in modules[1]: raise ValueError('missing corresponding FIFO')
    name=names[0]
    if ports(modules[0][name]) != ports(modules[1][name]): raise ValueError('FIFO ports differ')
    args.stage.mkdir(parents=True,exist_ok=False)
    for module,label in zip(modules,('reference','candidate')):
        (args.stage/(label+'.v')).write_text(module[name].replace('module '+name+'(', 'module '+label+'(')+'\n')
    w=args.width
    lines=[f'module fifo_equivalence(input wire clk, reset, push_valid, pop_ready, input wire [{w-1}:0] push_data, output wire ok);']
    for label in ('reference','candidate'):
        lines += [f'wire {label}_ready, {label}_valid;',f'wire [{w-1}:0] {label}_data;',
            f'{label} fifo_{label}(.clk(clk),.reset(reset),.push_valid(push_valid),.pop_ready(pop_ready),.push_data(push_data),.push_ready({label}_ready),.pop_valid({label}_valid),.pop_data({label}_data));']
    lines += ['assign ok = reset || ((reference_ready == candidate_ready) && (reference_valid == candidate_valid) && (!reference_valid || (reference_data == candidate_data)));','endmodule']
    (args.stage/'miter.v').write_text('\n'.join(lines)+'\n')
    script='read_verilog -sv reference.v candidate.v miter.v\nprep -top fifo_equivalence -flatten\nmemory_map\nopt\ndffunmap\nsat -verify -seq 12 -prove ok 1 -prove-skip 1 -set-def-inputs -set-at 1 reset 1\n'
    (args.stage/'check.ys').write_text(script)
    command=[str(args.yosys),'-Q','-T','-s','check.ys']
    with (args.stage/'check.log').open('w') as log:subprocess.run(command,cwd=args.stage,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=300)
    if 'SUCCESS!' not in (args.stage/'check.log').read_text(): raise ValueError('SAT check did not finish')
    result={'cycles':12,'first_cycle_reset':True,'later_reset_unrestricted':True,'width':w,'depth':args.depth,
        'scope':'Bounded check, not an unbounded equivalence proof; invalid payloads are ignored.',
        'module':name,'inputs':{str(p):sha(p) for p in [args.baseline,args.candidate,args.yosys,Path(__file__)]},'command':command}
    (args.stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: twelve symbolic cycles, live payloads and both handshakes',flush=True)


def main() -> None:
    """Require exact generated RTL inputs and a fresh proof directory."""
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('baseline','candidate','yosys','stage'):parser.add_argument('--'+name,type=lambda p:Path(p).resolve(),required=True)
    parser.add_argument('--width',type=int,default=424);parser.add_argument('--depth',type=int,default=1)
    args=parser.parse_args()
    if min(args.width,args.depth)<1:parser.error('width and depth must be positive')
    run(args)


if __name__=='__main__':main()
