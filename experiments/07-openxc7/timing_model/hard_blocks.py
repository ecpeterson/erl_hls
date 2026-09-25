#!/usr/bin/env python3
"""Map explicit register/RAM/DSP modes for primitive timing calibration."""
import argparse
from collections import Counter
import json
from pathlib import Path
from characterize import run, sha


def prepare(stage: Path, yosys: Path) -> None:
    """Map the existing endpoint-audit fixtures without altering their primitive modes."""
    stage.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parents[1] / 'timing_coverage/fixture.v'
    rows = []
    for mode, name in enumerate(('logic', 'ram', 'ram_registered', 'dsp', 'dsp_registered', 'ram_dsp')):
        root = stage / name
        root.mkdir()
        (root / 'fixture.v').write_text(source.read_text())
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
        rows.append({'name': name, 'split': 'primitive', 'counts': dict(Counter(c['type'] for c in cells.values())),
                     'hard_modes': {n: c['parameters'] for n, c in cells.items() if c['type'].startswith(('RAMB', 'DSP'))},
                     'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
    (stage / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
                                                  'probes': rows}, indent=2) + '\n')


def main() -> None:
    """Require an explicit native mapper and a fresh stage."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('yosys', type=Path)
    args = parser.parse_args()
    prepare(args.stage.resolve(), args.yosys.resolve())


if __name__ == '__main__':
    main()
