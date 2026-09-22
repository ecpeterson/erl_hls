#!/usr/bin/env python3
"""Import an export with the official Trace Processor and compare every slice and causal edge."""
import argparse
import csv
import io
import json
from pathlib import Path
import subprocess


def verify(processor: Path, profile: dict, trace: Path) -> dict:
    """Require exact nanosecond times, IDs and graph endpoints after native Perfetto import."""
    query = """
    SELECT 'slice' AS kind, EXTRACT_ARG(arg_set_id, 'args.event_id') AS source,
           '' AS target, ts, dur FROM slice
    UNION ALL
    SELECT 'flow', EXTRACT_ARG(s.arg_set_id, 'args.event_id'),
           EXTRACT_ARG(t.arg_set_id, 'args.event_id'), 0, 0
    FROM flow f JOIN slice s ON s.id=f.slice_out JOIN slice t ON t.id=f.slice_in;
    """
    result = subprocess.run([str(processor), str(trace), '-Q', query], check=True, capture_output=True, text=True)
    rows = list(csv.DictReader(io.StringIO(result.stdout)))
    actual = [(r['source'], int(r['ts']), int(r['dur'])) for r in rows if r['kind'] == 'slice']
    expected = [(e['id'], e['ts'], e['dur']) for e in profile['events']]
    if sorted(actual) != sorted(expected):
        raise ValueError('Perfetto import changed slice IDs, times or durations')
    actual_edges = [(r['source'], r['target']) for r in rows if r['kind'] == 'flow']
    expected_edges = [(e['source'], e['target']) for e in profile['edges']]
    if sorted(actual_edges) != sorted(expected_edges):
        raise ValueError('Perfetto import changed dependency endpoints')
    return {'slices': len(actual), 'flows': len(actual_edges)}


def main() -> None:
    """Validate an existing export without regenerating it."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('processor', type=Path)
    parser.add_argument('profile', type=Path)
    parser.add_argument('trace', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.processor, json.loads(args.profile.read_text()), args.trace)))


if __name__ == '__main__':
    main()
