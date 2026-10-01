#!/usr/bin/env python3
"""Compare host adapter overhead with an immediate in-memory broker double.

Run rebar3 eunit first. Each sample starts a fresh VM; warmup/startup are excluded.
This does not measure physical broker I/O, FPGA throughput, or total allocations.
"""
import argparse
import json
from pathlib import Path
from backend_paths import erlang_paths
import platform
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(output, repeats):
    output.mkdir(parents=True, exist_ok=False)
    samples = []
    modes = ['proxy', 'tcp', 'local']
    for repeat in range(repeats):
        for mode in modes[repeat % 3:] + modes[:repeat % 3]:
            carrier = 'hls_local' if mode == 'local' else 'inet_tcp'
            command = ['erl', '+S', '4:4', '-noshell', '-proto_dist', carrier, '-pa',
                       *map(str, erlang_paths()), '-eval',
                       f'ok = hls_carrier_bench:run({mode}), halt().']
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=60)
            (output / f'{repeat}-{mode}.log').write_text(result.stdout)
            result.check_returncode()
            data = json.loads(next(line[6:] for line in result.stdout.splitlines() if line.startswith('BENCH ')))
            samples.append(dict(data, repeat=repeat, command=command))
            print(mode, repeat, round(data['latency_mean_us'], 2),
                  round(data['pipeline_calls_per_second']), flush=True)
    summary = {}
    for mode in modes:
        selected = [s for s in samples if s['mode'] == mode]
        summary[mode] = {key: {'mean': statistics.mean(values), 'variance': statistics.pvariance(values),
                              'min': min(values), 'max': max(values)}
                         for key in selected[0] if isinstance(selected[0][key], (float, int))
                         for values in [[s[key] for s in selected]]}
    report = {'platform': platform.platform(), 'samples': samples, 'summary': summary}
    (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repeats', type=int, default=5)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error('--repeats must be positive')
    run(args.output.resolve(), args.repeats)
