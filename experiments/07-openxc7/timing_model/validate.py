#!/usr/bin/env python3
"""Compare equal-depth XLS schedules with streaming RTL checks and native mapping."""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import re
from characterize import run, sha


def source(width: int) -> str:
    """Build a mixed-cost dependency chain, with a bounded unsigned final result."""
    t = f'bits[{width}]'
    rows = [f'package mixed_cost\ntop fn main(' + ', '.join(f'{p}: {t}' for p in 'abcdef') + f') -> {t} {{']
    for index, (name, op, operands) in enumerate([
        ('sum', 'add', 'a, b'), ('difference', 'sub', 'c, d'),
        ('product', 'smul', 'sum, difference'), ('offset', 'add', 'product, e'),
        ('offset2', 'add', 'offset, a'), ('offset3', 'sub', 'offset2, b'),
        ('less', 'ult', 'offset3, f'), ('result', 'sel', 'less, cases=[f, offset3]')], 7):
        rows.append(f"  {'ret ' if name == 'result' else ''}{name}: {'bits[1]' if name == 'less' else t} = {op}({operands}, id={index})")
    return '\n'.join(rows) + '\n}\n'


def testbench(root: Path, width: int, latency: int, iverilog: Path, vvp: Path) -> None:
    """Check every result from a full-rate stream, including overflow and fill/drain."""
    rng = random.Random(260925)
    mask = (1 << width) - 1
    samples = [[0] * 6, [mask] * 6, [1, mask, 0, 1, mask, 1]]
    samples += [[rng.randrange(mask + 1) for _ in range(6)] for _ in range(200)]
    vectors = []
    for a, b, c, d, e, f in samples:
        value = ((a + b) * (c - d) + e + a - b) & mask
        expected = min(value, f)
        packed = 0
        for number in (a, b, c, d, e, f, expected):
            packed = (packed << width) | number
        vectors.append(f'{packed:0{(7*width+3)//4}x}')
    (root / 'vectors.hex').write_text('\n'.join(vectors) + '\n')
    (root / 'testbench.v').write_text(f'''module testbench;
reg clk = 0;
always #5 clk = ~clk;
reg [{width-1}:0] a,b,c,d,e,f;
wire [{width-1}:0] out;
reg [{7*width-1}:0] vectors [0:{len(samples)-1}];
integer i;
operation dut(.clk(clk), .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .out(out));
initial begin
  $readmemh("vectors.hex", vectors);
  for (i=0; i<{len(samples)+latency}; i=i+1) begin
    @(negedge clk);
    {{a,b,c,d,e,f}} = vectors[i%{len(samples)}][{7*width-1}:{width}];
    @(posedge clk); #1;
    if (i >= {latency-1} && i-{latency-1} < {len(samples)})
      if (out !== vectors[i-{latency-1}][{width-1}:0])
        $fatal(1, "stream mismatch at %0d: got %h", i, out);
  end
  $display("PASS {len(samples)} back-to-back results");
  $finish;
end
endmodule
''')
    run([iverilog, '-g2012', '-s', 'testbench', '-o', 'simulation.vvp', 'operation.v', 'testbench.v'], root, 'iverilog')
    run([vvp, 'simulation.vvp'], root, 'simulation')
    (root / 'simulation.vvp').unlink()


def map_pipeline(root: Path, yosys: Path) -> dict:
    """Map a pipeline and define only its unspecified startup bits for timing import."""
    (root / 'map.ys').write_text('read_verilog operation.v harness.v\n'
        'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\nwrite_edif -pvector bra mapped.edf\n')
    run([yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map')
    data = json.loads((root / 'mapped.json').read_text())
    data['modules'] = {'probe_top': data['modules']['probe_top']}
    (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    cells = data['modules']['probe_top']['cells']
    # The pipeline contract starts after fill; define otherwise unspecified startup bits.
    for cell in cells.values():
        for key, value in cell['parameters'].items():
            if key.startswith(('INIT', 'SRVAL')):
                cell['parameters'][key] = value.replace('x', '0')
    (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    run([yosys, '-Q', '-q', '-p',
         'read_verilog -lib +/xilinx/cells_sim.v; read_json mapped.json; write_edif -pvector bra mapped.edf'], root, 'edif')
    return cells


def prepare(args: argparse.Namespace) -> None:
    """Map the same functions at the same latency and II with each chosen model."""
    args.stage.mkdir(parents=True, exist_ok=False)
    rows = []
    for width in (16, 24, 32):
        for model in ('unit', 'xc7_7030'):
            name = f'mixed_{width}_{model}'
            root = args.stage / name
            root.mkdir()
            (root / 'probe.ir').write_text(source(width))
            flags = [f'--delay_model={model}', '--pipeline_stages=3', '--flop_inputs=true',
                     '--flop_outputs=true', '--use_system_verilog=false', '--module_name=operation',
                     '--output_signature_path=signature.textproto', '--output_schedule_path=schedule.textproto']
            if model == 'xc7_7030':
                flags += [f'--xc7_delay_table={args.table}']
            run([args.codegen, *flags, 'probe.ir'], root, 'codegen', root / 'operation.v')
            match = re.search(r'latency:\s*(\d+)', (root / 'signature.textproto').read_text())
            if not match:
                raise ValueError('missing pipeline latency')
            latency = int(match[1])
            testbench(root, width, latency, args.iverilog, args.vvp)
            ports = ', '.join(f'input wire [{width-1}:0] {p}' for p in 'abcdef')
            (root / 'harness.v').write_text(f'module probe_top(input wire clock, {ports}, output wire [{width-1}:0] out);\n'
                'operation dut(.clk(clock), ' + ', '.join(f'.{p}({p})' for p in 'abcdef') + ', .out(out));\nendmodule\n')
            cells = map_pipeline(root, args.yosys)
            rows.append({'name': name, 'split': 'composition', 'model': model, 'width': width,
                         'latency': latency, 'initiation_interval': 1,
                         'counts': dict(Counter(c['type'] for c in cells.values())),
                         'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
            print(name, flush=True)
    (args.stage / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
        'table_sha256': sha(args.table), 'codegen_sha256': sha(args.codegen), 'probes': rows}, indent=2) + '\n')


def main() -> None:
    """Require calibrated native tools and a fresh validation directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'codegen', 'table', 'yosys', 'iverilog', 'vvp'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    prepare(parser.parse_args())


if __name__ == '__main__':
    main()
