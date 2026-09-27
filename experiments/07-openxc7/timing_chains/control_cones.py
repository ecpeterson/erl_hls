#!/usr/bin/env python3
"""Compare mapped control dependencies from result FIFO occupancy to stage enables."""
import argparse
from functools import lru_cache
import json
from pathlib import Path
import re

from architecture import sha


def analyze(path: Path) -> dict:
    """Count conservative primitive levels on named cones, excluding clocked feedback.

    Cell inputs are conservatively connected to every output. Counts are upper
    bounds on structural depth, not sensitizable paths or timing estimates.
    Reachable hard arithmetic is rejected rather than modeled as a LUT.
    """
    module = json.loads(path.read_text())['modules']['phi_decoder_profile_top']
    cells, names = module['cells'], module['netnames']
    drivers = {}
    for name, cell in cells.items():
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    if isinstance(bit, int):
                        if bit in drivers:
                            raise ValueError('multiple drivers')
                        drivers[bit] = name
    sources = {n: v['bits'][0] for n, v in names.items()
               if n.endswith('.materialized_fifo_fifo__executor_result_.slots')}
    endpoints = {n: v['bits'][0] for n, v in names.items() if len(v['bits']) == 1 and
                 ((n.endswith('.p0_stage_done') and 'SharedService' in n and 'SharedExecutor' not in n) or
                  (n.endswith('.stage_outputs_ready_0') and 'ReductionPlane' in n) or
                  re.fullmatch(r'scheduler_\d+_state.rd_addr', n))}
    if not sources or not endpoints:
        raise ValueError('missing named launch/endpoint controls')
    measurements = []
    for source, launch in sources.items():
        @lru_cache(None)
        def cone(bit: int) -> tuple[str, ...] | None:
            """Return the longest structural path from this launch bit, or no dependency."""
            if bit == launch:
                return ()
            if bit not in drivers:
                return None
            name = drivers[bit]
            cell = cells[name]
            kind = cell['type']
            if kind.startswith(('FD', 'RAMB')):
                return None
            inputs = [b for p, bits in cell['connections'].items()
                      if cell['port_directions'][p] == 'input' for b in bits if isinstance(b, int)]
            paths = [found for b in inputs if (found := cone(b)) is not None]
            if not paths:
                return None
            if not re.fullmatch(r'LUT[1-6]|MUXF[78]|INV|CARRY4', kind):
                raise ValueError(f'unsupported source-reachable primitive: {kind} {name}')
            return max(paths, key=len) + (name,)

        for endpoint, bit in endpoints.items():
            chain = cone(bit)
            if chain is not None:
                measurements.append({'source': source, 'endpoint': endpoint, 'levels': len(chain),
                    'chain': [{'cell': n, 'type': cells[n]['type']} for n in chain]})
    return {'netlist': str(path), 'sha256': sha(path), 'paths': measurements,
            'scope': 'conservative cell dependency depth; not a timing or sensitizability proof'}


def main() -> None:
    """Retain exact before/after paths and reject mismatched named dependencies."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    before, after = analyze(args.baseline), analyze(args.candidate)
    key = lambda p: (p['source'], p['endpoint'])
    old = {key(p): p for p in before['paths']}
    new = {key(p): p for p in after['paths']}
    if old.keys() != new.keys():
        raise ValueError('source/endpoint reachability changed; review before comparing depths')
    changes = [{'source': k[0], 'endpoint': k[1], 'before': old[k]['levels'], 'after': new[k]['levels']}
               for k in old]
    args.output.write_text(json.dumps({'baseline': before, 'candidate': after, 'changes': changes}, indent=2) + '\n')
    for row in changes:
        print(row['before'], '->', row['after'], row['endpoint'], flush=True)


if __name__ == '__main__':
    main()
