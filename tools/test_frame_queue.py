#!/usr/bin/env python3
"""Prove compiled queue-bank updates equivalent to serial indexed pop then push."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def fixture(count: int, proof: bool = False) -> str:
    """Expose every queue bit; optional miter covers arbitrary state and controls."""
    result = "bool" if proof else f"uN[{258 * count}]"
    finish = """  let expected = if controls[0+:u1] != u1:0 {
    update(bank, pop_source, reference_pop(bank[pop_source]))
  } else { bank };
  let expected = if controls[1+:u1] != u1:0 {
    update(expected, push_source, frame_queue::push(expected[push_source], frame))
  } else { expected };
  let admitted = (!controls[0+:u1] || pop_source < COUNT) &&
    (!controls[1+:u1] || push_source < COUNT);
  !admitted || actual == expected
""" if proof else f"""  let packed = unroll_for! (i, values): (u32, uN[258][COUNT]) in u32:0..COUNT {{
    let q = actual[i];
    update(values, i, q.current_valid ++ axis::bits_from_frame(q.current) ++
      q.lookahead_valid ++ axis::bits_from_frame(q.lookahead))
  }}(zero!<uN[258][COUNT]>());
  packed as uN[{258 * count}]
"""
    return f"""import axis;
import frame_queue;
const COUNT = u32:{count};
// Reference retains the prior payload-preserving pop, independent of the library.
fn reference_pop(queue: frame_queue::Queue) -> frame_queue::Queue {{
  frame_queue::Queue {{
    current_valid: queue.lookahead_valid,
    current: if queue.lookahead_valid {{ queue.lookahead }} else {{ queue.current }},
    lookahead_valid: u1:0,
    lookahead: queue.lookahead,
  }}
}}
// One combinational bank transition; enabled addresses must be in range.
pub fn main(raw: uN[{258 * count}], controls: u2,
    pop_source: u32, push_source: u32, payload: uN[128]) -> {result} {{
  let words = raw as uN[258][COUNT];
  let bank = unroll_for! (i, queues): (u32, frame_queue::Queue[COUNT]) in u32:0..COUNT {{
    let word = words[i];
    update(queues, i, frame_queue::Queue {{
      current_valid: word[257+:u1],
      current: axis::frame_from_bits(word[129+:uN[128]]),
      lookahead_valid: word[128+:u1],
      lookahead: axis::frame_from_bits(word[0+:uN[128]]),
    }})
  }}(zero!<frame_queue::Queue[COUNT]>());
  let frame = axis::frame_from_bits(payload);
  let actual = frame_queue::update_bank(bank, controls[0+:u1], pop_source,
    controls[1+:u1], push_source, frame);
{finish}}}
"""


def run(argv: list[str | Path], stage: Path, name: str) -> None:
    """Run a bounded proof phase, preserving generated RTL and diagnostics."""
    with (stage / name).open('w') as out, (stage / f'{name}.stderr').open('w') as err:
        subprocess.run(list(map(str, argv)), stdout=out, stderr=err, check=True, timeout=180)


def main() -> None:
    """Prove every data/control combination for representative bank populations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--library', type=Path, default=ROOT / 'priv/xls/lib')
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/frame-queue-proof')
    args = parser.parse_args()
    xls, stage = args.xls.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    paths = [f'--dslx_path={args.library.resolve()}',
             f'--dslx_stdlib_path={xls / "xls/dslx/stdlib"}']
    run([xls / 'interpreter_main', '--compare=jit', *paths,
         args.library.resolve() / 'frame_queue.x'], stage, 'library.log')
    for count in (1, 2, 3, 9):
        name = f'bank{count}'
        source = stage / f'{name}.x'
        source.write_text(fixture(count, proof=True))
        run([xls / 'ir_converter_main', '--top=main', *paths, source], stage, f'{name}.ir')
        run([xls / 'opt_main', stage / f'{name}.ir'], stage, f'{name}.opt.ir')
        run([xls / 'codegen_main', '--generator=combinational', '--module_name=bank',
             '--use_system_verilog=false', stage / f'{name}.opt.ir'], stage, f'{name}.v')
        script = stage / f'{name}.ys'
        script.write_text(f'read_verilog "{stage / (name + ".v")}"\n'
                          'prep -top bank -flatten\nopt\n'
                          'sat -verify -prove out 1 -set-def-inputs -show-inputs\n')
        run([args.yosys, '-Q', '-T', '-s', script], stage, f'{name}-proof.log')
        print(f'PASS: {count} queues, all state/payload bits, valid enabled indices, '
              'arbitrary disabled indices', flush=True)


if __name__ == '__main__':
    main()
