#!/usr/bin/env python3
"""Map the two 16-slot requester-context adapters to Xilinx 7-series primitives."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def measure(yosys, stage):
    stage.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'rtl/hls_return_routes.v'
    report = {'yosys': subprocess.check_output([str(yosys), '-V'], text=True).strip(),
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'slots': 16, 'target': 'xc7', 'adapters': {}}
    for name, cast in [('application', '255'), ('debug', "32'shffffffff")]:
        script = stage / f'{name}.ys'
        stats = stage / f'{name}.json'
        script.write_text(f'''read_verilog -sv "{source}"
chparam -set SLOTS 16 -set CAST_TXID {cast} hls_return_routes
hierarchy -check -top hls_return_routes
proc
opt
check -assert
scc -expect 0
synth_xilinx -family xc7 -top hls_return_routes -noiopad -noclkbuf
tee -o "{stats}" stat -json
''')
        with (stage / f'{name}.log').open('w') as log:
            subprocess.run([str(yosys), '-Q', '-T', '-s', str(script)], stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=120)
        cells = json.loads(stats.read_text())['modules']['\\hls_return_routes']['num_cells_by_type']
        report['adapters'][name] = {'logic_luts': sum(n for kind, n in cells.items() if kind.startswith('LUT')),
                                    'flip_flops': sum(n for kind, n in cells.items() if kind.startswith('FD')),
                                    'primitives': cells}
    (stage / 'report.json').write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    print(json.dumps(report, sort_keys=True, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('yosys', type=Path)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/context-area')
    args = parser.parse_args()
    measure(args.yosys.resolve(), args.stage.resolve())
