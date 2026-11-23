#!/usr/bin/env python3
"""Prepare preserved DSP A/B cascade outputs for independent timing extraction."""
import argparse
from collections import Counter
from itertools import product
import json
from pathlib import Path
from characterize import harness, run, sha


def source(a: str, b: str, registers: int, cascade: int) -> str:
    """Expose both cascade buses and the product with explicit legal register modes."""
    if a not in ('DIRECT', 'CASCADE') or b not in ('DIRECT', 'CASCADE'):
        raise ValueError('unknown input selection')
    if (registers, cascade) not in ((0, 0), (1, 1), (2, 1), (2, 2)):
        raise ValueError('unsupported cascade register configuration')
    return f'''// Cascade ports are dedicated inter-DSP wires, never fabric endpoints.
module operation(input clock,
    input [29:0] a, acin, input [17:0] b, bcin, output [95:0] out);
  wire [29:0] first_a, last_a;
  wire [17:0] first_b, last_b;
  wire [47:0] product_value, forwarded_value;
  cascade_stage producer(.clock(clock), .a(acin), .b(bcin),
    .acin(30'd0), .bcin(18'd0), .acout(first_a), .bcout(first_b));
  cascade_stage #(.A_SRC("{a}"), .B_SRC("{b}"), .REGISTERS({registers}),
    .CASCADE_REGISTERS({cascade})) middle(.clock(clock), .a(a), .b(b),
    .acin(first_a), .bcin(first_b), .acout(last_a), .bcout(last_b), .p(product_value));
  // Concatenate the forwarded buses onto P so the fabric can capture them.
  cascade_stage #(.A_SRC("CASCADE"), .B_SRC("CASCADE"), .CONCATENATE(1)) consumer(
    .clock(clock), .a(30'd0), .b(18'd0), .acin(last_a), .bcin(last_b), .p(forwarded_value));
  assign out = {{forwarded_value, product_value}};
endmodule

// One explicit DSP mode; each stage preserves the intended register settings.
module cascade_stage #(parameter A_SRC="DIRECT", B_SRC="DIRECT",
    REGISTERS=0, CASCADE_REGISTERS=0, CONCATENATE=0)(input clock,
    input [29:0] a, acin, input [17:0] b, bcin,
    output [29:0] acout, output [17:0] bcout, output [47:0] p);
  (* keep = 1, dont_touch = "yes" *) DSP48E1 #(
    .A_INPUT(A_SRC), .B_INPUT(B_SRC),
    .AREG(REGISTERS), .BREG(REGISTERS),
    .ACASCREG(CASCADE_REGISTERS), .BCASCREG(CASCADE_REGISTERS),
    .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(0),
    .ALUMODEREG(0), .CARRYINREG(0), .CARRYINSELREG(0),
    .INMODEREG(0), .OPMODEREG(0), .USE_MULT(CONCATENATE ? "NONE" : "MULTIPLY")
  ) dsp (
    .CLK(clock), .A(a), .ACIN(acin), .B(b), .BCIN(bcin),
    .C(48'd0), .D(25'd0), .PCIN(48'd0),
    .OPMODE(CONCATENATE ? 7'b0000011 : 7'b0000101), .ALUMODE(4'd0), .INMODE(5'd0),
    .CARRYIN(1'b0), .CARRYCASCIN(1'b0), .CARRYINSEL(3'd0), .MULTSIGNIN(1'b0),
    .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1),
    .CEC(1'b1), .CED(1'b1), .CEAD(1'b1), .CEM(1'b1), .CEP(1'b1),
    .CEALUMODE(1'b1), .CECARRYIN(1'b1), .CECTRL(1'b1), .CEINMODE(1'b1),
    .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
    .RSTM(1'b0), .RSTP(1'b0), .RSTALUMODE(1'b0),
    .RSTALLCARRYIN(1'b0), .RSTCTRL(1'b0), .RSTINMODE(1'b0),
    .ACOUT(acout), .BCOUT(bcout), .P(p)
  );
endmodule
'''


def prepare(stage: Path, yosys: Path) -> None:
    """Map sixteen mode fixtures, retaining every fabric boundary and DSP parameter."""
    stage.mkdir(parents=True, exist_ok=False)
    rows = []
    for a, b, (registers, cascade) in product(
            ('DIRECT', 'CASCADE'), ('DIRECT', 'CASCADE'), ((0, 0), (1, 1), (2, 1), (2, 2))):
        name = f'{a.lower()}_{b.lower()}_r{registers}_c{cascade}'
        root = stage / name
        root.mkdir()
        (root / 'operation.v').write_text(source(a, b, registers, cascade))
        wrapper = harness('operation', [('a', 30), ('acin', 30), ('b', 18), ('bcin', 18)], 96)
        wrapper = wrapper.replace('operation dut(', 'operation dut(.clock(clock), ')
        (root / 'harness.v').write_text(wrapper)
        (root / 'map.ys').write_text(
            'read_verilog operation.v harness.v\n'
            'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
            'check -assert\nscc -expect 0\ndelete t:$scopeinfo\n'
            'write_json mapped.json\nwrite_edif -pvector bra mapped.edf\n')
        run([yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map', timeout=300)
        data = json.loads((root / 'mapped.json').read_text())
        cells = data['modules']['probe_top']['cells']
        dsps = {name: cell for name, cell in cells.items() if cell['type'] == 'DSP48E1'}
        if len(dsps) != 3 or sum(c['type'] == 'FDRE' for c in cells.values()) != 192:
            raise ValueError(f'{name}: primitive or fabric boundary changed')
        middle = dsps['dut.middle.dsp']
        expected = dict(AREG=registers, BREG=registers, ACASCREG=cascade, BCASCREG=cascade)
        if any(int(middle['parameters'][key], 2) != value for key, value in expected.items()):
            raise ValueError(f'{name}: register mode changed')
        if middle['parameters']['A_INPUT'] != a or middle['parameters']['B_INPUT'] != b:
            raise ValueError(f'{name}: input selection changed')
        data['modules'] = {'probe_top': data['modules']['probe_top']}
        (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
        rows.append(dict(name=name, split='primitive', requested=dict(
            A_INPUT=a, B_INPUT=b, **expected), counts=dict(Counter(c['type'] for c in cells.values())),
            files={p.name: sha(p) for p in root.iterdir() if p.is_file()}))
        print(name, flush=True)
    (stage / 'manifest.json').write_text(json.dumps(dict(schema=1, part='xc7z030sbg485-1',
        tools={str(yosys): sha(yosys)}, probes=rows), indent=2) + '\n')


def main() -> None:
    """Require an explicit mapper and a fresh corpus directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    parser.add_argument('yosys', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    prepare(args.stage, args.yosys)


if __name__ == '__main__':
    main()
