#!/usr/bin/env python3
"""Validate retained board inspection evidence without rerunning or changing a qualified witness.

The same reader accepts attached RTL and physical-host run directories. It reads
native ownership metadata and existing ETF observations only. It neither starts
a host connection nor infers physical timing, DMA drain or image identity from
successful replies. Application-oracle validation remains a separate report.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any


READ = '''[Bundle,Stage]=init:get_plain_arguments(),
{ok,DB}=file:read_file(filename:join(Bundle,"interface.etf")),
#{domains:=Domains}=binary_to_term(DB),
Files=filelib:wildcard(filename:join(Stage,"board*-bootstrap.etf"))++
      filelib:wildcard(filename:join(Stage,"board*-inspection-*.etf")),
Observations=[begin {ok,B}=file:read_file(P),Raw=binary_to_term(B),
Value=case Raw of #{values:=Vs}->Raw#{values=>[V#{value=>binary_to_list(maps:get(value,V))}||V<-Vs]};_->Raw end,
#{file=>unicode:characters_to_binary(filename:basename(P)),value=>Value} end||P<-Files],
io:put_chars(json:encode(#{domains=>[#{index=>I,actors=>As}||#{index:=I,actors:=As}<-Domains],
                         observations=>Observations})),halt().'''


def require(condition: bool, message: str) -> None:
    """Reject incomplete or contradictory retained evidence even under optimized Python execution."""
    if not condition:
        raise ValueError(message)


def unsigned(value: object, width: int, *, nonzero: bool = False) -> bool:
    """Recognize an exact native integer identity, excluding booleans and wrapped values."""
    return type(value) is int and int(nonzero) <= value < (1 << width)


def board_status(value: dict[str, Any], index: int, session: int, incarnation: int, attached: bool) -> None:
    """Check board, parser lifetime and healthy carrier scope on one canonical retained status."""
    require(value.get('kind') == 'board' and value.get('abi') == 1 and value.get('role') == index + 1
            and value.get('status') == 'ok', 'wrong board status scope')
    require(value.get('domain_session') == value.get('endpoint_session') == session
            and value.get('incarnation') == incarnation, 'wrong board session/incarnation')
    require(unsigned(value.get('request'), 32, nonzero=True), 'invalid status request identity')
    health = value.get('health', {})
    require(health.get('domain_attached') is attached and health.get('endpoint_attached') is attached
            and health.get('carrier_armed') is True and health.get('carrier_fault') == 0
            and all(health.get(field) is False for field in
                    ('domain_wire_fault', 'endpoint_wire_fault', 'router_fault'))
            and unsigned(health.get('phase_code'), 3), 'unhealthy or unattached board observation')


def validate(profile: str, domains: list[dict[str, Any]], result: dict[str, Any],
             observations: list[dict[str, Any]]) -> dict[str, Any]:
    """Require both selected boards and both recorded incarnations, with exactly their native actor inventories.

    Process inspection requires every reply to succeed and at least one nonzero
    snapshot per board/lifetime. Individual zero snapshots remain legal. The none
    profile permits unsupported replies only with their canonical zero snapshot.
    Values are passive evidence; no expected actor-state model is invented here.
    """
    require(profile in ('process', 'none'), 'unsupported selected inspection profile')
    require(len(domains) == 2 and {row['index'] for row in domains} == {0, 1}, 'expected two source domains')
    actors = {row['index']: row['actors'] for row in domains}
    require(all(isinstance(ids, list) and ids and len(ids) == len(set(ids))
                and all(unsigned(actor, 32) for actor in ids) for ids in actors.values()), 'invalid native actor inventory')
    require(not set(actors[0]) & set(actors[1]), 'overlapping source actor ownership')
    lifetimes = result.get('incarnations', [])
    require(len(lifetimes) == 2, 'expected two source lifetimes')
    epochs = [row.get('domain_incarnations') for row in lifetimes]
    require(all(isinstance(row, list) and len(row) == 2 and all(unsigned(epoch, 64, nonzero=True) for epoch in row)
                for row in epochs), 'invalid recorded domain incarnations')
    require(all(epochs[1][index] > epochs[0][index] for index in (0, 1)), 'replacement incarnation did not advance')
    by_name = {}
    for row in observations:
        file = row.get('file')
        require(isinstance(file, str) and file not in by_name and
                re.fullmatch(r'board[01]-(?:bootstrap|inspection-[1-9][0-9]*)\.etf', file) is not None,
                'duplicate or unknown observation file')
        by_name[file] = row['value']
    expected = {f'board{index}-bootstrap.etf' for index in (0, 1)} | {
        f'board{index}-inspection-{epochs[lifetime][index]}.etf' for index in (0, 1) for lifetime in (0, 1)}
    require(by_name.keys() == expected, 'missing, extra or wrong-lifetime observation records')
    records = []
    for index in (0, 1):
        bootstrap = by_name[f'board{index}-bootstrap.etf']
        cold, established = bootstrap['cold'], bootstrap['established']
        session = established.get('domain_session')
        require(unsigned(session, 64, nonzero=True), 'invalid established session')
        board_status(cold, index, 0, 0, False)
        board_status(established, index, session, 0, True)
        seen_requests = {cold['request'], established['request']}
        require(len(seen_requests) == 2, 'reused bootstrap request identity')
        for lifetime in (0, 1):
            epoch = epochs[lifetime][index]
            observation = by_name[f'board{index}-inspection-{epoch}.etf']
            status, values = observation['status'], observation['values']
            board_status(status, index, session, epoch, True)
            require(isinstance(values, list) and len(values) == len(actors[index]), 'missing actor inspection replies')
            replies = {}
            nonzero, unsupported = 0, 0
            for value in values:
                actor, code, data = value.get('actor'), value.get('status'), value.get('value')
                require(unsigned(actor, 32) and actor in actors[index] and actor not in replies,
                        'wrong or repeated actor inspection scope')
                require(value.get('kind') == 'inspection' and value.get('session') == session
                        and value.get('incarnation') == epoch, 'wrong inspection session/incarnation')
                require(unsigned(value.get('request'), 32, nonzero=True) and value['request'] not in seen_requests,
                        'invalid or reused inspection request identity')
                seen_requests.add(value['request'])
                require(isinstance(data, list) and len(data) == 16 and all(unsigned(byte, 8) for byte in data),
                        'invalid retained snapshot bytes')
                require(code == 'ok' or (profile == 'none' and code == 'unsupported'),
                        'inspection response does not satisfy selected profile')
                require(code != 'unsupported' or not any(data), 'unsupported response carries snapshot data')
                nonzero += int(any(data))
                unsupported += int(code == 'unsupported')
                replies[actor] = code
            require(status['request'] not in seen_requests, 'reused inspection status identity')
            seen_requests.add(status['request'])
            require(profile != 'process' or nonzero > 0, 'process inspection has no meaningful retained snapshot')
            records.append({'board_index': index, 'physical_role': index + 1, 'lifetime': lifetime,
                            'session': session, 'incarnation': epoch, 'actors': sorted(replies),
                            'reply_count': len(values), 'unsupported': unsupported, 'nonzero_snapshots': nonzero})
    return {'schema': 'hls_domain_board_observations_v1', 'passed': True, 'inspection': profile,
            'boards': 2, 'lifetimes': 2, 'records': records,
            'evidence': 'Finite retained bootstrap and incarnation-scoped passive inspection observations.',
            'limits': 'No application-oracle, deployed image identity, physical timing, CDC, DMA drain or complete actor-state proof.'}


def digest(path: Path) -> str:
    """Bind one small retained report or metadata file by its exact bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    """Assess existing ETF observations from either a simulated or physical run, writing one fresh report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=lambda value: Path(value).resolve())
    parser.add_argument('--bundle', required=True, type=lambda value: Path(value).resolve())
    parser.add_argument('--output', required=True, type=lambda value: Path(value).resolve())
    args = parser.parse_args()
    observation_paths = sorted([*args.stage.glob('board*-bootstrap.etf'), *args.stage.glob('board*-inspection-*.etf')])
    paths = [args.bundle / 'fixture.json', args.bundle / 'interface.etf', args.stage / 'result.json',
             Path(__file__).resolve(), *observation_paths]
    hashes = {path: digest(path) for path in paths}
    fixture, result = json.loads(paths[0].read_text()), json.loads((args.stage / 'result.json').read_text())
    projection = subprocess.run(['erl', '+S', '2:2', '-noshell', '-eval', READ, '-extra', str(args.bundle), str(args.stage)],
                                check=True, capture_output=True, text=True, timeout=30)
    retained = json.loads(projection.stdout)
    require({row['file'] for row in retained['observations']} == {path.name for path in observation_paths},
            'observation inventory changed during read')
    report = validate(fixture['inspection'], retained['domains'], result, retained['observations'])
    require(all(digest(path) == expected for path, expected in hashes.items()), 'retained input changed during assessment')
    report['inputs'] = {str(path): expected for path, expected in hashes.items()}
    with args.output.open('x') as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write('\n')
    print(json.dumps({'passed': True, 'inspection': report['inspection'], 'boards': 2, 'lifetimes': 2,
                      'inspection_replies': sum(row['reply_count'] for row in report['records'])}))


if __name__ == '__main__':
    main()
