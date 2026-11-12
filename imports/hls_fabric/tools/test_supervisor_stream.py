"""Qualify autonomous child publication over framed hardware and real ERTS distribution."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import time

from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment, erlang_paths
from protocol_test_build import compile_build


def native(stage: Path, scenario: str = 'permanent') -> Path:
    """Retain the shared native source/supervisor scenario once before hardware testing."""
    module = 'hls_temporary_supervisor_live' if scenario == 'temporary' else 'hls_supervisor_stream_live'
    expression = ('[Stage]=init:get_plain_arguments(),'
                  f'ok={module}:native(Stage),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), '-eval',
         expression, '-extra', stage / 'native'], stage, 'native', timeout=60)
    assert json.loads((stage / 'native/result.json').read_text())['passed']
    return stage / 'native/result.etf'


def emit(stage: Path, scenario: str = 'permanent') -> Path:
    """Emit source-defined supervision of two copies of the same typed actuator."""
    child = ('#{sources=>[{"test/hls_recovery_actuator_fixture.erl",[]}],'
             'topology=>{hls_recovery_actuator_fixture,topology,[]},actor_limit=>1,control=>rectangle}')
    declaration = ('supervisor=>{hls_temporary_supervisor_otp,[]},'
                   'templates=>hls_temporary_supervisor_otp:templates(unbound_owner),'
                   if scenario == 'temporary' else
                   'supervisor=>{hls_fpga_supervisor_otp,{unbound_owner,'
                   '#{strategy=>one_for_one,intensity=>8,period=>60}}},')
    expression = ('[Output]=init:get_plain_arguments(),Child=' + child + ','
                  'Config=#{' + declaration +
                  'children=>#{a=>Child,b=>Child},clock_hz=>10000},'
                  '_=hls_protocol_supervisor:write_stream(Config,Output),halt().')
    bundle = stage / 'source'
    run(['erl', '+S', '2:2', '-noshell', '-eval', expression, '-extra', bundle],
        stage, 'emit', env=erlang_environment('test'))
    return bundle


def checks(xls: Path, bundle: Path, stage: Path, scenario: str = 'permanent') -> Path:
    """Exercise finite supervised observer histories using the same emitted source as RTL."""
    target = stage / 'stream-checks'
    target.mkdir()
    template = ROOT / 'test/supervised_domain_stream_semantics.x.in'
    source = target / 'checks.x'
    interface = bundle / 'child_0/domain/interface.etf'
    expression = (
        '[Interface,Template,Output]=init:get_plain_arguments(),'
        '{ok,B}=file:read_file(Interface),'
        '#{transport:=#{packet_words:=Words,state_bit_budget:=Budget},'
        'actors:=#{actuator:=#{schemas:=Schemas}}}=binary_to_term(B),'
        '#{selector:=SelectTag,width:=SelectWidth}=maps:get(select_profile,Schemas),'
        '{ok,T}=file:read_file(Template),'
        'Pairs=[{<<"@@PACKET_BITS@@">>,Words*32},{<<"@@STATE_BUDGET@@">>,Budget},'
        '{<<"@@SELECT_TAG@@">>,SelectTag},{<<"@@SELECT_WORDS@@">>,(SelectWidth+31) div 32}],'
        'Text=lists:foldl(fun({K,V},A)->binary:replace(A,K,integer_to_binary(V),[global]) end,T,Pairs),'
        'ok=file:write_file(Output,Text,[exclusive]),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-eval', expression, '-extra',
         interface, template, source], target, 'prepare', env=erlang_environment('test'))
    child = bundle / 'child_0'
    imports = [child / name for name in ['domain', 'network', 'actors', 'dslx',
               'support/fabric/xls/lib', 'support/compiler/xls/lib', 'support/compiler/xls/fabric']]
    run([xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none',
         '--max_ticks=1000', '--warnings_as_errors=false',
         '--dslx_path=' + ':'.join(map(str, imports)),
         '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), source], target, 'witness')
    if scenario == 'temporary':
        temporary = ROOT / 'test/supervisor_temporary_semantics.x'
        units = json.loads((bundle / 'source-build.json').read_text())['units']
        paths = next(u['dslx_path'] for u in units if u['top'] == 'supervisor_clock')
        run([xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none',
             '--max_ticks=1000', '--warnings_as_errors=false',
             '--dslx_path=' + ':'.join(str(bundle / p) for p in paths),
             '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), temporary], target, 'temporary')
    result = target / 'result.json'
    result.write_text(json.dumps({'passed': True, 'evidence': 'Finite supervised observer and selected temporary-controller witnesses.',
        'inputs': {str(path): digest(path) for path in [template, interface, source,
            *([ROOT / 'test/supervisor_temporary_semantics.x'] if scenario == 'temporary' else [])]},
        'controller_inputs': {str(path): digest(path) for path in (bundle / 'supervisor').glob('*.x')},
        'output': digest(target / 'witness.log'), 'child_inputs': child_inputs(bundle),
        'interpreter': digest(xls / 'interpreter_main')}, indent=2)+'\n')
    return result


def child_inputs(bundle: Path) -> dict[str, str]:
    """Bind every frozen child source/support input while excluding compiled products."""
    manifest = json.loads((bundle / 'source-build.json').read_text())
    return {entry['file']: digest(bundle / entry['file']) for entry in manifest['inputs']
            if entry['file'].startswith('child_0/')}


def checked(result: Path, xls: Path, bundle: Path) -> Path:
    """Reuse finite checks only when all child sources, test and interpreter are identical."""
    previous = json.loads(result.read_text())
    # The source-analysis descriptor contains fresh Erlang references; DSLX does not consume it.
    relevant = lambda values: {name: sha for name, sha in values.items()
                               if name != 'child_0/transport.etf'}
    assert previous['passed'] and relevant(previous['child_inputs']) == relevant(child_inputs(bundle))
    assert previous['interpreter'] == digest(xls / 'interpreter_main')
    for name, expected in (previous['inputs'] | previous['controller_inputs']).items():
        assert digest(Path(name)) == expected, name
    return result


def build(xls: Path, stage: Path, source: Path | None = None, checks_result: Path | None = None, scenario: str = 'permanent') -> tuple[Path, Path]:
    """Compile independent control/child units and stateless wiring from their emitted manifest."""
    bundle = source or emit(stage, scenario)
    semantic_checks = checked(checks_result, xls, bundle) if checks_result else checks(xls, bundle, stage, scenario)
    compiled = compile_build(xls, bundle, profile='test')
    manifest = json.loads((bundle / 'source-build.json').read_text())
    rtl = [compiled / name for name in dict.fromkeys(
        name for unit in manifest['units'] for name in unit['rtl'])]
    harness = ROOT / 'test/rtl/supervisor_stream_sim.cpp'
    run(['verilator', '--cc', '--exe', '--build', '--top-module', 'protocol_supervisor_stream',
         '--Mdir', stage / 'obj_dir', '-j', '1', '-Wno-fatal', '-CFLAGS', '-std=c++17',
         '-o', 'simulation', *rtl, harness], stage, 'verilator')
    binary = stage / 'obj_dir/simulation'
    inputs = [*rtl, harness, ROOT / 'test/rtl/framed_fifo_stream.h',
              ROOT / 'test/rtl/framed_fifo_control.h', bundle / 'source-build.json',
              bundle / 'compiled.run.json', bundle / 'interface.etf', semantic_checks]
    inputs.extend(bundle.glob('child_*/domain/interface.etf'))
    binary.with_suffix('.json').write_text(json.dumps({
        'binary_sha256': digest(binary), 'bundle': str(bundle),
        'inputs': {str(p): digest(p) for p in inputs}}, indent=2) + '\n')
    return binary, bundle


def reuse(binary: Path) -> tuple[Path, Path]:
    """Verify all retained hardware inputs before correcting a host-only witness."""
    manifest = json.loads(binary.with_suffix('.json').read_text())
    assert digest(binary) == manifest['binary_sha256']
    for name, expected in manifest['inputs'].items():
        assert digest(Path(name)) == expected, name
    return binary, Path(manifest['bundle'])


def witness(binary: Path, bundle: Path, reference: Path, stage: Path, scenario: str = 'permanent') -> None:
    """Transport only public word beats; Erlang drives ordinary typed application traffic."""
    live = stage / 'rtl'
    live.mkdir()
    shutil.copyfile(bundle / 'interface.etf', live / 'interface.etf')
    for index in range(2):
        shutil.copyfile(bundle / f'child_{index}/domain/interface.etf', live / f'child_{index}.etf')
    with (live / 'simulation.log').open('x') as log:
        process = subprocess.Popen([binary, live], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while not (live / 'domain1_application_rx').exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('supervisor simulation did not create FIFOs')
                time.sleep(.02)
            module = 'hls_temporary_supervisor_live' if scenario == 'temporary' else 'hls_supervisor_stream_live'
            expression = ('[Stage,Native]=init:get_plain_arguments(),'
                          f'ok={module}:run(Stage,Native),halt().')
            run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'),
                 '-eval', expression, '-extra', live, reference], live, 'host', timeout=90)
            assert process.wait(timeout=10) == 0
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
    assert 'PASS supervisor stream RTL:' in (live / 'simulation.log').read_text()
    result = json.loads((live / 'result.json').read_text())
    assert result['passed'] and result['descriptor_closure'] and result['native_history_matches']


def main() -> None:
    """Keep each attempt separate and reuse only explicitly verified successful artifacts."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=['permanent', 'temporary'], default='permanent')
    parser.add_argument('--stage', required=True, type=lambda p: Path(p).resolve())
    parser.add_argument('--xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--checks-result', type=lambda p: Path(p).resolve())
    parser.add_argument('--source-bundle', type=lambda p: Path(p).resolve())
    parser.add_argument('--binary', type=lambda p: Path(p).resolve())
    parser.add_argument('--native-result', type=lambda p: Path(p).resolve())
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if not args.native_only and not args.xls and not args.binary:
        parser.error('supply --xls or --binary')
    args.stage.mkdir()
    reference = args.native_result or native(args.stage, args.scenario)
    if args.native_only:
        return
    binary, bundle = reuse(args.binary) if args.binary else build(args.xls, args.stage, args.source_bundle, args.checks_result, args.scenario)
    if not args.build_only:
        witness(binary, bundle, reference, args.stage, args.scenario)
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'binary': str(binary), 'bundle': str(bundle),
        'native_reference': str(reference), 'build_only': args.build_only,
        'evidence': 'Finite native/RTL witness; no physical reset or live board qualification.'}, indent=2)+'\n')


if __name__ == '__main__':
    main()
