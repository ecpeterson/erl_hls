"""Compile packed links and collect finite boundary-level service and framing witnesses."""
import json
from pathlib import Path
import re
import shutil
import statistics

from backend_paths import ROOT
from backend_commands import digest, execute
from transport_codegen import specialize


def summarize(values: list[float]) -> dict:
    """Summarize nonempty throughput windows; larger values are better."""
    return {'samples': len(values), 'best': max(values), 'mean': statistics.mean(values),
            'variance': statistics.pvariance(values), 'worst': min(values)}


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
    tracked = [ROOT/'apps/hls_lowering/priv/xls/hls_packed_link.x', public/'priv/xls/lib/axis.x', public/'priv/xls/lib/frame_config.x', Path(__file__),
               ROOT/'tools/hls_fabric/test_packed_credit.py', ROOT/'tools/hls_fabric/backend_commands.py',
               ROOT/'tools/hls_fabric/transport_codegen.py',
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
    for path in tracked[:3]:
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
        execute(command, stage, name, timeout=600, output=stage / output)
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
    path = ROOT/'apps/hls_fabric/test/rtl/packed_credit_fault_tb.sv'
    (stage/'fault-test.sv').write_text(testbench(path))
    execute(['iverilog', '-g2012', '-s', 'packed_credit_fault_tb',
         f'-Ppacked_credit_fault_tb.WORDS={words}', f'-Ppacked_credit_fault_tb.CREDITS={credits}',
         f'-Ppacked_credit_fault_tb.COMPACT={int(compact)}',
         '-o', 'fault.vvp', 'fault-test.sv', 'bridge.v'], stage, 'fault-compile', timeout=600)
    execute(['vvp', 'fault.vvp'], stage, 'fault', timeout=600)
    log = (stage/'fault.log').read_text()
    if 'PASS:' not in log:
        raise ValueError('incomplete framing fault tests')
    print(log, end='', flush=True)
    return {'testbench_sha256': digest(stage/'fault-test.sv'), 'log_sha256': digest(stage/'fault.log')}


def simulate(stage: Path, words: int, credits: int, active: int, delay: int,
             stalls: bool = False, block: bool = False, restart: bool = False, pattern: int = 0) -> dict:
    """Require exact wire/delivery order, reserved credits, fair progress and complete drain."""
    (stage/'test.sv').write_text(testbench(ROOT/'apps/hls_fabric/test/rtl/packed_credit_service_tb.sv'))
    parameters = dict(WORDS=words, CREDITS=credits, ACTIVE=active, DELAY=delay,
                      STALLS=int(stalls), BLOCK=int(block), RESTART=int(restart), PATTERN=pattern)
    name = '-'.join(f'{k.lower()}{v}' for k, v in parameters.items())
    execute(['iverilog', '-g2012', '-s', 'packed_credit_service_tb',
         *[f'-Ppacked_credit_service_tb.{k}={v}' for k, v in parameters.items()],
         '-o', 'test.vvp', 'test.sv', 'bridge.v'], stage, name+'-compile', timeout=600)
    execute(['vvp', 'test.vvp'], stage, name, timeout=600)
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
