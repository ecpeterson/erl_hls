#!/usr/bin/env python3
"""Compare adapter boundary latency and prove a directly connected pair has no combinational cycles."""
import argparse
import json
from pathlib import Path
import re

from test_actor_rtl import digest, execute
from test_packed_credit import simulate
from transport_codegen import replace_module


def paired_endpoints(words: int) -> str:
    """Connect both data/credit directions without inserting any testbench storage."""
    lines = ['module packed_pair(input wire clk, reset, input wire [2047:0] frames,',
             'input wire [15:0] frame_valid, output wire [15:0] frame_ready,',
             'output wire [2047:0] delivered, output wire [15:0] delivered_valid,',
             'input wire [15:0] delivered_ready, output wire [63:0] faults, output wire [1:0] fault_valid);']
    for d in range(2):
        lines += [f'wire [{words*34-1}:0] link_{d};', f'wire valid_{d}, ready_{d};']
    for d in range(2):
        ports = ['.clk(clk)', '.reset(reset)', f'._link_in(link_{1-d})',
                 f'._link_in_vld(valid_{1-d})', f'._link_in_rdy(ready_{1-d})',
                 f'._link_out(link_{d})', f'._link_out_vld(valid_{d})', f'._link_out_rdy(ready_{d})',
                 f'._fault_out(faults[{32*d}+:32])', f'._fault_out_vld(fault_valid[{d}])', '._fault_out_rdy(1\'b1)']
        for lane in range(8):
            i = 8*d+lane
            ports += [f'._frames_in__{lane}(frames[{128*i}+:128])',
                      f'._frames_in__{lane}_vld(frame_valid[{i}])', f'._frames_in__{lane}_rdy(frame_ready[{i}])',
                      f'._frames_out__{lane}(delivered[{128*i}+:128])',
                      f'._frames_out__{lane}_vld(delivered_valid[{i}])', f'._frames_out__{lane}_rdy(delivered_ready[{i}])']
        lines.append(f'packed_link endpoint_{d}('+',\n'.join(ports)+');')
    return '\n'.join([*lines, 'endmodule', ''])


def loop_check(stage: Path, words: int, yosys: str) -> dict:
    """Check the composed ready/valid graph, including feedback that crosses endpoint ports."""
    wrapper = stage/'pair.v'
    wrapper.write_text(paired_endpoints(words))
    script = stage/'pair.ys'
    script.write_text('read_verilog -sv bridge.v pair.v\nhierarchy -check -top packed_pair\n'
                      'proc\nflatten\nopt\ncheck -assert\nscc -expect 0\n')
    execute([yosys, '-Q', '-T', '-s', str(script)], stage, 'pair', timeout=180)
    return {'wrapper_sha256': digest(wrapper), 'script_sha256': digest(script), 'log_sha256': digest(stage/'pair.log')}


def module(rtl: str, kind: str) -> tuple[str, str]:
    """Require a single adapter of the selected kind in the symmetric eight-lane fixture."""
    match, = re.finditer(r'^module (__hls_packed_link__'+kind+r'_\w+)\(.*?^endmodule', rtl, re.M | re.S)
    return match[1], match[0]


def measure(original: Path, updated: Path, stage: Path, yosys: str) -> dict:
    """Isolate receive forwarding, transmit forwarding with credit retiming, and their combination."""
    before, after = original.read_text(), updated.read_text()
    receive_name, old_receive = module(before, 'Deliver')
    new_receive_name, new_receive = module(after, 'Deliver')
    if receive_name != new_receive_name:
        raise ValueError('adapter module names differ across builds')
    variants = {'baseline': before, 'receive': replace_module(before, receive_name, new_receive),
                'transmit': replace_module(after, receive_name, old_receive), 'combined': after}
    report = {'inputs': {str(p): digest(p) for p in (original, updated, Path(__file__))},
              'scope': 'Eight lanes, four 32-bit words per transfer, four credits, 8 ns clock; first unstalled frame after reset.',
              'variants': {}}
    stage.mkdir(parents=True, exist_ok=False)
    for name, rtl in variants.items():
        path = stage/name
        path.mkdir()
        (path/'bridge.v').write_text(rtl)
        checks = loop_check(path, 4, yosys)
        result = simulate(path, 4, 4, 1, 0)
        report['variants'][name] = {'rtl_sha256': digest(path/'bridge.v'), 'combinational': checks, **result}
        print(name, result['first_frame_latency'], flush=True)
        (stage/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=Path)
    parser.add_argument('updated', type=Path)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    measure(args.original.resolve(), args.updated.resolve(), args.stage.resolve(), args.yosys)
