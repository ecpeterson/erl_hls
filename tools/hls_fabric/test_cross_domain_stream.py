"""Qualify framed dependent-group recovery through production runtime and real ERTS distribution."""
import argparse
import json
import re
import shutil
import subprocess
import time
from pathlib import Path
from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment, erlang_paths
from protocol_test_build import compile_build


def emit(stage: Path) -> Path:
    """Build the existing source fixture through the production framed composer once."""
    bundle = stage / 'source'
    run(['erl', '+S', '2:2', '-noshell', '-eval',
         '[Output]=init:get_plain_arguments(),ok=hls_cross_domain_build:write_stream(Output),halt().',
         '-extra', bundle], stage, 'emit', env=erlang_environment('test'))
    return bundle


def account_state(bundle: Path, compiled: Path, stage: Path) -> None:
    """Check declared component source ceilings and complete optimized state against preregistered bounds."""
    manifest = json.loads((bundle/'source-build.json').read_text())
    fixture = json.loads((bundle/'stream-fixture.json').read_text())
    rows = []
    for unit in manifest['units']:
        path = compiled/unit['directory']/'optimized.ir'
        header, = [line for line in path.read_text().splitlines() if line.startswith('top proc ')]
        parameters = header.split('out>(', 1)[1].split(', init=', 1)[0]
        fields = re.findall(r'(__state_\d+): bits\[(\d+)\](?= pos=|,|$)', parameters)
        assert fields and [name for name, _ in fields] == re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*):', parameters)
        rows.append({'unit': unit['directory'], 'elements': len(fields),
                     'bits': sum(int(width) for _, width in fields), 'sha256': digest(path)})
    total = sum(row['bits'] for row in rows)
    assert total <= 32000
    assert fixture['management_state_bits'] <= 2048
    assert fixture['management_packet_words'] <= 16
    channel_limit = fixture['frame_bits'] + 8 + 384
    assert fixture['channel_storage_bits'] <= channel_limit
    domains = []
    for domain in fixture['domains']:
        transport = domain['transport']
        assert transport['packet_words'] <= 30
        limit = 4*(transport['packet_words']+2)*32 + domain['call_slots']*34 + 1089
        assert transport['state_bit_budget'] <= limit
        domains.append({'index': domain['index'], 'packet_words': transport['packet_words'],
                        'call_slots': domain['call_slots'],
                        'declared_source_ceiling_bits': transport['state_bit_budget'],
                        'preregistered_limit_bits': limit})
    (stage/'state-budget.json').write_text(json.dumps({'passed': True, 'units': rows,
        'aggregate_optimized_bits': total, 'aggregate_budget_bits': 32000,
        'domain_source_ceilings': domains,
        'channel_source_ceiling_bits': fixture['channel_storage_bits'],
        'channel_source_limit_bits': channel_limit,
        'management_source_ceiling_bits': fixture['management_state_bits'],
        'management_source_limit_bits': 2048,
        'management_rx_packet_words': fixture['management_packet_words'],
        'management_tx_packet_words': fixture['management_packet_words'],
        'management_packet_words_limit': 16,
        'access': 'One selected metadata read/command per management edge; application payload never enters this parser.',
        'limits': 'Source values are declared component ceilings; optimized values count complete IR state signatures. Neither is mapped area or physical timing.'}, indent=2)+'\n')


def checks(xls: Path, bundle: Path, stage: Path) -> Path:
    """Exercise finite framing histories against the actual emitted parser and shared kernel."""
    fixture = json.loads((bundle/'stream-fixture.json').read_text())
    template = ROOT/'apps/hls_fabric/test/domain_channel_stream_semantics.x.in'
    text = template.read_text().replace('@@LINK@@', '0')
    for name, value in fixture['status_codes'].items():
        text = text.replace('@@'+name.upper()+'@@', str(value))
    assert '@@' not in text
    source = stage/'channel-stream-checks.x'
    source.write_text(text)
    manifest = json.loads((bundle/'source-build.json').read_text())
    paths = list(dict.fromkeys(path for unit in manifest['units'] for path in unit['dslx_path']))
    run([xls/'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none',
         '--max_ticks=1000', '--warnings_as_errors=false',
         '--dslx_path='+':'.join(str(bundle/path) for path in paths),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'), source], stage, 'channel-stream-checks')
    result = stage/'checks-result.json'
    result.write_text(json.dumps({'passed': True, 'cases': 7, 'source': digest(source),
        'template': digest(template), 'interpreter': digest(xls/'interpreter_main'),
        'inputs': {entry['file']: digest(bundle/entry['file']) for entry in manifest['inputs']},
        'scope': 'Finite parser/kernel composition witnesses, not unbounded proofs.'}, indent=2)+'\n')
    return result


def build(xls: Path, stage: Path, source: Path | None, checks_result: Path | None) -> tuple[Path, Path]:
    """Compile emitted units serially, then build a simulator exposing only public pins."""
    bundle = source or emit(stage)
    if checks_result:
        prior = json.loads(checks_result.read_text())
        assert prior['passed'] and prior['interpreter'] == digest(xls/'interpreter_main')
        assert prior['template'] == digest(ROOT/'apps/hls_fabric/test/domain_channel_stream_semantics.x.in')
        for name, expected in prior['inputs'].items():
            assert digest(bundle/name) == expected, name
        semantic_checks = checks_result
    else:
        semantic_checks = checks(xls, bundle, stage)
    compiled = compile_build(xls, bundle, profile='test')
    account_state(bundle, compiled, stage)
    return compile_adapter(bundle, compiled, stage, semantic_checks)


def compile_adapter(bundle: Path, compiled: Path, stage: Path, semantic_checks: Path) -> tuple[Path, Path]:
    """Build only the public transport harness around already qualified immutable RTL."""
    manifest = json.loads((bundle/'source-build.json').read_text())
    rtl = [compiled/name for name in dict.fromkeys(name for unit in manifest['units'] for name in unit['rtl'])]
    harness = ROOT/'apps/hls_fabric/test/rtl/cross_domain_stream_sim.cpp'
    run(['verilator', '--cc', '--exe', '--build', '--top-module', 'protocol_domains_stream',
         '--Mdir', stage/'obj_dir', '-j', '1', '-Wno-fatal', '-CFLAGS', '-std=c++17',
         '-o', 'simulation', *rtl, harness], stage, 'verilator', timeout=None)
    binary = stage/'obj_dir/simulation'
    inputs = [*rtl, harness, ROOT/'apps/hls_fabric/test/rtl/framed_fifo_endpoint.h',
              ROOT/'apps/hls_fabric/test/rtl/framed_fifo_stream.h', ROOT/'apps/hls_fabric/test/rtl/framed_fifo_control.h',
              bundle/'source-build.json', bundle/'compiled.run.json', bundle/'interface.etf',
              bundle/'stream-fixture.json', bundle/'channel_management/interface.etf', semantic_checks]
    inputs.extend(bundle.glob('domain_*/domain/interface.etf'))
    binary.with_suffix('.json').write_text(json.dumps({'binary_sha256': digest(binary), 'bundle': str(bundle),
        'inputs': {str(path): digest(path) for path in inputs}}, indent=2)+'\n')
    return binary, bundle


def reuse(binary: Path) -> tuple[Path, Path]:
    """Reuse successful hardware only when every retained source and interface hash matches."""
    metadata = json.loads(binary.with_suffix('.json').read_text())
    assert digest(binary) == metadata['binary_sha256']
    for name, expected in metadata['inputs'].items():
        assert digest(Path(name)) == expected, name
    return binary, Path(metadata['bundle'])


def witness(binary: Path, bundle: Path, native: Path, stage: Path) -> None:
    """Run the actual host APIs with bounded transport stalls and stale-beat injection."""
    live = stage/'rtl'
    live.mkdir()
    for index in range(3):
        (live/f'domain{index}').mkdir()
        shutil.copyfile(bundle/f'domain_{index}/domain/interface.etf', live/f'domain{index}/interface.etf')
    (live/'channel0').mkdir()
    shutil.copyfile(bundle/'channel_management/interface.etf', live/'channel0/interface.etf')
    accepted = json.loads((bundle/'stream-fixture.json').read_text())['accepted']
    with (live/'simulation.log').open('x') as log:
        child = subprocess.Popen([binary, live, str(accepted)], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic()+10
            while not (live/'domain2_application_rx').exists():
                if child.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('framed simulator did not create FIFOs')
                time.sleep(.02)
            run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), '-eval',
                 '[Stage,Native]=init:get_plain_arguments(),ok=hls_cross_domain_stream_live:run(Stage,Native),halt().',
                 '-extra', live, native], live, 'host', timeout=120)
            assert child.wait(timeout=10) == 0
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
    assert 'PASS cross-domain stream RTL:' in (live/'simulation.log').read_text()
    result = json.loads((live/'result.json').read_text())
    assert result['passed'] and result['native_history_matches'] and result['descriptor_closure']
    (stage/'result.json').write_text(json.dumps({'passed': True, 'binary': str(binary),
        'binary_sha256': digest(binary), 'native': str(native), 'native_sha256': digest(native),
        'result': result, 'evidence': 'Finite public-port simulation with real ERTS distribution; no physical deployment claim.'}, indent=2)+'\n')


def main() -> None:
    """Keep failed attempts separate and permit verified hardware reuse for host-only corrections."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, type=lambda value: Path(value).resolve())
    parser.add_argument('--native', type=lambda value: Path(value).resolve())
    parser.add_argument('--xls', type=lambda value: Path(value).resolve())
    parser.add_argument('--source', type=lambda value: Path(value).resolve())
    parser.add_argument('--checks-result', type=lambda value: Path(value).resolve())
    parser.add_argument('--binary', type=lambda value: Path(value).resolve())
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if not args.binary and not args.xls:
        parser.error('supply --xls or --binary')
    if not args.build_only and not args.native:
        parser.error('witness requires retained --native history')
    args.stage.mkdir()
    binary, bundle = reuse(args.binary) if args.binary else build(args.xls, args.stage, args.source, args.checks_result)
    if not args.build_only:
        witness(binary, bundle, args.native, args.stage)


if __name__ == '__main__':
    main()
