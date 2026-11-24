#!/usr/bin/env python3
"""Measure full-duplex bridge service while varying active lanes and wire latency."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_resource, compiler_root
import re
import shutil

from backend_paths import ROOT
from backend_commands import digest, execute
from link_service_witness import summarize


def measure(xls: Path, public: Path, stage: Path) -> dict:
    """Build once and require ordered drain in twenty controlled bidirectional workloads."""
    stage.mkdir(parents=True, exist_ok=False)
    source = ROOT/'apps/hls_target/priv/xls/hls_credit_link.x'
    axis = compiler_resource(public, 'hls_compile', 'priv/xls/lib/axis.x')
    frame_config = compiler_resource(public, 'hls_compile', 'priv/xls/lib/frame_config.x')
    template = ROOT/'apps/hls_fabric/test/rtl/credit_service_tb.sv'
    tracked = [source, axis, frame_config, template, Path(__file__), ROOT/'tools/hls_fabric/link_service_witness.py',
               ROOT/'tools/hls_fabric/backend_commands.py',
               *[xls/name for name in ('ir_converter_main', 'opt_main', 'codegen_main')],
               *(xls/'xls/dslx/stdlib').rglob('*.x')]
    inputs = {str(p): digest(p) for p in tracked}
    for p in (source, axis, frame_config): shutil.copy(p, stage/p.name)
    wrapper = '''// Eight independent lanes in each direction, using the production bridge.
import axis;
import hls_credit_link;
pub proc Top {
  config(link_in: chan<axis::Beat> in, link_out: chan<axis::Beat> out,
         frames_in: chan<axis::Frame>[8] in, frames_out: chan<axis::Frame>[8] out,
         fault_out: chan<u32> out) {
    spawn hls_credit_link::Bridge<u32:8,u32:8,u16:0x4850>(link_in,link_out,frames_in,frames_out,fault_out);
    ()
  }
  init { () }
  next(state: ()) { state }
}
'''
    (stage/'credit_service.x').write_text(wrapper)
    ports = []
    for lane in range(8):
        ports += [f'._frames_in__{lane}(frames[device][{lane}]), ._frames_in__{lane}_vld(frame_valid[device][{lane}]), ._frames_in__{lane}_rdy(frame_ready[device][{lane}])',
                  f'._frames_out__{lane}(delivered[device][{lane}]), ._frames_out__{lane}_vld(delivered_valid[device][{lane}]), ._frames_out__{lane}_rdy(1\'b1)']
    (stage/'test.sv').write_text(template.read_text().replace('@@CONNECTIONS@@', ',\n      '.join(ports)))
    commands = [
        ([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false', '--dslx_path=.',
          f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', 'credit_service.x'], 'convert', 'bridge.ir'),
        ([str(xls/'opt_main'), 'bridge.ir'], 'optimize', 'bridge.opt.ir'),
        ([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
          '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
          '--module_name=credit_service', 'bridge.opt.ir'], 'codegen', 'bridge.v')]
    for command, name, output in commands: execute(command, stage, name, timeout=600, output=stage / output)
    rows = []
    for active in (1, 2, 4, 8):
        for delay in (0, 2, 8, 16, 64):
            name = f'active-{active}-delay-{delay}'
            execute(['iverilog', '-g2012', '-s', 'credit_service_tb', f'-Pcredit_service_tb.ACTIVE={active}',
                 f'-Pcredit_service_tb.DELAY={delay}', '-o', 'test.vvp', 'test.sv', 'bridge.v'], stage, name+'-compile', timeout=600)
            execute(['vvp', 'test.vvp'], stage, name, timeout=600)
            log = (stage/f'{name}.log').read_text()
            bins = [dict(zip(('device', 'bin', 'cycles', 'words', 'frames', 'blocked'), map(int, m)))
                    for m in re.findall(r'METRIC device=(\d+) bin=(\d+) cycles=(\d+) words=(\d+) frames=(\d+) blocked=(\d+)', log)]
            if 'PASS:' not in log or len(bins) != 16:
                raise ValueError('incomplete service experiment')
            if active == 8 and delay <= 16 and any(b['words'] != b['cycles'] for b in bins):
                raise ValueError('eight saturated lanes lost word-rate service')
            if active == 4 and delay <= 2 and any(b['words']/b['cycles'] < .95 for b in bins):
                raise ValueError('four-lane short-link service regressed')
            row = {'active_lanes': active, 'wire_stages': delay, 'bins': bins,
                   'wire_utilization': summarize([b['words']/b['cycles'] for b in bins]),
                   'frames_per_cycle': summarize([b['frames']/b['cycles'] for b in bins])}
            rows.append(row)
            print(active, delay, row['wire_utilization'], flush=True)
    if inputs != {str(p): digest(p) for p in tracked}: raise ValueError('service inputs changed')
    report = {'inputs': inputs, 'commands': [c for c, _, _ in commands],
              'rtl_sha256': digest(stage/'bridge.v'), 'wrapper_sha256': digest(stage/'credit_service.x'),
              'testbench_sha256': digest(stage/'test.sv'), 'results': rows}
    (stage/'service.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main() -> None:
    """Choose pinned tools and a new directory for all build and simulation evidence."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('xls', type=Path)
    p.add_argument('--erl-hls', type=Path, default=None)
    p.add_argument('--stage', type=Path, required=True)
    a = p.parse_args()
    a.erl_hls = compiler_root("test", a.erl_hls)
    measure(a.xls.resolve(), a.erl_hls.resolve(), a.stage.resolve())


if __name__ == '__main__':
    main()
