#!/usr/bin/env python3
"""Experiment with RAM payload storage in existing scheduler completion FIFOs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from fifo_experiment import MODULE, compare, ports, sha
import sys
sys.path.append(str(Path(__file__).resolve().parents[3] / "tools/hls_fabric"))
from prove_fifo import run as bounded_compare
from types import SimpleNamespace


from completion_fifo import payload_memory, transform


def prepare(reference: Path, stage: Path, cycle_compare: bool) -> dict:
    """Derive a separate artifact; never mutate a compiler cache or reference bundle."""
    rtl, audit = transform((reference/'phi_decoder_profile.v').read_text())
    source = json.loads((reference/'phi_decoder_profile.build.json').read_text())
    stage.mkdir(parents=True, exist_ok=False)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(reference/name, stage/name)
    (stage/'phi_decoder_profile.v').write_text(rtl)
    manifest = {key: source[key] for key in ('schema', 'profile', 'tools', 'stdlib', 'ram_configuration')}
    manifest['rtl'] = {name: sha(stage/name) for name in
                      ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')}
    manifest['completion_storage_experiment'] = dict(audit,
        reference_manifest_sha256=sha(reference/'phi_decoder_profile.build.json'),
        transform_sha256=sha(Path(__file__)), capacity_changed=False,
        latency_changed=False, invalid_payload_reset=False)
    (stage/'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if cycle_compare:
        compare(reference, stage, manifest['profile'])
    return manifest


def map_fifos(reference: Path, candidate: Path, stage: Path, yosys: Path) -> dict:
    """Map every changed FIFO shape in isolation, recording raw primitive counts."""
    old = {m[1]: m[0] for m in MODULE.finditer(reference.read_text())}
    new = {m[1]: m[0] for m in MODULE.finditer(candidate.read_text())}
    changed = [name for name in old if old[name] != new[name]]
    if not changed or any(not name.startswith('fifo_for_depth_') for name in changed):
        raise ValueError('expected a FIFO-only comparison')
    seen, results = set(), []
    stage.mkdir(parents=True, exist_ok=False)
    for name in changed:
        shape = (re.search(r'fifo_for_depth_(\d+)_', name)[1], ports(old[name])['push_data'])
        if shape in seen:
            continue
        seen.add(shape)
        for label, source in (('reference', old[name]), ('candidate', new[name])):
            run = stage / f'{len(seen)}-{label}'
            run.mkdir()
            (run/'fifo.v').write_text(source.replace('module '+name+'(', 'module completion_fifo(')+'\n')
            script = '''read_verilog -sv fifo.v
synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top completion_fifo
check -assert
scc -expect 0
tee -o stat.json stat -json
write_verilog mapped.v
'''
            (run/'map.ys').write_text(script)
            command = [str(yosys), '-Q', '-T', '-s', 'map.ys']
            with (run/'map.log').open('w') as log:
                subprocess.run(command, cwd=run, stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=600)
            cells = json.loads((run/'stat.json').read_text())['design']['num_cells_by_type']
            results.append({'module': name, 'shape': shape, 'variant': label,
                'source_sha256': sha(run/'fifo.v'), 'script_sha256': sha(run/'map.ys'),
                'command': command, 'primitives': cells})
            print(label, shape, cells, flush=True)
    report = {'yosys_sha256': sha(yosys), 'reference_sha256': sha(reference),
        'candidate_sha256': sha(candidate), 'runs': results,
        'scope': 'Isolated FIFO mapping; no placement, timing or complete-device area claim.'}
    (stage/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def check_lanes(reference: Path, candidate: Path, stage: Path, yosys: Path) -> dict:
    """Check each changed ring for twelve symbolic cycles with an eight-bit payload.

    This bounded storage/control witness does not establish full-width equivalence.
    Full-width application and mapped-primitive simulations are separate checks.
    """
    old = {m[1]: m[0] for m in MODULE.finditer(reference.read_text())}
    new = {m[1]: m[0] for m in MODULE.finditer(candidate.read_text())}
    stage.mkdir(parents=True, exist_ok=False)
    results = []
    for name in old:
        if old[name] == new[name]:
            continue
        width = int(ports(old[name])['push_data'].split('[')[1].split(':')[0])+1
        depth = int(re.search(r'fifo_for_depth_(\d+)_', name)[1])
        if width <= 8:
            raise ValueError('payload reduction needs an original width above eight')
        run = stage/str(len(results))
        run.mkdir()
        for label, body in (('reference', old[name]), ('candidate', new[name])):
            (run/(label+'.v')).write_text(body.replace(f'[{width-1}:0]', '[7:0]')+'\n')
        bounded_compare(SimpleNamespace(baseline=run/'reference.v',
            candidate=run/'candidate.v', yosys=yosys, stage=run/'symbolic',
            width=8, depth=depth))
        results.append({'module': name, 'original_width': width,
                        'witness': str(run.relative_to(stage)/'symbolic/result.json')})
    if not results:
        raise ValueError('no changed FIFO modules')
    report = {'reference_sha256': sha(reference), 'candidate_sha256': sha(candidate),
        'scope': 'Eight-bit payload abstraction; twelve symbolic cycles including unrestricted later reset.',
        'runs': results}
    (stage/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def check_mapped(stage: Path, yosys: Path) -> None:
    """Compare actual mapped RAM primitives to both full-width reference FIFO shapes."""
    report = json.loads((stage/'report.json').read_text())
    library = yosys.parent.parent/'share/yosys/xilinx/cells_sim.v'
    bench = Path(__file__).with_name('completion_fifo_tb.sv').resolve()
    checks = []
    for index in range(1, 1+len(report['runs'])//2):
        reference, candidate = stage/f'{index}-reference', stage/f'{index}-candidate'
        source = (reference/'fifo.v').read_text().replace('module completion_fifo(', 'module reference_fifo(')
        (candidate/'reference.v').write_text(source)
        width = int(ports(source)['push_data'].split('[')[1].split(':')[0])+1
        commands = [
            ['iverilog', '-g2012', '-s', 'completion_fifo_tb', f'-Pcompletion_fifo_tb.WIDTH={width}',
             '-o', 'mapped.vvp', str(bench), 'reference.v', 'mapped.v', str(library)],
            ['vvp', 'mapped.vvp']]
        for label, command in zip(('mapped-compile', 'mapped-check'), commands):
            with (candidate/(label+'.log')).open('w') as log:
                subprocess.run(command, cwd=candidate, stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=120)
        message = (candidate/'mapped-check.log').read_text()
        if 'PASS:' not in message:
            raise ValueError('mapped FIFO witness did not finish')
        (candidate/'mapped.vvp').unlink()
        print(message, end='')
        checks.append({'width': width, 'commands': commands,
                       'log_sha256': sha(candidate/'mapped-check.log')})
    (stage/'mapped-checks.json').write_text(json.dumps({'checks': checks,
        'testbench_sha256': sha(bench), 'primitive_library_sha256': sha(library)}, indent=2)+'\n')


def main() -> None:
    """Require a retained reference and fresh experiment destination."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--compare', action='store_true')
    parser.add_argument('--yosys', type=lambda p: Path(p).resolve(),
                        help='also run bounded payload-lane checks and isolated synthesis')
    args = parser.parse_args()
    result = prepare(args.reference, args.stage, args.compare)
    if args.yosys:
        reference = args.reference/'phi_decoder_profile.v'
        candidate = args.stage/'phi_decoder_profile.v'
        check_lanes(reference, candidate, args.stage/'lane-checks', args.yosys)
        map_fifos(reference, candidate, args.stage/'fifo-mapping', args.yosys)
        check_mapped(args.stage/'fifo-mapping', args.yosys)
    print(json.dumps(result['completion_storage_experiment'], indent=2))


if __name__ == '__main__':
    main()
