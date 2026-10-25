"""Relink transport-only D6 experiments while retaining byte-identical compiled actor modules.

This accepts the pinned XLS generator's simple module/instance grammar and rejects
any changed graph, actor, library, RAM wrapper or non-transport top-level wiring.
It is an experiment build accelerator, not a general Verilog rewriting frontend.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re

from transport_codegen import specialize
from backend_commands import digest, execute
from phi_build_artifacts import mesh_artifacts


def modules(text: str) -> dict[str, str]:
    """Split compiler-emitted modules, rejecting duplicate names or unexplained content."""
    matches = list(re.finditer(r'^module (\w+)\(.*?^endmodule\s*', text, re.M | re.S))
    result = {m[1]: m[0] for m in matches}
    remainder = re.sub(r'^module (\w+)\(.*?^endmodule\s*', '', text, flags=re.M | re.S)
    if not result or len(result) != len(matches) or remainder.strip():
        raise ValueError('unsupported generated module grammar')
    return result


def ports(module: str) -> dict[str, tuple[str, int]]:
    """Read only simple unsigned wire ports from an XLS module declaration."""
    header, = re.findall(r'^module \w+\((.*?)\n\);', module, re.S)
    pattern = r'\s*(input|output) wire(?: \[(\d+):0\])? (\w+)\s*,?'
    fields = re.findall(pattern, header)
    if re.sub(pattern, '', header).strip():
        raise ValueError('unsupported generated port grammar')
    result = {name: (direction, int(high)+1 if high else 1) for direction, high, name in fields}
    if len(result) != len(fields):
        raise ValueError('duplicate generated port')
    return result


def namespace(text: str, prefix: str) -> tuple[str, dict[str, str]]:
    """Give separately compiled modules disjoint names without altering signals or expressions."""
    names = modules(text)
    # Module definitions and instance types are the only module-name occurrences.
    # Keep the FIFO type grammar consumed by the checked public debug adapter.
    substitutions = {name: (re.sub(r'^(fifo_for_depth_\d+_ty_)', lambda m: m[1]+prefix, name)
                            if name.startswith('fifo_for_depth_') else prefix+name) for name in names}
    pattern = re.compile(r'\b(?:'+ '|'.join(map(re.escape, sorted(names, key=len, reverse=True)))+r')\b')
    renamed = pattern.sub(lambda match: substitutions[match[0]], text)
    return renamed, modules(renamed)


def widen(module: str, signal: str, width: int) -> str:
    """Change exactly one old 33-bit declaration at a checked link data boundary."""
    result, count = re.subn(r'\b(input wire|output wire|wire) \[32:0\] '+re.escape(signal)+r'([,;])',
                           lambda m: f'{m[1]} [{width-1}:0] {signal}{m[2]}', module)
    if count != 1:
        raise ValueError(f'expected one link declaration for {signal}, found {count}')
    return result


def gateway(source: str) -> tuple[str, str]:
    """Extract the generated gateway's literal parameters and event-array size."""
    params, = re.findall(r'spawn hls_partition_io::Boundary<([^>]+)>\(', source)
    count, = re.findall(r'^u32:(\d+),', params)
    return params, count


def validate_sources(base: Path, source: Path, words: int, credits: int, compact: bool = False) -> None:
    """Permit only explicit transport bindings and new deployment-identity constants."""
    if json.loads((base/'source-hashes.json').read_text()) != mesh_artifacts(base/'source'):
        raise ValueError('base generated sources differ from their recorded build')
    for path in (base/'source').glob('*.x'):
        current = source/path.name
        old, new = path.read_text(), current.read_text()
        if re.fullmatch(r'phi_device_\d+\.x', path.name):
            old = old.replace('import hls_credit_link;', 'import hls_packed_link;')
            old = re.sub(r'(link_\d+_(?:in|out): chan<)axis::Beat(>)', rf'\g<1>bits[{34*words}]\2', old)
            old = re.sub(r'hls_credit_link::Bridge<([^>]+)>',
                         lambda m: f'hls_packed_link::Bridge<{m[1]}, u32:{words}, u32:{credits}'
                         + (', true' if compact else '') + '>', old)
            old_params, _ = gateway(old)
            new_params, _ = gateway(new)
            old_fields, new_fields = [p.strip() for p in old_params.split(',')], [p.strip() for p in new_params.split(',')]
            if len(old_fields) != 7 or [old_fields[0], *old_fields[5:]] != [new_fields[0], *new_fields[5:]]:
                raise ValueError('actor reuse changed gateway endpoints or event capacity')
            old = old.replace('Boundary<'+old_params+'>', 'Boundary<'+new_params+'>')
        if old != new:
            raise ValueError(f'actor reuse would change non-transport source: {path.name}')
    for pattern in ('*_actors.json', '*_schedule.term', '*_ram.v'):
        for path in (base/'source').glob(pattern):
            old, new = path.read_text(), (source/path.name).read_text()
            if pattern == '*_ram.v':
                old = re.sub(r'\[32:0\]( _link_\d+_(?:in|out)\b)', f'[{34*words-1}:0]'+r'\1', old)
            if old != new:
                raise ValueError(f'actor reuse would change storage/projection: {path.name}')


def compile_component(args: argparse.Namespace, name: str, source: str) -> dict:
    """Compile and cache one small component with the same XLS scheduling options as full devices."""
    stage = args.stage/'components'/name
    inputs = {'top': source, 'source_hashes_sha256': digest(args.stage/'source-hashes.json'),
              'transport_codegen': digest(Path(__file__).with_name('transport_codegen.py')), 'tools': {tool: digest(args.xls/tool) for tool in ('ir_converter_main', 'opt_main', 'codegen_main')}}
    if (stage/'complete.json').exists():
        record = json.loads((stage/'complete.json').read_text())
        if record['inputs'] != inputs or record['rtl_sha256'] != digest(stage/'component.v'):
            raise ValueError('completed component changed')
        return record
    stage.mkdir(parents=True, exist_ok=False)
    (stage/'top.x').write_text(source)
    commands = [
        ('convert', [str(args.xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false',
                     f'--dslx_path={args.stage/"source"}', f'--dslx_stdlib_path={args.xls/"xls/dslx/stdlib"}', str(stage/'top.x')], 'component.ir'),
        ('optimize', [str(args.xls/'opt_main'), str(stage/'component.ir')], 'component.opt.ir'),
        ('codegen', [str(args.xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
                     '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
                     '--module_name=component', str(stage/'component.opt.ir')], 'component.v')]
    for label, command, output in commands:
        execute(command, stage, label, timeout=1200, output=stage/output)
    specialize(args.xls/'codegen_main', stage/'component.opt.ir', stage/'component.v', stage/'adapters')
    record = {'inputs': inputs, 'rtl_sha256': digest(stage/'component.v'),
              'commands': [command for _, command, _ in commands]}
    (stage/'complete.json').write_text(json.dumps(record, indent=2)+'\n')
    print(f'Compiled reusable {name}', flush=True)
    return record


def prepare(args: argparse.Namespace, devices: list[dict]) -> None:
    """Check the baseline and compile only each lane-count variant and each new identity gateway."""
    base = args.reuse_actors
    source = args.stage/'source'
    validate_sources(base, source, args.link_words, args.link_credits, args.link_compact)
    old_inputs = json.loads((base/'inputs.json').read_text())
    current_inputs = json.loads((args.stage/'inputs.json').read_text())
    if (old_inputs['tools'] != current_inputs['tools']
            or {k: v for k, v in old_inputs['files'].items() if k.startswith('stdlib/')}
            != {k: v for k, v in current_inputs['files'].items() if k.startswith('stdlib/')}):
        raise ValueError('actor reuse requires identical compiler and instrumentation tools')
    components = {}
    for device in devices:
        d = device['id']
        if json.loads((base/f'device{d}/complete.json').read_text()) != mesh_artifacts(base/f'device{d}'):
            raise ValueError(f'base device {d} changed')
        for link in device['links']:
            tx, rx = link['tx_lanes'], link['rx_lanes']
            components[f'link_{tx}_{rx}'] = f'''import axis;
import hls_packed_link;
pub proc Top {{
  config(link_in: chan<bits[{34*args.link_words}]> in, link_out: chan<bits[{34*args.link_words}]> out,
         frames_in: chan<axis::Frame>[{tx}] in, frames_out: chan<axis::Frame>[{rx}] out,
         fault_out: chan<u32> out) {{
    spawn hls_packed_link::Bridge<u32:{tx}, u32:{rx}, u16:18512, u32:{args.link_words}, u32:{args.link_credits}{', true' if args.link_compact else ''}>(
      link_in, link_out, frames_in, frames_out, fault_out); ()
  }}
  init {{ () }}
  next(state: ()) {{ state }}
}}
'''
        params, count = gateway((source/f'phi_device_{d}.x').read_text())
        components[f'gateway_{d}'] = f'''import axis;
import hls_partition_io;
import hls_spatial_router;
pub proc Top {{
  config(input: chan<axis::Beat> in, output: chan<axis::Beat> out,
         control: chan<hls_spatial_router::SpatialFrame> out, events: chan<axis::Frame>[{count}] in) {{
    spawn hls_partition_io::Boundary<{params}>(input, output, control, events); ()
  }}
  init {{ () }}
  next(state: ()) {{ state }}
}}
'''
    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        list(workers.map(lambda pair: compile_component(args, *pair), components.items()))


def link_device(args: argparse.Namespace, device: dict) -> None:
    """Replace module instances and link-width declarations; retain every other actor/wrapper byte."""
    d, width = device['id'], 34*args.link_words
    old_path = args.reuse_actors/f'device{d}/phi_device_{d}.v'
    library = modules(old_path.read_text())
    top_name = f'phi_device_{d}'
    top = library.pop(top_name)
    original = top
    attached, replacements = {}, []
    pattern = re.compile(r'^  (__hls_credit_link__Bridge_\w+|__hls_partition_io__Boundary_\w+) (\w+) \(\n(.*?)^  \);', re.M | re.S)
    matches = list(pattern.finditer(top))
    if len(matches) != len(device['links'])+1:
        raise ValueError('unexpected peer/gateway instance population')
    for match in reversed(matches):
        old_module, instance, body = match.groups()
        signals = dict(re.findall(r'^    \.(\w+)\((\w+)\),?$', body, re.M))
        if set(signals) != set(ports(library[old_module])):
            raise ValueError('unsupported component connection expression')
        if old_module.startswith('__hls_credit_link__'):
            index, = re.findall(r'^_link_(\d+)_in$', signals['_link_in'])
            link, = [l for l in device['links'] if l['index'] == int(index)]
            name = f'link_{link["tx_lanes"]}_{link["rx_lanes"]}'
            updated_ports = {key: (direction, width if key in ('_link_in', '_link_out') else bits)
                             for key, (direction, bits) in ports(library[old_module]).items()}
        else:
            name = f'gateway_{d}'
            updated_ports = ports(library[old_module])
        component_path = args.stage/'components'/name/'component.v'
        _, component_modules = namespace(component_path.read_text(), name+'__')
        new_module = name+'__component'
        if ports(component_modules[new_module]) != updated_ports:
            raise ValueError('replacement component changed a non-link port')
        attached.update(component_modules)
        top = top[:match.start()] + f'  {new_module} {instance} (\n{body}  );' + top[match.end():]
        replacements.append({'old_module': old_module, 'new_module': new_module,
                             'instance': instance, 'component_sha256': digest(component_path)})
    for match in matches:
        if match[1].startswith('__hls_credit_link__'):
            signals = dict(re.findall(r'^    \.(\w+)\((\w+)\),?$', match[3], re.M))
            index, = re.findall(r'^_link_(\d+)_in$', signals['_link_in'])
            for signal in (signals['_link_in'], f'_link_{index}_out', signals['_link_out']):
                top = widen(top, signal, width)
    library.update(attached)
    library[top_name] = top
    # Retain exactly the module dependency closure, excluding obsolete bridge logic.
    pending, included = [top_name], set()
    while pending:
        name = pending.pop()
        if name in included:
            continue
        included.add(name)
        pending += [kind for kind in re.findall(r'^  (\w+) \w+ \(', library[name], re.M) if kind in library]
    stage = args.stage/f'device{d}'
    stage.mkdir(parents=True, exist_ok=False)
    output = stage/f'phi_device_{d}.v'
    output.write_text('\n'.join(library[name] for name in sorted(included)))
    record = {'mode': 'checked-component-link', 'base': str(old_path), 'base_rtl_sha256': digest(old_path),
              'base_complete_sha256': digest(old_path.parent/'complete.json'),
              'source_hashes_sha256': digest(args.stage/'source-hashes.json'),
              'driver_sha256': digest(Path(__file__)), 'replacements': replacements,
              'old_top_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'new_top_sha256': hashlib.sha256(top.encode()).hexdigest(), 'outputs': {output.name: digest(output)}}
    (stage/'build.json').write_text(json.dumps(record, indent=2)+'\n')
