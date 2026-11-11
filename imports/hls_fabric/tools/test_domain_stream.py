"""Run matched recovery scenarios on ERTS and independent framed RTL domains."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import time

from backend_commands import digest, run
from backend_paths import ROOT, erlang_paths, erlang_environment
from protocol_test_build import compile_build


def compile_host(stage: Path) -> Path:
    """Compile only the maintained source application and backend-neutral witnesses."""
    ebin = stage / 'ebin'
    ebin.mkdir()
    sources = [ROOT / 'test' / name for name in [
        'hls_recovery_actuator_fixture.erl', 'hls_recovery_policy_fixture.erl',
        'hls_recovery_device_model.erl', 'hls_recovery_supervisor.erl',
        'hls_recovery_application.erl', 'hls_recovery_application_tests.erl',
        'hls_recovery_stream_live.erl', 'hls_domain_reattach_live.erl',
        'hls_domain_shutdown_live.erl', 'hls_shutdown_supervisor.erl', 'hls_test_nodes.erl',
    ]]
    run(['erlc', *[value for path in erlang_paths('test') for value in ('-pa', path)],
         '+debug_info', '-Werror', '-o', ebin, *sources], stage, 'host-compile')
    return ebin


def native(stage: Path, ebin: Path, scenario: str) -> Path:
    """Retain a separate native expected history before any RTL simulation starts."""
    target = stage / 'native'
    module = 'hls_domain_shutdown_live' if scenario == 'shutdown' else 'hls_recovery_stream_live'
    expression = ('[Stage]=init:get_plain_arguments(), '
                  f'ok={module}:native(Stage),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), ebin,
         '-eval', expression, '-extra', target], stage, 'native', timeout=60)
    assert json.loads((target / 'result.json').read_text())['passed']
    return target / 'result.etf'


def stream_checks(xls: Path, bundle: Path, stage: Path) -> Path:
    """Run the finite framing/clock checks with widths read from the emitted runtime interface."""
    stage.mkdir()
    template = ROOT / 'test/domain_stream_semantics.x.in'
    interface = bundle / 'domain/interface.etf'
    source = stage / 'stream_checks.x'
    expression = (
        '[Interface,Template,Output]=init:get_plain_arguments(),'
        '{ok,B}=file:read_file(Interface),'
        '#{transport:=#{packet_words:=Words,state_bit_budget:=Budget},'
        'call_slots:=Slots,codecs:=Codecs,actors:=#{actuator:=#{schemas:=Schemas}}}=binary_to_term(B),'
        '#{selector:=SelectTag,width:=SelectWidth}=maps:get(select_profile,Schemas),'
        '{ok,T}=file:read_file(Template),'
        'Pairs=[{<<"@@PACKET_BITS@@">>,Words*32},{<<"@@SLOTS@@">>,Slots},'
        '{<<"@@STATUS_BITS@@">>,hls_type:width(maps:get(status,Codecs))},'
        '{<<"@@ACTION_BITS@@">>,hls_type:width(maps:get(action,Codecs))},'
        '{<<"@@STATE_BUDGET@@">>,Budget},'
        '{<<"@@SELECT_TAG@@">>,SelectTag},{<<"@@SELECT_WORDS@@">>,(SelectWidth+31) div 32}],'
        'Text=lists:foldl(fun({K,V},A)->binary:replace(A,K,integer_to_binary(V),[global]) end,T,Pairs),'
        'ok=file:write_file(Output,Text,[exclusive]),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-eval', expression, '-extra',
         interface, template, source], stage, 'prepare', env=erlang_environment('test'))
    imports = [bundle / directory for directory in [
        'domain', 'actors', 'network', 'dslx', 'support/fabric/xls/lib',
        'support/fabric/xls/fabric', 'support/compiler/xls/lib', 'support/compiler/xls/fabric',
    ]]
    run([xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none',
         '--max_ticks=1000', '--warnings_as_errors=false',
         '--dslx_path=' + ':'.join(map(str, imports)),
         '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), source], stage, 'witness')
    result = {'passed': True, 'evidence': 'Finite DSLX framing and clock-transition witnesses.',
              'inputs': {str(path): digest(path) for path in [template, interface, xls / 'interpreter_main']},
              'outputs': {str(path): digest(path) for path in [source, stage / 'witness.log']}}
    report = stage / 'result.json'
    report.write_text(json.dumps(result, indent=2) + '\n')
    return report


def build(xls: Path | None, stage: Path, ebin: Path,
          source_bundle: Path | None = None) -> tuple[Path, Path]:
    """Compile hardware once after finite stream checks; reuse XLS emission when supplied."""
    if xls is None:
        raise ValueError('--xls is required unless reusing --binary')
    if source_bundle is None:
        config = ('#{sources=>[{"test/hls_recovery_actuator_fixture.erl",[]}],'
                  'topology=>{hls_recovery_actuator_fixture,topology,[]},'
                  'actor_limit=>1,control=>rectangle}')
        expression = ('[Output]=init:get_plain_arguments(), '
                      '_=hls_protocol_domain:write_stream(' + config + ',Output),halt().')
        bundle = stage / 'source'
        run(['erl', '+S', '2:2', '-pa', ebin, '-noshell', '-eval', expression,
             '-extra', bundle], stage, 'emit', env=erlang_environment('test'))
        compiled = compile_build(xls, bundle, profile='test')
    else:
        bundle = source_bundle
        compiled = (bundle / 'compiled').resolve(strict=True)
    checks = stream_checks(xls, bundle, stage / 'stream-checks')
    interface = bundle / 'domain/interface.etf'
    rtl = [compiled / 'domain/stream_core.v', compiled / 'domain/domain_stream.sv']
    inputs = {str(path.resolve()): digest(path) for path in [
        *rtl, interface, bundle / 'source-build.json', bundle / 'compiled.run.json',
        ROOT / 'test/rtl/domain_stream_sim.cpp', ROOT / 'test/rtl/framed_fifo_stream.h',
        ROOT / 'test/domain_stream_semantics.x.in', checks,
    ]}
    run(['verilator', '--cc', '--exe', '--build', '--top-module', 'domain_stream',
         '--Mdir', stage / 'obj_dir', '-j', '1', '-Wno-fatal',
         '-CFLAGS', '-std=c++17', '-o', 'simulation', *rtl,
         ROOT / 'test/rtl/domain_stream_sim.cpp'], stage, 'verilator')
    assert inputs == {path: digest(Path(path)) for path in inputs}
    binary = stage / 'obj_dir/simulation'
    manifest = {'binary_sha256': digest(binary), 'interface': str(interface.resolve()),
                'inputs': inputs, 'source_bundle': str(bundle.resolve()),
                'stream_checks': str(checks.resolve())}
    binary.with_suffix('.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return binary, interface


def reuse_binary(binary: Path) -> tuple[Path, Path]:
    """Verify the exact simulator, generated RTL, interface and transport harness before reuse."""
    manifest = json.loads(binary.with_suffix('.json').read_text())
    assert digest(binary) == manifest['binary_sha256'], 'reused simulator changed'
    for name, expected in manifest['inputs'].items():
        assert digest(Path(name)) == expected, 'reused hardware input changed: ' + name
    return binary, Path(manifest['interface'])


def witness(binary: Path, interface: Path, stage: Path, ebin: Path,
            native_result: Path | None, scenario: str) -> None:
    """Drive independent actual RTL cores through shipped brokers/backend and the selected remote application."""
    live = stage / 'rtl'
    live.mkdir()
    shutil.copyfile(interface, live / 'interface.etf')
    with (live / 'simulation.log').open('x') as log:
        count = 3 if scenario == 'shutdown' else 2
        simulator = subprocess.Popen([binary, live, str(count)], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while not (live / f'domain{count - 1}_application_rx').exists():
                if simulator.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('domain stream simulator did not initialize')
                time.sleep(.02)
            module = 'hls_domain_shutdown_live' if scenario == 'shutdown' else 'hls_recovery_stream_live'
            expression = ('[Stage,Native]=init:get_plain_arguments(), '
                          f'ok={module}:run(Stage,Native),halt().') if native_result else (
                          '[Stage]=init:get_plain_arguments(),ok=hls_domain_reattach_live:run(Stage),halt().')
            run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), ebin,
                 '-eval', expression, '-extra', live, *([native_result] if native_result else [])], live, 'host', timeout=60)
            if simulator.wait(timeout=10) != 0:
                raise RuntimeError((live / 'simulation.log').read_text())
        finally:
            if simulator.poll() is None:
                simulator.terminate()
                simulator.wait(timeout=5)
    assert 'PASS domain stream RTL:' in (live / 'simulation.log').read_text()
    result = json.loads((live / 'result.json').read_text())
    assert result['passed'] and result['descriptor_closure']
    if native_result:
        assert result['native_history_matches']
    else:
        trace = (live / 'domain1_application-words.log').read_text()
        assert 'd00dfeed 0' in trace, 'partial old input was not accepted before rotation'


def main() -> None:
    """Keep fresh evidence while reusing explicit immutable hardware or an existing native witness."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xls', type=lambda value: Path(value).resolve())
    parser.add_argument('--work', required=True, type=lambda value: Path(value).resolve())
    hardware = parser.add_mutually_exclusive_group()
    hardware.add_argument('--source-bundle', type=lambda value: Path(value).resolve(),
                          help='Reuse this emitted and XLS-compiled bundle; check streams and build its simulator.')
    hardware.add_argument('--binary', type=lambda value: Path(value).resolve(),
                          help='Reuse a simulator with its unchanged build manifest; no hardware rebuild.')
    parser.add_argument('--native-result', type=lambda value: Path(value).resolve(),
                        help='Reuse an already successful result.etf for this same application.')
    parser.add_argument('--scenario', choices=['application', 'reattach', 'shutdown'], default='application',
                        help='Select matched application/shutdown histories or actual transport replacement.')
    args = parser.parse_args()
    if args.xls is None and args.binary is None:
        parser.error('supply --xls for a build or --binary to reuse qualified hardware')
    args.work.mkdir()
    tracked = [ROOT / path for path in [
        'test/hls_recovery_profile.hrl', 'test/hls_recovery_actuator_fixture.erl',
        'test/hls_recovery_policy_fixture.erl', 'test/hls_recovery_device_model.erl',
        'test/hls_recovery_supervisor.erl', 'test/hls_recovery_application.erl',
        'test/hls_recovery_application_tests.erl', 'test/hls_recovery_stream_live.erl',
        'test/hls_domain_reattach_live.erl', 'test/hls_domain_shutdown_live.erl',
        'test/hls_shutdown_supervisor.erl', 'test/hls_test_nodes.erl', 'test/rtl/domain_stream_sim.cpp',
        'test/rtl/framed_fifo_stream.h', 'src/runtime/domain/hls_domain_fabric.erl',
        'src/runtime/domain/hls_domain_endpoint.erl', 'src/wire/hls_domain_wire.erl',
        'tools/test_domain_stream.py', 'test/domain_stream_semantics.x.in',
    ]]
    inputs = {str(path): digest(path) for path in tracked}
    (args.work / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    ebin = compile_host(args.work)
    expected = (args.native_result or native(args.work, ebin, args.scenario)) if args.scenario != 'reattach' else None
    if expected:
        assert json.loads(expected.with_suffix('.json').read_text())['passed']
        inputs[str(expected)] = digest(expected)
    binary, interface = (reuse_binary(args.binary) if args.binary else
                         build(args.xls, args.work, ebin, args.source_bundle))
    witness(binary, interface, args.work, ebin, expected, args.scenario)
    assert inputs == {name: digest(Path(name)) for name in inputs}
    products = ([expected.with_suffix('.json')] if expected else []) + [args.work / 'rtl/result.json', binary]
    result = {
        'passed': True, 'inputs': inputs,
        'outputs': {str(path): digest(path) for path in products},
        'hardware_manifest': str(binary.with_suffix('.json')),
        'evidence': ('Finite matched native/RTL recovery application.' if expected else
                     'Finite public-port RTL reattachment through a real ERTS distribution peer.'),
        'limits': 'No physical watchdog, board reset, unbounded progress or exhaustive equivalence claim.',
    }
    (args.work / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
