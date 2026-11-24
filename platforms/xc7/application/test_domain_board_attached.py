#!/usr/bin/env python3
"""Exercise frozen process-inspection board compositions through the actual attached host.

No source lowering, XLS, physical image build or board access occurs here. The
caller owns serial footprint guarding. Compilation and the finite witness are
separate commands so a host-side failure need not rebuild successful RTL models.
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

PLATFORM = Path(__file__).resolve().parents[1]
ROOT = PLATFORM.parents[1]
sys.path[:0] = [str(PLATFORM), str(ROOT / 'tools/hls_fabric'),
                str(ROOT / 'workloads/hls_phi/tools')]
from application.domain_board import bundle, command
from backend_commands import digest
from backend_paths import erlang_paths
from test_domain_repetition import runtime_inputs
from protocol_repetition_result import compare


def save(path: Path, value: dict) -> None:
    """Retain a fresh phase record, including failures."""
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def unchanged(inputs: dict[str, str]) -> None:
    """Reject mutation of any retained executable, RTL or host witness input."""
    for name, expected in inputs.items():
        if digest(Path(name)) != expected:
            raise ValueError('changed witness input: ' + name)


def build(args: argparse.Namespace) -> None:
    """Compile each exact board release separately, then link the two public-pin models."""
    args.stage.mkdir(parents=True, exist_ok=False)
    result = {'success': False, 'evidence': 'Simulator compilation only; not hardware qualification.'}
    try:
        inputs = {str(Path(__file__).resolve()): digest(Path(__file__))}
        selected = []
        for index, manifest_path in enumerate(args.image_manifest):
            config = json.loads(manifest_path.read_text())
            if (config['role'], config['domain_index']) != (index + 1, index):
                raise ValueError('image manifests must be ordered physical roles 1,2')
            inputs[str(manifest_path)] = digest(manifest_path)
            roots, rtl = [], []
            for row in config['bundles']:
                root, sources = bundle(row, inputs)
                roots.append(root); rtl.extend(sources)
            board = roots[config['board_bundle']]
            metadata = json.loads((board / 'board_control/interface.json').read_text())
            if (metadata['role'], metadata['domain_index'], metadata['inspection']) != (index + 1,index,'process'):
                raise ValueError('need exact process-inspection board compositions')
            domain = roots[0]; network = roots[2]
            if (network / 'evidence/domain-interface.etf').read_bytes() != (domain / 'interface.etf').read_bytes():
                raise ValueError('network/domain identity mismatch')
            domain_source, network_source = args.domain_source, args.network_source
            for release, source in ((domain,domain_source),(network,network_source)):
                if (source / 'compiled').resolve(strict=True) != release:
                    raise ValueError('explicit source does not select the manifest-declared release: ' + str(source))
                for name in ('source-build.json','interface.etf'):
                    if digest(source / name) != digest(release / name):
                        raise ValueError('compiled release differs from its retained source: ' + str(source))
                    inputs[str(source / name)] = digest(source / name)
                source_manifest = json.loads((source / 'source-build.json').read_text())
                for member in source_manifest['inputs']:
                    path = (source / member['file']).resolve(strict=True)
                    if not path.is_relative_to(source) or digest(path) != member['sha256']:
                        raise ValueError('changed or escaping retained source input: ' + str(path))
                    inputs[str(path)] = member['sha256']
            if selected and (domain_source,network_source) != (selected[0]['domain'],selected[0]['network']):
                raise ValueError('roles must share one retained domain/network source definition')
            selected.append({'rtl': list(dict.fromkeys(rtl)), 'domain': domain_source, 'network': network_source})
        for name in ('fixture.json', 'fixture.etf', 'interface.etf'):
            path = selected[0]['domain'] / name
            inputs[str(path)] = digest(path)
        fixture = json.loads((selected[0]['domain'] / 'fixture.json').read_text())
        if (fixture['width'],fixture['split'],fixture['inspection']) != (8,4,'process'):
            raise ValueError('need the retained N8/4+4 process fixture')
        source = Path(__file__).with_name('domain_board_attached_sim.cpp')
        header = ROOT / 'apps/hls_fabric/test/rtl/framed_fifo_stream.h'
        shutil.copyfile(header,args.stage / header.name)
        verilator = Path(shutil.which('verilator') or 'verilator').resolve(strict=True)
        for path in (source,header,verilator,PLATFORM / 'application/domain_board.py',
                     ROOT / 'tools/hls_fabric/backend_commands.py',
                     ROOT / 'workloads/hls_phi/tools/test_domain_repetition.py',
                     ROOT / 'workloads/hls_phi/tools/protocol_repetition_result.py'):
            inputs[str(path)] = digest(path)
        for index in (1,0):
            directory = args.stage / f'build-role{index}'; directory.mkdir()
            obj = args.stage / f'obj{index}'
            flags = ['--cc','--build','--top-module','domain_board','--prefix',f'Vboard{index}',
                     '--Mdir',str(obj),'-j','1','-Wno-fatal']
            if index == 0:
                flags += ['--exe','-o','simulation','-CFLAGS',
                    f'-std=c++17 -I{args.stage} -I{args.stage / "obj1"}',
                    '-LDFLAGS',str(args.stage / 'obj1/Vboard1__ALL.a')]
            else:
                flags += ['-CFLAGS','-std=c++17']
            command([str(verilator),*flags,*map(str,selected[index]['rtl']),*([str(source)] if index == 0 else [])],
                    ROOT,directory,1800)
        unchanged(inputs)
        binary = args.stage / 'obj0/simulation'
        result.update(success=True,binary=str(binary),binary_sha256=digest(binary),inputs=inputs,
            bundle=str(selected[0]['domain']),network=str(selected[0]['network']))
    except BaseException as error:
        result['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        save(args.stage / 'build.json',result)


HOST = '''[Bundle,Network,Stage,Namespace]=init:get_plain_arguments(),
ok=hls_domain_board_host:run(Bundle,Network,Stage,#{namespace=>list_to_integer(Namespace),
session=>1,first_request=>1,incarnation_files=>#{0=>filename:join(Stage,"role0.incarnations"),
1=>filename:join(Stage,"role1.incarnations")},create_stores=>true}),
Files=filelib:wildcard(filename:join(Stage,"board*-bootstrap.etf"))++
filelib:wildcard(filename:join(Stage,"board*-inspection-*.etf")),
Observations=[begin {ok,B}=file:read_file(P),Raw=binary_to_term(B),
Value=case Raw of #{values:=Vs}->Raw#{values=>[V#{value=>binary_to_list(maps:get(value,V))}||V<-Vs]};_->Raw end,
#{file=>unicode:characters_to_binary(filename:basename(P)),value=>Value} end||P<-Files],
ok=file:write_file(filename:join(Stage,"board-observations.json"),json:encode(Observations),[exclusive]),halt().'''


def witness(args: argparse.Namespace) -> None:
    """Run unmodified production host/client against both boards and the retained BEAM oracle."""
    built = json.loads(args.build_record.read_text())
    if not built['success']:
        raise ValueError('simulator build did not succeed')
    inputs = dict(built['inputs'])
    inputs[str(args.build_record)] = digest(args.build_record)
    inputs[built['binary']] = built['binary_sha256']
    inputs[str(args.native)] = digest(args.native)
    paths = [*args.ebin,*erlang_paths(args.profile)]
    inputs.update(runtime_inputs(paths,True))
    for module in ('hls_domain_board_host','hls_domain_board_client','hls_dma_device'):
        matches = [path / f'{module}.beam' for path in paths if (path / f'{module}.beam').is_file()]
        if not matches:
            raise ValueError('compile selected host profile first: ' + module)
        inputs.update({str(path):digest(path) for path in matches})
    unchanged(inputs)
    args.stage.mkdir(parents=True,exist_ok=False)
    live = args.stage / 'live'; live.mkdir()
    result = {'success':False,'inputs':inputs,'physical_carrier':False,'physical_dma':False}
    try:
        with (live / 'simulation.log').open('x') as log:
            child = subprocess.Popen([built['binary'],str(live)],stdout=log,stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while not (live / 'transport.ready').exists():
                    if child.poll() is not None or time.monotonic() >= deadline:
                        raise ValueError('attached simulator did not create ready cold host banks')
                    time.sleep(.02)
                host = args.stage / 'host'; host.mkdir()
                command(['erl','+S','2:2','-noshell','-pa',*map(str,paths),'-eval',HOST,'-extra',
                         built['bundle'],built['network'],str(live),str(args.namespace)],ROOT,host,580)
                if child.wait(timeout=10) != 0:
                    raise ValueError('attached simulator failed')
            finally:
                if child.poll() is None:
                    child.terminate()
                    try: child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill(); child.wait(timeout=5)
        actual = json.loads((live / 'result.json').read_text())
        expected = json.loads(args.native.read_text())
        if not (actual['passed'] and actual['descriptors_closed'] and actual['old_pids_terminal']
                and actual['evidence'] == 'finite_attached_independent_endpoint_public_stream_witness'
                and len(actual['incarnations']) == 2 and actual['endpoint_namespace'] == args.namespace):
            raise ValueError('missing attached application/lifetime evidence')
        for row in actual['incarnations']:
            compare(row | {'descriptors_closed':True},expected,8)
        first,second = actual['incarnations']
        for field in ('domain_incarnations','channel_generations'):
            if not all(b > a for a,b in zip(first[field],second[field])):
                raise ValueError('replacement identity did not increase: ' + field)
        if not (actual['recovery']['one_for_all'] and actual['recovery']['source_failure_code'] > 0
                and actual['recovery']['old_endpoints'] == 24 and not actual['held_output_frontier_witness']):
            raise ValueError('missing natural source failure/replacement evidence')
        observations = json.loads((live / 'board-observations.json').read_text())
        bootstrap = [row['value'] for row in observations if '-bootstrap.' in row['file']]
        inspection = [row['value'] for row in observations if '-inspection-' in row['file']]
        if len(bootstrap) != 2 or len(inspection) != 4:
            raise ValueError('missing real bootstrap or per-incarnation inspection replies')
        for row in bootstrap:
            if not (row['cold']['domain_session'] == 0 and row['established']['status'] == 'ok'
                    and row['established']['domain_session'] == row['established']['endpoint_session'] == 1):
                raise ValueError('real parser bootstrap did not establish both sessions')
        for row in inspection:
            if not row['values'] or any(value['status'] != 'ok' for value in row['values']):
                raise ValueError('real process-inspection route failed')
            if not any(any(value['value']) for value in row['values']):
                raise ValueError('all real process inspection replies were empty')
        transport = json.loads((live / 'transport.json').read_text())
        if transport['clock_periods'] != [6,10] or transport['session_pin_injection']:
            raise ValueError('wrong attached simulation boundary')
        unchanged(inputs)
        result.update(success=True,result=actual,transport=transport,observations=observations,
            evidence='Finite actual attached-host/client/board-control/domain/network RTL witness with two source lifetimes and retained BEAM oracle. Ideal atomic carrier, no PS/DMA/MAC/physical CDC or board qualification.')
    except BaseException as error:
        result['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        save(args.stage / 'result.json',result)


def main() -> None:
    """Fresh bounded phases are explicit; failures and successful compilation are retained."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='phase',required=True)
    compile_args = sub.add_parser('build')
    compile_args.add_argument('--image-manifest',type=lambda p:Path(p).resolve(),action='append',required=True)
    compile_args.add_argument('--domain-source',type=lambda p:Path(p).resolve(),required=True)
    compile_args.add_argument('--network-source',type=lambda p:Path(p).resolve(),required=True)
    compile_args.add_argument('--stage',type=lambda p:Path(p).resolve(),required=True)
    run_args = sub.add_parser('witness')
    run_args.add_argument('--build-record',type=lambda p:Path(p).resolve(),required=True)
    run_args.add_argument('--native',type=lambda p:Path(p).resolve(),required=True)
    run_args.add_argument('--stage',type=lambda p:Path(p).resolve(),required=True)
    run_args.add_argument('--profile',default='test')
    run_args.add_argument('--ebin',type=lambda p:Path(p).resolve(),action='append',default=[])
    run_args.add_argument('--namespace',type=int,required=True)
    args = parser.parse_args()
    if args.phase == 'build':
        if len(args.image_manifest) != 2: parser.error('supply exactly two ordered role image manifests')
        build(args)
    else:
        if not 0 < args.namespace < 1 << 64: parser.error('namespace must be nonzero u64')
        witness(args)


if __name__ == '__main__':
    main()
