#!/usr/bin/env python3
"""Check compiled limb arithmetic against Python integers, including truncation."""
import argparse
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = [(7, 5, 15, 3, 2), (37, 38, 80, 24, 17),
            (49, 33, 35, 24, 17), (129, 65, 200, 24, 17)]
ROUNDS = [(w, d) for w in (8, 37, 65) for d in (1, 2, 3, 12, 13, 1000, 4294967295)]


def signed(value: int, width: int) -> int:
    """Interpret a truncated bit pattern as a signed integer."""
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def cases() -> list[tuple[int, int, int]]:
    """Exhaust the small product and sample full-width products, biases and quotients."""
    rng = random.Random(260927)
    values = [(a, b, rng.getrandbits(200)) for a in range(-64, 64) for b in range(32)]
    extremes = [0, 1, -1, -(1 << 128), (1 << 128) - 1]
    for bit in (7, 17, 24, 36, 48, 64, 96):
        extremes.extend(sign * (1 << bit) + delta for sign in (-1, 1) for delta in (-1, 0, 1))
    values += [(n, m, bias) for n in extremes for m in (0, 1, (1 << 65) - 1)
               for bias in (0, (1 << 200) - 1)]
    values += [(signed(rng.getrandbits(129), 129), rng.getrandbits(65), rng.getrandbits(200))
               for _ in range(3000)]
    return values


def expected(a: int, b: int, bias: int) -> tuple[int, int]:
    """Pack independent integer results in DSLX tuple order."""
    fields = [(out, signed(a, aw) * (b & ((1 << bw) - 1)) + bias)
              for aw, bw, out, _, _ in PRODUCTS]
    for width, denominator in ROUNDS:
        n = signed(a, width)
        magnitude = (abs(n) + denominator // 2) // denominator
        fields.append((width, -magnitude if n < 0 else magnitude))
    encoded, bits = 0, 0
    for width, value in fields:
        encoded = (encoded << width) | (value & ((1 << width) - 1))
        bits += width
    return encoded, bits


def run(command: list[str], stage: Path, label: str) -> None:
    """Retain commands and diagnostics, and bound each compiler/simulation invocation."""
    (stage / (label + '.command.json')).write_text(json.dumps(command) + '\n')
    with (stage / label).open('w') as out, (stage / (label + '.stderr')).open('w') as err:
        subprocess.run(command, cwd=stage, stdout=out, stderr=err, check=True, timeout=600)


def main() -> None:
    """Require native XLS tools and an unused output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    stage = args.stage
    stage.mkdir(parents=True, exist_ok=False)
    types = [f'uN[{out}]' for _, _, out, _, _ in PRODUCTS] + [f'sN[{w}]' for w, _ in ROUNDS]
    expressions = [f'hls_multiply::signed_unsigned_add<u32:{left}, u32:{right}>'
                   f'(a as sN[{aw}], b as uN[{bw}], bias as uN[{out}])'
                   for aw, bw, out, left, right in PRODUCTS]
    expressions += [f'hls_fixed::round_ratio_chunked<u32:{d}, u32:24, u32:17>(a as sN[{w}])'
                    for w, d in ROUNDS]
    (stage / 'arithmetic.x').write_text('import hls_fixed;\nimport hls_multiply;\n'
        '// Mixed widths exercise signed limbs, rounding and modular truncation.\n'
        'pub fn arithmetic(a: sN[129], b: uN[65], bias: uN[200]) -> (' + ', '.join(types) + ') {\n'
        '  (' + ',\n   '.join(expressions) + ')\n}\n')
    run([str(args.xls / 'ir_converter_main'), '--warnings_as_errors=false', '--top=arithmetic',
         '--dslx_path=' + str(ROOT / 'priv/xls/lib'),
         '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), 'arithmetic.x'], stage, 'design.ir')
    run([str(args.xls / 'opt_main'), 'design.ir'], stage, 'design.opt.ir')
    run([str(args.xls / 'codegen_main'), '--generator=combinational', '--use_system_verilog=false',
         '--module_name=arithmetic', 'design.opt.ir'], stage, 'arithmetic.v')
    vectors = cases()
    output_bits = expected(0, 0, 0)[1]
    total = 129 + 65 + 200 + output_bits
    lines = []
    for a, b, bias in vectors:
        encoded = (((a & ((1 << 129) - 1)) << 65) | b) << 200 | bias
        encoded = (encoded << output_bits) | expected(a, b, bias)[0]
        lines.append(f'{encoded:0{(total + 3) // 4}x}')
    (stage / 'vectors.hex').write_text('\n'.join(lines) + '\n')
    (stage / 'testbench.sv').write_text(f'''module testbench;
reg [128:0] a; reg [64:0] b; reg [199:0] bias;
wire [{output_bits-1}:0] out; reg [{output_bits-1}:0] expected;
reg [{total-1}:0] vectors[0:{len(vectors)-1}]; integer i;
arithmetic dut(.*);
initial begin
  $readmemh("vectors.hex", vectors);
  for (i=0; i<{len(vectors)}; i=i+1) begin
    {{a,b,bias,expected}} = vectors[i]; #1;
    if (out !== expected) $fatal(1,"arithmetic mismatch case %0d",i);
  end
  $display("PASS {len(vectors)} inputs, {len(types)} results/input"); $finish;
end
endmodule
''')
    run(['iverilog', '-g2012', '-s', 'testbench', '-o', 'simulation.vvp',
         'testbench.sv', 'arithmetic.v'], stage, 'compile.log')
    run(['vvp', 'simulation.vvp'], stage, 'simulation.log')
    print((stage / 'simulation.log').read_text(), end='')
    (stage / 'simulation.vvp').unlink()


if __name__ == '__main__':
    main()
