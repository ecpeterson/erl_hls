#!/usr/bin/env python3
"""Experimentally replicate LUT drivers without changing combinational functions."""
import argparse
from collections import defaultdict
import copy
import hashlib
import json
from pathlib import Path
import re
from typing import Any

# Conservatively exclude clock/reset uses, including C even on non-FF cells.
PROTECTED_PORTS = {'C', 'CLK', 'CK', 'WCLK', 'CLKA', 'CLKB', 'CLKARDCLK',
                   'CLKBWRCLK', 'CLR', 'PRE', 'R', 'S', 'RESET'}


def top_module(design: dict[str, Any]) -> dict[str, Any]:
    """Select the single flattened top while allowing unused primitive definitions."""
    tops = [module for module in design['modules'].values()
            if int(str(module.get('attributes', {}).get('top', '0')), 2) == 1]
    if len(tops) != 1:
        raise ValueError('expected one top module')
    for cell in tops[0]['cells'].values():
        definition = design['modules'].get(cell['type'], {})
        if definition.get('cells'):
            raise ValueError('expected a flattened design')
    return tops[0]


def replicate(original: dict[str, Any], limit: int) -> tuple[dict[str, Any], dict[str, Any]]:
    """Split original LUT consumers into groups; retain sequential cells and latency.

    One pass can increase upstream fan-out through replica inputs. Fixed-location
    LUTs and nets with clock/reset consumers are excluded. This is an opt-in
    placement experiment, not a synthesis default or timing guarantee.
    """
    if limit < 2:
        raise ValueError('consumer limit must be at least two')
    design = copy.deepcopy(original)
    module = top_module(design)
    reference = top_module(original)
    cells = module['cells']
    users: dict[int, list[tuple[str, str, int]]] = defaultdict(list)
    bit_ids = []
    for name, cell in reference['cells'].items():
        for port, bits in cell['connections'].items():
            bit_ids += [bit for bit in bits if type(bit) is int]
            if cell['port_directions'][port] == 'input':
                for index, bit in enumerate(bits):
                    if type(bit) is int:
                        users[bit].append((name, port, index))
    bit_ids += [bit for net in module['netnames'].values()
                for bit in net['bits'] if type(bit) is int]
    next_bit = max(bit_ids) + 1
    aliases, replicas = {}, {}
    for name, source in sorted(reference['cells'].items()):
        if not re.fullmatch('LUT[1-6]', source['type']):
            continue
        if any(key.upper() in {'LOC', 'BEL'} for key in source['attributes']):
            continue
        output, = source['connections']['O']
        targets = sorted(users[output])
        if len(targets) <= limit or any(port in PROTECTED_PORTS for _, port, _ in targets):
            continue
        for number, start in enumerate(range(limit, len(targets), limit), 1):
            clone_name = f'{name}$fanout_copy${number}'
            if clone_name in cells or clone_name in module['netnames']:
                raise ValueError('replica name collision')
            clone = copy.deepcopy(source)
            clone['connections']['O'] = [next_bit]
            clone['attributes']['keep'] = '00000000000000000000000000000001'
            cells[clone_name] = clone
            module['netnames'][clone_name] = {'hide_name': 1, 'bits': [next_bit], 'attributes': {}}
            aliases[next_bit] = output
            replicas[clone_name] = name
            for target, port, index in targets[start:start + limit]:
                cells[target]['connections'][port][index] = next_bit
            next_bit += 1
    verify(original, design, aliases, replicas)
    return design, {'consumer_group': limit, 'added_luts': len(replicas),
                    'aliases': aliases, 'replicas': replicas,
                    'verification': 'every original cell and replica equals its source after wire-alias substitution'}


def verify(original: dict[str, Any], design: dict[str, Any], aliases: dict[int, int],
           replicas: dict[str, str]) -> None:
    """Check the full substitution, not just cell counts or chosen consumers.

    Identical LUTs on identical logical inputs establish each new wire alias;
    substituting those aliases recovers the original synchronous circuit.
    Original port/parameter/attribute changes or unexplained cells fail.
    """
    restored = copy.deepcopy(design)
    module = top_module(restored)
    reference = top_module(original)
    for cell in module['cells'].values():
        for port, bits in cell['connections'].items():
            cell['connections'][port] = [aliases.get(bit, bit) for bit in bits]
    for clone, source in replicas.items():
        cell = module['cells'].pop(clone)
        cell['attributes'] = dict(cell['attributes'])
        if 'keep' in reference['cells'][source]['attributes']:
            cell['attributes']['keep'] = reference['cells'][source]['attributes']['keep']
        else:
            cell['attributes'].pop('keep')
        if cell != reference['cells'][source]:
            raise ValueError(f'replica function differs: {clone}')
        module['netnames'].pop(clone)
    if restored != original:
        raise ValueError('transformation changed more than equivalent LUT drivers')


def main() -> None:
    """Write a separate experimental netlist with an auditable substitution record."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--limit', type=int, default=64)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output must be new')
    raw = args.netlist.read_bytes()
    result, record = replicate(json.loads(raw), args.limit)
    args.output.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    record.update({'input_sha256': hashlib.sha256(raw).hexdigest(),
                   'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
                   'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    args.output.with_suffix('.replication.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f'Added {record["added_luts"]} equivalent LUT drivers; full substitution verified')


if __name__ == '__main__':
    main()
