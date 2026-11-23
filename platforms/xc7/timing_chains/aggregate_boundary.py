#!/usr/bin/env python3
"""Screen XLS aggregate FIFOs without rescheduling any application proc RTL."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from architecture import sha
from module_substitution import substitute


def instances(text: str) -> dict[str, str]:
    """Find final scheduler aggregate FIFOs, excluding aggregate-source mux inputs."""
    return {instance: module for module, instance in re.findall(
        r'\b(\w+) (materialized_fifo_fifo__scheduler_\d+_aggregate_) \(', text)}


def main() -> None:
    """Retain the changed channel declarations, generated FIFO RTL and input hashes."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'ir', 'command', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=False)
    old = (args.reference / 'phi_decoder_profile.v').read_text()
    selected = instances(old)
    if not selected:
        raise ValueError('no aggregate FIFOs')
    source = args.ir.read_text()
    changes = []

    def buffer(match: re.Match) -> str:
        """Add one bypassing slot with occupancy-only upstream readiness."""
        before = match[0]
        if 'fifo_depth=0' not in before or 'register_push_outputs=false' not in before:
            raise ValueError('expected an unbuffered aggregate channel')
        after = before.replace('fifo_depth=0', 'fifo_depth=1').replace(
            'register_push_outputs=false', 'register_push_outputs=true')
        changes.append({'before': before.strip(), 'after': after.strip()})
        return after

    candidate = re.sub(r'^  chan _scheduler_\d+_aggregate\(.*$', buffer, source, flags=re.M)
    if len(changes) != len(selected):
        raise ValueError('IR and RTL aggregate channels differ')
    ir = args.stage / args.ir.name
    ir.write_text(candidate)
    command = json.loads(args.command.read_text())
    command[-1] = str(ir)
    generated = args.stage / 'generated.v'
    with generated.open('w') as out, (args.stage / 'codegen.log').open('w') as err:
        subprocess.run(command, cwd=args.stage, stdout=out, stderr=err, check=True, timeout=600)
    new = generated.read_text()
    replacements = instances(new)
    if replacements.keys() != selected.keys():
        raise ValueError('generated aggregate instances changed')
    modules = []
    for instance, old_type in selected.items():
        if len(re.findall(r'\b' + re.escape(old_type) + r' \w+ \(', old)) != 1:
            raise ValueError('FIFO type is shared with an unselected channel')
        new_type = replacements[instance]
        module = re.search(r'^module ' + re.escape(new_type) + r'\(.*?^endmodule', new, re.M | re.S)[0]
        modules.append(module.replace('module ' + new_type + '(', 'module ' + old_type + '(', 1))
    replacement = args.stage / 'replacement.v'
    replacement.write_text('\n\n'.join(modules) + '\n')
    substitute(args.reference, replacement, args.stage / 'compiled',
               '|'.join(map(re.escape, selected.values())))
    witness = Path(__file__).with_name('aggregate_fifo_tb.sv')
    simulation = args.stage / 'fifo.vvp'
    subprocess.run(['iverilog', '-g2012', '-s', 'aggregate_fifo_tb',
                    '-DDUT=' + next(iter(selected.values())), '-o', str(simulation),
                    str(witness), str(replacement)], check=True, timeout=60)
    with (args.stage / 'fifo-witness.log').open('w') as log:
        subprocess.run(['vvp', str(simulation)], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=60)
    simulation.unlink()
    (args.stage / 'inputs.json').write_text(json.dumps({
        'inputs': {str(p): sha(p) for p in (args.ir, args.command, Path(command[0]), witness)},
        'command': command, 'channels': changes, 'instances': selected,
        'scope': 'only final aggregate FIFO module bodies replaced; all application procs unchanged'
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
