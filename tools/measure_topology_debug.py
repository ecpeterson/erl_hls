#!/usr/bin/env python3
"""Measure the optional query logic at its observation boundary with Yosys XC7.

Application signals become unconstrained inputs, retaining aliases/constants.
This isolates diagnostic logic cost; it does not measure whole-design area or
routing delay, or account for optimization from application-specific invariants.
"""
from pathlib import Path
import argparse
import hashlib
import sys
import json
import subprocess
import statistics

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tools'))
import topology_debug as topology
import topology_debug_actors as actors


def distribution(values):
    return {'best': min(values), 'mean': statistics.mean(values),
            'variance': statistics.pvariance(values), 'worst': max(values)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('instrumented', type=Path, help='instrumentation directory containing manifest/hierarchy/flat JSON')
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--seeds', type=int, default=5)
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error('--seeds must be positive')
    stage = args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.instrumented / 'manifest.json').read_text())
    body = {k: v for k, v in manifest.items() if k != 'fingerprint'}
    canonical = json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()
    fingerprint = hashlib.sha256(canonical).hexdigest()
    if manifest['schema'] != 3 or manifest['fingerprint'] != fingerprint:
        raise ValueError('corrupt or unsupported manifest')
    hierarchy = json.loads((args.instrumented / 'hierarchy.json').read_text())
    flat = json.loads((args.instrumented / 'flat.json').read_text())['modules'][manifest['top']]
    banks = actors.discover(manifest['actor_projection'], manifest['actor_root'], hierarchy,
                            flat, manifest['top'], topology.flat_bit(flat, [], manifest['clock']))
    physical = [r for r in manifest['resources'] if r['kind'] != 'actor']
    all_bits = sorted({b for r in physical for b in r['bits'] if isinstance(b, int)} |
                      {b for bank in banks for b in bank['taps'] if isinstance(b, int)})
    indices = {b: i for i, b in enumerate(all_bits)}

    def vector(bits):
        return '{' + ', '.join(f'observed[{indices[b]}]' if isinstance(b, int) else "1'b" + b
                              for b in reversed(bits)) + '}'

    rtl = root / 'priv/rtl/debug'
    yosys = args.yosys
    (stage / 'yosys-version.txt').write_bytes(subprocess.check_output([yosys, '-V']))
    results = []
    for mode in ('physical', 'actors'):
        selected = banks if mode == 'actors' else []
        count = len(physical) + sum(b['slots'] for b in selected)
        lines = ['module measured(input wire clk, reset,',
                 f'input wire [{len(all_bits) - 1}:0] observed,',
                 'input wire [31:0] s_data, input wire [3:0] s_keep, input wire s_last,s_valid,',
                 'output wire s_ready, output wire [31:0] m_data, output wire [3:0] m_keep,',
                 'output wire m_last,m_valid, input wire m_ready);',
                 f'wire [{count * 32 - 1}:0] probe_values;']
        for r in physical:
            bits = r['bits'] + ['0'] * (32 - r['width'])
            lines.append(f"assign probe_values[{32 * r['id']}+:32] = {vector(bits)};")
        if selected:
            taps = [b for bank in banks for b in bank['taps']]
            lines.append(f'wire [{len(taps) - 1}:0] actor_writes = {vector(taps)};')
            lines.append(actors.wrapper(banks, len(physical), 'clk', 'reset', False))
        fingerprint = int.from_bytes(bytes.fromhex(manifest['fingerprint']), 'little')
        lines.append(f"hls_topology_debug #(.RESOURCES({count}), .CHANNELS({len(manifest['probes'])}), "
                     f".ACTORS({count - len(physical)}), .FINGERPRINT(256'h{fingerprint:x})) controller (.*);")
        lines.append('endmodule')
        folder = stage / mode
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'sidecar.v').write_text('\n'.join(lines) + '\n')
        for seed in range(1, args.seeds + 1):
            prefix = folder / f'seed-{seed}'
            sources = [folder / 'sidecar.v', rtl / 'hls_actor_snapshot.v',
                       rtl / 'hls_topology_debug.v', rtl / 'hls_debug_frame_rx.v']
            script = 'read_verilog -sv ' + ' '.join(map(topology.quote, sources)) + '\n'
            script += f'hierarchy -check -top measured\nproc\nflatten\nopt\nrename -scramble-name -seed {seed}\n'
            script += 'synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top measured\n'
            script += f"tee -o {topology.quote(prefix.with_suffix('.json'))} stat -json -tech xilinx\n"
            prefix.with_suffix('.ys').write_text(script)
            with prefix.with_suffix('.log').open('w') as log:
                subprocess.run([yosys, '-Q', '-s', str(prefix.with_suffix('.ys'))],
                               stdout=log, stderr=log, check=True)
            cells = json.loads(prefix.with_suffix('.json').read_text())['design']['num_cells_by_type']
            row = {'mode': mode, 'seed': seed,
                   'LUT': sum(v for k, v in cells.items() if k.startswith('LUT')),
                   'FF': sum(v for k, v in cells.items() if k.startswith('FD')),
                   'BRAM': sum(v for k, v in cells.items() if k.startswith('RAMB'))}
            results.append(row)
            (stage / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
            print(row, flush=True)
    summary = {}
    for mode in ('physical', 'actors'):
        rows = [r for r in results if r['mode'] == mode]
        summary[mode] = {k: distribution([r[k] for r in rows]) for k in ('LUT', 'FF', 'BRAM')}
    (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(summary, flush=True)


if __name__ == '__main__':
    main()
