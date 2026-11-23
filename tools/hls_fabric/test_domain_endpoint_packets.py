"""Simulate a normally compiled packet router against finite explicit arbitration and framing vectors."""
import argparse
import json
import os
from pathlib import Path
import re
from typing import Any

from backend_commands import digest, run
from backend_paths import ROOT
from test_domain_endpoints import Endpoint, bundle_file, executable, field_value, hexadecimal, pins, require, wiring


REQUIRED_COVERAGE = {
    'eight_offer_round_robin', 'stalled_selection_pinned', 'rx_progress_while_tx_stalled',
    'all_data_ack_full_identity', 'selected_receive_backpressure', 'stale_identity_delegated',
    'malformed_route_kind_length_reserved_slot_padding', 'canonical_before_restore',
    'sticky_fault_requires_cold_reset', 'tx_fault_detection_edge_rx_transfer',
    'tx_canonical_validation', 'carrier_fault_fences', 'cold_reset_masks_handshakes', 'finite_quiet_tail',
}


def profile(trace: dict[str, Any]) -> tuple[Endpoint, list[dict[str, Any]]]:
    """Validate the public eight-endpoint adapter inventory without inspecting generated RTL internals."""
    value = trace.get('profile')
    require(isinstance(value, dict) and value.get('module') == 'endpoint_packets', 'wrong packet-router profile')
    require(value.get('state_bit_budget') == 4 and value.get('packet_bits') == 1024
            and value.get('frame_bits') == 672, 'unexpected packet-router dimensions')
    inputs, outputs = pins(value.get('inputs')), pins(value.get('outputs'))
    endpoints = trace.get('endpoints')
    require(isinstance(endpoints, list) and len(endpoints) == 8, 'expected eight endpoint offers')
    require([item.get('id') for item in endpoints] == [8, 17, 26, 50, 1, 28, 37, 0x100003d],
            'wrong full-width route inventory')
    require([item.get('kind') for item in endpoints] == ['tx'] * 4 + ['rx'] * 4, 'wrong endpoint directions')
    expected_inputs = {'reset': 1, 'carrier_fault': 1, 'packet_tx_ready': 1,
                       'packet_rx': 1024, 'packet_rx_words': 6, 'packet_rx_valid': 1}
    expected_outputs = {'packet_tx': 1024, 'packet_tx_words': 6, 'packet_tx_valid': 1,
                        'packet_rx_ready': 1, 'router_fault': 1}
    for item in endpoints:
        prefix = f'endpoint_{item["id"]}_'
        tx = item['kind'] == 'tx'
        offer, received = ('tx_', 'credit_') if tx else ('ack_', 'data_')
        expected_inputs[prefix + offer + 'valid'] = 1
        expected_inputs[prefix + ('credit_ready' if tx else 'data_ready')] = 1
        expected_outputs[prefix + ('data_tx_ready' if tx else 'ack_tx_ready')] = 1
        expected_outputs[prefix + received + 'valid'] = 1
        for suffix, width in [('namespace', 64), ('generation', 64), ('source_incarnation', 64),
                              ('destination_incarnation', 64), ('sequence', 32)]:
            expected_inputs[prefix + offer + suffix] = width
            expected_outputs[prefix + received + suffix] = width
        for suffix, width in [('slot', 8), ('frame', 672)]:
            (expected_inputs if tx else expected_outputs)[prefix + ('tx_' if tx else 'data_') + suffix] = width
        mask, constant, fixed = item.get('common_mask'), item.get('common_value'), item.get('common_fixed_bits')
        require(type(mask) is int and 0 < mask < 1 << 672 and type(constant) is int
                and constant >= 0 and constant & mask == constant and type(fixed) is int and mask.bit_count() == fixed,
                'invalid retained common canonical bits')
    require(dict(inputs) == expected_inputs and dict(outputs) == expected_outputs, 'unexpected public pin inventory')
    # The existing mechanical adapter helper needs the native frame profile but performs no endpoint modeling.
    return Endpoint('endpoint_packets', inputs, outputs, 20, 672), endpoints


def checked_trace(trace: dict[str, Any]) -> tuple[Endpoint, list[dict[str, Any]]]:
    """Check finite rows, exact coverage references and complete comparison of all live packet fields."""
    require(trace.get('version') == 1 and trace.get('evidence') == 'finite_endpoint_packets_rtl_witness',
            'unsupported packet-router trace')
    layout, endpoints = profile(trace)
    supplied = trace.get('rows')
    require(isinstance(supplied, list) and 32 <= len(supplied) <= 512, 'invalid finite trace length')
    rows, labels, checked = [], set(), 0
    controls = [name for name, width in layout.outputs if width == 1]
    for index, row in enumerate(supplied):
        require(isinstance(row, dict), 'invalid trace row')
        label, covers, delay = row.get('label'), row.get('covers'), row.get('delay')
        require(isinstance(label, str) and 0 < len(label) <= 160 and label not in labels, 'invalid or repeated row label')
        labels.add(label)
        require(isinstance(covers, list) and covers and all(isinstance(name, str) for name in covers)
                and len(set(covers)) == len(covers), 'invalid row coverage')
        require(type(delay) is int and 1 <= delay <= 11, 'invalid sampled-edge delay')
        command = hexadecimal(row.get('input'), layout.input_bits)
        expected = hexadecimal(row.get('expected'), layout.output_bits)
        mask = hexadecimal(row.get('mask'), layout.output_bits)
        require(all(field_value(layout.outputs, mask, name) == 1 for name in controls), 'unchecked handshake or fault bit')
        if index == 0:
            require(field_value(layout.inputs, command, 'reset') == 1, 'first edge must cold-reset the router')
        tx, rx = row.get('selected_tx'), row.get('selected_rx')
        require(type(tx) is int and -1 <= tx < 8 and type(rx) is int and -1 <= rx < 8, 'invalid explicit owner')
        require(field_value(layout.outputs, expected, 'packet_tx_valid') == int(tx >= 0), 'inconsistent TX winner')
        if tx >= 0:
            require(all(field_value(layout.outputs, mask, name) == (1 << width) - 1
                        for name, width in [('packet_tx', 1024), ('packet_tx_words', 6)]), 'unchecked outgoing packet')
        for owner, item in enumerate(endpoints):
            prefix = f'endpoint_{item["id"]}_' + ('credit_' if item['kind'] == 'tx' else 'data_')
            require(field_value(layout.outputs, expected, prefix + 'valid') == int(rx == owner),
                    'inconsistent incoming endpoint owner')
            if owner == rx:
                require(all(field_value(layout.outputs, mask, name) == (1 << width) - 1
                            for name, width in layout.outputs if name.startswith(prefix)), 'unchecked incoming identity or frame')
        checked |= mask
        rows.append(dict(row, input=command, expected=expected, mask=mask))
    require(checked == (1 << layout.output_bits) - 1, 'not every output bit was checked')
    coverage = trace.get('coverage')
    require(isinstance(coverage, dict) and REQUIRED_COVERAGE <= set(coverage), 'missing required scenarios')
    for name, indices in coverage.items():
        expected_indices = [index for index, row in enumerate(rows) if name in row['covers']]
        require(isinstance(indices, list) and bool(indices) and indices == expected_indices, 'incorrect coverage references')
    fair = [row['selected_tx'] for row in rows if row['label'].startswith('round_robin_')]
    require(fair == list(range(8)) * 2, 'missing two explicit all-offer arbitration rounds')
    require({row['selected_rx'] for row in rows if row['label'].startswith('incoming_full_identity_')} == set(range(8)),
            'missing full-identity DATA/ACK route')
    return layout, rows


def compiled_inputs(bundle: Path, manifest: dict[str, Any], compiled: dict[str, Any]) -> tuple[dict[Path, str], list[Path]]:
    """Accept only successful normal source-build compilation with unchanged frozen source and RTL identities."""
    manifest_path = bundle / 'source-build.json'
    require(compiled.get('source_build_sha256') == digest(manifest_path), 'source manifest identity mismatch')
    inputs = {manifest_path: digest(manifest_path), bundle / 'compiled.json': digest(bundle / 'compiled.json')}
    supplied = manifest.get('inputs')
    require(isinstance(supplied, list) and supplied, 'missing frozen source inventory')
    for item in supplied:
        path = bundle_file(bundle, item['file'])
        require(path not in inputs and digest(path) == item['sha256'], 'changed or duplicate source input')
        inputs[path] = item['sha256']
    require(bundle / 'endpoint-packets-trace.json' in inputs, 'trace is not a frozen source input')
    units = manifest.get('units')
    require(isinstance(units, list) and len(units) == 1 and units[0]['top'] == 'endpoint_packets_clock',
            'witness requires exactly the standalone router unit')
    unit = units[0]
    require({'--pipeline_stages=1', '--flop_inputs=false', '--flop_outputs=false', '--reset=reset'}
            <= set(unit['codegen_flags']), 'incompatible router sampled-clock schedule')
    completed = compiled.get('units')
    require(isinstance(completed, list) and len(completed) == 1
            and completed[0]['directory'] == unit['directory'], 'compiled unit mismatch')
    commands = completed[0]['commands']
    require(all(command['exit'] == 0 for command in commands), 'failed compiler stage')
    codegen = [command for command in commands if command['stage'] == 'codegen']
    require(len(codegen) == 1 and codegen[0]['output'] == unit['output'], 'missing router codegen result')
    require(digest(bundle_file(bundle, unit['output'])) == codegen[0]['sha256'], 'changed generated router core')
    inventory = compiled.get('rtl')
    require(isinstance(inventory, dict) and inventory, 'missing compiled RTL inventory')
    for files in inventory.values():
        for item in files:
            path = bundle_file(bundle, item['file'])
            require(digest(path) == item['sha256'], 'changed compiled RTL')
            require(path not in inputs or inputs[path] == item['sha256'], 'conflicting RTL input identity')
            inputs[path] = item['sha256']
    rtl = [bundle_file(bundle, name) for name in unit['rtl']]
    require(all(path in inputs for path in rtl), 'unit RTL is absent from frozen inventories')
    return inputs, rtl


def expression(fields: list[tuple[str, int]], name: str, vector: str) -> str:
    """Select one public field from its retained vector order for additional dynamic bench assertions."""
    remaining = sum(width for _, width in fields)
    for selected, width in fields:
        remaining -= width
        if selected == name:
            return f'{vector}[{remaining + width - 1}:{remaining}]'
    raise ValueError('missing pin: ' + name)


def controls(layout: Endpoint) -> str:
    """Expose only public packet handshakes and cold reset to the finite bench's stall monitor."""
    return '\n'.join(f'wire [{width - 1}:0] {name} = {expression(fields, name, vector)};'
                     for fields, vector, names in [(layout.inputs, 'router_inputs', ['reset', 'packet_tx_ready', 'packet_rx_valid']),
                                                    (layout.outputs, 'router_outputs', ['packet_tx', 'packet_tx_words',
                                                                                      'packet_tx_valid', 'packet_rx_ready'])]
                     for name in names for width in [dict(fields)[name]])


def main() -> None:
    """Run bounded Icarus comparison over a precompiled router and retain exact finite evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=lambda value: Path(value).resolve(), help='normal compiled source-build release')
    parser.add_argument('stage', type=lambda value: Path(value).resolve(), help='fresh witness directory')
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG', 'iverilog'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    args = parser.parse_args()
    manifest = json.loads((args.bundle / 'source-build.json').read_text())
    compiled = json.loads((args.bundle / 'compiled.json').read_text())
    inputs, rtl = compiled_inputs(args.bundle, manifest, compiled)
    trace = json.loads((args.bundle / 'endpoint-packets-trace.json').read_text())
    layout, rows = checked_trace(trace)
    iverilog, vvp = executable(args.iverilog), executable(args.vvp)
    template_path = ROOT / 'test/rtl/domain_endpoint_packets_tb.sv.in'
    for path in (Path(__file__).resolve(), ROOT / 'tools/test_domain_endpoints.py',
                 ROOT / 'tools/backend_commands.py', ROOT / 'tools/backend_paths.py', template_path, iverilog, vvp):
        inputs[path] = digest(path)
    args.stage.mkdir(parents=True)
    replacements = {'@@WIRING@@': wiring('router', layout), '@@CONTROLS@@': controls(layout),
                    '@@IN_BITS@@': str(layout.input_bits), '@@OUT_BITS@@': str(layout.output_bits),
                    '@@ROWS@@': str(len(rows)), '@@TIMEOUT@@': str(len(rows) * 16 + 100)}
    source = template_path.read_text()
    for marker, value in replacements.items():
        require(marker in source, 'missing testbench marker: ' + marker)
        source = source.replace(marker, value)
    require('@@' not in source, 'unresolved testbench marker')
    bench = args.stage / 'domain_endpoint_packets_tb.sv'
    bench.write_text(source)
    vectors = args.stage / 'vectors.txt'
    vectors.write_text(''.join(f'{row["input"]:x} {row["expected"]:x} {row["mask"]:x} {row["delay"]}\n' for row in rows))
    labels = args.stage / 'trace-labels.json'
    labels.write_text(json.dumps([{key: row[key] for key in ('label', 'covers', 'selected_tx', 'selected_rx')}
                                 for row in rows], indent=2) + '\n')
    for path in [bench, vectors, labels]:
        inputs[path] = digest(path)
    simulation = args.stage / 'domain_endpoint_packets.vvp'
    run([iverilog, '-g2012', '-s', 'domain_endpoint_packets_tb', '-o', simulation, bench, *rtl],
        args.stage, 'iverilog', timeout=120)
    run([vvp, simulation, '+vectors=' + str(vectors)], args.stage, 'witness', timeout=60)
    tx_count = sum(field_value(layout.outputs, row['expected'], 'packet_tx_valid')
                   * field_value(layout.inputs, row['input'], 'packet_tx_ready') for row in rows)
    rx_count = sum(field_value(layout.outputs, row['expected'], 'packet_rx_ready')
                   * field_value(layout.inputs, row['input'], 'packet_rx_valid') for row in rows)
    verdict = f'DOMAIN_ENDPOINT_PACKETS_PASS steps={len(rows)} checked_steps={len(rows)} tx={tx_count} rx={rx_count}'
    require(re.search(re.escape(verdict) + r'(?:\n|$)', (args.stage / 'witness.log').read_text()) is not None,
            'missing complete finite router witness verdict')
    for path, expected in inputs.items():
        require(digest(path) == expected, 'input changed during witness: ' + str(path))
    evidence = {'passed': True, 'evidence': trace['evidence'], 'steps': len(rows),
                'checked_steps': len(rows), 'outgoing_transfers': tx_count, 'incoming_transfers': rx_count,
                'coverage': trace['coverage'], 'compiled_source_sha256': compiled['source_build_sha256'],
                'xls_tools': compiled['xls_tools'], 'inputs': {str(path): value for path, value in inputs.items()},
                'domain': 'Exactly the retained finite public-pin vectors, including full packets when valid; '
                          'two all-offer arbitration rounds and explicitly named stall/fault edges.',
                'assumptions': 'One sampled local clock; each endpoint preserves offered fields until acceptance '
                               'or explicit cancellation. Endpoint ownership and carrier delivery are controlled externally.',
                'trust': 'Native hls_type binding packing and source codec plans, explicit Erlang fixture expectations, '
                         'mechanical testbench, Erlang emitter, XLS and Icarus simulation.',
                'limits': trace['limits'],
                'artifacts': {path.name: digest(path) for path in args.stage.iterdir() if path.is_file()}}
    (args.stage / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(verdict, flush=True)


if __name__ == '__main__':
    main()
