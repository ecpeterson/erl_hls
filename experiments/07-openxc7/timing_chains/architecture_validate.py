#!/usr/bin/env python3
"""Check architecture variants against the retained BEAM oracle and reset/stall witness."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def command(argv: list[str], stage: Path, name: str) -> None:
    """Retain diagnostics and bound each compiler or simulation invocation."""
    with (stage / (name + '.log')).open('w') as log:
        subprocess.run(argv, cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=600)


def validate(stage: Path, reference: Path) -> None:
    """Match complete normal/stalled event sequences and independent reset prefixes."""
    spec = importlib.util.spec_from_file_location('decoder_profiles', ROOT / 'tools/test_decoder_profiles.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    expected = helper.sequences(json.loads((reference / 'oracle.json').read_text()))
    files = [str(stage / n) for n in ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')]
    samples = []
    for stalled in (0, 1):
        run = stage / f'stalled-{stalled}'
        run.mkdir(exist_ok=True)
        command(['iverilog', '-g2012', '-s', 'phi_decoder_profile_tb', '-o', 'sim.vvp',
                 '-Pphi_decoder_profile_tb.WIDTH=2', '-Pphi_decoder_profile_tb.HEIGHT=1',
                 f'-Pphi_decoder_profile_tb.STALL_OUTPUTS={stalled}',
                 str(ROOT / 'test/rtl/phi_decoder_profile_tb.sv'), *files], run, 'compile')
        command(['vvp', 'sim.vvp'], run, 'simulation')
        actual = helper.sequences(helper.rtl_events(run / 'phi_decoder_profile.events'))
        if actual != expected:
            raise AssertionError(f'{stage.name}: stalled={stalled}: event sequence differs from BEAM')
        log = (run / 'simulation.log').read_text()
        if 'PASS: decoder-only' not in log:
            raise AssertionError('missing complete witness')
        samples.append({'stalled': bool(stalled), 'events': sum(map(len, actual.values())),
                        'cycles_per_step': float(re.search(r'cycles_per_step=([0-9.]+)', log)[1]),
                        'metrics': [s for s in log.splitlines() if s.startswith('PROFILE_')]})
        (run / 'sim.vvp').unlink()
    text = '\n'.join((reference / 'compiled' / n).read_text() for n in
                     ('phi_decoder_profile.v', 'phi_decoder_profile_top.v'))
    modules = re.findall(r'^module\s+(\w+)\s*\(', text, re.M)
    text = re.sub(r'\b(?:' + '|'.join(map(re.escape, modules)) + r')\b',
                  lambda m: 'baseline_' + m[0], text)
    (stage / 'reference.v').write_text(text)
    command(['iverilog', '-g2012', '-s', 'phi_compare_tb', '-o', 'compare.vvp',
             '-Pphi_compare_tb.WIDTH=2', '-Pphi_compare_tb.HEIGHT=1', '-Pphi_compare_tb.CYCLE_EXACT=0',
             str(ROOT / 'experiments/07-openxc7/phi_compare_tb.sv'), 'reference.v', *files], stage, 'compare-compile')
    command(['vvp', 'compare.vvp'], stage, 'compare')
    if 'PASS:' not in (stage / 'compare.log').read_text():
        raise AssertionError('missing reset witness')
    (stage / 'comparison.json').write_text(json.dumps({'samples': samples,
        'reset_stalls': (stage / 'compare.log').read_text()}, indent=2) + '\n')
    for name in ('reference.v', 'compare.vvp'):
        (stage / name).unlink()
    print(json.dumps(samples, indent=2), flush=True)


def main() -> None:
    """Require the candidate and original prepared oracle bundle."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    parser.add_argument('reference', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    validate(args.stage, args.reference)


if __name__ == '__main__':
    main()
