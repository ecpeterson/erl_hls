#!/usr/bin/env python3
"""Build and verify the complete recurrence, preserving evidence for each explicit cut."""
import argparse
import json
import sys
from pathlib import Path
import random
import shutil

from architecture import sha
from staged_reciprocal import ROOT, map_kernel, run

HERE = Path(__file__).resolve().parent


def recurrence(field0: int, field1: int, sum0: int, sum1: int, anyon: int) -> tuple[int, int]:
    """Independent unbounded-integer oracle: round away at ties, add source, saturate."""
    def rounded(n: int) -> int:
        """Round signed division without a reciprocal or finite-width multiplication."""
        return (1 if n >= 0 else -1) * ((abs(n) + 6) // 12)
    def clipped(n: int) -> int:
        """Clamp a mathematical integer to the signed scalar domain."""
        return min((1 << 31) - 1, max(-(1 << 31), n))
    return (clipped((anyon << 16) + rounded(6*field0 + 2*field1 + sum0)),
            clipped(rounded(field0 + 7*field1 + sum1)))


def wrapper(split: bool) -> str:
    """Expose one fixed-latency recurrence with global stall and reset-flushed validity."""
    stages = 5 if split else 1
    logic = '''wire [73:0] n, q; wire [959:0] p; wire [319:0] r;
reg [73:0] nr, qr; reg [959:0] pr; reg [319:0] rr;
reg [31:0] source0, source1, source2, source3;
numerical_numerators n_dut(.field0(field0), .field1(field1), .sum0(sum0), .sum1(sum1), .out(n));
numerical_products p_dut(.n(nr), .out(p));
numerical_reduce r_dut(.rows(pr), .out(r));
numerical_quotients q_dut(.rows(rr), .out(q));
numerical_saturate s_dut(.q(qr), .anyon(source3), .out(value));
always @(posedge clk) if (enable) begin
  nr <= n; pr <= p; rr <= r; qr <= q;
  source0 <= anyon; source1 <= source0; source2 <= source1; source3 <= source2;
end''' if split else '''numerical_reference r_dut(.field0(field0), .field1(field1),
  .sum0(sum0), .sum1(sum1), .anyon(anyon), .out(value));'''
    shift = '{valid[3:0], in_valid}' if split else 'in_valid'
    return f'''// A result appears after {stages} enabled edges; reset discards in-flight work.
module kernel(input wire clk, reset, enable, in_valid,
  input wire [31:0] field0, field1, anyon,
  input wire [33:0] sum0, sum1,
  output reg [63:0] out, output wire out_valid);
reg [{stages-1}:0] valid = 0;
wire [63:0] value;
always @(posedge clk) begin
  if (reset) valid <= 0;
  else if (enable) valid <= {shift};
  if (enable) out <= value;
end
assign out_valid = valid[{stages-1}];
{logic}
endmodule
'''


def vectors() -> list[tuple[int, int, int, int, int]]:
    """Exercise saturation, rounding ties, source extremes and four-neighbor sums."""
    edges = (-(1 << 31), -(1 << 31)+1, -65536, -1, 0, 1, 65536, (1 << 31)-1)
    cases = [(a, b, s, t, source) for a in edges for b in edges
             for s in (-(1 << 33), -6, 6, (1 << 33)-4)
             for t in (-(1 << 33), -6, 6, (1 << 33)-4)
             for source in (0, 1, 32768, (1 << 32)-1)]
    cases += [(0, 0, n, -n, 0) for n in range(-8192, 8193)]
    rng = random.Random(260927)
    cases += [(rng.randint(-(1 << 31), (1 << 31)-1),
               rng.randint(-(1 << 31), (1 << 31)-1),
               rng.randint(-(1 << 33), (1 << 33)-4),
               rng.randint(-(1 << 33), (1 << 33)-4), rng.getrandbits(1))
              for _ in range(10000)]
    return cases


def verify(stage: Path, cells: Path | None = None) -> dict:
    """Scoreboard every live result through random stalls and reset, before and after mapping."""
    cases = vectors()
    if cells:
        # Keep every Cartesian boundary case and a smaller deterministic sample
        # of ties/random interiors; gate-level event simulation is much slower.
        cases = cases[:4096] + cases[4096:20481:257] + cases[-1024:]
    words = []
    for row in cases:
        result = recurrence(*row)
        encoded = 0
        for value, width in zip((*row, (result[1] & 0xffffffff) << 32 | (result[0] & 0xffffffff)),
                                (32, 32, 34, 34, 32, 64)):
            encoded = encoded << width | (value & ((1 << width)-1))
        words.append(f'{encoded:057x}')
    (stage/'vectors.hex').write_text('\n'.join(words)+'\n')
    bench = '''module testbench;
parameter LATENCY = 5;
reg clk = 0; always #5 clk = !clk;
reg reset = 1, enable = 0, in_valid = 0;
reg [31:0] field0, field1, anyon; reg [33:0] sum0, sum1;
wire [63:0] out; wire out_valid;
kernel dut(.*);
reg [227:0] cases[0:COUNT-1]; reg [63:0] expected[0:LATENCY-1], wanted;
reg [LATENCY-1:0] live = 0;
reg [31:0] rng = 32'h487138bd;
integer i = 0, cycle = 0, j, checked = 0, stalled = 0, flushed = 0;
initial begin
  $readmemh("vectors.hex", cases);
  repeat (COUNT*3) begin
    @(negedge clk);
    rng = {rng[30:0], rng[31]^rng[21]^rng[1]^rng[0]};
    reset = cycle == 0 || cycle % 5003 == 5002;
    enable = rng[3:0] != 0;
    in_valid = i < COUNT && rng[7:4] != 0;
    {field0,field1,sum0,sum1,anyon,wanted} = i < COUNT ? cases[i] : 0;
    @(posedge clk);
    if (reset) begin live = 0; flushed = flushed + 1; end
    else if (enable) begin
      for (j=LATENCY-1;j>0;j=j-1) expected[j] = expected[j-1];
      expected[0] = wanted; live = (live << 1) | in_valid;
      if (in_valid) i = i + 1;
    end else stalled = stalled + 1;
    #1;
    if (out_valid !== live[LATENCY-1]) $fatal(1,"valid cycle %0d",cycle);
    if (out_valid && out !== expected[LATENCY-1])
      $fatal(1,"value cycle %0d got %h expected %h",cycle,out,expected[LATENCY-1]);
    if (out_valid && enable && !reset) checked = checked + 1;
    if (i == COUNT && live == 0) begin
      $display("PASS inputs=%0d checked=%0d stalls=%0d resets=%0d cycles=%0d",i,checked,stalled,flushed,cycle);
      $finish;
    end
    cycle = cycle + 1;
  end
  $fatal(1,"timeout");
end
endmodule
'''.replace('COUNT', str(len(cases)))
    (stage/'testbench.sv').write_text(bench)
    results = {}
    for name, latency in (('reference', 1), ('split', 5)):
        root = stage/name
        sources = [str(root/'mapped.v'), str(cells)] if cells else [str(p) for p in root.glob('*.v') if p.name != 'mapped.v']
        label = ('mapped-' if cells else '') + name
        run(['iverilog', '-g2012', '-s', 'testbench', '-Ptestbench.LATENCY='+str(latency),
             '-o', 'sim.vvp', str(stage/'testbench.sv'), *sources], stage, label+'-iverilog')
        run(['vvp', 'sim.vvp'], stage, label+'-simulation')
        result = (stage/(label+'-simulation.log')).read_text().splitlines()[0]
        if not result.startswith('PASS '):
            raise ValueError(result)
        results[name] = result
    (stage/'sim.vvp').unlink()
    return results


def build(args: argparse.Namespace) -> dict:
    """Compile each cut once and compare against the exact current application recurrence."""
    sys.path.insert(0, str(ROOT / 'tools/hls_fabric'))
    from compiler_paths import compiler_root
    public = compiler_root(args.profile, args.erl_hls, ROOT)
    args.stage.mkdir(parents=True, exist_ok=False)
    sources = [HERE/'phi_numerical.x', HERE/'staged_reciprocal.x',
               ROOT/'apps/hls_phi/src/phi_field.x',
               *[public/'priv/xls/lib'/name for name in ('hls_fixed.x', 'hls_multiply.x', 'hls_vec.x')]]
    identities = {str(p): sha(p) for p in [Path(__file__), *sources, args.yosys,
                  *[args.xls/name for name in ('ir_converter_main', 'opt_main', 'codegen_main')]]}
    for name, functions in (('reference', ('reference',)),
                            ('split', ('numerators', 'products', 'reduce', 'quotients', 'saturate'))):
        root = args.stage/name
        root.mkdir()
        for source in sources:
            shutil.copyfile(source, root/source.name)
        for function in functions:
            for label, argv, output in (
                ('convert', [str(args.xls/'ir_converter_main'), '--top='+function, '--dslx_path=.',
                    '--dslx_stdlib_path='+str(args.xls/'xls/dslx/stdlib'), 'phi_numerical.x'], function+'.ir'),
                ('opt', [str(args.xls/'opt_main'), function+'.ir'], function+'.opt.ir'),
                ('codegen', [str(args.xls/'codegen_main'), '--generator=combinational', '--use_system_verilog=false',
                    '--module_name=numerical_'+function, function+'.opt.ir'], function+'.v')):
                run(argv, root, function+'-'+label, output)
        (root/'kernel.v').write_text(wrapper(name == 'split'))
    result = {'inputs': identities, 'rtl': verify(args.stage), 'mapping': {}}
    cells = args.yosys.parent.parent/'share/yosys/xilinx/cells_sim.v'
    args.pack_candidate_registers = False
    for name in ('reference', 'split'):
        result['mapping'][name] = map_kernel(args, name)
        root = args.stage/name
        (root/'export.ys').write_text(f'read_verilog -lib {cells}\nread_json mapped.json\nwrite_verilog -noattr mapped.v\n')
        run([str(args.yosys), '-Q', '-T', '-s', 'export.ys'], root, 'export')
    result['mapped'] = verify(args.stage, cells)
    if identities != {name: sha(Path(name)) for name in identities}:
        raise ValueError('inputs changed during run')
    (args.stage/'summary.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main() -> None:
    """Require explicit tool versions and a fresh result directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'xls', 'yosys'):
        parser.add_argument('--'+name, required=True, type=lambda p: Path(p).resolve())
    parser.add_argument('--erl-hls', type=Path, help='Explicit compiler source root.')
    parser.add_argument('--profile', default='default')
    result = build(parser.parse_args())
    print(json.dumps({key: value for key, value in result.items() if key not in ('inputs', 'mapping')}, indent=2))
    for name, row in result['mapping'].items():
        print(name, row['luts'], 'LUTs', row['cells'], 'DSP depth', row['serial_dsp_upper_bound'])


if __name__ == '__main__':
    main()
