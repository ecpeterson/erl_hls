#!/usr/bin/env python3
"""Measure topology/actor queries and optional counters/trace with Yosys XC7.

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


def cell_counts(cells):
    # XC7 primitive footprints from AMD UG953. RAM32M/RAM64M each occupy
    # four SLICEM LUTs, even when some ports/bits are unused. Count them in
    # addition to logic LUTs so moving registers into RAM cannot hide area.
    # https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/RAM32M
    memory_luts = {'RAM32M': 4, 'RAM64M': 4,
                   'RAM32X1S': 1, 'RAM32X1S_1': 1, 'RAM32X2S': 1,
                   'RAM64X1S': 1, 'RAM64X1S_1': 1,
                   'RAM128X1S': 2, 'RAM256X1S': 4,
                   'RAM32X1D': 2, 'RAM64X1D': 2, 'RAM128X1D': 4}
    ram = {k: v for k, v in cells.items() if k.startswith('RAM') and not k.startswith('RAMB')}
    if unknown := ram.keys() - memory_luts.keys():
        raise ValueError(f'unaccounted distributed RAM primitives: {sorted(unknown)}')
    logic = sum(v for k, v in cells.items() if k.startswith('LUT'))
    memory = sum(memory_luts[k] * v for k, v in ram.items())
    return {'LUT': logic + memory, 'LUT_logic': logic, 'LUT_RAM': memory,
            'FF': sum(v for k, v in cells.items() if k.startswith('FD')),
            'RAMB18': cells.get('RAMB18E1', 0), 'RAMB36': cells.get('RAMB36E1', 0)}


def sidecar(mode, physical, selected, indices, manifest):
    def vector(bits):
        return '{' + ', '.join(f'observed[{indices[b]}]' if isinstance(b, int) else "1'b" + b
                              for b in reversed(bits)) + '}'

    count = len(physical) + sum(b['slots'] for b in selected)
    ports = ['module measured(input wire clk, reset,',
             f'input wire [{len(indices) - 1}:0] observed,',
             'input wire [31:0] s_data, input wire [3:0] s_keep, input wire s_last,s_valid,',
             'output wire s_ready, output wire [31:0] m_data, output wire [3:0] m_keep,',
             'output wire m_last,m_valid, input wire m_ready']
    monitor = mode in ('boundary', 'all')
    if monitor:
        ports += [', input wire [31:0] rx_data, tx_data,',
                  'input wire rx_valid, rx_ready, rx_last, tx_valid, tx_ready, tx_last,',
                  'input wire [31:0] s_mon_data, input wire [3:0] s_mon_keep,',
                  'input wire s_mon_valid, s_mon_last, output wire s_mon_ready,',
                  'output wire [31:0] m_mon_data, output wire [3:0] m_mon_keep,',
                  'output wire m_mon_valid, m_mon_last, input wire m_mon_ready']
        ports.append(');')
    else:
        ports[-1] += ');'
    lines = ports
    if mode != 'boundary':
        lines.append(f'wire [{len(physical) * 64 - 1}:0] probe_values;')
    for r in physical if mode != 'boundary' else []:
        bits = r['bits'] + ['0'] * (64 - r['width'])
        lines.append(f"assign probe_values[{64 * r['id']}+:64] = {vector(bits)};")
    if selected:
        taps = [b for bank in selected for b in bank['taps']]
        lines.append(f'wire [{len(taps) - 1}:0] actor_writes = {vector(taps)};')
    if mode != 'boundary':
        lines.append(actors.wrapper(selected, len(physical), 'clk', 'reset', False))
    fingerprint = int.from_bytes(bytes.fromhex(manifest['fingerprint']), 'little')
    if mode != 'boundary':
        lines.append(f"hls_topology_debug #(.RESOURCES({count}), .CHANNELS({len(manifest['probes'])}), "
                     f".ACTORS({count - len(physical)}), .FINGERPRINT(256'h{fingerprint:x})) controller (.*);")
    else:
        lines.append("assign s_ready=0; assign m_data=0; assign m_keep=0; assign m_last=0; assign m_valid=0;")
    if monitor:
        lines.append('hls_debug_monitor #(.ROUTED(1)) boundary (.aclk(clk), .aresetn(!reset),')
        connections = [f'.app_{d}_t{signal}({d}_{signal})'
                       for d in ('rx', 'tx') for signal in ('data', 'valid', 'ready', 'last')]
        connections += [f'.{d}_dbg_t{signal}({d}_mon_{signal})'
                        for d in ('s', 'm') for signal in ('data', 'keep', 'valid', 'ready', 'last')]
        lines.append(', '.join(connections) + ');')
    lines.append('endmodule')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('instrumented', type=Path, help='instrumentation directory containing manifest/hierarchy/flat JSON')
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--seeds', type=int, default=5)
    parser.add_argument('--monitor-rtl', type=Path,
                        help='directory with lowered hls_debug_observer.v and hls_debug_server.v; '
                             'also measure routed counters/trace and all hooks together')
    parser.add_argument('--modes', nargs='+', choices=['physical', 'actor_state', 'actors', 'boundary', 'all'],
                        help='measure only these modes (default: all available modes)')
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error('--seeds must be positive')
    if args.monitor_rtl:
        for name in ('hls_debug_observer.v', 'hls_debug_server.v'):
            if not (args.monitor_rtl / name).is_file():
                parser.error(f'missing generated monitor RTL: {args.monitor_rtl / name}')
    stage = args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.instrumented / 'manifest.json').read_text())
    body = {k: v for k, v in manifest.items() if k != 'fingerprint'}
    canonical = json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()
    fingerprint = hashlib.sha256(canonical).hexdigest()
    if manifest['schema'] != 4 or manifest['fingerprint'] != fingerprint:
        raise ValueError('corrupt or unsupported manifest')
    hierarchy = json.loads((args.instrumented / 'hierarchy.json').read_text())
    flat = json.loads((args.instrumented / 'flat.json').read_text())['modules'][manifest['top']]
    banks = actors.discover(manifest['actor_projection'], manifest['actor_root'], hierarchy,
                            flat, manifest['top'], topology.flat_bit(flat, [], manifest['clock']))
    physical = [r for r in manifest['resources'] if r['kind'] != 'actor']
    all_bits = sorted({b for r in physical for b in r['bits'] if isinstance(b, int)} |
                      {b for bank in banks for b in bank['taps'] if isinstance(b, int)})
    indices = {b: i for i, b in enumerate(all_bits)}

    rtl = root / 'priv/rtl/debug'
    yosys = args.yosys
    (stage / 'yosys-version.txt').write_bytes(subprocess.check_output([yosys, '-V']))
    modes = ['physical']
    if any('mailbox' in bank for bank in banks):
        modes.append('actor_state')
    modes.append('actors')
    if args.monitor_rtl:
        modes += ['boundary', 'all']
    if args.modes:
        if unavailable := set(args.modes) - set(modes):
            parser.error(f'modes unavailable with these inputs: {sorted(unavailable)}')
        modes = list(dict.fromkeys(args.modes))
    results = []
    for mode in modes:
        selected = banks if mode in ('actor_state', 'actors', 'all') else []
        if mode == 'actor_state':
            # Hold the query protocol and observed application fixed while
            # measuring just the pre-existing phase/failure retention path.
            selected = [{k: v for k, v in bank.items() if k != 'mailbox'}
                        for bank in banks]
            for bank in selected:
                bank['taps'] = bank['taps'][:1 + bank['address_width'] + 25]
        folder = stage / mode
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'sidecar.v').write_text(sidecar(mode, physical, selected, indices, manifest))
        monitor = mode in ('boundary', 'all')
        sources = [folder / 'sidecar.v', rtl / 'hls_actor_snapshot.v',
                   rtl / 'hls_topology_debug.v', rtl / 'hls_debug_frame_rx.v']
        if monitor:
            sources += [rtl / name for name in ('hls_debug_monitor.v', 'hls_debug_tap.v', 'hls_trace_store.v')]
            sources += [args.monitor_rtl / name for name in ('hls_debug_observer.v', 'hls_debug_server.v')]
        provenance = {'manifest': manifest['fingerprint'], 'mode': mode,
                      'sources': {str(p.resolve()): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
        (folder / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
        for seed in range(1, args.seeds + 1):
            prefix = folder / f'seed-{seed}'
            script = 'read_verilog -sv ' + ' '.join(map(topology.quote, sources)) + '\n'
            script += f'hierarchy -check -top measured\nproc\nflatten\nopt\nrename -scramble-name -seed {seed}\n'
            script += 'synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top measured\n'
            script += 'check -assert\nscc -expect 0\n'
            script += f"tee -o {topology.quote(prefix.with_suffix('.json'))} stat -json -tech xilinx\n"
            prefix.with_suffix('.ys').write_text(script)
            with prefix.with_suffix('.log').open('w') as log:
                subprocess.run([yosys, '-Q', '-s', str(prefix.with_suffix('.ys'))],
                               stdout=log, stderr=log, check=True)
            cells = json.loads(prefix.with_suffix('.json').read_text())['design']['num_cells_by_type']
            row = {'mode': mode, 'seed': seed, **cell_counts(cells)}
            results.append(row)
            (stage / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
            print(row, flush=True)
    summary = {}
    for mode in modes:
        rows = [r for r in results if r['mode'] == mode]
        summary[mode] = {k: distribution([r[k] for r in rows])
                         for k in ('LUT', 'LUT_logic', 'LUT_RAM', 'FF', 'RAMB18', 'RAMB36')}
    (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(summary, flush=True)


if __name__ == '__main__':
    main()
