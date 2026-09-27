#!/usr/bin/env python3
"""Screen bit-preserving field division factoring with explicit input bounds."""
import argparse
from collections import Counter
import itertools
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys

from architecture import sha


def source(factored: bool, center: bool = False) -> str:
    """Emit a four-neighbor Q15.16 recurrence with unchanged rounding/saturation."""
    width = 36 if factored else 37
    rounding = 'hls_fixed::round_ratio<u32:12>(numerator)'
    if factored:
        rounding = '''{
    let bias = if numerator < sN[36]:0 { sN[37]:1 } else { sN[37]:2 };
    let shifted = (((numerator as sN[37]) + bias) >> u32:2) as sN[35];
    hls_fixed::round_ratio<u32:3>(shifted)
  }'''
    pair = (f'sN[{width}]:6 * (a as sN[{width}]) + sN[{width}]:2 * (b as sN[{width}])'
            if center else f'(a as sN[{width}]) + sN[{width}]:7 * (b as sN[{width}])')
    if center:
        rounding = f'((anyon as s64) << u32:16) + (({rounding}) as s64)'
    return f'''import hls_fixed;
// Sum holds at most four signed-32 neighbors; preserve Q15.16 and ties away.
pub fn main({'anyon: u32, ' if center else ''}a: s32, b: s32, sum: sN[34]) -> s32 {{
  let numerator = {pair} +
    (sum as sN[{width}]);
  hls_fixed::saturate<u32:32>({rounding})
}}
'''


def run(command: list[str], stage: Path, label: str, output: str | None = None) -> None:
    """Run a bounded check, preserving its command and diagnostics."""
    (stage / (label + '.command.json')).write_text(json.dumps(command) + '\n')
    with (stage / (output or label + '.log')).open('w') as out, (stage / (label + '.stderr')).open('w') as err:
        subprocess.run(command, cwd=stage, stdout=out, stderr=err, check=True, timeout=300)


def prove(stage: Path, z3: Path, center: bool = False) -> None:
    """Prove identity and every signed intermediate bound, including bias overflow."""
    text = '''(set-logic QF_LIA)
(set-option :timeout 10000)
(declare-const n Int)
(assert (and (<= (- 34359738368) n) (< n 34359738368)))
(define-fun bias () Int (ite (< n 0) 1 2))
(define-fun shifted () Int (div (+ n bias) 4))
(define-fun reference () Int
  (ite (< n 0) (- (div (+ (- n) 6) 12)) (div (+ n 6) 12)))
(define-fun candidate () Int
  (ite (< shifted 0) (- (div (+ (- shifted) 1) 3)) (div (+ shifted 1) 3)))
(push)
(assert (not (= reference candidate)))
(check-sat)
(pop)
; Signed-37 bias addition and signed-35 cast cannot wrap.
(push)
(assert (not (and (<= (- 68719476736) (+ n bias)) (< (+ n bias) 68719476736)
                 (<= (- 17179869184) shifted) (< shifted 17179869184))))
(check-sat)
(pop)
; Actual reciprocal expressions: signed-80 old product, signed-74 new product.
(define-fun old_product () Int (* n 183251937963))
(define-fun new_product () Int (* shifted 45812984491))
(push)
(assert (not (and
  (<= (- 604462909807314587353088) old_product)
  (< (+ old_product 1099511627776) 604462909807314587353088)
  (<= (- 9444732965739290427392) new_product)
  (< (+ new_product 68719476736) 9444732965739290427392)
  (= reference (div (+ old_product 1099511627776) 2199023255552))
  (= candidate (div (+ new_product 68719476736) 137438953472)))))
(check-sat)
(pop)
; The full signed-34 input sum and weighted signed-32 pair fit signed 36.
(declare-const a Int)
(declare-const b Int)
(declare-const neighbors Int)
(push)
(assert (and (<= (- 2147483648) a) (< a 2147483648)
             (<= (- 2147483648) b) (< b 2147483648)
             (<= (- 8589934592) neighbors) (< neighbors 8589934592)))
(assert (not (and (<= (- 34359738368) (+ a (* 7 b) neighbors))
                 (< (+ a (* 7 b) neighbors) 34359738368))))
(check-sat)
(pop)
; A single bias for both signs is deliberately wrong at negative half ties.
(define-fun bad_shift () Int (div (+ n 2) 4))
(define-fun bad () Int (ite (< bad_shift 0)
  (- (div (+ (- bad_shift) 1) 3)) (div (+ bad_shift 1) 3)))
(assert (not (= reference bad)))
(check-sat)
'''
    if center:
        text = text.replace('(+ a (* 7 b) neighbors)', '(+ (* 6 a) (* 2 b) neighbors)')
        text = text.replace('; A single bias', '''; The unsigned-32 anyon offset and rounded field cannot overflow signed 64.
(declare-const anyon Int)
(push)
(assert (and (<= 0 anyon) (< anyon 4294967296)))
(assert (not (and
  (<= (- 9223372036854775808) (+ (* anyon 65536) reference))
  (< (+ (* anyon 65536) reference) 9223372036854775808))))
(check-sat)
(pop)
; A single bias''')
    (stage / 'finite-width.smt2').write_text(text)
    run([str(z3), 'finite-width.smt2'], stage, 'proof')
    if (stage / 'proof.log').read_text().split() != ['unsat'] * (5 if center else 4) + ['sat']:
        raise AssertionError('identity, width proof or mutation check failed')


def vectors() -> list[tuple[int, int, int]]:
    """Cover half ties, sign boundaries, full-width extremes and reproducible random inputs."""
    low, high = -(1 << 31), (1 << 31) - 1
    values = (low, low + 1, -7, -1, 0, 1, 7, high - 1, high)
    cases = list(itertools.product(values, values, (4 * low, -12, -6, -1, 0, 1, 6, 12, 4 * high)))
    cases += [(0, 0, n) for n in range(-65536, 65537)]
    for base in (4 * low, low, high, 4 * high):
        cases += [(a, b, base + delta) for a, b in itertools.product(values, repeat=2)
                  for delta in range(-13, 14) if 4 * low <= base + delta <= 4 * high]
    rng = random.Random(260926)
    cases += [(rng.randint(low, high), rng.randint(low, high), rng.randint(4 * low, 4 * high))
              for _ in range(20000)]
    return cases


def verify(stage: Path, center: bool = False) -> int:
    """Compare both compiled combinational circuits with independent integer rounding."""
    rows = []
    inputs = vectors()
    cases = [(a, b, total, 0) for a, b, total in inputs]
    if center:
        # Keep every half-tie test unsaturated, then exercise offset/saturation
        # boundaries independently instead of correlating anyon with parity.
        cases += [(a, b, total, anyon) for a, b, total in inputs[:729]
                  for anyon in (1, 2, 32767, 32768, 2**32-1)]
    for a, b, total, anyon in cases:
        n = 6 * a + 2 * b + total if center else a + 7 * b + total
        expected = (abs(n) + 6) // 12 * (-1 if n < 0 else 1)
        expected += anyon << 16
        expected = max(-(1 << 31), min((1 << 31) - 1, expected))
        word = ((a & (2**32-1)) << 98) | ((b & (2**32-1)) << 66) | ((total & (2**34-1)) << 32) | (expected & (2**32-1))
        if center:
            word |= anyon << 130
        rows.append(f'{word:041x}' if center else f'{word:033x}')
    (stage / 'vectors.hex').write_text('\n'.join(rows) + '\n')
    (stage / 'testbench.v').write_text(f'''module testbench;
reg [31:0] a,b,anyon; reg [33:0] sum; wire [31:0] old_value,new_value;
reg [{161 if center else 129}:0] cases[0:{len(rows)-1}]; integer i;
reference old_dut({'.anyon(anyon),' if center else ''}.a(a),.b(b),.sum(sum),.out(old_value));
factored new_dut({'.anyon(anyon),' if center else ''}.a(a),.b(b),.sum(sum),.out(new_value));
initial begin
  $readmemh("vectors.hex",cases);
  for(i=0;i<{len(rows)};i=i+1) begin
    {{{'anyon,' if center else ''}a,b,sum}}=cases[i][{161 if center else 129}:32]; #1;
    if(old_value !== cases[i][31:0] || new_value !== cases[i][31:0])
      $fatal(1,"case %0d: old=%h new=%h expected=%h",i,old_value,new_value,cases[i][31:0]);
  end
  $display("PASS {len(rows)} exact {'center' if center else 'bulk'} updates"); $finish;
end
endmodule
''')
    run(['iverilog', '-g2012', '-s', 'testbench', '-o', 'simulation.vvp',
         'reference/arithmetic.v', 'factored/arithmetic.v', 'testbench.v'], stage, 'iverilog')
    run(['vvp', 'simulation.vvp'], stage, 'simulation')
    (stage / 'simulation.vvp').unlink()
    return len(rows)


def prepare_vendor(stage: Path, yosys: Path, center: bool = False) -> None:
    """Prepare matched whole-kernel probes for a later Vivado run, without running it."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from timing_model.characterize import harness
    corpus = stage / 'vendor-kernels'
    corpus.mkdir(exist_ok=False)
    probes = []
    for name in ('reference', 'factored'):
        root = corpus / name
        root.mkdir()
        shutil.copyfile(stage / name / 'arithmetic.v', root / 'arithmetic.v')
        ports = ([('anyon', 32)] if center else []) + [('a', 32), ('b', 32), ('sum', 34)]
        (root / 'harness.v').write_text(harness(name, ports, 32))
        (root / 'map.ys').write_text('read_verilog arithmetic.v harness.v\n'
            'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
            'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
        run([str(yosys), '-Q', '-q', '-s', 'map.ys'], root, 'map')
        path = root / 'mapped.json'
        data = json.loads(path.read_text())
        top = data['modules']['probe_top']
        data['modules'] = {'probe_top': top}
        counts = Counter(c['type'] for c in top['cells'].values())
        if counts['FDRE'] != (162 if center else 130):
            raise AssertionError('whole-kernel launch/capture boundary changed')
        for cell in top['cells'].values():
            if cell['type'] == 'DSP48E1' and any(int(v, 2) for k, v in cell['parameters'].items() if k.endswith('REG')):
                raise AssertionError('kernel registers moved into a DSP')
        path.write_text(json.dumps(data, separators=(',', ':')) + '\n')
        run([str(yosys), '-Q', '-q', '-p',
             'read_verilog -lib +/xilinx/cells_sim.v; read_json mapped.json; write_edif -pvector bra mapped.edf'], root, 'edif')
        probes.append({'name': name, 'split': 'validation', 'counts': dict(counts),
                       'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
    (corpus / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
        'flow': 'synth_xilinx -abc9', 'tools': {str(yosys): sha(yosys)}, 'probes': probes}, indent=2) + '\n')


def prepare(args: argparse.Namespace) -> None:
    """Retain correctness, resource counts and exact shapes awaiting vendor calibration."""
    args.stage.mkdir(parents=True, exist_ok=False)
    prove(args.stage, args.z3, args.center)
    rows = []
    for name in ('reference', 'factored'):
        stage = args.stage / name
        stage.mkdir()
        shutil.copyfile(args.library, stage / 'hls_fixed.x')
        if (dependency := args.library.with_name('hls_multiply.x')).exists():
            shutil.copyfile(dependency, stage / dependency.name)
        kernel = 'center.x' if args.center else 'bulk.x'
        (stage / kernel).write_text(source(name == 'factored', args.center))
        run([str(args.xls / 'ir_converter_main'), '--top=main', '--dslx_path=.',
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), kernel], stage, 'ir', 'design.ir')
        run([str(args.xls / 'opt_main'), 'design.ir'], stage, 'opt', 'design.opt.ir')
        run([str(args.xls / 'codegen_main'), '--generator=combinational', '--use_system_verilog=false',
             '--module_name=' + name, 'design.opt.ir'], stage, 'codegen', 'arithmetic.v')
        (stage / 'map.ys').write_text('read_verilog arithmetic.v\nsynth_xilinx -flatten -abc9 -family xc7 '
            f'-top {name} -noiopad -noclkbuf\ncheck -assert\nscc -expect 0\ntee -o stat.json stat -json\n')
        run([str(args.yosys), '-Q', '-T', '-s', 'map.ys'], stage, 'map')
        counts = next(iter(json.loads((stage / 'stat.json').read_text())['modules'].values()))['num_cells_by_type']
        ir = (stage / 'design.opt.ir').read_text()
        products = [line.strip() for line in ir.splitlines() if re.search(r'= [su]mul\(', line)]
        rows.append({'variant': name, 'counts': counts, 'products': products,
                     'files': {p.name: sha(p) for p in stage.iterdir() if p.is_file()}})
        print(name, counts, flush=True)
    count = verify(args.stage, args.center)
    result = {'scope': 'finite-width arithmetic proof plus compiled RTL vectors; no physical timing claim',
              'rtl_vectors': count, 'measurements': rows,
              'proof_verdicts': (args.stage / 'proof.log').read_text().split(),
              'tools': {str(p): sha(p) for p in (args.yosys, args.z3,
                  *[args.xls / n for n in ('ir_converter_main', 'opt_main', 'codegen_main')])}}
    (args.stage / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    prepare_vendor(args.stage, args.yosys, args.center)
    print('PASS:', count, 'compiled RTL vectors', flush=True)


def main() -> None:
    """Require explicit retained arithmetic source, native tools and a fresh stage."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'xls', 'yosys', 'library', 'z3'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--center', action='store_true', help='test the center field including its anyon offset')
    prepare(parser.parse_args())


if __name__ == '__main__':
    main()
