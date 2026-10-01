#!/usr/bin/env python3
"""Map one immutable D6 device at matched scheduler/reduction placements."""
import argparse
import importlib
import json
from pathlib import Path
from backend_paths import PUBLIC
import statistics
import subprocess
import sys

from test_actor_rtl import digest
from test_phi_mesh import artifacts


def measure(args: argparse.Namespace) -> None:
    """Retain complete device resource counts; reject any changed compiled input or output."""
    device = args.build / f'device{args.device}'
    if json.loads((device/'complete.json').read_text()) != artifacts(device):
        raise ValueError('device differs from its checked build')
    if json.loads((args.build/'source-hashes.json').read_text()) != artifacts(args.build/'source'):
        raise ValueError('generated source differs from its checked build')
    args.stage.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(args.erl_hls/'tools'))
    accounting = importlib.import_module('measure_topology_debug')
    sources = [device/'debug'/name for name in ('instrumented.v', 'debug_top.v')]
    sources += [args.erl_hls/'priv/rtl/debug'/name for name in
                ('hls_debug_frame_rx.v', 'hls_debug_route.v', 'hls_topology_debug.v', 'hls_actor_snapshot.v')]
    hashes = {str(path): digest(path) for path in sources}
    manifest = json.loads((device/'debug/manifest.json').read_text())
    top = f'hls_phi_debug_{args.device}'
    report = {
        'scope': 'Complete D6 device: actors, state/mailbox RAM, application gateway, four credit links and public topology/actor queries. Excludes external CDC FIFOs, optional counters/trace, PS, DMA, Ethernet/GT and pads. Synthesis only; no placed frequency or fit claim.',
        'device': args.device, 'build': str(args.build),
        'build_inputs_sha256': digest(args.build/'inputs.json'),
        'complete_sha256': digest(device/'complete.json'),
        'reductions': json.loads((args.build/'source/bridge.json').read_text()).get('reductions', 'ordinary'),
        'scheduler_groups': [{k: bank[k] for k in ('index', 'module', 'slots')}
                             for bank in manifest['actor_projection']['banks']],
        'yosys': subprocess.check_output([args.yosys, '-V'], text=True).strip(),
        'sources': hashes, 'driver_sha256': digest(Path(__file__)), 'samples': []}
    for seed in args.seeds:
        script = args.stage/f'seed-{seed}.ys'
        script.write_text('read_verilog -sv '+' '.join(json.dumps(str(p)) for p in sources)+f'''
hierarchy -check -top {top}
proc
flatten
opt
rename -scramble-name -seed {seed}
synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top {top}
check -assert
scc -expect 0
tee -o seed-{seed}.json stat -json -tech xilinx
''')
        with (args.stage/f'seed-{seed}.log').open('w') as log:
            subprocess.run([args.yosys, '-Q', '-T', '-s', str(script)], cwd=args.stage,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=args.timeout)
        cells = json.loads((args.stage/f'seed-{seed}.json').read_text())['design']['num_cells_by_type']
        sample = {'seed': seed, **accounting.cell_counts(cells), 'DSP': cells.get('DSP48E1', 0), 'primitives': cells}
        report['samples'].append(sample)
        report['summary'] = {key: {'samples': len(values), 'best': min(values), 'mean': statistics.mean(values),
            'variance': statistics.pvariance(values), 'worst': max(values)}
            for key in ('LUT', 'LUT_logic', 'LUT_RAM', 'FF', 'RAMB18', 'RAMB36', 'DSP')
            for values in [[s[key] for s in report['samples']]]}
        (args.stage/'report.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(sample), flush=True)
    if hashes != {str(path): digest(path) for path in sources}:
        raise ValueError('hardware changed during mapping')


def main() -> None:
    """Select one representative board and start with a single matched naming seed."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--erl-hls', type=Path, default=PUBLIC)
    parser.add_argument('--device', type=int, default=0)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--seeds', type=int, nargs='+', default=[1])
    parser.add_argument('--timeout', type=int, default=3600)
    args = parser.parse_args()
    for name in ('build', 'stage', 'erl_hls'):
        setattr(args, name, getattr(args, name).resolve())
    measure(args)


if __name__ == '__main__':
    main()
