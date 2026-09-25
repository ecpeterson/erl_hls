"""Verify that Vivado linked the exact Yosys pin graph, including vector bit order."""
from __future__ import annotations
from collections import defaultdict
from copy import deepcopy
import json
import re
from pathlib import Path
from typing import Any


def normalize(data: dict[str, Any]) -> dict[str, Any]:
    """Expand Vivado's INV alias into its exact one-input LUT function."""
    result = deepcopy(data)
    for cell in result['modules']['probe_top']['cells'].values():
        if cell['type'] == 'INV':
            cell['type'] = 'LUT1'
            cell['connections']['I0'] = cell['connections'].pop('I')
            cell['parameters'] = {'INIT': '01'}
    return result


def pin_name(name: str, index: int, width: int, offset: int = 0) -> str:
    """Name scalar pins directly and vector pins by their logical bit index."""
    return name if width == 1 else f'{name}[{index + offset}]'


def expected_graph(data: dict[str, Any]) -> tuple[dict[str, str], set[frozenset[tuple[str, str]]]]:
    """Canonicalize native net connectivity without relying on generated net names."""
    top = data['modules']['probe_top']
    cells = {n: c['type'] for n, c in top['cells'].items() if c['type'] != '$scopeinfo'}
    nets: dict[int | str, set[tuple[str, str]]] = defaultdict(set)
    for name, cell in top['cells'].items():
        if name not in cells:
            continue
        connections = dict(cell['connections'])
        for port, bits in connections.items():
            for i, bit in enumerate(bits):
                nets[bit].add((name, pin_name(port, i, len(bits))))
    for port, info in top['ports'].items():
        for i, bit in enumerate(info['bits']):
            nets[bit].add(('@top', pin_name(port, i, len(info['bits']), info.get('offset', 0))))
    for bit in ('0', '1'):
        if bit in nets:
            nets[bit].add(('@constant', bit))
    return cells, {frozenset(pins) for pins in nets.values() if len(pins) > 1}


def unused_dsp_pins(data: dict[str, Any]) -> set[tuple[str, str]]:
    """Identify absent controls whose DSP register stages are provably bypassed."""
    ignored = set()
    for name, cell in data['modules']['probe_top']['cells'].items():
        if cell['type'] != 'DSP48E1':
            continue
        params = cell['parameters']
        def value(key: str) -> int:
            """Treat unspecified modes as enabled, so uncertainty never hides a pin."""
            return int(params.get(key, '1'), 2)
        pins = set()
        for prefix in ('A', 'B'):
            if value(prefix + 'REG') == 0 and value(prefix + 'CASCREG') == 0:
                pins.update(('CE' + prefix + '1', 'CE' + prefix + '2', 'RST' + prefix))
            elif value(prefix + 'REG') <= 1 and value(prefix + 'CASCREG') <= 1:
                pins.add('CE' + prefix + '1')
        groups = {
            ('CREG',): ('CEC', 'RSTC'), ('DREG',): ('CED',),
            ('ADREG',): ('CEAD',), ('DREG', 'ADREG'): ('RSTD',),
            ('MREG',): ('CEM', 'RSTM'), ('PREG',): ('CEP', 'RSTP'),
            ('ALUMODEREG',): ('CEALUMODE', 'RSTALUMODE'),
            ('CARRYINREG',): ('CECARRYIN', 'RSTALLCARRYIN'),
            ('OPMODEREG', 'CARRYINSELREG'): ('CECTRL', 'RSTCTRL'),
            ('INMODEREG',): ('CEINMODE', 'RSTINMODE'),
        }
        for modes, controls in groups.items():
            if all(value(mode) == 0 for mode in modes):
                pins.update(controls)
        ignored.update((name, pin) for pin in pins if pin not in cell['connections'])
    return ignored


def linked_graph(path: Path, ignored: set[tuple[str, str]] | None = None) -> tuple[dict[str, str], set[frozenset[tuple[str, str]]]]:
    """Canonicalize a Vivado export, recognizing added GND/VCC driver cells."""
    cells = {}
    nets: dict[str, set[tuple[str, str]]] = defaultdict(set)
    for line in path.read_text().splitlines():
        cell, kind, pin, net = line.split('\t')
        cell = cell.replace('\\\\', '\\')
        if kind in ('GND', 'VCC'):
            nets[net].add(('@constant', '0' if kind == 'GND' else '1'))
        else:
            if cell != '@top':
                cells[cell] = kind
            if net and (cell, pin) not in (ignored or set()):
                nets[net].add((cell, pin))
    # Separate constant drivers are electrically equivalent; merge their sinks.
    for bit in ('0', '1'):
        keys = [key for key, pins in nets.items() if ('@constant', bit) in pins]
        merged = set().union(*(nets.pop(key) for key in keys))
        if merged:
            nets['@constant' + bit] = merged
    return cells, {frozenset(pins) for pins in nets.values() if len(pins) > 1}


def parameter_value(text: str, binary: bool = False) -> int | str:
    """Normalize Yosys bit strings and Vivado Verilog literals for comparison."""
    value = text.strip()
    if value.upper() in ('TRUE', 'FALSE'):
        return int(value.upper() == 'TRUE')
    if binary and re.fullmatch('[01]+', value):
        return int(value, 2)
    match = re.fullmatch(r"[0-9]+'([bBdDhH])([0-9a-fA-F_]+)", value)
    if match:
        return int(match[2].replace('_', ''), {'b': 2, 'd': 10, 'h': 16}[match[1].lower()])
    return int(value) if re.fullmatch('[0-9]+', value) else value


def check_parameters(data: dict[str, Any], path: Path) -> int:
    """Reject changed or absent explicit primitive parameters, including LUT INIT."""
    observed = {}
    for line in path.read_text().splitlines():
        cell, parameter, value = line.split('\t')
        observed[(cell.replace('\\\\', '\\'), parameter)] = parameter_value(value)
    checked = 0
    for name, cell in data['modules']['probe_top']['cells'].items():
        for parameter, value in cell['parameters'].items():
            expected = parameter_value(value, binary=True)
            actual = observed.get((name, parameter))
            if actual != expected:
                raise ValueError(f'{name}.{parameter}: expected {expected!r}, imported {actual!r}')
            checked += 1
    return checked


def check(mapped: Path, linked: Path, parameters: Path | None = None) -> dict[str, int]:
    """Reject altered cells, split/joined nets, constant mistakes and reversed bus bits."""
    data = normalize(json.loads(mapped.read_text()))
    want_cells, want_nets = expected_graph(data)
    got_cells, got_nets = linked_graph(linked, unused_dsp_pins(data))
    if want_cells != got_cells:
        missing = set(want_cells.items()) - set(got_cells.items())
        extra = set(got_cells.items()) - set(want_cells.items())
        raise ValueError(f'changed primitive population: missing={sorted(missing)[:5]}, extra={sorted(extra)[:5]}')
    if want_nets != got_nets:
        missing = [sorted(n) for n in want_nets - got_nets]
        extra = [sorted(n) for n in got_nets - want_nets]
        raise ValueError(f'changed pin graph: {len(missing)} missing, {len(extra)} extra nets; '
                         f'example expected={[n[:5] for n in missing[:1]]}, actual={[n[:5] for n in extra[:1]]}')
    result = {'cells': len(want_cells), 'nets': len(want_nets)}
    if parameters is not None:
        result['parameters'] = check_parameters(data, parameters)
    return result


def main() -> None:
    """Audit one imported netlist before it is eligible for timing characterization."""
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mapped', type=Path)
    parser.add_argument('linked', type=Path, nargs='?')
    parser.add_argument('parameters', type=Path, nargs='?')
    parser.add_argument('--list-parameters', action='store_true')
    args = parser.parse_args()
    if args.list_parameters:
        cells = normalize(json.loads(args.mapped.read_text()))['modules']['probe_top']['cells']
        print(' '.join(sorted({p for cell in cells.values() for p in cell['parameters']})))
    else:
        if args.linked is None:
            parser.error('linked graph required')
        print(json.dumps(check(args.mapped, args.linked, args.parameters)))


if __name__ == '__main__':
    main()
