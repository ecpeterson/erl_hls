#!/usr/bin/env python3
"""Map explicit register/RAM/DSP modes for primitive timing calibration."""
import argparse
from collections import Counter
import json
from itertools import product
from pathlib import Path
import re
from characterize import run, sha


def fixtures(extended: bool) -> list[tuple[str, int, str]]:
    """Return exact primitive modes; extended cases cover likely pipeline/FIFO changes."""
    source = (Path(__file__).resolve().parents[1] / 'timing_coverage/fixture.v').read_text()
    if not extended:
        return [(name, mode, source) for mode, name in enumerate(
            ('logic', 'ram', 'ram_registered', 'dsp', 'dsp_registered', 'ram_dsp'))]
    rows = []
    for a, b, multiply, output in product(range(3), range(3), range(2), range(2)):
        if (a, b, multiply, output) in ((0, 0, 0, 0), (0, 0, 1, 1)):
            continue  # Already measured by the base fixtures.
        text = source.replace('.AREG(0), .BREG(0), .ACASCREG(0), .BCASCREG(0)',
            f'.AREG({a}), .BREG({b}), .ACASCREG({a}), .BCASCREG({b})')
        text = text.replace('.MREG(MODE == 4), .PREG(MODE == 4)',
                            f'.MREG({multiply}), .PREG({output})')
        inputs = f'ab{a}' if a == b else f'a{a}_b{b}'
        rows.append((f'dsp_{inputs}_m{multiply}_p{output}', 3, text))
    for primitive, address in (('SRL16E', '.A0(flow[1]), .A1(flow[2]), .A2(flow[3]), .A3(flow[4])'),
                               ('SRLC32E', '.A(flow[5:1])')):
        text = f"""// Variable-address shift storage, with fabric launch/capture endpoints.
module timing_coverage_fixture #(parameter MODE = 0)(input wire clock, output wire activity);
reg [31:0] flow = 32'h12345678;
reg digest = 0;
wire result;
always @(posedge clock) begin
    flow <= {{flow[30:0], flow[31]^flow[21]^flow[1]^flow[0]}};
    digest <= result;
end
{primitive} #(.INIT(0)) storage(.CLK(clock), .CE(flow[6]), .D(flow[0]), {address}, .Q(result));
assign activity = digest;
endmodule
"""
        rows.append((primitive.lower(), 0, text))
    return rows


def check_register_mode(name: str, cells: dict) -> dict[str, int]:
    """Reject a DSP probe if mapping changed its requested input/M/P register modes."""
    match = re.fullmatch(r'dsp_(?:ab([0-2])|a([0-2])_b([0-2]))_m([01])_p([01])', name)
    if match is None:
        return {}
    a, b = (int(match[1]), int(match[1])) if match[1] else (int(match[2]), int(match[3]))
    expected = dict(AREG=a, ACASCREG=a, BREG=b, BCASCREG=b, MREG=int(match[4]), PREG=int(match[5]))
    modes = [cell['parameters'] for cell in cells.values() if cell['type'] == 'DSP48E1']
    if len(modes) != 1 or any(int(modes[0][key], 2) != value for key, value in expected.items()):
        raise ValueError(f'{name}: mapping changed the requested DSP register configuration')
    return expected


def prepare(stage: Path, yosys: Path, extended: bool = False, names: list[str] | None = None) -> None:
    """Map the existing endpoint-audit fixtures without altering their primitive modes."""
    selected = fixtures(extended)
    if names is not None:
        if len(names) != len(set(names)) or set(names) - {row[0] for row in selected}:
            raise ValueError('unknown or duplicate primitive fixture')
        selected = [row for row in selected if row[0] in names]
    stage.mkdir(parents=True, exist_ok=False)
    rows = []
    for name, mode, source in selected:
        root = stage / name
        root.mkdir()
        (root / 'fixture.v').write_text(source)
        (root / 'map.ys').write_text(
            f'read_verilog fixture.v\nchparam -set MODE {mode} timing_coverage_fixture\n'
            'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top timing_coverage_fixture\n'
            'rename timing_coverage_fixture probe_top\ncheck -assert\nscc -expect 0\n'
            'delete t:$scopeinfo\nwrite_json mapped.json\nwrite_edif -pvector bra mapped.edf\n')
        run([yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map')
        data = json.loads((root / 'mapped.json').read_text())
        data['modules'] = {'probe_top': data['modules']['probe_top']}
        (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
        cells = data['modules']['probe_top']['cells']
        rows.append({'name': name, 'split': 'primitive', 'requested_registers': check_register_mode(name, cells), 'counts': dict(Counter(c['type'] for c in cells.values())),
                     'hard_modes': {n: c['parameters'] for n, c in cells.items() if c['type'].startswith(('RAMB', 'DSP', 'SRL'))},
                     'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
    (stage / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
                                                  'probes': rows}, indent=2) + '\n')


def main() -> None:
    """Require an explicit native mapper and a fresh stage."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('yosys', type=Path)
    parser.add_argument('--extended', action='store_true', help='additional DSP register and shift-register modes')
    parser.add_argument('--names', nargs='+', help='measure an explicit subset of the selected fixture set')
    args = parser.parse_args()
    prepare(args.stage.resolve(), args.yosys.resolve(), args.extended, args.names)


if __name__ == '__main__':
    main()
