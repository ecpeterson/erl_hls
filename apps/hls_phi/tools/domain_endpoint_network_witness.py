"""Bind retained independent endpoint networks into a finite public-port simulation adapter."""
import json
from pathlib import Path
import re
import shutil
from typing import Any

from backend_commands import digest, run
from backend_paths import ROOT, erlang_paths
from domain_endpoint_support import bundle_file, pins, require


# This reads retained Erlang metadata only; it does not elaborate source or run a compiler.
PROFILE = '''[Network,Output]=init:get_plain_arguments(),
{ok,Bytes}=file:read_file(filename:join(Network,"interface.etf")),
Interfaces=binary_to_term(Bytes),
B=fun unicode:characters_to_binary/1,
Pins=fun(Ps)->[#{name=>B(N),width=>W}||{N,W}<-Ps] end,
Rows=[begin
 #{role:=R,packets:=P,management:=M,network:=N}=I,
 #{domain_index:=Index,top_module:=Top,inputs:=Ins,outputs:=Outs}=N,
 true=lists:member({"domain_"++integer_to_list(Index)++"_fabric_fault",1},maps:get(inputs,R)),
 #{bits:=1024,data_words:=32,ack_words:=11,kind_bits:={0,8},data_kind:=1,ack_kind:=2,
   slot_bits:={8,8},reserved_zero_bits:={16,16},channel_bits:={32,32},binding_bits:={64,256},
   sequence_bits:={320,32},frame_bits:={352,672},ack_slot:=0,ack_unused_frame:=0,word_order:=little_endian}=maps:get(packet_format,P),
 #{codecs:=#{binding:={hls_type,hls_record,endpoint_binding,Fields}}}=P,
 [namespace,generation,source_incarnation,destination_incarnation]=[F||{F,_}<-Fields],
 #{index=>Index,module=>B(Top),inputs=>Pins(Ins),outputs=>Pins(Outs),
   role_source=>B(maps:get(source,R)),network_source=>B(maps:get(source,N)),
   domain_module=>B(maps:get(domain_module,R)),
   packet_core=>B(maps:get(core_module,P)),management_core=>B(maps:get(core_module,M)),
   endpoints=>[#{id=>Id,kind=>atom_to_binary(Kind),module=>B(Module),
       inputs=>Pins(EI),outputs=>Pins(EO)}||#{id:=Id,kind:=Kind,module:=Module,inputs:=EI,outputs:=EO}<-maps:get(endpoints,R)]}
end||I<-Interfaces],
ok=file:write_file(Output,json:encode(#{version=>1,roles=>Rows}),[exclusive]),halt().'''


def checked_bundle(source: Path, release: Path) -> tuple[dict[str, Any], dict[Path, str]]:
    """Validate every source and RTL member and every compiler result in one immutable normal release."""
    source = source.resolve(strict=True)
    release = release.resolve(strict=True)
    original, manifest_path, compiled_path = source / 'source-build.json', release / 'source-build.json', release / 'compiled.json'
    require(digest(original) == digest(manifest_path), 'selected source and compiled manifest differ')
    manifest, compiled = json.loads(manifest_path.read_text()), json.loads(compiled_path.read_text())
    require(compiled.get('source_build_sha256') == digest(manifest_path), 'compiled source identity mismatch')
    hashes = {path: digest(path) for path in (original, manifest_path, compiled_path)}
    supplied = manifest.get('inputs')
    require(isinstance(supplied, list) and bool(supplied), 'missing source inventory')
    seen = set()
    for item in supplied:
        require(item['file'] not in seen, 'duplicate source inventory entry')
        seen.add(item['file'])
        for base in (source, release):
            path = bundle_file(base, item['file'])
            require(digest(path) == item['sha256'], 'changed source input: ' + str(path))
            hashes[path] = item['sha256']
    inventory = compiled.get('rtl')
    require(isinstance(inventory, dict) and bool(inventory), 'missing compiled RTL inventory')
    for items in inventory.values():
        for item in items:
            path = bundle_file(release, item['file'])
            require(digest(path) == item['sha256'], 'changed compiled RTL: ' + str(path))
            require(path not in hashes or hashes[path] == item['sha256'], 'conflicting RTL identity')
            hashes[path] = item['sha256']
    units, completed = manifest.get('units'), compiled.get('units')
    require(isinstance(units, list) and isinstance(completed, list) and len(units) == len(completed), 'unit inventory mismatch')
    require(len({unit['directory'] for unit in units}) == len(units), 'duplicate compiler unit')
    for unit in units:
        matching = [item for item in completed if item['directory'] == unit['directory']]
        require(len(matching) == 1, 'missing compiled unit')
        commands = matching[0]['commands']
        require(bool(commands) and all(command['exit'] == 0 for command in commands), 'failed compiler stage')
        codegen = [command for command in commands if command['stage'] == 'codegen']
        require(len(codegen) == 1 and codegen[0]['output'] == unit['output'], 'missing unit codegen result')
        require(digest(bundle_file(release, unit['output'])) == codegen[0]['sha256'], 'changed codegen result')
        require(all(bundle_file(release, name) in hashes for name in unit['rtl']), 'unit RTL absent from inventory')
    return manifest, hashes


def network_profile(network: Path, stage: Path, profile: str, extra_ebin: list[Path]) -> tuple[dict[str, Any], Path]:
    """Extract only checked public pin/module metadata into the fresh test stage, outside frozen bundles."""
    output = stage / 'network-profile.json'
    paths = [*extra_ebin, *erlang_paths(profile)]
    run(['erl', '+S', '2:2', '-noshell', '-pa', *paths, '-eval', PROFILE, '-extra', network, output],
        stage, 'network-profile', timeout=60)
    value = json.loads(output.read_text())
    require(value.get('version') == 1 and [row.get('index') for row in value.get('roles', [])] == [0, 1],
            'expected exactly two retained roles')
    for row in value['roles']:
        require(row['module'] == f'endpoint_network_{row["index"]}', 'unexpected network module')
        row['inputs'], row['outputs'] = pins(row['inputs']), pins(row['outputs'])
        names = [name for name, _ in row['inputs'] + row['outputs']]
        require(len(set(names)) == len(names) and 'clk' not in names, 'colliding network pins')
        require(dict(row['inputs']).get('reset') == 1 and dict(row['inputs']).get('carrier_fault') == 1,
                'missing cold reset or carrier fault input')
        require(not any(name.endswith('fabric_fault') for name, _ in row['inputs']), 'network leaves local fabric fault unconnected')
        for field in ('module', 'domain_module', 'packet_core', 'management_core'):
            require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', row[field]) is not None, 'invalid emitted module name')
        endpoints = row['endpoints']
        require(len(endpoints) == 8 and [item['kind'] for item in endpoints].count('tx') == 4
                and [item['kind'] for item in endpoints].count('rx') == 4, 'expected four local TX/four RX endpoints')
        require(len({item['id'] for item in endpoints}) == 8, 'duplicate endpoint identity')
        for endpoint in endpoints:
            endpoint['inputs'], endpoint['outputs'] = pins(endpoint['inputs']), pins(endpoint['outputs'])
            require(type(endpoint['id']) is int and 0 <= endpoint['id'] < 1 << 32, 'invalid channel identity')
            require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', endpoint['module']) is not None, 'invalid endpoint module')
            drop = 'credit_drop' if endpoint['kind'] == 'tx' else 'data_drop'
            require(dict(endpoint['outputs']).get(drop) == 1 and dict(endpoint['outputs']).get('fault') == 1,
                    'missing native public drop/fault outputs')
    return value, output


def wrapper(stage: Path, profile: dict[str, Any], channels: list[dict[str, Any]]) -> Path:
    """Instantiate both existing networks with separate clocks and passive native public-output probes only."""
    ports, instances, probes = ['input wire clk_0', 'input wire clk_1'], [], []
    for row in profile['roles']:
        role = row['index']
        connections = [f'.clk(clk_{role})']
        for direction in ('input', 'output'):
            for name, width in row[direction + 's']:
                span = '' if width == 1 else f'[{width - 1}:0] '
                ports.append(f'{direction} wire {span}r{role}_{name}')
                connections.append(f'.{name}(r{role}_{name})')
        instances.append(f'{row["module"]} network_{role}(\n  ' + ',\n  '.join(connections) + '\n);')
    for channel in channels:
        index, source, destination = channel['index'], channel['source_domain'], channel['destination_domain']
        require({source, destination} == {0, 1}, 'crossing must connect the two roles')
        for role, kind, fields in [(source, 'tx', ['credit_drop', 'fault']), (destination, 'rx', ['data_drop', 'fault'])]:
            endpoint = [item for item in profile['roles'][role]['endpoints'] if item['id'] == index]
            require(len(endpoint) == 1 and endpoint[0]['kind'] == kind, 'source topology disagrees with native endpoint direction')
            for field in fields:
                name = f'probe_{index}_{kind}_{field}'
                ports.append('output wire ' + name)
                probes.append(f'assign {name} = network_{role}.role_unit.endpoint_{index}.{field};')
    output = stage / 'phi_endpoint_network_witness.sv'
    output.write_text('// Test-only mechanical composition. Probes read existing native output ports; no state is driven.\n'
                      'module phi_endpoint_network_witness(\n  ' + ',\n  '.join(ports) + '\n);\n'
                      + '\n'.join(instances + probes) + '\nendmodule\n')
    return output


def adapter(stage: Path, metadata: dict[str, Any], profile: dict[str, Any]) -> Path:
    """Bind generated public names to the unchanged FIFO framing and bounded packet transport harness."""
    initial, observations = [], []
    for row in profile['roles']:
        role = row['index']
        for name, width in row['inputs']:
            pin = f'core.r{role}_{name}'
            initial.append(f'{pin}=0;' if width <= 64 else f'for(unsigned i=0;i<{(width + 31) // 32};++i) {pin}[i]=0;')
        if metadata['inspection'] == 'process':
            domain = metadata['domains'][role]
            foreign = metadata['domains'][1 - role]['actors'][0]
            actors = ','.join(map(str, domain['actors']))
            observations.append(f'inspections[{role}].emplace_back(core.r{role}_domain_{role}_inspect_address,'
                f'core.r{role}_domain_{role}_inspect_incarnation,core.r{role}_domain_{role}_app_inspect_value,'
                f'std::vector<unsigned>{{{actors}}},{foreign},directory+"/domain{role}_inspection.control");')
    channels = []
    for channel in metadata['channels']:
        index = channel['index']
        channels.append(f'channels.emplace({index},Channel{{{index},{channel["source_domain"]},{channel["destination_domain"]},'
            f'core.probe_{index}_rx_data_drop,core.probe_{index}_tx_credit_drop,'
            f'core.probe_{index}_tx_fault,core.probe_{index}_rx_fault}});')
    template = ROOT / 'apps/hls_phi/test/rtl/phi_domain_endpoint_repetition_sim.cpp.in'
    text = template.read_text()
    replacements = {'@@INITIALIZE@@': '\n'.join(initial), '@@CHANNELS@@': '\n'.join(channels),
                    '@@INSPECTIONS@@': '\n'.join(observations)}
    for marker, value in replacements.items():
        require(marker in text, 'missing network adapter marker')
        text = text.replace(marker, value)
    require('@@' not in text, 'unresolved network adapter marker')
    output = stage / 'phi-domain-endpoint-repetition.cpp'
    output.write_text(text)
    for name in ('framed_fifo_endpoint.h', 'framed_fifo_stream.h', 'framed_fifo_control.h'):
        shutil.copyfile(ROOT / 'apps/hls_fabric/test/rtl' / name, stage / name)
    return output


def compile_adapter(domain: Path, domain_compiled: Path, network: Path, network_compiled: Path,
                    endpoints: Path, endpoint_compiled: Path, record: Path, stage: Path,
                    host_profile: str, extra_ebin: list[Path]) -> Path:
    """Compile only the test adapter around verified existing domain, endpoint, router and parser RTL."""
    domain_compiled, network_compiled, endpoint_compiled = [path.resolve(strict=True)
        for path in (domain_compiled, network_compiled, endpoint_compiled)]
    manifests, hashes = {}, {}
    for name, source, release in [('domain', domain, domain_compiled), ('network', network, network_compiled),
                                  ('endpoints', endpoints, endpoint_compiled)]:
        manifests[name], retained = checked_bundle(source, release)
        hashes.update(retained)
    require((network / 'evidence/domain-interface.etf').read_bytes() == (domain / 'interface.etf').read_bytes(),
            'network/domain interface identity mismatch')
    require((network / 'evidence/endpoint-interface.etf').read_bytes() == (endpoints / 'interface.etf').read_bytes(),
            'network/endpoint interface identity mismatch')
    provenance = json.loads(record.read_text())
    require(provenance['manifest'] == digest(network / 'source-build.json'), 'network emission manifest mismatch')
    external = provenance.get('external_inputs')
    require(isinstance(external, dict) and external, 'missing network dependency identities')
    for release in (domain_compiled, endpoint_compiled):
        for name in ('source-build.json', 'compiled.json'):
            path = release / name
            require(external.get(str(path)) == digest(path), 'selected parent release was not retained by network emission')
    for name, expected in external.items():
        path = Path(name)
        require(digest(path) == expected, 'changed network dependency: ' + name)
        hashes[path] = expected
    hashes[record] = digest(record)
    metadata = json.loads((domain / 'fixture.json').read_text())
    require(metadata['width'] == 8 and metadata['split'] == 4 and metadata['frame_words'] == 21
            and len(metadata['channels']) == 8 and metadata['physical_board_image'] is False, 'expected finite N8/4+4 source fixture')
    require([row['index'] for row in metadata['domains']] == [0, 1]
            and metadata['inspection'] in ('none', 'process'), 'unsupported role or inspection inventory')
    profile, profile_path = network_profile(network, stage, host_profile, extra_ebin)
    required = {'domain': {row['domain_module'] + '_core' for row in profile['roles']},
                'network': {row[field] for row in profile['roles'] for field in ('packet_core', 'management_core')},
                'endpoints': {item['module'] + '_core' for row in profile['roles'] for item in row['endpoints']}}
    rtl = []
    for name, release in [('domain', domain_compiled), ('network', network_compiled), ('endpoints', endpoint_compiled)]:
        units = [unit for unit in manifests[name]['units'] if unit['module'] in required[name]]
        require({unit['module'] for unit in units} == required[name], 'missing required reused units: ' + name)
        if name != 'domain':
            require(len(units) == len(manifests[name]['units']), 'unexpected endpoint/network compilation units')
        rtl.extend(bundle_file(release, path) for unit in units for path in unit['rtl'])
    for row in profile['roles']:
        rtl.extend(bundle_file(network_compiled, row[field]) for field in ('role_source', 'network_source'))
    rtl = list(dict.fromkeys(rtl))
    require(all(path in hashes for path in rtl), 'unretained RTL dependency')
    wrapper_path = wrapper(stage, profile, metadata['channels'])
    source = adapter(stage, metadata, profile)
    for path in [source, wrapper_path, profile_path, *stage.glob('*.h'), domain / 'fixture.etf', domain / 'fixture.json',
                 Path(__file__).resolve(), ROOT / 'tools/hls_fabric/domain_endpoint_support.py',
                 ROOT / 'tools/hls_fabric/backend_commands.py', ROOT / 'tools/hls_fabric/backend_paths.py',
                 ROOT / 'apps/hls_phi/test/rtl/phi_domain_endpoint_repetition_sim.cpp.in']:
        hashes[path] = digest(path)
    verilator = Path(shutil.which('verilator') or 'verilator').resolve(strict=True)
    hashes[verilator] = digest(verilator)
    run([verilator, '--cc', '--exe', '--build', '--top-module', 'phi_endpoint_network_witness',
         '--Mdir', stage / 'obj_dir', '-j', '1', '-Wno-fatal', '-CFLAGS', '-std=c++17',
         '-o', 'simulation', wrapper_path, *rtl, source], stage, 'verilator', timeout=1800)
    binary = stage / 'obj_dir/simulation'
    require(all(digest(path) == expected for path, expected in hashes.items()), 'input changed during adapter compilation')
    binary.with_suffix('.json').write_text(json.dumps({'binary_sha256': digest(binary), 'bundle': str(domain),
        'network': str(network), 'endpoint_bundle': str(endpoints), 'execution': 'independent_endpoint_network',
        'clock_periods': [6, 10], 'clock_phases': [0, 1],
        'inputs': {str(path): expected for path, expected in hashes.items()}}, indent=2) + '\n')
    return binary
