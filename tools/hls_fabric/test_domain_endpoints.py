"""Compare a finite native endpoint trace with its normally compiled TX/RX RTL."""
import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shutil
from typing import Any

from backend_commands import digest, run
from backend_paths import ROOT
from domain_endpoint_support import IDENTIFIER, bundle_file, pins, require


MAX_ROWS = 2048
HEX = re.compile(r'[0-9a-fA-F]+\Z')


@dataclass(frozen=True)
class Endpoint:
    """Checked sampled-pin layout; declaration order is most-significant field first."""

    module: str
    inputs: list[tuple[str, int]]
    outputs: list[tuple[str, int]]
    controller_words: int
    frame_bits: int

    @property
    def input_bits(self) -> int:
        """Return the complete mechanically packed command width."""
        return sum(width for _, width in self.inputs)

    @property
    def output_bits(self) -> int:
        """Return the complete mechanically packed observation width."""
        return sum(width for _, width in self.outputs)


def endpoint(value: object) -> Endpoint:
    """Check one endpoint profile without inferring its pin widths from RTL text."""
    require(isinstance(value, dict), 'invalid endpoint profile')
    module = value.get('module')
    require(isinstance(module, str) and IDENTIFIER.fullmatch(module) is not None,
            'invalid wrapper module')
    inputs, outputs = pins(value.get('inputs')), pins(value.get('outputs'))
    require(not {name for name, _ in inputs} & {name for name, _ in outputs},
            'input/output pin collision')
    require(('reset', 1) in inputs and 'clk' not in dict(inputs + outputs),
            'missing cold reset or colliding clock pin')
    words, frame_bits = value.get('controller_words'), value.get('frame_bits')
    require(type(words) is int and 1 <= words <= 255, 'invalid controller capacity')
    require(type(frame_bits) is int and 0 < frame_bits <= 8192, 'invalid data frame width')
    return Endpoint(module, inputs, outputs, words, frame_bits)


def hexadecimal(value: object, width: int) -> int:
    """Read a bounded hexadecimal trace vector without silently truncating high bits."""
    require(isinstance(value, str) and 0 < len(value) <= (width + 3) // 4,
            'invalid trace vector length')
    require(HEX.fullmatch(value) is not None, 'invalid hexadecimal trace vector')
    result = int(value, 16)
    require(result < 1 << width, 'trace vector exceeds its declared width')
    return result


def field_value(fields: list[tuple[str, int]], vector: int, selected: str) -> int:
    """Decode one named field from the emitter's declared MSB-first pin order."""
    remaining = sum(width for _, width in fields)
    for name, width in fields:
        remaining -= width
        if name == selected:
            return (vector >> remaining) & ((1 << width) - 1)
    raise ValueError('missing pin: ' + selected)


def checked_trace(trace: dict[str, Any]) -> tuple[dict[str, Endpoint], list[dict[str, Any]]]:
    """Validate reset initialization, finite row bounds and complete output-bit coverage."""
    require(trace.get('version') == 1 and trace.get('evidence') == 'finite_native_rtl_witness',
            'unsupported endpoint trace')
    profiles = trace.get('profiles')
    require(isinstance(profiles, dict) and set(profiles) == {'tx', 'rx'}, 'missing endpoint profiles')
    endpoints = {role: endpoint(profiles[role]) for role in ('tx', 'rx')}
    scenarios = trace.get('scenarios')
    require(isinstance(scenarios, list) and 0 < len(scenarios) <= 64
            and all(isinstance(name, str) and 0 < len(name) <= 160 for name in scenarios),
            'missing finite scenario inventory')
    require(len(set(scenarios)) == len(scenarios), 'duplicate scenario name')
    supplied = trace.get('rows')
    require(isinstance(supplied, list) and 2 < len(supplied) <= MAX_ROWS, 'invalid finite trace length')
    rows, seen, coverage = [], set(), {'tx': 0, 'rx': 0}
    for index, row in enumerate(supplied):
        require(isinstance(row, dict), 'invalid trace row')
        role, label, delay = row.get('role'), row.get('label'), row.get('delay')
        require(role in endpoints, 'unknown trace role')
        require(isinstance(label, str) and 0 < len(label) <= 160, 'missing trace row label')
        require(type(delay) is int and 1 <= delay <= 11, 'invalid sampled-edge delay')
        profile = endpoints[role]
        command = hexadecimal(row.get('input'), profile.input_bits)
        expected = hexadecimal(row.get('expected'), profile.output_bits)
        mask = hexadecimal(row.get('mask'), profile.output_bits)
        reset = field_value(profile.inputs, command, 'reset')
        require(mask != 0 or reset == 1, 'unchecked non-reset edge at row ' + str(index))
        if role not in seen:
            require(reset == 1 and mask == 0, 'endpoint must start with unchecked cold reset')
            seen.add(role)
        coverage[role] |= mask
        rows.append({'role': role, 'label': label, 'delay': delay,
                     'input': command, 'expected': expected, 'mask': mask})
    require(seen == {'tx', 'rx'}, 'both endpoint clocks must be exercised')
    for role, profile in endpoints.items():
        require(coverage[role] == (1 << profile.output_bits) - 1,
                'not every output bit was checked for ' + role)
    return endpoints, rows


def wiring(role: str, profile: Endpoint) -> str:
    """Connect named wrapper pins directly to metadata-derived vector slices."""
    declarations = [f'reg {role}_clk = 0;',
                    f'reg [{profile.input_bits - 1}:0] {role}_inputs = 0;',
                    f'wire [{profile.output_bits - 1}:0] {role}_outputs;']
    connections = [f'.clk({role}_clk)']
    for fields, suffix in ((profile.inputs, 'inputs'), (profile.outputs, 'outputs')):
        remaining = sum(width for _, width in fields)
        for name, width in fields:
            remaining -= width
            bits = str(remaining) if width == 1 else f'{remaining + width - 1}:{remaining}'
            connections.append(f'.{name}({role}_{suffix}[{bits}])')
    declarations.append(f'{profile.module} {role}_dut(\n  ' + ',\n  '.join(connections) + '\n);')
    return '\n'.join(declarations)


def executable(value: str) -> Path:
    """Resolve the actual executable whose bytes will be retained in the evidence."""
    path = Path(shutil.which(value) or value).resolve(strict=True)
    require(path.is_file() and os.access(path, os.X_OK), 'not an executable: ' + str(path))
    return path


def compiled_inputs(bundle: Path, manifest: dict[str, Any], compiled: dict[str, Any]) -> dict[Path, str]:
    """Verify the normal source-build record, its snapshots and compiled RTL identities."""
    manifest_path = bundle / 'source-build.json'
    require(compiled.get('source_build_sha256') == digest(manifest_path),
            'compiled source manifest identity mismatch')
    supplied = manifest.get('inputs')
    require(isinstance(supplied, list) and bool(supplied), 'missing source input inventory')
    inputs = {manifest_path: digest(manifest_path), bundle / 'compiled.json': digest(bundle / 'compiled.json')}
    for item in supplied:
        path = bundle_file(bundle, item['file'])
        require(path not in inputs, 'duplicate source input')
        require(digest(path) == item['sha256'], 'changed source input: ' + item['file'])
        inputs[path] = item['sha256']
    require(bundle / 'endpoint-trace.json' in inputs, 'trace is absent from frozen source inputs')
    rtl = compiled.get('rtl')
    require(isinstance(rtl, dict) and bool(rtl), 'missing compiled RTL inventory')
    for files in rtl.values():
        for item in files:
            path = bundle_file(bundle, item['file'])
            require(digest(path) == item['sha256'], 'changed compiled RTL: ' + item['file'])
            require(path not in inputs or inputs[path] == item['sha256'], 'conflicting RTL identity')
            inputs[path] = item['sha256']
    return inputs


def main() -> None:
    """Run only Icarus over two already compiled endpoints and retain finite witness evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=lambda value: Path(value).resolve(),
                        help='compiled release produced by compile_source_build, usually SOURCE/compiled')
    parser.add_argument('stage', type=lambda value: Path(value).resolve(), help='fresh witness directory')
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG', 'iverilog'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    args = parser.parse_args()
    manifest = json.loads((args.bundle / 'source-build.json').read_text())
    compiled = json.loads((args.bundle / 'compiled.json').read_text())
    inputs = compiled_inputs(args.bundle, manifest, compiled)
    trace = json.loads((args.bundle / 'endpoint-trace.json').read_text())
    profiles, rows = checked_trace(trace)
    units = manifest.get('units')
    require(isinstance(units, list) and len(units) == 2, 'witness needs exactly two endpoint units')
    by_top = {unit['top']: unit for unit in units}
    require(set(by_top) == {'endpoint_tx_clock', 'endpoint_rx_clock'}, 'unexpected compilation units')
    compiled_units = {unit['directory']: unit for unit in compiled['units']}
    require(set(compiled_units) == {unit['directory'] for unit in units}, 'compiled unit inventory mismatch')
    rtl = []
    required_flags = {'--pipeline_stages=1', '--flop_inputs=false', '--flop_outputs=false', '--reset=reset'}
    for role in ('tx', 'rx'):
        unit = by_top['endpoint_' + role + '_clock']
        require(required_flags <= set(unit['codegen_flags']), 'incompatible sampled-clock schedule')
        commands = compiled_units[unit['directory']]['commands']
        require(all(command['exit'] == 0 for command in commands), 'failed compiled stage')
        codegen = [command for command in commands if command['stage'] == 'codegen']
        require(len(codegen) == 1 and codegen[0]['output'] == unit['output'], 'missing compiled endpoint core')
        require(digest(bundle_file(args.bundle, unit['output'])) == codegen[0]['sha256'],
                'codegen product identity mismatch')
        for name in unit['rtl']:
            path = bundle_file(args.bundle, name)
            require(path in inputs, 'RTL is absent from the compiled inventory: ' + name)
            if path not in rtl:
                rtl.append(path)
    iverilog, vvp = executable(args.iverilog), executable(args.vvp)
    template_path = ROOT / 'apps/hls_fabric/test/rtl/domain_endpoints_tb.sv.in'
    for path in (Path(__file__).resolve(), ROOT / 'tools/hls_fabric/domain_endpoint_support.py',
                 ROOT / 'tools/hls_fabric/backend_commands.py',
                 ROOT / 'tools/hls_fabric/backend_paths.py', template_path, iverilog, vvp):
        inputs[path] = digest(path)
    args.stage.mkdir(parents=True)
    template = template_path.read_text()
    replacements = {'@@WIRING@@': '\n\n'.join(wiring(role, profiles[role]) for role in ('tx', 'rx')),
                    '@@INPUT_BITS@@': str(max(profile.input_bits for profile in profiles.values())),
                    '@@OUTPUT_BITS@@': str(max(profile.output_bits for profile in profiles.values())),
                    '@@ROWS@@': str(len(rows)), '@@TIMEOUT@@': str(len(rows) * 15 + 100)}
    for marker, value in replacements.items():
        require(marker in template, 'missing testbench template marker: ' + marker)
        template = template.replace(marker, value)
    require('@@' not in template, 'unresolved testbench template marker')
    bench = args.stage / 'domain_endpoints_tb.sv'
    bench.write_text(template)
    vectors = args.stage / 'trace.txt'
    vectors.write_text(''.join(f'{0 if row["role"] == "tx" else 1} {row["input"]:x} '
                              f'{row["expected"]:x} {row["mask"]:x} {row["delay"]}\n' for row in rows))
    (args.stage / 'trace-labels.json').write_text(json.dumps([
        {'row': index, 'role': row['role'], 'label': row['label']} for index, row in enumerate(rows)
    ], indent=2) + '\n')
    inputs[bench], inputs[vectors] = digest(bench), digest(vectors)
    simulation = args.stage / 'domain_endpoints.vvp'
    run([iverilog, '-g2012', '-s', 'domain_endpoints_tb', '-o', simulation, bench, *rtl],
        args.stage, 'iverilog', timeout=120)
    run([vvp, simulation, '+trace=' + str(vectors)], args.stage, 'witness', timeout=60)
    checked = sum(row['mask'] != 0 for row in rows)
    counts = {role: sum(row['role'] == role for row in rows) for role in ('tx', 'rx')}
    marker = (f'DOMAIN_ENDPOINTS_PASS steps={len(rows)} checked_steps={checked} '
              f'tx_steps={counts["tx"]} rx_steps={counts["rx"]}')
    require(marker in (args.stage / 'witness.log').read_text(), 'missing complete finite witness verdict')
    for path, expected_hash in inputs.items():
        require(digest(path) == expected_hash, 'input changed during witness: ' + str(path))
    evidence = {'passed': True, 'evidence': 'finite_native_rtl_witness', 'steps': len(rows),
                'checked_steps': checked, 'endpoint_steps': counts, 'scenarios': trace['scenarios'],
                'inputs': {str(path): value for path, value in inputs.items()},
                'compiled_source_sha256': compiled['source_build_sha256'],
                'xls_tools': compiled['xls_tools'],
                'domain': 'Exactly the retained finite sampled input rows from the native reference; '
                          'each row advances only its selected local endpoint clock.',
                'assumptions': 'The supplied trace was generated by the native step functions; '
                               'carrier framing/integrity and host binding evidence are supplied inputs.',
                'trust': 'Native Erlang kernels and trace generator, Erlang-to-DSLX lowering, XLS, '
                         'mechanical pin packing and Icarus simulation.',
                'limits': 'A finite simulation witness, not a formal proof, arbitrary-history '
                          'equivalence, physical CDC/reset qualification or recovery/progress claim.',
                'artifacts': {path.name: digest(path) for path in args.stage.iterdir() if path.is_file()}}
    (args.stage / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(marker, flush=True)


if __name__ == '__main__':
    main()
