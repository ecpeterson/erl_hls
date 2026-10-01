#!/usr/bin/env python3
"""Prove generated round-robin selection and a starvation-free grant ranking.

The reference scans in circular order. The implementation uses a request mask
and a priority encoder. All request masks, legal cursors, acceptance choices,
and watched contenders are symbolic; there is no sampled stimulus bound.
"""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command, stage, name):
    with (stage / name).open("w") as output, (stage / (name + ".stderr")).open("w") as errors:
        subprocess.run(list(map(str, command)), stdout=output,
                       stderr=errors, check=True, timeout=120)


def fixture(count, width):
    return f"""import arbitration;

pub fn arbiter(pending: uN[{count}], cursor: uN[{width}], accepted: bool)
    -> (bool, uN[{width}], uN[{width}]) {{
  let flags = rev(pending) as bool[{count}];
  let (valid, winner) = arbitration::select(flags, cursor);
  let next_cursor = if accepted && valid {{
    arbitration::successor<u32:{count}>(winner)
  }} else {{ cursor }};
  (valid, winner, next_cursor)
}}
"""


def reference(count, width):
    return f"""module check_arbitration(
    input [{count - 1}:0] pending,
    input [{width - 1}:0] cursor, watched,
    input accepted,
    output ok);
  wire [{2 * width}:0] out;
  arbiter dut(.pending(pending), .cursor(cursor), .accepted(accepted), .out(out));
  wire valid = out[{2 * width}];
  wire [{width - 1}:0] winner = out[{2 * width - 1}:{width}];
  wire [{width - 1}:0] next_cursor = out[{width - 1}:0];
  integer offset, candidate, distance, next_distance;
  reg expected_valid;
  reg [{width - 1}:0] expected_winner, expected_cursor;
  always @* begin
    expected_valid = 0;
    expected_winner = 0;
    for (offset = 0; offset < {count}; offset = offset + 1) begin
      candidate = cursor + offset;
      if (candidate >= {count}) candidate = candidate - {count};
      if (!expected_valid && pending[candidate]) begin
        expected_valid = 1;
        expected_winner = candidate;
      end
    end
    expected_cursor = cursor;
    if (accepted && expected_valid)
      expected_cursor = expected_winner == {count - 1} ? 0 : expected_winner + 1;
    distance = watched >= cursor ? watched - cursor : watched + {count} - cursor;
    next_distance = watched >= next_cursor ? watched - next_cursor : watched + {count} - next_cursor;
  end
  // A continuously pending contender is either chosen or moves strictly
  // closer after each accepted grant. Its initial distance is at most N-1.
  // Without acceptance the cursor stays fixed; backpressure is not a grant.
  wire ranking = !accepted || watched >= {count} || !pending[watched] ||
      (valid && (winner == watched || next_distance < distance));
  assign ok = cursor >= {count} ||
      (valid == expected_valid && winner == expected_winner &&
       next_cursor == expected_cursor && next_cursor < {count} && ranking);
endmodule
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/arbitration")
    args = parser.parse_args()
    xls, stage = args.xls.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    paths = [f"--dslx_path={ROOT / 'priv/xls/lib'}",
             f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}"]
    run([xls / "interpreter_main", "--compare=jit", *paths,
         ROOT / "priv/xls/lib/arbitration.x"], stage, "library.log")
    for count in (1, 2, 3, 4, 9, 16, 17, 32):
        # Narrow plane cursors and existing 32-bit scheduler clients share
        # the implementation. Include both representations in the proof.
        for width in (max(1, (count - 1).bit_length()), 32):
            name = f"n{count}_w{width}"
            source = stage / f"{name}.x"
            source.write_text(fixture(count, width))
            run([xls / "ir_converter_main", "--top=arbiter", *paths, source],
                stage, f"{name}.ir")
            run([xls / "opt_main", stage / f"{name}.ir"], stage, f"{name}.opt.ir")
            run([xls / "codegen_main", "--generator=combinational",
                 "--module_name=arbiter", "--use_system_verilog=false",
                 stage / f"{name}.opt.ir"], stage, f"{name}.v")
            ref = stage / f"{name}-reference.v"
            ref.write_text(reference(count, width))
            script = stage / f"{name}.ys"
            script.write_text(
                f'read_verilog "{stage / (name + ".v")}" "{ref}"\n'
                "prep -top check_arbitration -flatten\n"
                "opt\nsat -verify -prove ok 1 -set-def-inputs -show-inputs\n")
            run([args.yosys, "-Q", "-T", "-s", script], stage, f"{name}-proof.log")
            print(f"PASS: {count} contenders, {width}-bit cursor; exact choice, "
                  "cursor bounds, held cursor under stalls, decreasing grant rank", flush=True)


if __name__ == "__main__":
    main()
