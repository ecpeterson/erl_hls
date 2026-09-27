"""Read XLS dependency/stage evidence without treating a schedule as physical timing."""
from functools import lru_cache
import re


def ir_graph(text: str) -> dict:
    """Read single-line XLS nodes and their source stacks from scheduled or block IR."""
    files = {int(n): path for n, path in re.findall(r'^file_number (\d+) "([^"]+)"', text, re.M)}
    functions, current = {}, None
    for line in text.splitlines():
        header = re.match(r'(?:top )?(proc|fn|block) ([\w]+)[<(]', line)
        if header:
            current = functions.setdefault(header[2], {'kind': header[1], 'nodes': {}})
        node = re.match(r'  (?:ret )?([\w.]+): (.+) = (\w+)\((.*)\)$', line)
        if node and current is not None:
            name, kind, op, body = node.groups()
            identity = re.search(r'\bid=(\d+)', body)
            if identity is None:
                raise ValueError('XLS node without id')
            positions = re.search(r'\bpos=\[([^\]]*)\]', body)
            locations = [{'file': files[int(f)], 'line': int(l) + 1, 'column': int(c) + 1}
                         for f, l, c in re.findall(r'\((\d+),(\d+),(\d+)\)', positions[1] if positions else '')]
            current['nodes'][name] = {'id': int(identity[1]), 'name': name, 'type': kind,
                                     'op': op, 'arguments': body.split(', id=')[0],
                                     'locations': locations}
    for function in functions.values():
        nodes = function['nodes']
        for node in nodes.values():
            node['operands'] = list(dict.fromkeys(n for n in re.findall(r'[A-Za-z_][\w.]*', node['arguments'])
                                                 if n in nodes and n != node['name']))
    if not functions or not any(f['nodes'] for f in functions.values()):
        raise ValueError('empty or unsupported XLS IR')
    return functions


def schedule_nodes(text: str) -> dict:
    """Require explicit stage assignments for every timed node in a schedule textproto."""
    functions = {}
    for entry in re.split(r'^schedules \{\s*$', text, flags=re.M)[1:]:
        name = re.search(r'function: "([^"]+)"', entry)
        if name is None:
            raise ValueError('schedule without function')
        nodes, stage, current = {}, None, None
        for line in entry.splitlines():
            value = re.fullmatch(r'\s*stage: (\d+)', line)
            if value:
                stage = int(value[1])
            value = re.fullmatch(r'\s*node: "([^"]+)"', line)
            if value:
                if stage is None or value[1] in nodes:
                    raise ValueError('missing stage or duplicate scheduled node')
                current = nodes.setdefault(value[1], {'stage': stage})
            value = re.fullmatch(r'\s*(node_delay_ps|path_delay_ps): (\d+)', line)
            if value and current is not None:
                current[value[1]] = int(value[2])
        functions[name[1]] = nodes
    if not functions:
        raise ValueError('empty schedule')
    return functions


def analyze(ir: str, schedule: str, selection: str) -> list[dict]:
    """List arithmetic dependencies and actual stages; do not infer hidden solver constraints."""
    graph, stages = ir_graph(ir), schedule_nodes(schedule)
    result = []
    for name, function in graph.items():
        if not re.search(selection, name):
            continue
        nodes = function['nodes']
        timing = stages[name]

        @lru_cache(None)
        def ancestors(name: str) -> frozenset[str]:
            """Follow combinational operands; state reads end this graph's feedback arc."""
            return frozenset([name]).union(*(ancestors(n) for n in nodes[name]['operands']))

        products = []
        for node in nodes.values():
            if node['op'] not in ('smul', 'umul'):
                continue
            upstream = ancestors(node['name'])
            updates = [n for n in nodes.values() if n['op'] == 'next_value'
                       and node['name'] in ancestors(n['name'])]
            products.append(node | timing[node['name']] | {
                'input_boundaries': [nodes[n] | timing.get(n, {}) for n in sorted(upstream)
                                     if nodes[n]['op'] in ('state_read', 'receive')],
                'dependent_state_updates': [u | timing.get(u['name'], {}) for u in updates]})
        result.append({'function': name, 'state_reads': sum(n['op'] == 'state_read' for n in nodes.values()),
                       'max_stage_delay_ps': max(t.get('path_delay_ps', 0) for t in timing.values()),
                       'stage_delays_ps': {str(s): max(t.get('path_delay_ps', 0) for t in timing.values() if t['stage'] == s)
                                           for s in sorted({t['stage'] for t in timing.values()})},
                       'products': products,
                       'io': [n | timing.get(n['name'], {}) for n in nodes.values() if n['op'] in ('receive', 'send')]})
    if not result:
        raise ValueError('no selected processes')
    return result


def annotate_paths(paths: list[dict], block_ir: str, source_files: list[str]) -> None:
    """Link preserved generated net names to block IR ids and DSLX source stacks."""
    graph = ir_graph(block_ir)
    nodes = {n['id']: n | {'function': name} for name, f in graph.items() for n in f['nodes'].values()}
    for path in paths:
        evidence = {}
        for arc in path['arcs']:
            for text in [arc['resource'], *arc.get('aliases', [])]:
                for match in re.finditer(r'\b(?:p\d+_)?([a-z]+(?:_[a-z]+)*)_(\d+)(?=\[|\.|/|$)', text):
                    node = nodes.get(int(match[2]))
                    if node and node['op'] == match[1] and node['function'] in text:
                        evidence[node['id']] = node
        path['ir_nodes'] = list(evidence.values())
        # Attribute only recognized arithmetic nodes, never an adjacent unrelated signal.
        origins = set()
        for node in evidence.values():
            if node['op'] in ('smul', 'umul'):
                for filename in source_files:
                    location = next((loc for loc in node['locations'] if loc['file'] == filename), None)
                    if location:
                        origins.add(f"{filename}:{location['line']}")
        path['arithmetic_source_sites'] = sorted(origins)
