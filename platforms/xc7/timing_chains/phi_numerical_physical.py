#!/usr/bin/env python3
"""Route matched complete-engine probes with preserved launch/capture registers."""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil
import sys

import architecture_physical
from architecture import sha
from phi_numerical import HERE
from staged_reciprocal import run

sys.path.insert(0, str(HERE.parent))
from timing_coverage.check import check, requirements


def audit(root: Path) -> dict:
    """Include register enables/reset in the endpoint screen, not just data and DSP pins."""
    data = json.loads((root/'coverage.json').read_text())
    expected = requirements('dsp')
    for port in ('CE', 'SR'):
        if any(port in c['ports'] for c in data['cells'].values() if c['type'] == 'SLICE_FFX'):
            expected.append({'type': 'SLICE_FFX', 'port': port, 'class': 'register_input'})
    result = check(data, expected)
    (root/'control-endpoint-audit.json').write_text(json.dumps(result, indent=2)+'\n')
    if not result['endpoint_requirements_met']:
        raise ValueError('missing register control timing endpoints')
    return result


def prepare(root: Path, kernel: Path, yosys: Path, latency: int) -> dict:
    """Map the four-owner engine with identical registered pins around each variant."""
    root.mkdir(parents=True, exist_ok=False)
    sources = [HERE/'phi_numerical_bank.sv', *[p for p in kernel.glob('*.v') if p.name != 'mapped.v']]
    for source in sources:
        shutil.copyfile(source, root/source.name)
    (root/'native.v').write_text(f'''// Preserve the full command and response boundary for a matched timing screen.
module timing_chain(input wire clock, output reg activity = 0);
reg [203:0] stimulus = 1;
wire [202:0] launched;
wire [103:0] captured;
wire [103:0] response;
always @(posedge clock) begin
  stimulus <= {{stimulus[202:0], stimulus[203]^stimulus[196]^stimulus[21]^stimulus[0]}};
  activity <= ^captured;
end
genvar i;
generate for (i=0;i<203;i=i+1) begin: launch
  (* keep = 1, dont_touch = "yes" *) FDRE ff
    (.C(clock), .CE(1'b1), .R(1'b0), .D(stimulus[i]), .Q(launched[i]));
end
for (i=0;i<104;i=i+1) begin: capture
  (* keep = 1, dont_touch = "yes" *) FDRE ff
    (.C(clock), .CE(1'b1), .R(1'b0), .D(response[i]), .Q(captured[i]));
end endgenerate
phi_numerical_bank #(.SLOTS(4), .LATENCY({latency})) dut(
 .clk(clock), .reset(launched[0]), .cmd_valid(launched[1]), .rsp_ready(launched[2]),
 .cmd_kind(launched[4:3]), .cmd_slot(launched[6:5]), .cmd_epoch(launched[38:7]),
 .cmd_field0(launched[70:39]), .cmd_field1(launched[102:71]), .cmd_anyon(launched[134:103]),
 .cmd_sum0(launched[168:135]), .cmd_sum1(launched[202:169]),
 .cmd_ready(response[0]), .rsp_valid(response[1]), .rsp_slot(response[3:2]),
 .rsp_kind(response[5:4]), .rsp_error(response[7:6]), .rsp_epoch(response[39:8]),
 .rsp_field0(response[71:40]), .rsp_field1(response[103:72]));
endmodule
''')
    rtl = ' '.join([p.name for p in sources] + ['native.v'])
    (root/'map.ys').write_text('read_verilog -sv '+rtl+'\n'
        'scratchpad -set xilinx_dsp.multonly 1\n'
        'synth_xilinx -flatten -abc9 -nosrl -family xc7 -top timing_chain\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
    run([str(yosys), '-Q', '-T', '-s', 'map.ys'], root, 'map')
    data = json.loads((root/'mapped.json').read_text())
    architecture_physical.require_combinational_dsps(data)
    top = data['modules']['timing_chain']
    boundaries = [c for c in top['cells'].values() if c.get('attributes', {}).get('dont_touch') == 'yes']
    if len(boundaries) != 307 or any(c['type'] != 'FDRE' for c in boundaries):
        raise ValueError('launch/capture boundaries changed')
    data['modules'] = {'timing_chain': top}
    (root/'mapped.json').write_text(json.dumps(data, separators=(',', ':'))+'\n')
    result = {'cells': dict(Counter(c['type'] for c in top['cells'].values())),
              'preserved_boundary_registers': len(boundaries),
              'inputs': {str(p): sha(p) for p in [Path(__file__), yosys, *sources]}}
    (root/'mapping.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main() -> None:
    """Require passed mapped-engine simulations before the bounded physical comparison."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'kernel', 'bank', 'yosys', 'nextpnr', 'chipdb'):
        parser.add_argument('--'+name, required=True, type=lambda p: Path(p).resolve())
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()
    verification = json.loads((args.bank/'summary.json').read_text())
    args.stage.mkdir(parents=True, exist_ok=False)
    for name, latency in (('reference', 1), ('split', 5)):
        row = verification[name+'-4']
        if row['mapped'] != row['reset']:
            raise ValueError('mapped simulation differs from the RTL control')
        if any(sha(Path(path)) != value for path,value in row['mapping']['inputs'].items()):
            raise ValueError('verified sources or mapper changed')
        root = args.stage/name
        prepare(root, args.kernel/name, args.yosys, latency)
        architecture_physical.run(argparse.Namespace(stage=root, nextpnr=args.nextpnr, chipdb=args.chipdb,
            seed=args.seed, frequency=200, place_seconds=300, route_seconds=300))
        audit(root)
        print(name, json.loads((root/'timing.json').read_text())['fmax'], flush=True)


if __name__ == '__main__':
    main()
