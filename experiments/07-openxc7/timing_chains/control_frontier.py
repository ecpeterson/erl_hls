#!/usr/bin/env python3
"""Follow selected control launches to every reachable storage or unknown boundary.

This structural screen includes newly introduced endpoints. It conservatively
connects every supported primitive input to every output; levels are neither
sensitizable path lengths nor timing estimates. Unknown primitives stop traversal
and remain explicit in the report instead of masquerading as registers.
"""
import argparse
from collections import defaultdict, deque
from functools import lru_cache
import json
from pathlib import Path
import re

from architecture import sha

COMBINATIONAL = re.compile(r'LUT[1-6]|MUXF[78]|INV|CARRY4|IBUF|OBUF')
REGISTERS = re.compile(r'FD(?:RE|SE|CE|PE)')
MEMORIES = re.compile(r'RAMB(?:18|36)E1')
DEFAULT_LAUNCH = r'\.materialized_fifo_fifo__executor_result_\.slots$'


def category(kind: str) -> str:
    """Distinguish traversable logic, known storage, and uncovered boundaries."""
    if COMBINATIONAL.fullmatch(kind):
        return 'logic'
    if REGISTERS.fullmatch(kind):
        return 'register'
    if MEMORIES.fullmatch(kind):
        return 'ram'
    return 'unsupported'


def analyze(module: dict, launch_pattern: str, limit: int = 10) -> dict:
    """Inventory every reachable endpoint and retain the deepest unique input nets.

    Multiple storage pins sharing a control net form one row, with the complete
    pin count and a bounded sample of consumers. Only displayed paths are capped;
    endpoint and maximum-depth summaries account for all reachable inputs.
    """
    cells, names = module['cells'], module['netnames']
    aliases, users, drivers = defaultdict(list), defaultdict(list), {}
    for name, signal in names.items():
        for index, bit in enumerate(signal['bits']):
            if isinstance(bit, int):
                aliases[bit].append(name if len(signal['bits']) == 1 else f'{name}[{index}]')
    for name, cell in cells.items():
        for port, bits in cell['connections'].items():
            for index, bit in enumerate(bits):
                if not isinstance(bit, int):
                    continue
                if cell['port_directions'][port] == 'input':
                    users[bit].append((name, port, index))
                else:
                    if bit in drivers and drivers[bit] != name:
                        raise ValueError('multiple drivers')
                    drivers[bit] = name
    launches = {n: v['bits'][0] for n, v in names.items()
                if re.search(launch_pattern, n) and len(v['bits']) == 1 and isinstance(v['bits'][0], int)}
    if not launches:
        raise ValueError('no scalar launch signals matched')
    reports = []
    for source, launch in sorted(launches.items()):
        reachable, queue, endpoints = {launch}, deque([launch]), defaultdict(list)
        while queue:
            bit = queue.popleft()
            for name, port, index in users[bit]:
                cell = cells[name]
                kind = category(cell['type'])
                if kind != 'logic':
                    endpoints[kind, port, bit].append({'cell': name, 'type': cell['type'], 'port': port, 'index': index})
                    continue
                for output, bits in cell['connections'].items():
                    if cell['port_directions'][output] == 'output':
                        for out in bits:
                            if isinstance(out, int) and out not in reachable:
                                reachable.add(out)
                                queue.append(out)
        for port, signal in module.get('ports', {}).items():
            if signal['direction'] == 'output':
                for index, bit in enumerate(signal['bits']):
                    if bit in reachable:
                        endpoints['external', port, bit].append(
                            {'cell': '$top', 'type': 'top_output', 'port': port, 'index': index})
        visiting = set()

        @lru_cache(None)
        def chain(bit: int) -> tuple[str, ...]:
            """Recover the longest supported dependency; reject combinational loops."""
            if bit == launch:
                return ()
            if bit in visiting:
                raise ValueError('combinational cycle in launch cone')
            name = drivers[bit]
            cell = cells[name]
            if category(cell['type']) != 'logic':
                raise ValueError('reached an output across an untraversed boundary')
            visiting.add(bit)
            paths = [chain(b) for port, bits in cell['connections'].items()
                     if cell['port_directions'][port] == 'input' for b in bits if b in reachable]
            visiting.remove(bit)
            return max(paths, key=len) + (name,)

        # A loop is invalid even if it never reaches a storage or output pin.
        for bit in reachable:
            chain(bit)
        rows = []
        for (kind, port, bit), pins in endpoints.items():
            path = chain(bit)
            landmarks = []
            for index, name in enumerate(path):
                for output, bits in cells[name]['connections'].items():
                    if cells[name]['port_directions'][output] == 'output':
                        for out in bits:
                            for alias in aliases[out]:
                                if re.fullmatch(r'scheduler_\d+_state\.rd_addr(?:\[\d+\])?', alias):
                                    landmarks.append({'after_levels': index + 1, 'signal': alias})
            rows.append({'kind': kind, 'port': port, 'bit': bit, 'levels': len(path),
                         'consumer_count': len(pins), 'consumers': pins[:4],
                         'aliases': sorted(aliases[bit])[:4], 'landmarks': landmarks,
                         'chain': [{'cell': n, 'type': cells[n]['type']} for n in path]})
        groups = defaultdict(list)
        for row in rows:
            groups[row['kind'] + '/' + row['port']].append(row)
        reports.append({'source': source, 'groups': {
            key: {'input_nets': len(values), 'pins': sum(v['consumer_count'] for v in values),
                  'max_levels': max(v['levels'] for v in values),
                  'address_landmark_nets': sum(bool(v['landmarks']) for v in values),
                  'max_levels_without_address_landmark': max(
                      (v['levels'] for v in values if not v['landmarks']), default=None),
                  'deepest': sorted(values, key=lambda r: (-r['levels'], -r['consumer_count'], r['bit']))[:limit]}
            for key, values in sorted(groups.items())}})
    return {'launch_pattern': launch_pattern, 'retained_per_group': limit, 'sources': reports,
            'scope': 'conservative connectivity through listed primitives; unknown boundaries retained, no delay or sensitizability claim'}


def main() -> None:
    """Require explicit input/output files and preserve netlist identity in the report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--top', default='phi_decoder_profile_top')
    parser.add_argument('--launch', default=DEFAULT_LAUNCH)
    parser.add_argument('--limit', type=int, default=5)
    args = parser.parse_args()
    if args.limit < 1:
        parser.error('--limit must be positive')
    module = json.loads(args.netlist.read_text())['modules'][args.top]
    report = analyze(module, args.launch, args.limit)
    report.update(netlist=str(args.netlist), sha256=sha(args.netlist), top=args.top)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    for source in report['sources']:
        print(source['source'])
        for name, group in source['groups'].items():
            print(f"  {name}: {group['max_levels']} levels; {group['input_nets']} nets / {group['pins']} pins")


if __name__ == '__main__':
    main()
