#!/usr/bin/env python3
"""Compare unit and calibrated schedules for the existing fixed-point update kernel."""
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import re
from characterize import run, sha
from validate import map_pipeline


def vectors(root: Path, latency: int, iverilog: Path, vvp: Path) -> None:
    """Check exact signed reciprocal rounding at full rate, including extreme inputs."""
    rng = random.Random(260926)
    cases = [(0, 0, 0), (2**31-1, 2**31-1, 2**33-1), (-2**31, -2**31, -2**33)]
    cases += [tuple(rng.randrange(-(1 << (w-1)), 1 << (w-1)) for w in (32, 32, 34)) for _ in range(250)]
    rows = []
    for a, b, total in cases:
        value = (((a + 7*b + total) * 183251937963 >> 40) + 1) >> 1
        expected = max(-2**31, min(2**31-1, value)) & (2**32-1)
        packed = (((a & (2**32-1)) << 98) | ((b & (2**32-1)) << 66) |
                  ((total & (2**34-1)) << 32) | expected)
        rows.append(f'{packed:033x}')
    (root / 'vectors.hex').write_text('\n'.join(rows) + '\n')
    (root / 'testbench.v').write_text(f'''module testbench;
reg clk=0; always #5 clk=~clk;
reg [31:0] a,b; reg [33:0] sum; wire [31:0] out;
reg [129:0] vectors[0:{len(rows)-1}]; integer i;
operation dut(.clk(clk),.a(a),.b(b),.sum(sum),.out(out));
initial begin
  $readmemh("vectors.hex",vectors);
  for(i=0;i<{len(rows)+latency};i=i+1) begin
    @(negedge clk); {{a,b,sum}}=vectors[i%{len(rows)}][129:32];
    @(posedge clk); #1;
    if(i>={latency-1} && i-{latency-1}<{len(rows)})
      if(out !== vectors[i-{latency-1}][31:0]) $fatal(1,"kernel mismatch %0d: %h",i,out);
  end
  $display("PASS {len(rows)} full-rate fixed-point updates"); $finish;
end
endmodule
''')
    run([iverilog, '-g2012', '-s', 'testbench', '-o', 'simulation.vvp', 'operation.v', 'testbench.v'], root, 'iverilog')
    run([vvp, 'simulation.vvp'], root, 'simulation')
    (root / 'simulation.vvp').unlink()


def prepare(args: argparse.Namespace) -> None:
    """Compare equal latency/II, retaining the same optimized source for both models."""
    args.stage.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).with_name('fixed_point.ir')
    rows = []
    for model in ('unit', 'xc7_7030'):
        name = 'fixed_point_' + model
        root = args.stage / name
        root.mkdir()
        (root / 'probe.ir').write_text(source.read_text())
        flags = [f'--delay_model={model}', '--pipeline_stages=3', '--flop_inputs=true',
                 '--flop_outputs=true', '--use_system_verilog=false', '--module_name=operation',
                 '--output_signature_path=signature.textproto', '--output_schedule_path=schedule.textproto']
        if model == 'xc7_7030':
            flags += [f'--xc7_delay_table={args.table}']
        run([args.codegen, *flags, 'probe.ir'], root, 'codegen', root / 'operation.v')
        latency = int(re.search(r'latency:\s*(\d+)', (root / 'signature.textproto').read_text())[1])
        vectors(root, latency, args.iverilog, args.vvp)
        (root / 'harness.v').write_text('module probe_top(input wire clock, input wire [31:0] a,b, '
            'input wire [33:0] sum, output wire [31:0] out);\n'
            'operation dut(.clk(clock),.a(a),.b(b),.sum(sum),.out(out));\nendmodule\n')
        cells = map_pipeline(root, args.yosys)
        rows.append({'name': name, 'split': 'application', 'model': model, 'latency': latency,
                     'initiation_interval': 1, 'counts': dict(Counter(c['type'] for c in cells.values())),
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
