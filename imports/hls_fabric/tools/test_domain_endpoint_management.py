"""Simulate a normally compiled endpoint-management parser against a finite controlled-metadata script."""
import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
from typing import Any

from backend_commands import digest, run
from backend_paths import ROOT
from test_domain_endpoints import bundle_file, executable, field_value, hexadecimal, pins, require


REQUIRED_COVERAGE = {
    'response_stability_under_stall', 'independent_command_response_stalls',
    'single_receive_slot_backpressure', 'lost_bind_reply', 'lost_response_inspect_reconciliation',
    'tx_receiver_confirmation_only_bind_edge', 'rx_inspect_bind_fence',
    'stale_session_drop', 'stale_malformed_session_drop', 'unknown_id_no_mutation',
    'session_reset_only_parser', 'malformed_current_session_closes',
    'count_route_reserved_boundaries', 'strict_session_advance',
    'truncated_session_prefix_drop', 'tx_fence_has_no_receiver_pulse', 'finite_quiet_tail',
}


@dataclass(frozen=True)
class Profile:
    """Emitter-ordered pins, with controlled metadata separated from actual management outputs."""

    inputs: list[tuple[str, int]]
    outputs: list[tuple[str, int]]
    metadata: list[tuple[str, int]]
    commands: list[tuple[str, int]]

    @property
    def metadata_bits(self) -> int:
        """Return the complete controlled-observation vector width."""
        return sum(width for _, width in self.metadata)

    @property
    def command_bits(self) -> int:
        """Return the complete raw endpoint-command comparison width."""
        return sum(width for _, width in self.commands)


def bit(value: object) -> int:
    """Read an explicit numeric bit without accepting arbitrary truthy input."""
    require(type(value) is int and value in (0, 1), 'invalid bit')
    return value


def profile(value: object) -> Profile:
    """Check the isolated parser interface and prohibit hidden endpoint reset/lifecycle controls."""
    require(isinstance(value, dict) and value.get('module') == 'endpoint_management', 'wrong parser profile')
    require(value.get('state_bit_budget') == 1159 and value.get('payload_words') == 14
            and value.get('packet_words') == 16, 'unexpected parser storage or packet bound')
    inputs, outputs = pins(value.get('inputs')), pins(value.get('outputs'))
    require(not set(dict(inputs)) & set(dict(outputs)), 'colliding parser pins')
    metadata = [(name, width) for name, width in inputs if '_observed_' in name]
    commands = [(name, width) for name, width in outputs
                if name.startswith(('endpoint_8_', 'endpoint_61_'))]
    require(len(metadata) == 16 and len(commands) == 17, 'unexpected controlled endpoint inventory')
    require(not any(name.endswith('reset') for name, _ in outputs), 'parser can drive endpoint reset')
    require(not any(name.endswith(('local_ready', 'local_incarnation')) for name, _ in inputs),
            'parser unexpectedly samples endpoint lifecycle')
    external_inputs = {'reset': 1, 'endpoint_transport_reset': 1, 'endpoint_transport_session': 64,
                       'endpoint_management_word': 32, 'endpoint_management_valid': 1,
                       'endpoint_management_last': 1, 'endpoint_management_output_ready': 1}
    require(dict(inputs) == external_inputs | dict(metadata), 'unexpected external input pins')
    require(('endpoint_8_receiver_active', 1) in commands
            and 'endpoint_61_receiver_active' not in dict(commands), 'wrong receiver confirmation pins')
    return Profile(inputs, outputs, metadata, commands)


def checked_trace(trace: dict[str, Any]) -> tuple[Profile, int, list[dict[str, int]], list[dict[str, Any]]]:
    """Validate every finite action, mutation transition and coverage row before generating HDL."""
    require(trace.get('version') == 1 and trace.get('evidence') == 'finite_endpoint_management_parser_witness',
            'unsupported management trace')
    layout = profile(trace.get('profile'))
    initial = hexadecimal(trace.get('initial_metadata'), layout.metadata_bits)
    supplied = trace.get('mutations')
    require(isinstance(supplied, list) and 4 <= len(supplied) <= 32, 'invalid mutation inventory')
    mutations, retained = [], initial
    control_names = ['endpoint_8_bind_request', 'endpoint_8_fence',
                     'endpoint_61_bind_request', 'endpoint_61_fence']
    for item in supplied:
        require(isinstance(item, dict) and isinstance(item.get('label'), str), 'invalid mutation row')
        row = {key: hexadecimal(item.get(key), layout.command_bits if key == 'commands' else layout.metadata_bits)
               for key in ('commands', 'before', 'issue', 'after')}
        require(row['before'] == retained, 'native mutation metadata chain is discontinuous')
        require(sum(field_value(layout.commands, row['commands'], name) for name in control_names) == 1,
                'expected mutation must select exactly one control')
        confirm = field_value(layout.commands, row['commands'], 'endpoint_8_receiver_active')
        tx_bind = field_value(layout.commands, row['commands'], 'endpoint_8_bind_request')
        require(confirm == tx_bind, 'receiver confirmation outside TX bind')
        for field in ('namespace', 'generation', 'source_incarnation', 'destination_incarnation'):
            receiver = field_value(layout.commands, row['commands'], 'endpoint_8_receiver_' + field)
            requested = field_value(layout.commands, row['commands'], 'endpoint_8_' + field)
            require(receiver == (requested if tx_bind else 0), 'receiver confirmation binding mismatch')
        retained = row['after']
        mutations.append(row)
    rows = trace.get('rows')
    require(isinstance(rows, list) and 16 <= len(rows) <= 512, 'invalid finite script length')
    require(rows[0].get('action') == 'reset', 'script must initialize parser state')
    for index, row in enumerate(rows):
        require(isinstance(row, dict) and isinstance(row.get('label'), str)
                and 0 < len(row['label']) <= 160, 'invalid script label')
        covers = row.get('covers')
        require(isinstance(covers, list) and all(isinstance(name, str) for name in covers), 'missing coverage labels')
        action = row.get('action')
        if action in ('send', 'receive'):
            words = row.get('words')
            require(isinstance(words, list) and 2 <= len(words) <= 32, 'invalid wire vector length')
            row['decoded_words'] = [hexadecimal(word, 32) for word in words]
            if action == 'receive':
                require(len(words) == 16 and row['decoded_words'][0:2] == [2, (129 << 24) | 14],
                        'noncanonical expected response frame')
                require(type(row.get('discard')) is bool, 'missing discard disposition')
        elif action == 'session':
            session = row.get('session')
            require(type(session) is int and 0 < session < 1 << 64, 'invalid bootstrap session')
            bit(row.get('fault'))
            bit(row.get('attached'))
        elif action in ('hold', 'quiet'):
            require(type(row.get('cycles')) is int and 2 <= row['cycles'] <= 16, 'invalid finite observation horizon')
            if action == 'hold':
                bit(row.get('ready'))
            else:
                bit(row.get('fault'))
                bit(row.get('attached'))
        else:
            require(action == 'reset' and index == 0, 'unknown or repeated reset action')
    coverage = trace.get('coverage')
    require(isinstance(coverage, dict) and REQUIRED_COVERAGE <= set(coverage), 'missing required scenarios')
    for name, indices in coverage.items():
        expected = [index for index, row in enumerate(rows) if name in row['covers']]
        require(isinstance(indices, list) and indices == expected and bool(expected), 'incorrect coverage row references')
    require(any(row.get('discard') is True for row in rows), 'no lost-response case')
    return layout, initial, mutations, rows


def wiring(layout: Profile) -> str:
    """Wire actual parser pins to external stream controls and the explicit metadata model mux."""
    declarations = [f'wire [{layout.command_bits - 1}:0] command_outputs;', 'wire mutation_any;']
    for name, width in layout.outputs:
        declarations.append(f'wire [{width - 1}:0] {name};')
    connections = ['.clk(clock)']
    remaining = layout.metadata_bits
    metadata_slices = {}
    for name, width in layout.metadata:
        remaining -= width
        metadata_slices[name] = f'controlled_metadata[{remaining + width - 1}:{remaining}]'
    connections.extend(f'.{name}({metadata_slices.get(name, name)})' for name, _ in layout.inputs)
    connections.extend(f'.{name}({name})' for name, _ in layout.outputs)
    declarations.append('endpoint_management dut(\n  ' + ',\n  '.join(connections) + '\n);')
    declarations.append('assign command_outputs = {' + ', '.join(name for name, _ in layout.commands) + '};')
    declarations.append('assign mutation_any = endpoint_8_bind_request | endpoint_8_fence | '
                        'endpoint_61_bind_request | endpoint_61_fence;')
    return '\n'.join(declarations)


def compiled_inputs(bundle: Path, manifest: dict[str, Any], compiled: dict[str, Any]) -> tuple[dict[Path, str], list[Path]]:
    """Accept only a successful normal source-build result whose source and RTL identities still match."""
    manifest_path = bundle / 'source-build.json'
    require(compiled.get('source_build_sha256') == digest(manifest_path), 'source manifest identity mismatch')
    inputs = {manifest_path: digest(manifest_path), bundle / 'compiled.json': digest(bundle / 'compiled.json')}
    supplied = manifest.get('inputs')
    require(isinstance(supplied, list) and bool(supplied), 'missing frozen source inventory')
    for item in supplied:
        path = bundle_file(bundle, item['file'])
        require(path not in inputs and digest(path) == item['sha256'], 'changed or duplicate source input')
        inputs[path] = item['sha256']
    require(bundle / 'endpoint-management-trace.json' in inputs, 'trace is not a frozen source input')
    units = manifest.get('units')
    require(isinstance(units, list) and len(units) == 1 and units[0]['top'] == 'endpoint_management_clock',
            'witness requires exactly the standalone parser unit')
    unit = units[0]
    require({'--pipeline_stages=1', '--flop_inputs=false', '--flop_outputs=false', '--reset=reset'}
            <= set(unit['codegen_flags']), 'incompatible parser sampled-clock schedule')
    completed = compiled.get('units')
    require(isinstance(completed, list) and len(completed) == 1
            and completed[0]['directory'] == unit['directory'], 'compiled unit mismatch')
    commands = completed[0]['commands']
    require(all(command['exit'] == 0 for command in commands), 'failed compiler stage')
    codegen = [command for command in commands if command['stage'] == 'codegen']
    require(len(codegen) == 1 and codegen[0]['output'] == unit['output'], 'missing parser codegen result')
    require(digest(bundle_file(bundle, unit['output'])) == codegen[0]['sha256'], 'changed generated parser core')
    inventory = compiled.get('rtl')
    require(isinstance(inventory, dict) and bool(inventory), 'missing compiled RTL inventory')
    for files in inventory.values():
        for item in files:
            path = bundle_file(bundle, item['file'])
            require(digest(path) == item['sha256'], 'changed compiled RTL')
            require(path not in inputs or inputs[path] == item['sha256'], 'conflicting RTL input identity')
            inputs[path] = item['sha256']
    rtl = [bundle_file(bundle, name) for name in unit['rtl']]
    require(all(path in inputs for path in rtl), 'unit RTL is absent from frozen inventories')
    return inputs, rtl


def vectors(stage: Path, rows: list[dict[str, Any]], mutations: list[dict[str, int]]) -> list[Path]:
    """Write bounded action, packet and native metadata vectors with retained human row labels."""
    actions, words = [], []
    for row in rows:
        action = row['action']
        if action == 'reset':
            values = (0, 0, 0, 0)
        elif action == 'session':
            values = (1, row['session'], row['fault'], row['attached'])
        elif action in ('send', 'receive'):
            values = (2 if action == 'send' else 3, len(words), len(row['decoded_words']), int(row.get('discard', False)))
            words.extend(row['decoded_words'])
        elif action == 'hold':
            values = (4, row['cycles'], row['ready'], 0)
        else:
            values = (5, row['cycles'], row['fault'], row['attached'])
        actions.append(f'{values[0]} {values[1]:x} {values[2]} {values[3]}\n')
    paths = [stage / 'actions.txt', stage / 'words.txt', stage / 'mutations.txt', stage / 'trace-labels.json']
    paths[0].write_text(''.join(actions))
    paths[1].write_text(''.join(f'{word:08x}\n' for word in words))
    paths[2].write_text(''.join(' '.join(f'{row[key]:x}' for key in ('commands', 'before', 'issue', 'after')) + '\n'
                              for row in mutations))
    paths[3].write_text(json.dumps([{'row': index, 'action': row['action'], 'label': row['label'],
                                    'covers': row['covers']} for index, row in enumerate(rows)], indent=2) + '\n')
    return paths


def main() -> None:
    """Run bounded Icarus simulation over the already compiled parser and retain exact finite evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=lambda value: Path(value).resolve(), help='normal compiled source-build release')
    parser.add_argument('stage', type=lambda value: Path(value).resolve(), help='fresh witness directory')
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG', 'iverilog'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    args = parser.parse_args()
    manifest = json.loads((args.bundle / 'source-build.json').read_text())
    compiled = json.loads((args.bundle / 'compiled.json').read_text())
    inputs, rtl = compiled_inputs(args.bundle, manifest, compiled)
    trace = json.loads((args.bundle / 'endpoint-management-trace.json').read_text())
    layout, initial, mutations, rows = checked_trace(trace)
    iverilog, vvp = executable(args.iverilog), executable(args.vvp)
    template_path = ROOT / 'test/rtl/domain_endpoint_management_tb.sv.in'
    for path in (Path(__file__).resolve(), ROOT / 'tools/test_domain_endpoints.py',
                 ROOT / 'tools/backend_commands.py', ROOT / 'tools/backend_paths.py', template_path, iverilog, vvp):
        inputs[path] = digest(path)
    args.stage.mkdir(parents=True)
    count = sum(len(row.get('decoded_words', [])) for row in rows)
    replacements = {'@@WIRING@@': wiring(layout), '@@META_BITS@@': str(layout.metadata_bits),
                    '@@COMMAND_BITS@@': str(layout.command_bits), '@@INITIAL_METADATA@@': f'{initial:x}',
                    '@@ACTIONS@@': str(len(rows)), '@@MUTATIONS@@': str(len(mutations)),
                    '@@WORDS@@': str(count), '@@TIMEOUT@@': str(len(rows) * 20000 + 1000)}
    source = template_path.read_text()
    for marker, value in replacements.items():
        require(marker in source, 'missing testbench marker: ' + marker)
        source = source.replace(marker, value)
    require('@@' not in source, 'unresolved testbench marker')
    bench = args.stage / 'domain_endpoint_management_tb.sv'
    bench.write_text(source)
    artifacts = vectors(args.stage, rows, mutations)
    for path in [bench, *artifacts]:
        inputs[path] = digest(path)
    simulation = args.stage / 'domain_endpoint_management.vvp'
    run([iverilog, '-g2012', '-s', 'domain_endpoint_management_tb', '-o', simulation, bench, *rtl],
        args.stage, 'iverilog', timeout=120)
    run([vvp, simulation, '+actions=' + str(artifacts[0]), '+words=' + str(artifacts[1]),
         '+mutations=' + str(artifacts[2])], args.stage, 'witness', timeout=60)
    responses = sum(row['action'] == 'receive' for row in rows)
    discarded = sum(row.get('discard') is True for row in rows)
    pattern = (rf'DOMAIN_ENDPOINT_MANAGEMENT_PASS actions={len(rows)} mutations={len(mutations)} '
               rf'responses={responses} discarded={discarded} steps=([1-9][0-9]*)')
    match = re.search(pattern, (args.stage / 'witness.log').read_text())
    require(match is not None, 'missing complete finite parser witness verdict')
    for path, expected in inputs.items():
        require(digest(path) == expected, 'input changed during witness: ' + str(path))
    evidence = {'passed': True, 'evidence': trace['evidence'], 'actions': len(rows),
                'steps': int(match.group(1)), 'mutations': len(mutations), 'responses': responses,
                'discarded_responses': discarded, 'coverage': trace['coverage'],
                'compiled_source_sha256': compiled['source_build_sha256'], 'xls_tools': compiled['xls_tools'],
                'inputs': {str(path): value for path, value in inputs.items()},
                'domain': 'Exactly the retained finite framed command script and all generated command pins; '
                          'responses are checked word-for-word through deterministic ready/valid stalls.',
                'assumptions': 'Controlled metadata is supplied from native kernel issue-edge and post-edge results; '
                               'host TX binds assert prior RX confirmation and endpoint local lifetimes are fixed.',
                'trust': 'Native Erlang kernels and fixture generator, controlled-metadata testbench, '
                         'Erlang emitter, XLS and Icarus simulation.',
                'limits': trace['limits'],
                'artifacts': {path.name: digest(path) for path in args.stage.iterdir() if path.is_file()}}
    (args.stage / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(match.group(0), flush=True)


if __name__ == '__main__':
    main()
