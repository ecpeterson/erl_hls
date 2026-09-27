#!/usr/bin/env python3
"""Group saved physical timing paths and price added decoder feedback cycles."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import tarfile

from schedule_report import analyze, annotate_paths


def sha(data: bytes) -> str:
    """Fingerprint the exact bytes consumed by the report."""
    return hashlib.sha256(data).hexdigest()


def canonical(name: str) -> str:
    """Match Yosys names across EDIF escaping without discarding hierarchy."""
    return name.replace('\\', '')


def read_artifact(spec: dict, root: Path) -> tuple[str, dict]:
    """Read one file or archive member; reject stale pinned evidence."""
    path = root / spec['path']
    if 'member' in spec:
        with tarfile.open(path) as archive:
            stream = archive.extractfile(spec['member'])
            if stream is None:
                raise ValueError('artifact is not a regular file')
            data = stream.read()
    else:
        data = path.read_bytes()
    digest = sha(data)
    if spec.get('sha256', digest) != digest:
        raise ValueError(f'artifact changed: {path}')
    return data.decode(), dict(spec, sha256=digest)


def field(block: str, expression: str) -> str:
    """Require a report field rather than silently supplying a missing delay."""
    match = re.search(expression, block, re.M)
    if match is None:
        raise ValueError(f'missing timing field: {expression}')
    return match[1].strip()


def vivado_arcs(block: str, source: str, destination: str) -> list[dict]:
    """Extract the data path only, including launch delay and excluding clocks/setup."""
    arcs, pending, active = [], '', False
    row = re.compile(r'^(.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(?:[rf]\s+)?(\S.*)$')
    table = block.split('Netlist Resource(s)', 1)[1]
    for raw in table.splitlines():
        line = raw.strip()
        boundary = re.search(r'\b(?:RAMB\w+|FD\w+|DSP\w+|SRL\w+)\b', line)
        if canonical(line).endswith(canonical(source)) and boundary:
            active = True
            continue
        if not active:
            continue
        if canonical(line).endswith(canonical(destination)) and boundary:
            break
        match = row.match((pending + ' ' + line).strip())
        if match is None:
            if '(Prop_' in line:
                pending = line
            continue
        description = match[1].strip()
        pending = ''
        resource = match[4]
        if 'net (' in description:
            fanout = re.search(r'fo=(\d+)', description)
            arcs.append({'kind': 'net', 'resource': resource, 'delay_ns': float(match[2]),
                         'fanout': int(fanout[1]) if fanout else None})
        elif '(Prop_' in description:
            primitive = field(description, r'\b(\w+)\s+\(Prop_')
            arcs.append({'kind': 'cell', 'resource': resource, 'primitive': primitive,
                         'site': description.split()[0], 'delay_ns': float(match[2])})
        if canonical(resource) == canonical(destination):
            break
    if not arcs:
        raise ValueError('no data arcs found; unsupported timing report')
    return arcs


def parse_vivado(text: str) -> list[dict]:
    """Read single-cycle setup paths; periods include setup/skew, arc sums do not."""
    paths = []
    for block in re.split(r'(?=^Slack \()', text, flags=re.M)[1:]:
        source = field(block, r'^\s*Source:\s*([^\n]+)')
        destination = field(block, r'^\s*Destination:\s*([^\n]+)')
        requirement = float(field(block, r'^\s*Requirement:\s*([\d.]+)ns'))
        slack = float(field(block, r'^Slack[^:]+:\s*([-\d.]+)ns'))
        if 'Path Type:              Setup' not in block:
            raise ValueError('only setup paths are supported')
        groups = re.findall(r'clocked by (\S+)\s+\{', block)
        if len(groups) != 2 or groups[0] != groups[1]:
            raise ValueError('cross-clock or unclocked path requires separate analysis')
        clocks = [float(v) for v in re.findall(r'period=([\d.]+)ns', block)]
        if len(clocks) != 2 or any(abs(v - requirement) > 0.001 for v in clocks):
            raise ValueError('multi-cycle/phase-shifted timing is not a one-cycle period')
        data = float(field(block, r'Data Path Delay:\s*([\d.]+)ns'))
        logic = float(field(block, r'Data Path Delay:.*?logic ([\d.]+)ns'))
        route = float(field(block, r'Data Path Delay:.*?route ([\d.]+)ns'))
        arcs = vivado_arcs(block, source, destination)
        if abs(sum(a['delay_ns'] for a in arcs) - data) > 0.02:
            raise ValueError('parsed data arcs do not sum to the reported path delay')
        paths.append({'source': source, 'destination': destination, 'clock': groups[0],
                      'requirement_ns': requirement, 'period_ns': requirement - slack,
                      'data_ns': data, 'logic_ns': logic, 'route_ns': route, 'arcs': arcs})
    if not paths:
        raise ValueError('no setup paths')
    return paths


def parse_native(text: str) -> list[dict]:
    """Read nextpnr's rounded critical-path text; retain its lower precision."""
    paths = []
    for block in re.split(r'Critical path report for clock ', text)[1:]:
        arcs, source, destination = [], None, None
        for line in block.splitlines():
            cell = re.search(r'Info:\s+([\d.]+)\s+([\d.]+)\s+Source (.+)', line)
            net = re.search(r'Info:\s+([\d.]+)\s+([\d.]+)\s+Net (.+?) budget.*?\((\d+),(\d+)\) -> \((\d+),(\d+)\)', line)
            sink = re.search(r'Info:\s+Sink (.+)', line)
            if cell:
                source = source or cell[3]
                arcs.append({'kind': 'cell', 'resource': cell[3], 'delay_ns': float(cell[1])})
            if net:
                arcs.append({'kind': 'net', 'resource': net[3], 'delay_ns': float(net[1]),
                             'grid_displacement': abs(int(net[4]) - int(net[6])) + abs(int(net[5]) - int(net[7]))})
            if sink:
                destination = sink[1]
        setup = re.search(r'Info:\s+[\d.]+\s+([\d.]+)\s+Setup', block)
        totals = re.search(r'Info:\s+([\d.]+) ns logic, ([\d.]+) ns routing', block)
        if not source or not destination or not setup or not totals:
            raise ValueError('incomplete native setup path')
        paths.append({'source': source, 'destination': destination,
                      'clock': block.split("'", 2)[1], 'period_ns': float(setup[1]),
                      'logic_ns': float(totals[1]), 'route_ns': float(totals[2]),
                      'arcs': arcs, 'precision_ns': 0.1})
    if not paths:
        raise ValueError('no native setup paths')
    return paths


def enrich(paths: list[dict], netlist: dict | None) -> None:
    """Attach preserved net aliases/source attributes to physical cells when available."""
    if netlist is None:
        return
    modules = netlist['modules']
    if len(modules) != 1:
        raise ValueError('provenance requires one flattened module')
    top = next(iter(modules.values()))
    cells = {canonical(k): v for k, v in top['cells'].items()}
    aliases, sinks = {}, {}
    nets = {canonical(k): v for k, v in top['netnames'].items()}
    for name, cell in cells.items():
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'input':
                for bit in bits:
                    if isinstance(bit, int):
                        sinks.setdefault(bit, []).append((name, port))
    for name, net in top['netnames'].items():
        if not name.startswith('$'):
            for bit in net['bits']:
                if isinstance(bit, int):
                    aliases.setdefault(bit, set()).add(name)
    for path in paths:
        for arc in path['arcs']:
            if arc['kind'] == 'net':
                name = canonical(arc['resource'])
                net = nets.get(name)
                bit = net['bits'][0] if net and len(net['bits']) == 1 else None
                index = re.fullmatch(r'(.+)\[(\d+)\]', name)
                if net is None and index:
                    net = nets.get(index[1])
                    if net and not net.get('upto', 0):
                        offset = int(index[2]) - net.get('offset', 0)
                        if 0 <= offset < len(net['bits']):
                            bit = net['bits'][offset]
                if isinstance(bit, int):
                    arc['mapped_sink_pins'] = len(sinks.get(bit, []))
                    arc['mapped_sink_cells'] = len({name for name, _ in sinks.get(bit, [])})
                continue
            if arc['kind'] != 'cell':
                continue
            name, _, port = canonical(arc['resource']).rpartition('/')
            cell = cells.get(name)
            if cell is None:
                continue
            arc['primitive'] = cell['type']
            arc['source_locations'] = cell.get('attributes', {}).get('src', '').split('|')
            bits = cell['connections'].get(port.split('[')[0], [])
            index = re.search(r'\[(\d+)\]', port)
            if index:
                bits = bits[int(index[1]):int(index[1]) + 1]
            arc['aliases'] = sorted({a for bit in bits for a in aliases.get(bit, ())})


def family(path: dict) -> str:
    """Classify observed structure; labels are not a claim of semantic equivalence."""
    resources = ' '.join(a['resource'] for a in path['arcs'])
    primitives = [a.get('primitive', '') for a in path['arcs']]
    start, end = (boundary_name(path[key]) for key in ('source', 'destination'))
    if any(p.startswith('DSP') for p in primitives):
        middle = 'DSP/carry arithmetic'
    elif primitives.count('MUXF8') >= 8:
        middle = 'serial selector'
    elif 'ReductionPlane' in resources and ('stage_done' in resources or 'incoming_result' in resources):
        middle = 'service/reduction control'
    elif primitives.count('CARRY4') >= 4:
        middle = 'carry arithmetic'
    else:
        middle = 'other logic'
    sites = path.get('arithmetic_source_sites', [])
    if sites:
        middle += ' (' + ', '.join(sites) + ')'
    return f'{start} → {middle} → {end}'


def boundary_name(resource: str) -> str:
    """Label preserved RAM hierarchy; other setup boundaries remain registers."""
    if 'state.memory' in resource:
        return 'state RAM'
    if 'mailbox.memory' in resource:
        return 'mailbox RAM'
    if '.memory' in resource:
        return 'RAM'
    return 'register'


def summarize(paths: list[dict], cycles: float | None, added_cycles: list[float]) -> dict:
    """Group sampled paths and compute cycle budgets without predicting a new placement."""
    grouped = {}
    for index, path in enumerate(paths):
        name = family(path)
        path['family'] = name
        grouped.setdefault(name, []).append(index)
    worst = max(p['period_ns'] for p in paths)
    groups = []
    for name, indices in grouped.items():
        remaining = [p['period_ns'] for i, p in enumerate(paths) if i not in indices]
        selected = [paths[i] for i in indices]
        groups.append({'family': name, 'paths': len(indices), 'indices': indices,
                       'worst_ns': max(p['period_ns'] for p in selected),
                       'best_ns': min(p['period_ns'] for p in selected),
                       'unmodified_sample_floor_ns': max(remaining) if remaining else None,
                       'source_count': len({p['source'] for p in selected}),
                       'destination_count': len({p['destination'] for p in selected})})
    nets = sorted((a for p in paths for a in p['arcs'] if a['kind'] == 'net'),
                  key=lambda a: -a['delay_ns'])
    seen, distinct = set(), []
    for net in nets:
        if net['resource'] not in seen:
            seen.add(net['resource'])
            distinct.append(net)
    result = {'paths_reported': len(paths), 'period_ns': worst,
              'families': sorted(groups, key=lambda g: -g['worst_ns']), 'longest_nets': distinct[:10],
              'all_path_families_covered': False,
              'sample_floor_note': 'Untouched reported paths bound possible improvement; absent families remain unknown.'}
    if cycles is not None:
        if not math.isfinite(cycles) or cycles <= 0:
            raise ValueError('cycles_per_step must be positive')
        result.update(cycles_per_step=cycles, step_ns=cycles * worst,
                      target_1mhz_period_ns=1000 / cycles,
                      added_cycle_budget=[{'added_cycles': extra,
                          'break_even_period_ns': cycles * worst / (cycles + extra),
                          'target_1mhz_period_ns': 1000 / (cycles + extra)} for extra in added_cycles])
    return result


def markdown(report: dict) -> str:
    """Render the same structured results used by programmatic experiment screens."""
    lines = ['# ' + report['title'], '',
             'Saved path evidence; no new placement or board-clock qualification. Groups describe observed structure. '
             'A top-path sample does not reveal the next limit after removing every represented family.', '']
    for run in report['runs']:
        summary = run['summary']
        lines += ['## ' + run['name'], '',
                  f"{run['tool']}, {run['stage']}; requested period {run['constraint_ns']:g} ns. "
                  f"{summary['paths_reported']} distinct reported paths; worst {summary['period_ns']:.3f} ns.", '']
        if len(run.get('path_sets', [])) > 1:
            lines += ['| Queried endpoints/through-points | Paths | Worst period, ns | Logic / route, ns | Cell arcs |',
                      '|---|---:|---:|---:|---:|']
            for group in run['path_sets']:
                lines.append(f"| {group['name']} | {group['paths']} | {group['worst_ns']:.3f} | "
                             f"{group['logic_ns']:.3f} / {group['route_ns']:.3f} | {sum(group['cell_arcs'].values())} |")
            lines += ['', 'Query sets can overlap; the family table below deduplicates identical paths.', '']
        lines += [
                  '| Observed family | Paths | Period range, ns | Untouched sample floor, ns |',
                  '|---|---:|---:|---:|']
        for group in summary['families']:
            floor = group['unmodified_sample_floor_ns']
            lines.append(f"| {group['family']} | {group['paths']} | {group['best_ns']:.3f}–{group['worst_ns']:.3f} | "
                         + (f'{floor:.3f}' if floor is not None else 'Unknown') + ' |')
        if 'step_ns' in summary:
            lines += ['', f"At {summary['cycles_per_step']:g} simulated cycles/step: "
                      f"{summary['step_ns']/1000:.3f} µs. Unchanged-cycle 1 MHz requires "
                      f"{summary['target_1mhz_period_ns']:.3f} ns.", '',
                      '| Added cycles/step | Break-even period, ns | Period for 1 MHz, ns |',
                      '|---:|---:|---:|']
            for budget in summary['added_cycle_budget']:
                lines.append(f"| {budget['added_cycles']:g} | {budget['break_even_period_ns']:.3f} | "
                             f"{budget['target_1mhz_period_ns']:.3f} |")
        worst = max(run['paths'], key=lambda p: p['period_ns'])
        lines += ['', f"Worst path: {worst['logic_ns']:.3f} ns logic, {worst['route_ns']:.3f} ns interconnect. "
                  'Clock/setup adjustments are included in the period, not these two data-path components.', '']
        if 'precision_ns' in worst:
            lines += [f"Native text values are rounded to {worst['precision_ns']:g} ns.", '']
        if run.get('schedule'):
            lines += ['The XLS delays below exclude physical work outside each proc. '
                      'Dependency edges establish dataflow, not the scheduler’s complete constraint system.', '',
                      '| Process | State reads | Estimated stage delays, ns | Multiply stages |',
                      '|---|---:|---|---|']
            for function in run['schedule']:
                delays = ', '.join(f'{stage}: {delay/1000:.3f}' for stage, delay in function['stage_delays_ps'].items())
                products = ', '.join(f"{p['name']}={p['stage']}" for p in function['products'])
                lines.append(f"| `{function['function']}` | {function['state_reads']} | {delays} | {products} |")
            lines += ['']
    return '\n'.join(lines)


def build(manifest: dict, root: Path) -> dict:
    """Combine pinned report artifacts; never merge unlike tool/constraint populations."""
    if manifest.get('schema') != 1:
        raise ValueError('unsupported manifest schema')
    result = {'schema': 1, 'title': manifest['title'], 'runs': []}
    for spec in manifest['runs']:
        parser = {'vivado': parse_vivado, 'nextpnr': parse_native}[spec['tool']]
        sources, unique, sets = {}, {}, []
        queries = {'global': spec['paths']} | spec.get('path_sets', {})
        for label, artifact in queries.items():
            text, fingerprint = read_artifact(artifact, root)
            sources['paths' if label == 'global' else 'paths_' + label] = fingerprint
            parsed = parser(text)
            worst = max(parsed, key=lambda p: p['period_ns'])
            sets.append({'name': label, 'paths': len(parsed), 'worst_ns': worst['period_ns'],
                         'logic_ns': worst['logic_ns'], 'route_ns': worst['route_ns'],
                         'cell_arcs': dict(Counter(a.get('primitive', 'unspecified') for a in worst['arcs'] if a['kind'] == 'cell'))})
            for path in parsed:
                signature = json.dumps(path, sort_keys=True)
                if signature not in unique:
                    unique[signature] = path | {'reported_in': []}
                unique[signature]['reported_in'].append(label)
        paths = list(unique.values())
        if any(abs(p.get('requirement_ns', spec['constraint_ns']) - spec['constraint_ns']) > .001 for p in paths):
            raise ValueError('report and manifest constraints differ')
        if 'cycle_evidence' in spec:
            data, sources['cycle_evidence'] = read_artifact(spec['cycle_evidence'], root)
            value = json.loads(data)
            for key in spec['cycle_pointer'].strip('/').split('/'):
                value = value[int(key)] if isinstance(value, list) else value[key]
            if value != spec.get('cycles_per_step'):
                raise ValueError('cycle evidence disagrees with manifest')
        netlist = None
        if 'netlist' in spec:
            data, sources['netlist'] = read_artifact(spec['netlist'], root)
            netlist = json.loads(data)
        enrich(paths, netlist)
        schedule = None
        if 'block_ir' in spec:
            block, sources['block_ir'] = read_artifact(spec['block_ir'], root)
            annotate_paths(paths, block, spec.get('source_files', []))
        if 'scheduled_ir' in spec:
            ir, sources['scheduled_ir'] = read_artifact(spec['scheduled_ir'], root)
            stages, sources['schedule'] = read_artifact(spec['schedule'], root)
            schedule = analyze(ir, stages, spec['process_pattern'])
        extras = spec.get('added_cycles', [1, 14, 29])
        if any(not math.isfinite(x) or x < 0 for x in extras):
            raise ValueError('added cycles must be finite and nonnegative')
        result['runs'].append({key: spec[key] for key in ('name', 'tool', 'stage', 'constraint_ns')} |
                             {'artifacts': sources, 'paths': paths, 'path_sets': sets, 'schedule': schedule,
                              'summary': summarize(paths, spec.get('cycles_per_step'), extras)})
    return result


def main() -> None:
    """Generate JSON and Markdown from relocatable evidence paths without invoking tools."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='output filename without extension')
    parser.add_argument('--full-json', action='store_true', help='include every parsed arc and source attribution')
    args = parser.parse_args()
    data = args.manifest.read_bytes()
    report = build(json.loads(data), args.artifacts)
    report['manifest_sha256'] = sha(data)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.md').write_text(markdown(report))
    if not args.full_json:
        for run in report['runs']:
            del run['paths']
    report['includes_path_details'] = args.full_json
    args.output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
