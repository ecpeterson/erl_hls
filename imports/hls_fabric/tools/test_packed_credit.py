#!/usr/bin/env python3
"""Measure packed production bridges with opaque traffic and independent credits."""
import argparse
import json
from pathlib import Path
from backend_paths import PUBLIC
import re
import shutil

from test_credit_link import ROOT, digest, run
from test_credit_service import summarize
from transport_codegen import specialize


def wrapper(words: int, credits: int, compact: bool = False) -> str:
    """Bind eight symmetric lanes to a selected packed width and reserved window."""
    return f'''// Opaque frames over an explicitly sized packed physical boundary.
import axis;
import hls_packed_link;
pub proc Top {{
  config(link_in: chan<bits[{words * 34}]> in, link_out: chan<bits[{words * 34}]> out,
         frames_in: chan<axis::Frame>[8] in, frames_out: chan<axis::Frame>[8] out,
         fault_out: chan<u32> out) {{
    spawn hls_packed_link::Bridge<u32:8,u32:8,u16:0x4850,u32:{words},u32:{credits}{',true' if compact else ''}>(
      link_in,link_out,frames_in,frames_out,fault_out); ()
  }}
  init {{ () }}
  next(state: ()) {{ state }}
}}
'''


def compile_link(xls: Path, public: Path, stage: Path, words: int, credits: int, compact: bool = False) -> dict:
    """Compile a fresh bridge, or reuse only a complete digest-matched build."""
    tracked = [ROOT/'priv/xls/hls_packed_link.x', public/'priv/xls/lib/axis.x', Path(__file__), ROOT/'tools/transport_codegen.py',
               *[xls/name for name in ('ir_converter_main', 'opt_main', 'codegen_main')],
               *sorted((xls/'xls/dslx/stdlib').rglob('*.x'))]
    inputs = {'words': words, 'credits': credits, 'compact': compact, 'sources': {str(p): digest(p) for p in tracked}}
    stamp = stage/'build.json'
    if stamp.exists():
        record = json.loads(stamp.read_text())
        if record['inputs'] != inputs or record['rtl_sha256'] != digest(stage/'bridge.v'):
            raise ValueError('packed-link inputs or completed RTL changed')
        return record
    stage.mkdir(parents=True, exist_ok=False)
    for path in tracked[:2]:
        shutil.copy(path, stage/path.name)
    (stage/'top.x').write_text(wrapper(words, credits, compact))
    commands = [
        ([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false', '--dslx_path=.',
          f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', 'top.x'], 'convert', 'bridge.ir'),
        ([str(xls/'opt_main'), 'bridge.ir'], 'optimize', 'bridge.opt.ir'),
        ([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
          '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
          '--module_name=packed_link', 'bridge.opt.ir'], 'codegen', 'bridge.v')]
    for command, name, output in commands:
        run(command, stage, name, output)
    specialize(xls/'codegen_main', stage/'bridge.opt.ir', stage/'bridge.v', stage/'adapters')
    if inputs['sources'] != {str(p): digest(p) for p in tracked}:
        raise ValueError('packed-link inputs changed while compiling')
    record = {'inputs': inputs, 'commands': [c for c, _, _ in commands],
              'rtl_sha256': digest(stage/'bridge.v')}
    stamp.write_text(json.dumps(record, indent=2)+'\n')
    return record


def testbench(path: Path) -> str:
    """Bind the same generated ports to each boundary-level testbench."""
    ports = []
    for lane in range(8):
        ports += [f'._frames_in__{lane}(frames[device][{lane}]), ._frames_in__{lane}_vld(frame_valid[device][{lane}]), ._frames_in__{lane}_rdy(frame_ready[device][{lane}])',
                  f'._frames_out__{lane}(delivered[device][{lane}]), ._frames_out__{lane}_vld(delivered_valid[device][{lane}]), ._frames_out__{lane}_rdy(delivered_ready[device][{lane}])']
    return path.read_text().replace('@@CONNECTIONS@@', ',\n      '.join(ports))


def faults(stage: Path, words: int, credits: int, compact: bool = False) -> dict:
    """Require each malformed prefix/header/termination/credit to fault until reset."""
    path = ROOT/'test/rtl/packed_credit_fault_tb.sv'
    (stage/'fault-test.sv').write_text(testbench(path))
    run(['iverilog', '-g2012', '-s', 'packed_credit_fault_tb',
         f'-Ppacked_credit_fault_tb.WORDS={words}', f'-Ppacked_credit_fault_tb.CREDITS={credits}',
         f'-Ppacked_credit_fault_tb.COMPACT={int(compact)}',
         '-o', 'fault.vvp', 'fault-test.sv', 'bridge.v'], stage, 'fault-compile')
    run(['vvp', 'fault.vvp'], stage, 'fault')
    log = (stage/'fault.log').read_text()
    if 'PASS:' not in log:
        raise ValueError('incomplete framing fault tests')
    print(log, end='', flush=True)
    return {'testbench_sha256': digest(stage/'fault-test.sv'), 'log_sha256': digest(stage/'fault.log')}


def simulate(stage: Path, words: int, credits: int, active: int, delay: int,
             stalls: bool = False, block: bool = False, restart: bool = False, pattern: int = 0) -> dict:
    """Require exact wire/delivery order, reserved credits, fair progress and complete drain."""
    (stage/'test.sv').write_text(testbench(ROOT/'test/rtl/packed_credit_service_tb.sv'))
    parameters = dict(WORDS=words, CREDITS=credits, ACTIVE=active, DELAY=delay,
                      STALLS=int(stalls), BLOCK=int(block), RESTART=int(restart), PATTERN=pattern)
    name = '-'.join(f'{k.lower()}{v}' for k, v in parameters.items())
    run(['iverilog', '-g2012', '-s', 'packed_credit_service_tb',
         *[f'-Ppacked_credit_service_tb.{k}={v}' for k, v in parameters.items()],
         '-o', 'test.vvp', 'test.sv', 'bridge.v'], stage, name+'-compile')
    run(['vvp', 'test.vvp'], stage, name)
    log = (stage/f'{name}.log').read_text()
    bins = [dict(zip(('device', 'bin', 'cycles', 'words', 'beats', 'frames', 'blocked'), map(int, m)))
            for m in re.findall(r'METRIC device=(\d+) bin=(\d+) cycles=(\d+) words=(\d+) beats=(\d+) frames=(\d+) blocked=(\d+)', log)]
    if 'PASS:' not in log or len(bins) != 16:
        raise ValueError(f'incomplete packed-link experiment: {name}')
    latency = [dict(zip(('device', 'input_to_wire_cycles', 'wire_to_delivery_cycles'), map(int, row)))
               for row in re.findall(r'LATENCY device=(\d+) input_to_wire=(\d+) wire_to_delivery=(\d+)', log)]
    if len(latency) != 2:
        raise ValueError('missing packed-link boundary latencies')
    result = {'parameters': parameters, 'bins': bins, 'first_frame_latency': latency,
              'testbench_sha256': digest(stage/'test.sv'), 'log_sha256': digest(stage/f'{name}.log'),
              'word_capacity_utilization': summarize([b['words']/(words*b['cycles']) for b in bins]),
              'frames_per_cycle': summarize([b['frames']/b['cycles'] for b in bins]),
              'transfer_utilization': summarize([b['beats']/b['cycles'] for b in bins])}
    print(name, result['word_capacity_utilization'], flush=True)
    return result


def service_cases(quick: bool = False, regression: bool = False) -> list[tuple[int, int]]:
    """Select load/latency probes; callers always add stalled/reset and fault checks."""
    if quick:
        return [(8, 2)]
    if regression:
        return [(1, 0), (1, 64), (8, 0), (8, 64), (2, 2), (4, 16)]
    return [(active, delay) for active in (1, 2, 4, 8) for delay in (0, 2, 16, 64)]


def main() -> None:
    """Sweep small bridge builds before committing to complete-mesh recompilation."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('xls', type=Path)
    p.add_argument('--erl-hls', type=Path, default=PUBLIC)
    p.add_argument('--stage', type=Path, required=True)
    p.add_argument('--configs', nargs='+', default=['1:1', '1:4', '2:4', '4:4', '4:8'])
    sweep = p.add_mutually_exclusive_group()
    sweep.add_argument('--quick', action='store_true', help='run one saturated control plus stalled/reset isolation')
    sweep.add_argument('--regression', action='store_true',
                       help='cover load/latency boundaries and interior points without the full performance grid')
    p.add_argument('--compact', action='store_true', help='exercise compact lengths and metadata extensions, including header-only traffic')
    a = p.parse_args()
    configs = [tuple(map(int, c.split(':'))) for c in a.configs]
    if any(w not in (1, 2, 4) or c not in (1, 2, 4, 8, 16) for w, c in configs):
        p.error('configurations are WORDS:CREDITS with WORDS=1/2/4 and CREDITS=1/2/4/8/16')
    a.stage.mkdir(parents=True, exist_ok=True)
    for words, credits in configs:
        stage = a.stage/(f'words-{words}-credits-{credits}' + ('-compact' if a.compact else ''))
        record = compile_link(a.xls.resolve(), a.erl_hls.resolve(), stage.resolve(), words, credits, a.compact)
        cases = service_cases(a.quick, a.regression)
        rows = [simulate(stage, words, credits, active, delay, pattern=int(a.compact)) for active, delay in cases]
        rows.append(simulate(stage, words, credits, 8, 2, stalls=True, block=True, restart=True, pattern=int(a.compact)))
        if a.compact:
            rows += [simulate(stage, words, credits, active, 2, pattern=2) for active in (1, 8)]
            rows.append(simulate(stage, words, credits, 8, 2, pattern=0))
        record['results'] = rows
        record['faults'] = faults(stage, words, credits, a.compact)
        (stage/'service.json').write_text(json.dumps(record, indent=2)+'\n')


if __name__ == '__main__':
    main()
