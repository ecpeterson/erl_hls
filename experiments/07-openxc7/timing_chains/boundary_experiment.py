#!/usr/bin/env python3
"""Change selected aggregate boundaries in a verified dedicated-actor IR bundle."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

from architecture import sha


def schedule_cycles(path: Path) -> dict[str, dict[str, int]]:
    """Read node-to-stage assignments from the frozen compiler's schedule report."""
    result = {}
    for entry in re.split(r'^schedules \{\s*$', path.read_text(), flags=re.M)[1:]:
        name = re.search(r'function: "([^"]+)"', entry)[1]
        nodes, stage = {}, None
        for line in entry.splitlines():
            match = re.fullmatch(r'\s*stage: (\d+)', line)
            if match:
                stage = int(match[1])
            match = re.fullmatch(r'\s*node: "([^"]+)"', line)
            if match:
                if stage is None:
                    raise ValueError('node without a schedule stage')
                nodes[match[1]] = stage
        result[name] = nodes
    if not result:
        raise ValueError('empty schedule report')
    return result


def audit_schedules(reference: Path, stage: Path, variant: str) -> dict:
    """Require FIFO-only edits to preserve schedules and II edits to affect only phi actors."""
    old = schedule_cycles(reference / 'schedule.textproto')
    new = schedule_cycles(stage / 'schedule.textproto')
    if old.keys() != new.keys():
        raise AssertionError('process set changed')
    changed = {name: sum(old[name].get(node) != cycle for node, cycle in new[name].items())
               for name in old if old[name] != new[name]}
    allowed = {name for name in old if name.startswith('__phi_halo_cell__DedicatedActor_')}
    if variant.startswith('actor-ii2'):
        if set(changed) - allowed:
            raise AssertionError('recurrence edit changed an unexpected process schedule')
    elif changed:
        raise AssertionError('FIFO edit changed process scheduling')
    return {'changed_node_cycles': changed, 'unchanged_procs': sorted(set(old) - set(changed))}


def prepare(reference: Path, stage: Path, variant: str) -> None:
    """Derive a fresh candidate, recording every altered channel or recurrence arc."""
    records = json.loads((reference / 'commands.json').read_text())
    manifest = json.loads((reference / 'phi_decoder_profile.build.json').read_text())
    if manifest['profile'].get('architecture') != 'dedicated':
        raise ValueError('expected a dedicated-actor baseline')
    command = list(next(r for r in records if r['label'] == 'codegen')['command'])
    table = Path(next(s.split('=', 1)[1] for s in command if s.startswith('--xc7_delay_table=')))
    campaign = Path(__file__).resolve().parents[1] / 'results/architecture-2026-09-26/measurements.json'
    expected_table = json.loads(campaign.read_text())['timing_table_sha256']
    if (sha(Path(command[0])) != manifest['tools']['codegen_main'] or sha(table) != expected_table):
        raise ValueError('compiler or calibration differs from the baseline')
    for label, filename in (('opt', 'phi_decoder_profile.opt.ir'),
                            ('codegen', 'phi_decoder_profile.v')):
        record = next(row for row in records if row['label'] == label)
        if record['exit'] != 0 or sha(reference / filename) != record['output_sha256']:
            raise ValueError('reference output does not match its successful command')
    stage.mkdir(parents=True, exist_ok=False)
    for source in reference.glob('*.x'):
        shutil.copyfile(source, stage / source.name)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(reference / name, stage / name)
    text = (reference / 'phi_decoder_profile.opt.ir').read_text()
    changes = []
    channels = {'collector-register': r'_scheduler_[23]_aggregate',
                'actor-register': r'_dedicated_aggregate__[01]',
                'actor-ii2-batch-register': r'_phi_[xz]_reduction_batch__0'}
    if variant in channels:
        channel = channels[variant]
        pattern = rf'^  chan {channel}\([^\n]+$'
        def register(match: re.Match) -> str:
            """Record a two-entry FIFO with no combinational forward bypass."""
            old = match[0]
            expected_depth = 0 if variant == 'collector-register' else 1
            if f'fifo_depth={expected_depth}, bypass=true' not in old:
                raise ValueError('unexpected original FIFO policy')
            new = re.sub(r'fifo_depth=\d+, bypass=true, register_push_outputs=\w+',
                         'fifo_depth=2, bypass=false, register_push_outputs=true', old)
            changes.append({'before': old, 'after': new})
            return new
        text, count = re.subn(pattern, register, text, flags=re.M)
        if count != 2:
            raise ValueError(f'expected two channel declarations, found {count}')
    if variant.startswith('actor-ii2'):
        def label_actor(match: re.Match) -> str:
            """Label phi state reads; all other feedback arcs retain one-cycle limits."""
            old = match[0]
            if variant == 'actor-ii2-field-only':
                pattern = r'\bstate_read\(state_element=(__state_4_[01]),'
                new, count = re.subn(pattern, r'state_read(label="phi_actor", state_element=\1,', old)
                if count != 2:
                    raise ValueError('expected the two fixed-point field reads')
            else:
                new, count = re.subn(r'\bstate_read\(', 'state_read(label="phi_actor", ', old)
            if count == 0:
                raise ValueError('missing phi state recurrence')
            changes.append({'proc': old.split('<', 1)[0], 'labeled_nodes': count})
            return new
        text, count = re.subn(r'^proc __phi_halo_cell__DedicatedActor_[^\n]+\{\n.*?^\}',
                             label_actor, text, flags=re.M | re.S)
        if count != 2:
            raise ValueError('expected two phi actor specializations')
    elif variant not in channels:
        raise ValueError(variant)
    (stage / 'phi_decoder_profile.opt.ir').write_text(text)
    if variant.startswith('actor-ii2'):
        # The frozen parser reads a next_value label before parsing its value,
        # losing write labels. Match every write to the labeled phi reads.
        command = [s for s in command if not s.startswith('--worst_case_throughput=')]
        command[-1:-1] = ['--worst_case_throughput=2', '--default_arc_worst_case_throughput=1',
                          '--arc_worst_case_throughput=*:phi_actor=2']
    command.insert(-1, '--output_schedule_path=' + str(stage / 'schedule.textproto'))
    evidence = {'variant': variant, 'reference': str(reference), 'changes': changes,
                'reference_ir_sha256': sha(reference / 'phi_decoder_profile.opt.ir'),
                'ir_sha256': sha(stage / 'phi_decoder_profile.opt.ir'),
                'compiler_sha256': sha(Path(command[0])), 'command': command}
    (stage / 'boundary.json').write_text(json.dumps(evidence, indent=2) + '\n')
    start = time.monotonic()
    with (stage / 'phi_decoder_profile.v').open('w') as out, (stage / 'codegen.log').open('w') as err:
        result = subprocess.run(command, cwd=stage, stdout=out, stderr=err, timeout=1200)
    evidence.update(exit=result.returncode, seconds=time.monotonic() - start,
                    rtl_sha256=sha(stage / 'phi_decoder_profile.v'))
    (stage / 'boundary.json').write_text(json.dumps(evidence, indent=2) + '\n')
    if result.returncode:
        raise RuntimeError('codegen failed; retained diagnostics in ' + str(stage))
    if sha(Path(command[0])) != evidence['compiler_sha256'] or sha(table) != expected_table:
        raise RuntimeError('compiler or calibration changed while scheduling')
    evidence['schedule_check'] = audit_schedules(reference, stage, variant)
    (stage / 'boundary.json').write_text(json.dumps(evidence, indent=2) + '\n')
    manifest['boundary_experiment'] = evidence
    manifest['rtl'] = {name: sha(stage / name) for name in manifest['rtl']}
    (stage / 'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(variant, 'compiled', flush=True)


def main() -> None:
    """Require a verified dedicated baseline and an unused output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--variant', choices=('collector-register', 'actor-register', 'actor-ii2',
                        'actor-ii2-field-only', 'actor-ii2-batch-register'), required=True)
    args = parser.parse_args()
    prepare(args.reference, args.stage, args.variant)


if __name__ == '__main__':
    main()
