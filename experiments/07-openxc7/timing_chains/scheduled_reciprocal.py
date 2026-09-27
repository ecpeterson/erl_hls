#!/usr/bin/env python3
"""Check ordinary XLS reciprocal pipelines before and after Xilinx mapping."""
import argparse
import json
from pathlib import Path

from staged_reciprocal import ROOT, map_kernel, run, vectors
from architecture import sha


def verify(stage: Path, name: str, *, cells: Path | None = None) -> str:
    """Compare every accepted quotient with an integer oracle under stalls and resets."""
    source = [str(stage / name / 'kernel.v')] if cells is None else [str(stage / name / 'mapped.v'), str(cells)]
    label = name + ('-mapped' if cells else '-generated')
    run(['iverilog', '-g2012', '-s', 'testbench', '-o', 'sim.vvp', 'testbench.sv', *source], stage, label + '-compile')
    run(['vvp', 'sim.vvp'], stage, label + '-simulation')
    log = (stage / (label + '-simulation.log')).read_text()
    if not log.startswith('PASS '):
        raise ValueError(log)
    (stage / 'sim.vvp').unlink()
    return log.splitlines()[0]


def main() -> None:
    """Require explicit tools, stage budget and a fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'xls', 'codegen', 'table', 'yosys'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--stages', type=int, choices=(2, 3), default=2)
    parser.add_argument('--fabric-registers', action='store_true')
    args = parser.parse_args()
    stage = args.stage
    stage.mkdir(parents=True, exist_ok=False)
    cases = vectors()
    cases = cases[:1024] + cases[65024:66049] + cases[131073:131533] + cases[-3000:]
    encoded = [((n & ((1 << 37) - 1)) << 37) |
               ((((abs(n) + 6) // 12) * (-1 if n < 0 else 1)) & ((1 << 37) - 1)) for n in cases]
    (stage / 'vectors.hex').write_text('\n'.join(f'{v:019x}' for v in encoded) + '\n')
    (stage / 'testbench.sv').write_text('''module testbench;
reg clk=0; always #5 clk=!clk;
reg reset=1, _input_vld=0, _output_rdy=0;
reg [36:0] _input; wire [36:0] _output; wire _input_rdy, _output_vld;
reg [73:0] cases[0:COUNT-1]; reg [36:0] expected[0:COUNT-1];
reg [31:0] rng=32'h719acd83; reg blocked=0; reg [36:0] previous;
integer sent=0, received=0, head=0, tail=0, cycle=0, stalls=0, resets=0;
kernel dut(.*);
initial begin
  $readmemh("vectors.hex",cases);
  repeat(COUNT*8) begin
    @(negedge clk);
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    reset=cycle==0 || cycle%1009==1008;
    _input_vld=sent<COUNT;
    _input=sent<COUNT?cases[sent][73:37]:0;
    _output_rdy=rng[2:0]==0 || cycle%47<30;
    @(posedge clk);
    if(reset) begin head=0;tail=0;blocked=0;resets=resets+1;end
    else begin
      if(blocked && (!_output_vld || _output!==previous)) $fatal(1,"unstable blocked output");
      if(_input_vld && _input_rdy) begin expected[tail]=cases[sent][36:0];tail=tail+1;sent=sent+1;end
      if(_output_vld && _output_rdy) begin
        if(head==tail || _output!==expected[head]) $fatal(1,"quotient mismatch at cycle %0d: %h expected %h",cycle,_output,expected[head]);
        head=head+1;received=received+1;
      end
      blocked=_output_vld && !_output_rdy;previous=_output;
      if(blocked) stalls=stalls+1;
      if(sent==COUNT && head==tail) begin
        $display("PASS accepted=%0d checked=%0d stalls=%0d resets=%0d cycles=%0d",sent,received,stalls,resets,cycle);$finish;
      end
    end
    cycle=cycle+1;
  end
  $fatal(1,"no progress");
end
endmodule
'''.replace('COUNT', str(len(cases))))
    cells = args.yosys.parent.parent / 'share/yosys/xilinx/cells_sim.v'
    inputs = [ROOT / 'priv/xls/lib/hls_fixed.x', ROOT / 'priv/xls/lib/hls_multiply.x',
              args.table, args.codegen, args.yosys, cells,
              args.xls / 'ir_converter_main', args.xls / 'opt_main']
    summary = {'stages': args.stages, 'fabric_registers': args.fabric_registers,
               'inputs': {str(p): sha(p) for p in inputs}, 'variants': {}}
    for name, operation in [('reference', 'round_ratio<u32:12>'),
                            ('split', 'round_ratio_chunked<u32:12, u32:24, u32:17>')]:
        root = stage / name
        root.mkdir()
        (root / 'design.x').write_text('''import hls_fixed;
// Stateless exact arithmetic; ready/valid stage ownership is supplied by XLS.
pub proc Top {
  input: chan<sN[37]> in;
  output: chan<sN[37]> out;
  config(input: chan<sN[37]> in, output: chan<sN[37]> out) { (input, output) }
  init { () }
  next(state: ()) {
    let (tok, n) = recv(join(), input);
    send(tok, output, hls_fixed::OPERATION(n));
  }
}
'''.replace('OPERATION', operation))
        run([str(args.xls / 'ir_converter_main'), '--warnings_as_errors=false', '--top=Top',
             '--dslx_path=' + str(ROOT / 'priv/xls/lib'),
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), 'design.x'], root, 'ir', 'design.ir')
        run([str(args.xls / 'opt_main'), 'design.ir'], root, 'opt', 'design.opt.ir')
        run([str(args.codegen), '--pipeline_stages=' + str(args.stages), '--flop_inputs=false',
             '--flop_outputs=true', '--reset=reset', '--worst_case_throughput=1',
             '--delay_model=xc7_7030', '--xc7_delay_table=' + str(args.table), '--xc7_routed_delays=false',
             '--module_name=kernel', '--use_system_verilog=false', '--output_schedule_path=schedule.textproto',
             'design.opt.ir'], root, 'codegen', 'kernel.v')
        result = {'generated': verify(stage, name)}
        args.pack_candidate_registers = not args.fabric_registers
        result['mapping'] = map_kernel(args, name)
        run([str(args.yosys), '-Q', '-T', '-p', f'read_verilog -lib {cells}; read_json mapped.json; write_verilog -noattr mapped.v'], root, 'netlist')
        summary['variants'][name] = result
        (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        result['mapped'] = verify(stage, name, cells=cells)
        if summary['inputs'] != {str(p): sha(p) for p in inputs}:
            raise ValueError('arithmetic sources or tools changed during the check')
        (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(name, result['mapped'], flush=True)


if __name__ == '__main__':
    main()
