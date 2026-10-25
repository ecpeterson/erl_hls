#!/usr/bin/env python3
"""Measure packed production bridges with opaque traffic and independent credits."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root
from link_service_witness import compile_link, faults, simulate



def service_cases(quick: bool = False, regression: bool = False) -> list[tuple[int, int]]:
    """Select load/latency probes; callers always add stalled/reset and fault checks."""
    if quick:
        return [(8, 2)]
    if regression:
        return [(1, 0), (1, 64), (8, 0), (8, 64), (2, 2), (4, 16)]
    return [(active, delay) for active in (1, 2, 4, 8) for delay in (0, 2, 16, 64)]


def main() -> None:
    """Sweep small bridge builds before committing to complete-mesh recompilation."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('xls', type=Path)
    p.add_argument('--erl-hls', type=Path, help="Compiler override; defaults to the built test profile.")
    p.add_argument('--stage', type=Path, required=True)
    p.add_argument('--configs', nargs='+', default=['1:1', '1:4', '2:4', '4:4', '4:8'])
    sweep = p.add_mutually_exclusive_group()
    sweep.add_argument('--quick', action='store_true', help='run one saturated control plus stalled/reset isolation')
    sweep.add_argument('--regression', action='store_true',
                       help='cover load/latency boundaries and interior points without the full performance grid')
    p.add_argument('--compact', action='store_true', help='exercise compact lengths and metadata extensions, including header-only traffic')
    a = p.parse_args()
    a.erl_hls = compiler_root("test", a.erl_hls)
    configs = [tuple(map(int, c.split(':'))) for c in a.configs]
    if any(w not in (1, 2, 4) or c not in (1, 2, 4, 8, 16) for w, c in configs):
        p.error('configurations are WORDS:CREDITS with WORDS=1/2/4 and CREDITS=1/2/4/8/16')
    a.stage.mkdir(parents=True, exist_ok=True)
    for words, credits in configs:
        stage = a.stage/(f'words-{words}-credits-{credits}' + ('-compact' if a.compact else ''))
        record = compile_link(a.xls.resolve(), a.erl_hls.resolve(), stage.resolve(), words, credits, a.compact)
        cases = service_cases(a.quick, a.regression)
        rows = [simulate(stage, words, credits, active, delay, pattern=int(a.compact)) for active, delay in cases]
        rows.append(simulate(stage, words, credits, 8, 2, stalls=True, block=True, restart=True, pattern=int(a.compact)))
        if a.compact:
            rows += [simulate(stage, words, credits, active, 2, pattern=2) for active in (1, 8)]
            rows.append(simulate(stage, words, credits, 8, 2, pattern=0))
        record['results'] = rows
        record['faults'] = faults(stage, words, credits, a.compact)
        (stage/'service.json').write_text(json.dumps(record, indent=2)+'\n')


if __name__ == '__main__':
    main()
