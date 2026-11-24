#!/usr/bin/env python3
"""Generate paired surface-code noise samples and check BEAM state after every sheet."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import random
import subprocess
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from backend_paths import application_directory, erlang_paths

import generate
import generate_surface as surface


def faults(seed: int, probability: float, sheets: int, data_sites: int,
           measurement_sites: int) -> list[tuple[int, int]]:
    """Use the same draws at every probability; smaller rates select subsets of faults."""
    rng = random.Random(seed)
    return [(sum((rng.random() < probability) << bit for bit in range(data_sites)),
             sum((rng.random() < probability) << bit for bit in range(measurement_sites)))
            for _ in range(sheets)]


def digest(value: object) -> str:
    """Hash a canonical JSON value for retained state and input identities."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def prepare_beam(stage: Path) -> dict:
    """Compile current window sources and identify every loaded HLS dependency binary."""
    source = generate.ROOT / 'workloads/hls_snowflake/src'
    includes = source.parent / 'include'
    sources = [source / name for name in ('snowflake_node.erl', 'snowflake_geometry.erl', 'snowflake_window.erl')]
    dependencies = erlang_paths('default', generate.ROOT)
    target = stage / 'ebin'
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(['erlc', '+debug_info', '-Werror', '-I', str(includes),
                    *[item for path in dependencies for item in ('-pa', str(path))], '-o', str(target),
                    *map(str, sources)], cwd=generate.ROOT, check=True, timeout=120)
    provenance = {'source_sha256': {str(path.relative_to(generate.ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in [*sources, includes / 'snowflake_node.hrl', includes / 'snowflake_node_impl.hrl']},
                  'beam_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(target.glob('*.beam'))},
                  'hls_dependency_beam_sha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                                for dependency in dependencies for path in sorted(dependency.glob('*.beam'))}}
    (stage / 'beam-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    return provenance


def beam_check(case: dict, graph: dict, stage: Path) -> None:
    """Compare every sheet's full state, phase activity, transfers and ordered retirements."""
    source, output = stage / 'beam-input.json', stage / 'beam-output.json'
    source.write_text(json.dumps(case, separators=(',', ':')))
    expression = (
        f'{{ok,B}}=file:read_file({json.dumps(str(source))}),C=json:decode(B),'
        'D=maps:get(<<"distance">>,C),H=maps:get(<<"window_height">>,C),'
        'Phase=fun(P)->#{nodes:=Ns,edges:=Es}=maps:get(state,P),'
        '#{phase=>maps:get(phase,P),active_nodes=>length([N||N=#{active:=true}<-Ns]),'
        'busy_nodes=>length([N||N=#{busy:=true}<-Ns]),reset_nodes=>length([N||N=#{cid:= -1}<-Ns]),'
        'transfers=>[[maps:get(coordinate,lists:nth(A,Ns)),maps:get(coordinate,lists:nth(Bb,Ns)),'
        'maps:get(endpoints,lists:nth(E,Es))]||{A,Bb,E}<-maps:get(transfers,P,[])]} end,'
        'F=fun(E,S)->{N,R}=snowflake_window:decode(maps:get(<<"input_mask">>,E),S),'
        'T=[Phase(P)||P<-maps:get(trace,R)],'
        '{R#{trace:=T},N} end,'
        '{Reports,_}=lists:mapfoldl(F,snowflake_window:new(surface,D,H),maps:get(<<"sheets">>,C)),'
        f'ok=file:write_file({json.dumps(str(output))},json:encode(Reports)),halt().')
    subprocess.run(['erl', '+S', '2:2', '-noshell', '-pa',
                    *map(str, erlang_paths('default', generate.ROOT)), str(stage / 'ebin'), '-eval', expression],
                   cwd=generate.ROOT, check=True, timeout=600)
    reports = json.loads(output.read_text())
    node_order = [tuple(node['coordinate']) for node in graph['nodes']]
    edge_order = [tuple(map(tuple, edge)) for edge in graph['edges']]
    node_index, edge_index = {v: i for i, v in enumerate(node_order)}, {v: i for i, v in enumerate(edge_order)}
    for expected, actual in zip(case['sheets'], reports, strict=True):
        label = (case['name'], expected['index'])
        for key in ('input_mask', 'retired_sheet', 'retired_spatial_mask', 'retired_temporal_mask', 'phase_counts'):
            assert expected[key] == actual[key], (label, key)
        assert expected['reference_runtime_all'] + 1 == actual['ticks'], (label, 'ticks')
        nodes = {tuple(node['coordinate']): node for node in actual['state']['nodes']}
        edges = {tuple(map(tuple, edge['endpoints'])): edge for edge in actual['state']['edges']}
        state = {'nodes': [[int(nodes[point][field]) for field in generate.NODE_FIELDS] for point in node_order],
                 'edges': [[int(edges[edge][field]) for field in ('growth', 'correction')] for edge in edge_order]}
        assert expected['state'] == state, (label, 'full state')
        for reference_phase, phase in zip(expected['phases'], actual['trace'], strict=True):
            assert reference_phase['phase'] == phase['phase'], (label, 'phase')
            for key in ('active_nodes', 'busy_nodes', 'reset_nodes'):
                assert reference_phase[key] == phase[key], (label, key)
            transfers = [[node_index[tuple(a)], node_index[tuple(b)], edge_index[tuple(map(tuple, e))]]
                         for a, b, e in phase.get('transfers', [])]
            assert sorted(reference_phase['transfers']) == sorted(transfers), (label, 'transfers')
    source.unlink()
    output.unlink()


def main() -> None:
    """Retain compact, reproducible cohorts after independent reference and BEAM checks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=generate.CACHE / 'localuf')
    parser.add_argument('--output', type=Path, default=generate.ROOT / '_build/snowflake-noise')
    parser.add_argument('--sheets', type=int, default=512)
    parser.add_argument('--seeds', type=int, default=3)
    parser.add_argument('--distance', type=int, action='append', choices=(3, 5))
    parser.add_argument('--probability', type=float, action='append')
    args = parser.parse_args()
    if args.sheets < 96 or args.seeds < 1:
        parser.error('at least 96 sheets and one seed are required')
    probabilities = args.probability or [0.025, 0.005, 0.002]
    if any(not 0 <= probability <= 1 for probability in probabilities):
        parser.error('probabilities must lie in [0,1]')
    _, snowflake = generate.load_reference(args.reference)
    from localuf import Surface
    args.output.mkdir(parents=True, exist_ok=True)
    beam_provenance = prepare_beam(args.output)
    baseline = json.loads((generate.ROOT / 'workloads/hls_snowflake/priv/fixtures/surface-named.json').read_text())
    for distance in args.distance or (3, 5):
        graph = surface.geometry(surface.make_decoder(distance, Surface, snowflake))
        data_sites, measurement_sites = len(graph['spatial_edges']), len(graph['syndrome_coordinates'])
        for offset in range(args.seeds):
            seed = 0x53555246 + distance + offset
            for probability in probabilities:
                name = f'd{distance}-p{probability:g}-seed{offset}'
                path = args.output / (name + '.json')
                begin = time.monotonic()
                samples = faults(seed, probability, args.sheets, data_sites, measurement_sites)
                case = surface.run_case(name, distance, samples, Surface, snowflake)
                if offset == 0 and probability == 0.025:
                    old = next(case for case in baseline['cases'] if case['name'] == f'surface_d{distance}_continuous')
                    assert case['sheets'][:96] == old['sheets'][:96], 'Original cohort changed'
                beam_check(case, graph, args.output)
                state_digest = digest([sheet['state'] for sheet in case['sheets']])
                for sheet in case['sheets']:
                    sheet.pop('state')
                document = {'schema': 'snowflake-paired-noise-v1', 'reference_revision': generate.REVISION,
                            'noise': {'model': 'phenomenological, one CSS sector', 'data_probability': probability,
                                      'measurement_probability': probability, 'seed': seed, 'seed_offset': offset,
                                      'data_sites': data_sites, 'measurement_sites': measurement_sites,
                                      'pairing': 'Identical PRNG draws and site ordering at every probability'},
                            'checks': {'sheets': len(case['sheets']), 'full_state_sha256': state_digest,
                                       'beam_provenance_sha256': digest(beam_provenance),
                                       'reference_untouched_control': True, 'beam_full_state': True,
                                       'beam_phase_activity_and_transfers': True, 'beam_retirements': True},
                            'source_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in
                                             (Path(__file__), Path(surface.__file__), Path(generate.__file__))},
                            'case': case}
                path.write_text(json.dumps(document, separators=(',', ':')) + '\n')
                cohort = case['sheets'][:args.sheets]
                print(json.dumps({'case': name, 'seconds': round(time.monotonic() - begin, 2),
                                  'faults': sum(sheet['data_fault_mask'].bit_count() + sheet['measurement_fault_mask'].bit_count() for sheet in cohort),
                                  'phases': sum(sheet['reference_runtime_all'] + 1 for sheet in cohort)}), flush=True)


if __name__ == '__main__':
    main()
