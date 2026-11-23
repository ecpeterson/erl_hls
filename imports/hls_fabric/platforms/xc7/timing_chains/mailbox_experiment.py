#!/usr/bin/env python3
"""Replay mailbox selection variants while replacing only shared-service RTL."""
import argparse
import difflib
import json
from pathlib import Path
import shutil
import subprocess
import time

from architecture import sha
from completion_experiment import build
from module_substitution import substitute


def main() -> None:
    """Freeze source/tool identities, compile the variant and preserve unrelated modules."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'rtl-reference', 'library', 'codegen-command', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--parallel-rows', action='store_true')
    args = parser.parse_args()
    source = args.stage / 'sources'
    source.mkdir(parents=True, exist_ok=False)
    for path in args.reference.glob('*.x'):
        shutil.copyfile(path, source / path.name)
    shutil.copyfile(args.rtl_reference / 'phi_decoder_profile.build.json',
                    source / 'phi_decoder_profile.build.json')
    shutil.copyfile(args.library, source / 'mailbox.x')
    if args.parallel_rows:
        old = ('mailbox::select(\n            state.order[read_slot], state.occupied[read_slot],\n'
               '            state.postponed[read_slot])')
        new = 'mailbox::select_actor(\n            state.order, state.occupied, state.postponed, read_slot)'
        for name in ('phi_halo_cell.x', 'phi_syndrome_replay_cell.x'):
            path = source / name
            text = path.read_text()
            if text.count(old) != 1:
                raise ValueError('unexpected service selection source: ' + name)
            path.write_text(text.replace(old, new))
    patches = []
    for path in source.glob('*.x'):
        patches.extend(difflib.unified_diff((args.reference / path.name).read_text().splitlines(True),
            path.read_text().splitlines(True), fromfile=path.name, tofile=path.name))
    (args.stage / 'source.patch').write_text(''.join(patches))
    inputs = {str(p): sha(p) for p in [*args.reference.glob('*.x'), args.library, args.codegen_command]}
    (args.stage / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    build(source, args.reference)
    command = json.loads(args.codegen_command.read_text())
    manifest = json.loads((source / 'phi_decoder_profile.build.json').read_text())
    if sha(Path(command[0])) != manifest['tools']['codegen_main']:
        raise ValueError('codegen differs from baseline')
    (source / 'codegen-command.json').write_text(json.dumps(command, indent=2) + '\n')
    started = time.monotonic()
    with (source / 'generated.v').open('w') as out, (source / 'codegen.log').open('w') as err:
        subprocess.run(command, cwd=source, stdout=out, stderr=err, check=True, timeout=1200)
    (source / 'codegen-result.json').write_text(json.dumps({'command': command, 'exit': 0,
        'seconds': time.monotonic() - started, 'rtl_sha256': sha(source / 'generated.v')}, indent=2) + '\n')
    if inputs != {p: sha(Path(p)) for p in inputs}:
        raise ValueError('inputs changed during experiment')
    substitute(args.rtl_reference, source / 'generated.v', args.stage / 'compiled', '.*SharedService.*')


if __name__ == '__main__':
    main()
