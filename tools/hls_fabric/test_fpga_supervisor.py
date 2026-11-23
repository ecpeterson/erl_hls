"""Qualify a static compiled supervisor through public pins and ordinary host OTP."""
from pathlib import Path
import argparse
import json
import sys

from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment, erlang_paths
from protocol_test_build import compile_build


def native(stage: Path) -> Path:
    """Retain the independent ordinary OTP reference exactly once."""
    expression = ('[Stage]=init:get_plain_arguments(), '
                  '#{passed:=true}=hls_fpga_supervisor_otp_tests:run(Stage),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'),
         '-eval', expression, '-extra', stage / 'native'], stage, 'native', timeout=60)
    return stage / 'native/result.json'


def build(xls: Path, stage: Path) -> tuple[Path, Path]:
    """Emit one checked supervisor and two independent source domains, then compile once."""
    child = ('#{sources=>[{"test/hls_domain_counter.erl",[]},'
             '{"test/hls_domain_relay.erl",[]}],'
             'topology=>{hls_domain_counter,topology,[]},actor_limit=>2,control=>rectangle}')
    expression = ('[Output]=init:get_plain_arguments(), Child=' + child + ','
                  'Config=#{supervisor=>{hls_fpga_supervisor_otp,{unbound_owner,'
                  '#{strategy=>one_for_one,intensity=>2,period=>1}}},'
                  'children=>#{a=>Child,b=>Child},clock_hz=>10000},'
                  '_=hls_protocol_supervisor:write(Config,Output),halt().')
    bundle = stage / 'source'
    run(['erl', '+S', '2:2', '-noshell', '-eval', expression, '-extra', bundle],
        stage, 'emit', env=erlang_environment('test'))
    compiled = compile_build(xls, bundle, profile='test')
    rtl = [compiled / name for name in [
        'child_0/domain/core.v', 'child_0/domain/protocol_domain.sv',
        'child_1/domain/core.v', 'child_1/domain/protocol_domain.sv',
        'supervisor/core.v', 'supervisor/controller.sv', 'supervisor/protocol_supervisor.sv']]
    run(['verilator', '--cc', '--exe', '--build', '--top-module', 'protocol_supervisor',
         '--Mdir', stage / 'obj_dir', '-j', '1', '-Wno-fatal', '-CFLAGS', '-std=c++17',
         '-o', 'simulation', *rtl, ROOT / 'test/rtl/supervisor_sim.cpp'], stage, 'verilator')
    binary = stage / 'obj_dir/simulation'
    inputs = [*rtl, bundle / 'interface.etf', ROOT / 'test/rtl/supervisor_sim.cpp',
              bundle / 'source-build.json', bundle / 'compiled.run.json']
    manifest = {'binary_sha256': digest(binary), 'interface': str(bundle / 'interface.etf'),
                'inputs': {str(p): digest(p) for p in inputs}}
    binary.with_suffix('.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return binary, bundle / 'interface.etf'


def reuse(binary: Path) -> tuple[Path, Path]:
    """Verify previously generated hardware before a host-only harness correction."""
    manifest = json.loads(binary.with_suffix('.json').read_text())
    assert digest(binary) == manifest['binary_sha256']
    for name, expected in manifest['inputs'].items():
        assert digest(Path(name)) == expected, name
    return binary, Path(manifest['interface'])


def witness(binary: Path, interface: Path, reference: Path, stage: Path) -> None:
    """Run native host parent supervision against actual compiled child control and actors."""
    expression = ('[Binary,Interface,Native,Stage]=init:get_plain_arguments(),'
                  'ok=hls_fpga_supervisor_live:run(Binary,Interface,Native,Stage),halt().')
    run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), '-eval', expression,
         '-extra', binary, interface, reference, stage / 'rtl'], stage, 'rtl', timeout=120)
    result = json.loads((stage / 'rtl/result.json').read_text())
    assert result['passed'] and result['host_otp_parent']


def main() -> None:
    """Retain new evidence per attempt; allow explicit successful reference/hardware reuse."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--binary', type=lambda p: Path(p).resolve())
    parser.add_argument('--native-result', type=lambda p: Path(p).resolve())
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if not args.binary and not args.xls:
        parser.error('supply --xls or a verified --binary')
    args.stage.mkdir()
    reference = args.native_result or native(args.stage)
    assert json.loads(reference.read_text())['passed']
    binary, interface = reuse(args.binary) if args.binary else build(args.xls, args.stage)
    if not args.build_only:
        witness(binary, interface, reference, args.stage)
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'native_reference': str(reference), 'binary': str(binary),
        'interface': str(interface), 'build_only': args.build_only,
        'evidence': 'Finite native OTP and public-pin RTL witness; no physical qualification.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
