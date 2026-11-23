#!/usr/bin/env python3
"""Audit the small carry-head regression after native packing, without placement.

Checks the actual relocated LUT truth table exhaustively and rejects the
intrinsic O/CO output-mux clash. This is not general native equivalence or
complete placement/routing legality.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path


def integer(value: int | str) -> int:
    """Decode the packed integer parameters used by this finite fixture."""
    if isinstance(value,int):
        return value
    return int(value,2) if value and set(value) <= {'0','1'} else int(value)


def audit(packed: dict, mode: int) -> dict:
    """Require a real constant/dynamic head relocation and no residual carry output clash."""
    if mode not in (0,1,2) or len(packed['modules']) != 1:
        raise ValueError('expected one finite fixture module and MODE 0,1,2')
    cells = next(iter(packed['modules'].values()))['cells']
    users = defaultdict(list)
    constants = {}
    for name,cell in cells.items():
        for port,bits in cell['connections'].items():
            if cell['port_directions'][port] == 'input':
                for bit in bits:
                    users[bit].append((name,port))
            elif cell['type'] in ('PSEUDO_GND','PSEUDO_VCC'):
                constants.update({bit:int(cell['type'] == 'PSEUDO_VCC') for bit in bits})
    if 'target' not in cells or cells['target']['type'] != 'CARRY4':
        raise ValueError('retained target carry cell missing')
    target = cells['target']; ports = target['connections']
    initial = target['parameters'].get('PRECYINIT_CONST')
    if mode in (0,1):
        if initial is None or integer(initial) != mode or ports.get('CIN'):
            raise ValueError('constant carry-in was not explicitly folded into PRECYINIT')
        carry_bits = [bit for bit,value in constants.items() if value == mode]
    else:
        if initial is not None or len(ports.get('CIN',[])) != 1:
            raise ValueError('dynamic carry spine was replaced by a constant')
        carry_bits = ports['CIN']
        if carry_bits[0] in constants:
            raise ValueError('dynamic carry fixture became constant')
    sums = [(name,cell) for name,cell in cells.items() if '$sumLUT$' in name
            and cell['type'] == 'SLICE_LUTX' and cell['connections'].get('A1') == ports['S0']
            and cell['connections'].get('A2',[None])[0] in carry_bits]
    if len(sums) != 1:
        raise ValueError('head sum lacks one actual relocated S0 XOR carry-in LUT')
    name,lut = sums[0]
    if set(lut['connections']) != {'A1','A2','O6'}:
        raise ValueError('unexpected relocated sum LUT interface')
    truth = integer(lut['parameters']['INIT'])
    for select in (0,1):
        for carry in (0,1):
            if ((truth >> (select | carry << 1)) & 1) != (select ^ carry):
                raise ValueError('relocated native LUT does not implement the exhaustive sum identity')
    if not any(users[bit] for bit in lut['connections']['O6']):
        raise ValueError('relocated sum has no actual consumers')
    if any(users[bit] for bit in ports.get('O0',[])):
        raise ValueError('root O0 still has consumers after relocation')
    checked = 0
    for carry_name,cell in cells.items():
        if cell['type'] != 'CARRY4':
            continue
        for bit in range(4):
            out = [user for net in cell['connections'].get(f'O{bit}',[]) for user in users[net]]
            co = [user for net in cell['connections'].get(f'CO{bit}',[]) for user in users[net]
                  if not (cells[user[0]]['type'] == 'CARRY4' and user[1] == 'CIN')]
            if out and co:
                raise ValueError(f'intrinsic O/CO output-mux clash: {carry_name} bit{bit}')
            checked += 1
    return {'passed':True,'mode':mode,'head_sum_lut':name,'boolean_assignments':4,
        'carry_lanes_checked':checked,'physical_placement_checked':False,
        'scope':'Actual packed head LUT S xor C truth table and absence of simultaneous external O/CO claims in this no-FF fixture; not complete native legality/equivalence.'}


def main() -> None:
    """Read only one small saved packed regression; fail rather than read a full image."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packed',type=Path,required=True)
    parser.add_argument('--mode',type=int,choices=(0,1,2),required=True)
    args = parser.parse_args()
    if args.packed.stat().st_size > 4*1024*1024:
        raise ValueError('regression packed input exceeds 4 MiB')
    print(json.dumps(audit(json.loads(args.packed.read_text()),args.mode),indent=2))


if __name__ == '__main__':
    main()
