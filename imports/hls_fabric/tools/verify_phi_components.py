#!/usr/bin/env python3
"""Require identical generated board logic after renaming local identifiers and transparent wrappers.

This is a conservative comparison for pinned XLS output, not a general Verilog
equivalence checker: it leaves every expression, register, width and connection
intact. Different but equivalent logic fails the comparison.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from phi_mesh_components import modules, ports
from backend_commands import digest

INSTANCE = re.compile(r'^  (\w+) (\w+) \(\n(.*?)^  \);', re.M | re.S)
NET = re.compile(r'^  (?:wire|reg) (?:\[[^\]]+\] )?(\w+)', re.M)


def transparent(library: dict[str, str], name: str) -> str | None:
    """Recognize only a single child with identical ports and direct input/output wiring."""
    module = library[name]
    instances = list(INSTANCE.finditer(module))
    if len(instances) != 1:
        return None
    instance = instances[0]
    child = instance[1]
    interface = ports(module)
    if ports(library[child]) != interface:
        return None
    pairs = re.findall(r'^    \.(\w+)\((\w+)\),?$', instance[3], re.M)
    connections = dict(pairs)
    if len(pairs) != len(connections) or set(connections) != set(interface):
        return None
    assignments = re.findall(r'^  assign (\w+) = (\w+);$', module, re.M)
    wires = re.findall(r'^  wire(?: \[(\d+):0\])? (\w+);$', module, re.M)
    outputs = {p: connections[p] for p, (direction, _) in interface.items() if direction == 'output'}
    expected_wires = {connections[p]: width for p, (direction, width) in interface.items() if direction == 'output'}
    if (any(connections[p] != p for p, (direction, _) in interface.items() if direction == 'input')
            or dict(assignments) != outputs or len(assignments) != len(outputs)
            or {wire: int(high)+1 if high else 1 for high, wire in wires} != expected_wires
            or len(wires) != len(expected_wires) or set(expected_wires) & set(interface)):
        return None
    # Nothing other than these wires, one instance and assignments is admitted.
    remaining = INSTANCE.sub('', module)
    remaining = re.sub(r'^module \w+\(.*?^\);', '', remaining, flags=re.M | re.S)
    remaining = re.sub(r'^  wire(?: \[\d+:0\])? \w+;$|^  assign \w+ = \w+;$|^endmodule', '', remaining, flags=re.M)
    remaining = re.sub(r'//[^\n]*', '', remaining)
    if remaining.strip() or re.sub(r'\s*\.\w+\(\w+\),?', '', instance[3]).strip():
        return None
    return child


def canonical(library: dict[str, str], name: str, records: dict[str, str], active: set[str]) -> str:
    """Retain all logic verbatim while consistently renaming module-local nets, instances and labels."""
    if name in records:
        return records[name]
    if name in active:
        raise ValueError('recursive module instantiation')
    active.add(name)
    child = transparent(library, name)
    if child is not None:
        result = canonical(library, child, records, active)
    else:
        body = library[name]
        mapping = {name: 'CANON_MODULE'}
        groups = [('NET', NET.findall(body)), ('BLOCK', re.findall(r'begin : (\w+)', body))]
        for kind, names in groups:
            if len(set(names)) != len(names):
                raise ValueError('duplicate local identifier')
            for i, local in enumerate(names):
                if local in mapping or local.startswith('CANON_'):
                    raise ValueError('ambiguous local identifier')
                mapping[local] = f'CANON_{kind}_{i}'
        for i, instance in enumerate(INSTANCE.finditer(body)):
            typ, local = instance.group(1, 2)
            identity = hashlib.sha256(canonical(library, typ, records, active).encode()).hexdigest()
            mapping[typ] = 'CANON_TYPE_'+identity
            if local in mapping:
                raise ValueError('instance identifier collides with local net')
            mapping[local] = f'CANON_INST_{i}'
        # A named port is part of the child interface, never a local identifier.
        pattern = re.compile(r'(?<!\.)\b(?:'+'|'.join(map(re.escape, sorted(mapping, key=len, reverse=True)))+r')\b')
        result = pattern.sub(lambda match: mapping[match[0]], body).strip()
    active.remove(name)
    records[name] = result
    return result


def compare(reference: Path, candidate: Path, top: str) -> dict:
    """Require identical reachable circuits; report input hashes and the canonical circuit hash."""
    records = [{}, {}]
    normalized = [canonical(modules(path.read_text()), top, record, set())
                  for path, record in zip((reference, candidate), records)]
    if normalized[0] != normalized[1]:
        raise ValueError('generated board logic differs beyond local names and transparent wrappers')
    return {'reference': str(reference), 'candidate': str(candidate), 'top': top,
            'reference_sha256': digest(reference), 'candidate_sha256': digest(candidate),
            'canonical_sha256': hashlib.sha256(normalized[0].encode()).hexdigest(),
            'reachable_modules': [len(record) for record in records], 'checker_sha256': digest(Path(__file__)),
            'scope': 'All reachable board RTL. Consistent local-identifier renaming and checked direct-wire wrappers only; no behavioral simplification.'}


def main() -> None:
    """Retain a reproducible full-board comparison beside the experiment evidence."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('reference', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('--top', default='phi_device_0')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    report = compare(a.reference.resolve(), a.candidate.resolve(), a.top)
    a.output.write_text(json.dumps(report, indent=2)+'\n')
    print('PASS: identical complete-board logic after local renaming and transparent wrappers')


if __name__ == '__main__':
    main()
