"""Run a finite standalone board-control RTL witness over a normally compiled source bundle."""
import argparse
import json
import os
from pathlib import Path
import re
from typing import Any

from backend_commands import digest, run
from backend_paths import ROOT
from test_domain_endpoints import Endpoint, bundle_file, executable, hexadecimal, pins, require


REQUIRED = {'cold_reset_masks_controls', 'status_snapshot', 'route_preserving_ingress',
            'independent_payload_stalls', 'unknown_route_silent_drain', 'strict_session_advance',
            'two_parser_acknowledgment', 'session_reset_is_transport_only', 'establish_waits_for_packet_boundary',
            'packet_locked_output_arbitration', 'response_stability_under_stall', 'inspection_error_zeroes_snapshot',
            'malformed_local_framing', 'physical_fault_survives_session_change', 'finite_quiet_tail'}
OBSERVATIONS = {'domain_session': 64, 'endpoint_session': 64, 'domain_current': 64, 'domain_phase': 3,
                'domain_attached': 1, 'endpoint_attached': 1, 'domain_wire_fault': 1, 'endpoint_wire_fault': 1,
                'router_fault': 1, 'carrier_fault': 8, 'carrier_armed': 1}


def trace_layout(trace: dict[str, Any]) -> tuple[Endpoint, list[tuple[str, int]], list[dict[str, Any]]]:
    """Validate public metadata, bounded golden packets, pulse counts and actual coverage references."""
    require(trace.get('version') == 1 and trace.get('evidence') == 'finite_board_control_rtl_witness', 'wrong witness kind')
    profile = trace.get('profile')
    require(isinstance(profile, dict) and profile.get('module') == 'domain_board_control'
            and profile.get('state_bits') == 723 and profile.get('state_bit_budget') == 768, 'wrong control profile')
    inputs, outputs, observations = pins(profile.get('inputs')), pins(profile.get('outputs')), pins(profile.get('observations'))
    require(dict(observations) == OBSERVATIONS and set(observations) <= set(inputs), 'unexpected observation model')
    require(set(dict(inputs)).isdisjoint(dict(outputs)) and dict(inputs).get('inspect_value') == 128, 'invalid pin inventory')
    require([name for name, _ in outputs if name.endswith('reset')] == ['transport_reset'], 'control drives nontransport reset')
    require(dict(outputs).get('inspect_incarnation') == 64 and dict(outputs).get('inspect_address') == 32, 'missing sparse inspection pins')
    require(trace.get('inspection') in ('none', 'process') and trace.get('role') in (1, 2), 'invalid board identity/capability')
    require(type(trace.get('actor')) is int and 0 <= trace['actor'] < 1 << 32, 'invalid selected actor')
    hexadecimal(trace.get('snapshot'), 128)
    native = trace.get('native_frames')
    require(isinstance(native, dict) and set(native) == {'domain', 'endpoint'}, 'missing native framed responses')
    for name, route in [('domain', 0), ('endpoint', 2)]:
        native[name] = [hexadecimal(word, 32) for word in native[name]]
        require(2 <= len(native[name]) <= 32 and native[name][0] == route, 'wrong native route frame')
    rows = trace.get('actions')
    require(isinstance(rows, list) and 16 <= len(rows) <= 128 and rows[0].get('action') == 'reset', 'invalid finite actions')
    labels, pulses = set(), 0
    for index, row in enumerate(rows):
        require(isinstance(row, dict) and isinstance(row.get('label'), str)
                and 0 < len(row['label']) <= 160 and row['label'] not in labels, 'invalid or repeated label')
        labels.add(row['label'])
        require(isinstance(row.get('covers'), list) and row['covers']
                and all(isinstance(name, str) for name in row['covers']), 'missing row coverage')
        action = row.get('action')
        if action in ('reset', 'observe'):
            require(action != 'reset' or index == 0, 'unexpected repeated cold reset')
            value = row.get('observation')
            require(isinstance(value, dict) and set(value) == set(OBSERVATIONS), 'incomplete controlled observations')
            for name, width in observations:
                require(type(value[name]) is int and 0 <= value[name] < 1 << width, 'invalid observation value')
        elif action in ('exchange', 'mux', 'locked', 'forward'):
            request = row.get('request')
            require(isinstance(request, list) and 1 <= len(request) <= 32, 'invalid request word count')
            row['request'] = [hexadecimal(word, 32) for word in request]
            if action == 'forward':
                require(row.get('target') in (1, 2) and row['request'][0] == (0 if row['target'] == 1 else 2), 'wrong forwarding target')
                continue
            response = row.get('response')
            require(isinstance(response, list) and len(response) in (0, 13), 'invalid expected local response count')
            row['response'] = [hexadecimal(word, 32) for word in response]
            if response:
                require(row['response'][0] in (3, 4) and row['response'][1] == 0x8000000b, 'noncanonical expected response')
            pulse, ack = row.get('pulse'), row.get('ack')
            require(type(pulse) is int and 0 <= pulse < 1 << 64 and ack in (0, 1, 2), 'invalid session observation transition')
            require(pulse != 0 or ack == 0, 'acknowledgment without session pulse')
            pulses += int(pulse != 0)
        else:
            require(action == 'quiet' and type(row.get('cycles')) is int and 2 <= row['cycles'] <= 16, 'invalid quiet action')
    require(pulses == trace.get('expected_session_pulses') == 6, 'missing finite session transitions')
    coverage = trace.get('coverage')
    require(isinstance(coverage, dict) and REQUIRED <= set(coverage), 'missing required coverage')
    selected = 'inspection_unsupported' if trace['inspection'] == 'none' else 'inspection_native_sparse_snapshot'
    require(selected in coverage, 'missing selected inspection capability witness')
    for name, indices in coverage.items():
        require(indices == [index for index, row in enumerate(rows) if name in row['covers']] and indices,
                'incorrect finite coverage references')
    return Endpoint('domain_board_control', inputs, outputs, 11, 352), observations, rows


def compiled_inputs(bundle: Path) -> tuple[dict[str, Any], dict[Path, str], list[Path]]:
    """Validate normal source-build completion, all frozen source inputs and the standalone control RTL."""
    manifest_path, compiled_path = bundle / 'source-build.json', bundle / 'compiled.json'
    manifest, compiled = json.loads(manifest_path.read_text()), json.loads(compiled_path.read_text())
    require(compiled.get('source_build_sha256') == digest(manifest_path), 'compiled source identity mismatch')
    hashes = {manifest_path: digest(manifest_path), compiled_path: digest(compiled_path)}
    for item in manifest['inputs']:
        path = bundle_file(bundle, item['file'])
        require(path not in hashes and digest(path) == item['sha256'], 'changed or duplicate source input')
        hashes[path] = item['sha256']
    require(bundle / 'board-control-trace.json' in hashes, 'trace is not a frozen source input')
    units = manifest['units']
    require(len(units) == 1 and units[0]['top'] == 'board_control_clock', 'expected one standalone control unit')
    unit = units[0]
    require({'--pipeline_stages=1', '--flop_inputs=false', '--flop_outputs=false', '--reset=reset'} <= set(unit['codegen_flags']),
            'incompatible sampled-clock schedule')
    completed = compiled['units']
    require(len(completed) == 1 and completed[0]['directory'] == unit['directory'], 'compiled unit mismatch')
    commands = completed[0]['commands']
    require(commands and all(command['exit'] == 0 for command in commands), 'failed compiler stage')
    codegen = [command for command in commands if command['stage'] == 'codegen']
    require(len(codegen) == 1 and codegen[0]['output'] == unit['output']
            and digest(bundle_file(bundle, unit['output'])) == codegen[0]['sha256'], 'changed or missing codegen output')
    for files in compiled['rtl'].values():
        for item in files:
            path = bundle_file(bundle, item['file'])
            require(digest(path) == item['sha256'] and (path not in hashes or hashes[path] == item['sha256']), 'changed compiled RTL')
            hashes[path] = item['sha256']
    rtl = [bundle_file(bundle, name) for name in unit['rtl']]
    require(all(path in hashes for path in rtl), 'unretained RTL input')
    return compiled, hashes, rtl


def wiring(layout: Endpoint) -> str:
    """Declare and connect actual control pins, keeping the sparse observation model outside the DUT."""
    declarations, connections = [], ['.clk(clock)']
    for direction, fields in [('input', layout.inputs), ('output', layout.outputs)]:
        for name, width in fields:
            kind = 'reg' if direction == 'input' and name != 'inspect_value' else 'wire'
            initial = ' = 0' if kind == 'reg' else ''
            declarations.append(f'{kind} [{width - 1}:0] {name}{initial};')
            connections.append(f'.{name}({name})')
    return '\n'.join(declarations) + '\ndomain_board_control dut(\n  ' + ',\n  '.join(connections) + '\n);'


def vectors(stage: Path, trace: dict[str, Any], observations: list[tuple[str, int]]) -> tuple[list[Path], dict[str, str]]:
    """Serialize explicit actions and golden words; no parser or arbitration state is modeled in Python."""
    native, words, actions, snapshots = trace['native_frames'], [], [], []
    domain_offset = len(words); words.extend(native['domain'])
    endpoint_offset = len(words); words.extend(native['endpoint'])
    kinds = {'reset': 0, 'exchange': 1, 'observe': 2, 'forward': 3, 'mux': 4, 'locked': 5, 'quiet': 6}
    for row in trace['actions']:
        kind = row['action']; a = b = c = d = aux = pulse = ack = 0
        if kind in ('reset', 'observe'):
            a = len(snapshots); value = 0
            for name, width in observations:
                value = (value << width) | row['observation'][name]
            snapshots.append(value)
        elif kind == 'quiet':
            a = row['cycles']
        else:
            a, b = len(words), len(row['request']); words.extend(row['request'])
            if kind == 'forward':
                aux = row['target']
            else:
                c, d = len(words), len(row['response']); words.extend(row['response'])
                pulse, ack = row['pulse'], row['ack']
        actions.append(f'{kinds[kind]} {a} {b} {c} {d} {aux} {pulse:x} {ack}\n')
    paths = [stage / 'actions.txt', stage / 'words.txt', stage / 'observations.txt', stage / 'trace-labels.json']
    paths[0].write_text(''.join(actions))
    paths[1].write_text(''.join(f'{word:08x}\n' for word in words))
    paths[2].write_text(''.join(f'{value:x}\n' for value in snapshots))
    paths[3].write_text(json.dumps([{key: row[key] for key in ('label', 'covers')} for row in trace['actions']], indent=2) + '\n')
    return paths, {'@@DOMAIN_OFFSET@@': str(domain_offset), '@@DOMAIN_WORDS@@': str(len(native['domain'])),
                   '@@ENDPOINT_OFFSET@@': str(endpoint_offset), '@@ENDPOINT_WORDS@@': str(len(native['endpoint'])),
                   '@@WORDS@@': str(len(words)), '@@OBSERVATIONS@@': str(len(snapshots))}


def main() -> None:
    """Run bounded Icarus simulation and retain finite pin/packet evidence separately for each inspection profile."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=lambda value: Path(value).resolve(), help='normal compiled source-build release')
    parser.add_argument('stage', type=lambda value: Path(value).resolve(), help='fresh finite witness directory')
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG', 'iverilog'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    args = parser.parse_args()
    compiled, hashes, rtl = compiled_inputs(args.bundle)
    trace = json.loads((args.bundle / 'board-control-trace.json').read_text())
    layout, observations, rows = trace_layout(trace)
    iverilog, vvp = executable(args.iverilog), executable(args.vvp)
    template_path = ROOT / 'test/rtl/domain_board_control_tb.sv.in'
    for path in (Path(__file__).resolve(), ROOT / 'tools/test_domain_endpoints.py', ROOT / 'tools/backend_commands.py',
                 ROOT / 'tools/backend_paths.py', template_path, iverilog, vvp):
        hashes[path] = digest(path)
    args.stage.mkdir(parents=True)
    artifacts, replacements = vectors(args.stage, trace, observations)
    replacements.update({'@@WIRING@@': wiring(layout), '@@OBS_BITS@@': str(sum(width for _, width in observations)),
        '@@OBS_ASSIGN@@': '{' + ','.join(name for name, _ in observations) + '} = value;',
        '@@ACTOR@@': str(trace['actor']), '@@SNAPSHOT@@': trace['snapshot'], '@@ACTIONS@@': str(len(rows)),
        '@@TIMEOUT@@': str(len(rows) * 20000 + 1000)})
    text = template_path.read_text()
    for marker, replacement in replacements.items():
        require(marker in text, 'missing bench marker: ' + marker)
        text = text.replace(marker, replacement)
    require('@@' not in text, 'unresolved bench marker')
    bench = args.stage / 'domain_board_control_tb.sv'; bench.write_text(text)
    for path in [bench, *artifacts]:
        hashes[path] = digest(path)
    simulation = args.stage / 'domain_board_control.vvp'
    run([iverilog, '-g2012', '-s', 'domain_board_control_tb', '-o', simulation, bench, *rtl], args.stage, 'iverilog', timeout=120)
    run([vvp, simulation, '+actions=' + str(artifacts[0]), '+words=' + str(artifacts[1]),
         '+observations=' + str(artifacts[2])], args.stage, 'witness', timeout=60)
    mux = sum(row['action'] == 'mux' for row in rows); locked = sum(row['action'] == 'locked' for row in rows)
    responses = sum(bool(row.get('response')) for row in rows) + 2 * mux + locked
    forwarded = sum(len(row['request']) for row in rows if row['action'] == 'forward')
    domain_words = len(trace['native_frames']['domain']) * (mux + locked)
    endpoint_words = len(trace['native_frames']['endpoint']) * mux
    pattern = (rf'BOARD_CONTROL_PASS actions={len(rows)} sessions=6 responses={responses} forwarded={forwarded} '
               rf'domain={domain_words} endpoint={endpoint_words} steps=([1-9][0-9]*)')
    match = re.search(pattern, (args.stage / 'witness.log').read_text())
    require(match is not None, 'missing complete finite control verdict')
    require(all(digest(path) == expected for path, expected in hashes.items()), 'input changed during witness')
    evidence = {'passed': True, 'evidence': trace['evidence'], 'inspection': trace['inspection'], 'actions': len(rows),
        'session_pulses': 6, 'responses': responses, 'steps': int(match.group(1)), 'coverage': trace['coverage'],
        'compiled_source_sha256': compiled['source_build_sha256'], 'xls_tools': compiled['xls_tools'],
        'inputs': {str(path): value for path, value in hashes.items()},
        'domain': 'Exactly the retained finite framed requests and golden response words, with deterministic payload/output stalls.',
        'assumptions': 'Controlled native parser sessions acknowledge only explicit pulses; process observation is a selected public-input model. '
                       'Establishment follows the documented packet/quiescence boundary after the deliberately held packet drains.',
        'trust': 'Retained native phase codec, explicit Erlang fixture expectations, controlled-input bench, emitter, XLS and Icarus.',
        'limits': trace['limits'], 'artifacts': {path.name: digest(path) for path in args.stage.iterdir() if path.is_file()}}
    (args.stage / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(match.group(0), flush=True)


if __name__ == '__main__':
    main()
