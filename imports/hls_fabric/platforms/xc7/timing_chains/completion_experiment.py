#!/usr/bin/env python3
"""Isolate generated completion sharing in a retained small-core executor."""
import argparse
import difflib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

from architecture import sha
from executor_arrival import prepare as compile_executor


def function(text: str, name: str) -> str:
    """Require one complete generated function with an unindented closing brace."""
    matches = re.findall(r'^(?:pub )?fn ' + re.escape(name) + r'\(.*?^}', text, re.M | re.S)
    if len(matches) != 1:
        raise ValueError('expected one function: ' + name)
    return matches[0]


def prepare(args: argparse.Namespace) -> Path:
    """Change only aggregate acceptance and dispatch; freeze all other source/RTL."""
    manifest = json.loads((args.rtl_reference / 'phi_decoder_profile.build.json').read_text())
    baseline = manifest['executor_arrival_experiment']
    table = next(s.split('=', 1)[1] for s in baseline['command'] if s.startswith('--xc7_delay_table='))
    if (sha(args.codegen) != manifest['tools']['codegen_main'] or
            sha(args.table) != baseline['inputs'][table] or
            not baseline['cell_only'] or baseline['additional_delay_ps'] != 0 or
            baseline.get('kept_product_inputs', [])):
        raise ValueError('require the unchanged cell-only, zero-allowance baseline tools and schedule')
    stage = args.stage / 'sources'
    stage.mkdir(parents=True, exist_ok=False)
    for source in args.reference.glob('*.x'):
        shutil.copyfile(source, stage / source.name)
    for name in ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v',
                 'phi_decoder_profile.json', 'phi_decoder_profile.build.json'):
        shutil.copyfile(args.rtl_reference / name, stage / name)
    source = stage / 'phi_halo_cell.x'
    old, generated = source.read_text(), args.generated.read_text()
    helper = function(old, 'shared_machine_aggregate')
    new_helper = function(generated, 'shared_machine_accept_aggregate')
    old_execute, new_execute = (function(text, 'shared_execute') for text in (old, generated))
    old_dispatch = old_execute[old_execute.index('  let dispatched = '):old_execute.index('  let entered = ')]
    new_dispatch = new_execute[new_execute.index('  let completion_machine = '):new_execute.index('  let entered = ')]
    new = old.replace(helper, new_helper).replace(old_dispatch, new_dispatch)
    if new == old or new.count(new_helper) != 1 or new.count(new_dispatch) != 1:
        raise ValueError('unexpected source layout')
    source.write_text(new)
    (stage / 'source.patch').write_text(''.join(difflib.unified_diff(
        old.splitlines(True), new.splitlines(True), fromfile=source.name, tofile=source.name)))
    evidence = {'reference': str(args.reference), 'rtl_reference': str(args.rtl_reference),
                'generated': {str(args.generated): sha(args.generated)},
                'source_inputs': {p.name: sha(p) for p in args.reference.glob('*.x')},
                'sources': {p.name: sha(p) for p in stage.glob('*.x')},
                'rtl': sha(args.rtl_reference / 'phi_decoder_profile.v')}
    (stage / 'inputs.json').write_text(json.dumps(evidence, indent=2) + '\n')
    return stage


def build(stage: Path, reference: Path) -> None:
    """Replay the frozen whole-application conversion/optimization before extraction."""
    records = json.loads((reference / 'commands.json').read_text())[:2]
    tools = json.loads((stage / 'phi_decoder_profile.build.json').read_text())['tools']
    if [r['label'] for r in records] != ['ir', 'opt']:
        raise ValueError('expected recorded IR and optimization commands')
    for record, name in zip(records, ('phi_decoder_profile.ir', 'phi_decoder_profile.opt.ir')):
        binary = Path(record['command'][0])
        if sha(binary) != tools[binary.name]:
            raise ValueError('converter/optimizer differs from the selected baseline')
        started = time.monotonic()
        with (stage / name).open('w') as out, (stage / (record['label'] + '.log')).open('w') as err:
            result = subprocess.run(record['command'], cwd=stage, stdout=out, stderr=err, timeout=1200)
        record.update(exit=result.returncode, seconds=time.monotonic() - started,
                      output_sha256=sha(stage / name))
        (stage / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
        result.check_returncode()


def main() -> None:
    """Require frozen source/RTL controls and the newly generated actor source."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'rtl-reference', 'generated', 'stage', 'codegen', 'table'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    stage = prepare(args)
    build(stage, args.reference)
    compile_executor(argparse.Namespace(
        reference=stage, stage=args.stage / 'compiled', codegen=args.codegen, table=args.table,
        executor='__phi_halo_cell__SharedExecutor_0_next', channel='_request_in',
        delay_ps=0, symmetric=False, cell_only=True, keep_product_inputs=False))


if __name__ == '__main__':
    main()
