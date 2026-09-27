#!/usr/bin/env python3
"""Screen explicit reciprocal-product pipeline cuts without claiming routed timing."""
import argparse
from collections import Counter
import functools
import json
from pathlib import Path
import random
import shutil
import subprocess
import sys

from architecture import sha

ROOT = Path(__file__).resolve().parents[3]


def run(argv: list[str], root: Path, label: str, output: str | None = None) -> None:
    """Retain the exact command and diagnostics; fail on errors or a five-minute timeout."""
    (root / f'{label}.command.json').write_text(json.dumps(argv) + '\n')
    with (root / (output or f'{label}.log')).open('w') as out, (root / f'{label}.stderr').open('w') as err:
        subprocess.run(argv, cwd=root, stdout=out, stderr=err, check=True, timeout=300)


def wrapper(split: bool) -> str:
    """Give both arithmetic variants three enabled cycles and the same valid/reset contract."""
    logic = '''wire [479:0] p; wire [159:0] r; wire [36:0] q;
reg [479:0] p_reg; reg [159:0] r_reg;
products p_dut(.n(n), .out(p));
reduce r_dut(.rows(p_reg), .out(r));
finish f_dut(.rows(r_reg), .out(q));
always @(posedge clk) if (enable) begin
  p_reg <= p; r_reg <= r; out <= q;
end''' if split else '''wire [36:0] q; reg [36:0] q0, q1;
reference r_dut(.n(n), .out(q));
always @(posedge clk) if (enable) begin
  q0 <= q; q1 <= q0; out <= q1;
end'''
    return f'''// Three-stage fixed-latency experiment. Global enable stalls every stage.
// Reset flushes validity; payload bits while invalid are unspecified.
module kernel(input wire clk, reset, enable, in_valid,
  input wire [36:0] n, output reg [36:0] out, output wire out_valid);
reg [2:0] valid = 0;
always @(posedge clk) begin
  if (reset) valid <= 0;
  else if (enable) valid <= {{valid[1:0], in_valid}};
end
assign out_valid = valid[2];
{logic}
endmodule
'''


def vectors() -> list[int]:
    """Cover extremes, ties, limb transitions and reproducible random full-width inputs."""
    low, high = -(1 << 36), (1 << 36) - 1
    values = list(range(-65536, 65537))
    for base in (low, high, *[sign * (1 << bit) for bit in (17, 24, 34, 35) for sign in (-1, 1)]):
        values += [base + d for d in range(-25, 26) if low <= base + d <= high]
    rng = random.Random(260927)
    values += [rng.randint(low, high) for _ in range(30000)]
    return values


def verify(stage: Path, cells: Path | None = None) -> dict:
    """Compare pipelined RTL with independent integer rounding, including flushes and stalls."""
    cases = vectors()
    mask = (1 << 37) - 1
    encoded = []
    for n in cases:
        rounded = ((abs(n) + 6) // 12) * (-1 if n < 0 else 1)
        encoded.append(f'{((n & mask) << 37) | (rounded & mask):019x}')
    (stage / 'vectors.hex').write_text('\n'.join(encoded) + '\n')
    testbench = '''module testbench;
reg clk = 0; always #5 clk = !clk;
reg reset = 1, enable = 0, in_valid = 0; reg [36:0] n;
wire [36:0] out; wire out_valid;
kernel dut(.*);
reg [73:0] cases[0:COUNT-1];
reg [36:0] expected[0:2]; reg [2:0] valid = 0;
integer i = 0, cycle = 0, checked = 0, stalled = 0, flushed = 0;
reg [31:0] rng = 32'h3e97ac14;
initial begin
  $readmemh("vectors.hex", cases);
  repeat (COUNT*3) begin
    @(negedge clk);
    rng = {rng[30:0], rng[31]^rng[21]^rng[1]^rng[0]};
    reset = cycle == 0 || cycle % 10007 == 10006;
    enable = rng[3:0] != 0;
    in_valid = i < COUNT && rng[7:4] != 0;
    n = i < COUNT ? cases[i][73:37] : 0;
    @(posedge clk);
    if (reset) begin valid = 0; flushed = flushed + 1; end
    else if (enable) begin
      expected[2] = expected[1]; expected[1] = expected[0];
      expected[0] = i < COUNT ? cases[i][36:0] : 0;
      valid = {valid[1:0], in_valid};
      if (in_valid) i = i + 1;
    end else stalled = stalled + 1;
    #1;
    if (out_valid !== valid[2]) $fatal(1,"valid mismatch cycle %0d",cycle);
    if (out_valid && out !== expected[2])
      $fatal(1,"value mismatch cycle %0d: %h != %h",cycle,out,expected[2]);
    if (out_valid && enable && !reset) checked = checked + 1;
    if (i == COUNT && valid == 0) begin
      $display("PASS inputs=%0d checked=%0d stalls=%0d resets=%0d cycles=%0d",i,checked,stalled,flushed,cycle);
      $finish;
    end
    cycle = cycle + 1;
  end
  $fatal(1,"timeout");
end
endmodule
'''.replace('COUNT', str(len(cases)))
    (stage / 'testbench.sv').write_text(testbench)
    results = {}
    for name in ('reference', 'split'):
        root = stage / name
        sources = ([str(stage / 'mapped-check' / (name + '.v')), str(cells)] if cells else
                   [str(p) for p in sorted(root.glob('*.v'))])
        label = ('mapped-' if cells else '') + name
        argv = ['iverilog', '-g2012', '-s', 'testbench', '-o', str(stage / 'sim.vvp'),
                str(stage / 'testbench.sv'), *sources]
        run(argv, stage, f'{label}-iverilog')
        run(['vvp', str(stage / 'sim.vvp')], stage, f'{label}-simulation')
        result = (stage / f'{label}-simulation.log').read_text().splitlines()[0]
        if not result.startswith('PASS '):
            raise ValueError(result)
        results[name] = result
    (stage / 'sim.vvp').unlink()
    return {'inputs': len(cases), 'results': results, 'evidence': 'RTL simulation witnesses'}


def verify_mapped(args: argparse.Namespace, cells: Path) -> dict:
    """Exercise the synthesized pipeline, including DSP internal-register packing."""
    root = args.stage / 'mapped-check'
    root.mkdir()
    for name in ('reference', 'split'):
        mapped = args.stage / name / 'mapped.json'
        (root / f'{name}.ys').write_text(f'read_verilog -lib {cells}\nread_json {mapped}\n'
            f'write_verilog -noattr {name}.v\n')
        run([str(args.yosys), '-Q', '-T', '-s', f'{name}.ys'], root, name)
    return verify(args.stage, cells)


def dsp_depth(top: dict) -> int:
    """Upper-bound serial DSPs between fabric registers; ignore internal DSP registers conservatively."""
    drivers = {}
    cells = top['cells']
    for name, cell in cells.items():
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    if isinstance(bit, int):
                        if bit in drivers:
                            raise ValueError('multiple drivers')
                        drivers[bit] = name
    active = set()

    @functools.cache
    def depth(name: str) -> int:
        """Count DSPs along conservative all-input-to-all-output combinational cell edges."""
        cell = cells[name]
        if cell['type'].startswith('FD'):
            return 0
        if name in active:
            raise ValueError('unexpected combinational cycle')
        active.add(name)
        dependencies = {drivers[b] for p, bits in cell['connections'].items()
                        if cell['port_directions'][p] == 'input'
                        for b in bits if b in drivers}
        value = int(cell['type'] == 'DSP48E1') + max((depth(n) for n in dependencies), default=0)
        active.remove(name)
        return value

    return max((depth(n) for n in cells), default=0)


def map_kernel(args: argparse.Namespace, name: str) -> dict:
    """Map the entire pipeline, retain EDIF, and inspect surviving DSP/register boundaries."""
    root = args.stage / name
    rtl = ' '.join(p.name for p in sorted(root.glob('*.v')))
    (root / 'map.ys').write_text(f'read_verilog {rtl}\n'
        + packing_policy(args, name) +
        'synth_xilinx -flatten -abc9 -nosrl -family xc7 -noiopad -noclkbuf -top kernel\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n'
        'write_edif -pvector bra mapped.edf\n')
    run([str(args.yosys), '-Q', '-T', '-s', 'map.ys'], root, 'map')
    data = json.loads((root / 'mapped.json').read_text())
    top = data['modules']['kernel']
    counts = Counter(c['type'] for c in top['cells'].values())
    dsps = {n: {k: int(v, 2) for k, v in c['parameters'].items() if k.endswith('REG')}
            for n, c in top['cells'].items() if c['type'] == 'DSP48E1'}
    data['modules'] = {'kernel': top}
    (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    return {'cells': dict(counts), 'luts': sum(n for k, n in counts.items() if k.startswith('LUT')),
            'dsp_registers': dsps, 'serial_dsp_upper_bound': dsp_depth(top),
            'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}}


def packing_policy(args: argparse.Namespace, name: str) -> str:
    """Keep candidate cuts in fabric unless explicitly testing DSP-register absorption."""
    return ('scratchpad -set xilinx_dsp.multonly 1\n'
            if name == 'split' and not args.pack_candidate_registers else '')


def prepare_vendor(args: argparse.Namespace) -> None:
    """Wrap all inputs/outputs in preserved registers for the existing physical-report workflow."""
    sys.path.insert(0, str(ROOT / 'experiments/07-openxc7'))
    from timing_model.characterize import harness
    corpus = args.stage / 'vendor'
    corpus.mkdir()
    probes = []
    for name in ('reference', 'split'):
        root = corpus / name
        root.mkdir()
        for source in (args.stage / name).glob('*.v'):
            shutil.copyfile(source, root / source.name)
        source = harness('kernel', [('n', 37), ('reset', 1), ('enable', 1), ('in_valid', 1)], 38)
        source = source.replace('kernel dut(', 'kernel dut(.clk(clock), ')
        source = source.replace('.out(value));', '.out(value[36:0]), .out_valid(value[37]));')
        (root / 'harness.v').write_text(source)
        rtl = ' '.join(p.name for p in sorted(root.glob('*.v')))
        (root / 'map.ys').write_text(f'read_verilog {rtl}\n'
            + packing_policy(args, name) +
            'synth_xilinx -flatten -abc9 -nosrl -family xc7 -noiopad -noclkbuf -top probe_top\n'
            'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n'
            'write_edif -pvector bra mapped.edf\n')
        run([str(args.yosys), '-Q', '-T', '-s', 'map.ys'], root, 'map')
        data = json.loads((root / 'mapped.json').read_text())
        top = data['modules']['probe_top']
        boundaries = [c for c in top['cells'].values() if c.get('attributes', {}).get('dont_touch') == 'yes']
        if len(boundaries) != 78 or any(c['type'] != 'FDRE' for c in boundaries):
            raise ValueError('launch/capture boundary was not preserved')
        data['modules'] = {'probe_top': top}
        (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
        probes.append({'name': name, 'split': 'validation',
            'cells': dict(Counter(c['type'] for c in top['cells'].values())),
            'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
    (corpus / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
        'flow': 'synth_xilinx -abc9 -nosrl', 'probes': probes}, indent=2) + '\n')


def main() -> None:
    """Compile a fresh fixed-width arithmetic screen with explicit tools and exact input hashes."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'xls', 'yosys'):
        parser.add_argument('--' + name, type=lambda s: Path(s).resolve(), required=True)
    parser.add_argument('--pack-candidate-registers', action='store_true',
                        help='diagnostic: allow DSP register absorption; mapped simulation must still pass')
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=False)
    cells = args.yosys.parent.parent / 'share/yosys/xilinx/cells_sim.v'
    sources = [Path(__file__), Path(__file__).with_suffix('.x'), ROOT / 'priv/xls/lib/hls_fixed.x',
               ROOT / 'priv/xls/lib/hls_multiply.x', cells,
               cells.with_name('cells_map.v'), cells.with_name('xc7_dsp_map.v'),
               ROOT / 'experiments/07-openxc7/timing_model/characterize.py']
    tools = [args.yosys, *[args.xls / n for n in ('ir_converter_main', 'opt_main', 'codegen_main')],
             *[Path(shutil.which(n)) for n in ('iverilog', 'vvp')]]
    identities = {str(p): sha(p) for p in sources + tools}
    for name, functions in (('reference', ('reference',)), ('split', ('products', 'reduce', 'finish'))):
        root = args.stage / name
        root.mkdir()
        shutil.copyfile(Path(__file__).with_suffix('.x'), root / 'staged_reciprocal.x')
        for library in ('hls_fixed.x', 'hls_multiply.x'):
            shutil.copyfile(ROOT / 'priv/xls/lib' / library, root / library)
        for function in functions:
            for label, argv, output in (
                    ('convert', [str(args.xls / 'ir_converter_main'), '--top=' + function, '--dslx_path=.',
                        '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), 'staged_reciprocal.x'], function + '.ir'),
                    ('opt', [str(args.xls / 'opt_main'), function + '.ir'], function + '.opt.ir'),
                    ('codegen', [str(args.xls / 'codegen_main'), '--generator=combinational',
                        '--use_system_verilog=false', '--module_name=' + function, function + '.opt.ir'], function + '.v')):
                run(argv, root, function + '-' + label, output)
        (root / 'kernel.v').write_text(wrapper(name == 'split'))
    verification = verify(args.stage)
    rows = {}
    for name in ('reference', 'split'):
        rows[name] = map_kernel(args, name)
        print(name, rows[name]['cells'], 'DSP depth', rows[name]['serial_dsp_upper_bound'], flush=True)
    mapped_verification = verify_mapped(args, cells)
    prepare_vendor(args)
    if identities != {str(p): sha(p) for p in sources + tools}:
        raise ValueError('inputs changed during run')
    (args.stage / 'summary.json').write_text(json.dumps({'inputs': identities, 'verification': verification,
        'mapped_verification': mapped_verification,
        'measurements': rows, 'scope': 'isolated arithmetic pipeline; no routed or application timing claim',
        'candidate_register_packing': args.pack_candidate_registers,
        'latency_enabled_cycles': 3, 'initiation_interval': 1}, indent=2) + '\n')


if __name__ == '__main__':
    main()
