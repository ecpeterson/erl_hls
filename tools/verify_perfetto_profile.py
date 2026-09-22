#!/usr/bin/env python3
"""Import an export with the official Trace Processor and compare every slice and causal edge."""
import argparse
import csv
import io
import json
from pathlib import Path
from collections import defaultdict
import subprocess

from hls_profile import counter_name


def verify(processor: Path, profile: dict, trace: Path) -> dict:
    """Require exact event/flow identities and all timestamped counter samples after native import."""
    query = """
    SELECT 'slice' AS kind, hex(EXTRACT_ARG(arg_set_id, 'args.event_id')) AS source,
           hex(EXTRACT_ARG(arg_set_id, 'args.profile_dependencies')) AS target, ts, dur FROM slice
    UNION ALL
    SELECT 'flow', hex(EXTRACT_ARG(s.arg_set_id, 'args.event_id')),
           hex(EXTRACT_ARG(t.arg_set_id, 'args.event_id')), 0, 0
    FROM flow f JOIN slice s ON s.id=f.slice_out JOIN slice t ON t.id=f.slice_in
    UNION ALL
    SELECT 'counter', hex(t.name), '', c.ts, printf('%!.17g', c.value) FROM counter c JOIN track t ON t.id=c.track_id;
    """
    result = subprocess.run([str(processor), str(trace), '-Q', query], check=True, capture_output=True, text=True)
    # The CLI's CSV printer does not escape embedded quotes and rounds native float columns.
    # Hex-encoded text and SQL-formatted round-trip floats avoid losing evidence in that boundary.
    rows = list(csv.DictReader(io.StringIO(result.stdout)))
    for row in rows:
        for field in ('source', 'target'):
            row[field] = bytes.fromhex(row[field]).decode('utf-8')
    actual = [(r['source'], int(r['ts']), int(r['dur'])) for r in rows if r['kind'] == 'slice']
    expected = [(e['id'], e['ts'], e['dur']) for e in profile['events']]
    if sorted(actual) != sorted(expected):
        raise ValueError('Perfetto import changed slice IDs, times or durations')
    expected_evidence = defaultdict(list)
    for edge in profile['edges']:
        expected_evidence[edge['target']].append(edge)
    for row in rows:
        if row['kind'] == 'slice' and json.loads(row['target']) != expected_evidence[row['source']]:
            raise ValueError('Perfetto import changed dependency evidence')
    actual_edges = [(r['source'], r['target']) for r in rows if r['kind'] == 'flow']
    expected_edges = [(e['source'], e['target']) for e in profile['edges']]
    if sorted(actual_edges) != sorted(expected_edges):
        raise ValueError('Perfetto import changed dependency endpoints')
    actual_counters = [(r['source'], int(r['ts']), float(r['dur'])) for r in rows if r['kind'] == 'counter']
    expected_counters = [(counter_name(c)+' value', c['ts'], c['value']) for c in profile.get('counters', [])]
    if sorted(actual_counters) != sorted(expected_counters):
        raise ValueError('Perfetto import changed counter identity, timestamps or values')
    return {'slices': len(actual), 'flows': len(actual_edges), 'counters': len(actual_counters)}


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
