#!/usr/bin/env python3
"""Route verified reciprocal probes locally, rejecting unsupported DSP-register modes."""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil

import architecture_physical
from architecture import sha
from staged_reciprocal import run


def prepare(args: argparse.Namespace, name: str, summary: dict, manifest: dict) -> Path:
    """Preserve vendor launch/capture registers inside a small native activity harness."""
    root = args.stage / name
    root.mkdir()
    source = args.source / 'vendor' / name
    row = next(p for p in manifest['probes'] if p['name'] == name)
    for filename, fingerprint in row['files'].items():
        if sha(source / filename) != fingerprint:
            raise ValueError(f'changed vendor input: {name}/{filename}')
    for path in source.glob('*.v'):
        shutil.copyfile(path, root / path.name)
    (root / 'native.v').write_text('''// Native pins drive a registered stimulus; probe_top owns the measured boundaries.
module timing_chain(input wire clock, output reg activity = 0);
reg [39:0] stimulus = 1;
wire [37:0] captured;
always @(posedge clock) begin
  stimulus <= {stimulus[38:0], stimulus[39]^stimulus[37]^stimulus[20]^stimulus[0]};
  activity <= ^captured;
end
probe_top probe(.clock(clock), .n(stimulus[36:0]), .reset(stimulus[37]),
  .enable(stimulus[38]), .in_valid(stimulus[39]), .out(captured));
endmodule
''')
    packing = ('scratchpad -set xilinx_dsp.multonly 1\n'
               if name == 'split' and not summary['candidate_register_packing'] else '')
    rtl = ' '.join(p.name for p in sorted(root.glob('*.v')))
    (root / 'map.ys').write_text(f'read_verilog {rtl}\n' + packing +
        'synth_xilinx -flatten -abc9 -nosrl -family xc7 -top timing_chain\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
    run([str(args.yosys), '-Q', '-T', '-s', 'map.ys'], root, 'map')
    data = json.loads((root / 'mapped.json').read_text())
    architecture_physical.require_combinational_dsps(data)
    top = data['modules']['timing_chain']
    boundaries = [c for c in top['cells'].values() if c.get('attributes', {}).get('dont_touch') == 'yes']
    if len(boundaries) != 78 or any(c['type'] != 'FDRE' for c in boundaries):
        raise ValueError('launch/capture boundary changed')
    data['modules'] = {'timing_chain': top}
    (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    (root / 'mapping.json').write_text(json.dumps({'cells': dict(Counter(c['type'] for c in top['cells'].values())),
        'inputs': {str(p): sha(p) for p in (Path(__file__), args.yosys,
            args.source / 'summary.json', args.source / 'vendor/manifest.json')},
        'preserved_boundary_registers': len(boundaries)}, indent=2) + '\n')
    return root


def main() -> None:
    """Require successful mapped simulation and the same mapper before a matched physical screen."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'stage', 'yosys', 'nextpnr', 'chipdb'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()
    summary = json.loads((args.source / 'summary.json').read_text())
    manifest = json.loads((args.source / 'vendor/manifest.json').read_text())
    if summary['inputs'].get(str(args.yosys)) != sha(args.yosys):
        raise ValueError('mapper differs from verified arithmetic screen')
    if not all(v.startswith('PASS ') for v in summary['mapped_verification']['results'].values()):
        raise ValueError('mapped simulation did not pass')
    args.stage.mkdir(parents=True, exist_ok=False)
    for name in ('reference', 'split'):
        root = prepare(args, name, summary, manifest)
        architecture_physical.run(argparse.Namespace(stage=root, nextpnr=args.nextpnr,
            chipdb=args.chipdb, seed=args.seed, frequency=200, place_seconds=600, route_seconds=600))
        timing = json.loads((root / 'timing.json').read_text())
        print(name, timing['fmax'], flush=True)


if __name__ == '__main__':
    main()
