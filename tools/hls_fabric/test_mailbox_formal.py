#!/usr/bin/env python3
"""SAT-check mailbox selection and inductive metadata contracts at explicit sizes."""
from compiler_paths import compiler_root
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    """Fingerprint exact sources, binaries and solver evidence."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv: list[str], stage: Path, output: str) -> None:
    """Retain each bounded solver/compiler invocation and fail on any error."""
    (stage / (output + '.command.json')).write_text(json.dumps(argv) + '\n')
    with (stage / output).open('w') as out, (stage / (output + '.stderr')).open('w') as err:
        subprocess.run(argv, stdout=out, stderr=err, check=True, timeout=180)


def prove(source: str, args: argparse.Namespace, name: str, expected: str = 'unsat') -> dict:
    """Prove a combinational proposition for all defined input bits, without sampling."""
    stage = args.stage / name
    stage.mkdir(parents=True, exist_ok=True)
    (stage / 'contract.x').write_text('import mailbox_refinement;\n' + source)
    started = time.monotonic()
    run([str(args.xls / 'ir_converter_main'), '--top=contract', '--warnings_as_errors=false',
         '--dslx_path=' + str(ROOT / 'test_data') + ':' + str(args.library) + ':' + str(ROOT / 'apps/hls_lowering/priv/xls/lib') + ':' + str(compiler_root('test') / 'priv/xls/lib'),
         '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), str(stage / 'contract.x')], stage, 'contract.ir')
    run([str(args.xls / 'opt_main'), str(stage / 'contract.ir')], stage, 'contract.opt.ir')
    run([str(args.xls / 'codegen_main'), '--generator=combinational', '--module_name=contract',
         '--use_system_verilog=false', str(stage / 'contract.opt.ir')], stage, 'contract.v')
    script = stage / 'proof.ys'
    script.write_text(f'read_verilog -sv "{stage / "contract.v"}"\n'
                      'prep -top contract -flatten\nopt\n'
                      'sat ' + ('-verify ' if expected == 'unsat' else '') +
                      '-prove out 1 -set-def-inputs -show-inputs\n')
    run([str(args.yosys), '-Q', '-T', '-s', str(script)], stage, 'proof.log')
    verdict = ('no model found: SUCCESS!' if expected == 'unsat' else 'model found: FAIL!')
    if 'SAT proof finished - ' + verdict not in (stage / 'proof.log').read_text():
        raise AssertionError('missing expected solver verdict')
    return {'name': name, 'method': 'SAT', 'verdict': expected,
            'seconds': time.monotonic() - started,
            'artifacts': {p.name: digest(p) for p in stage.iterdir() if p.is_file()}}


def main() -> None:
    """Record quantified domains separately from the number of parameter instances."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--yosys', type=Path, default=Path('yosys'))
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), default=ROOT / '_build/mailbox-formal')
    parser.add_argument('--library', type=lambda p: Path(p).resolve(), default=ROOT / 'apps/hls_lowering/priv/xls/lib')
    args = parser.parse_args()
    args.yosys = Path(shutil.which(str(args.yosys)) or args.yosys).resolve()
    inputs = [args.library / 'mailbox.x', ROOT / 'test_data/mailbox_refinement.x', Path(__file__),
              args.yosys, *[args.xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')],
              *sorted((ROOT / 'apps/hls_lowering/priv/xls/lib').glob('*.x')),
              *sorted((compiler_root('test') / 'priv/xls/lib').glob('*.x')),
              *sorted((args.xls / 'xls/dslx/stdlib').rglob('*.x'))]
    identities = {str(p): digest(p) for p in inputs}
    results = []
    for actors, depth in ((1, 1), (2, 3), (2, 5), (3, 8)):
        row = prove(f'''pub fn contract(order: u8[{depth}][{actors}], occupied: u8[{actors}],
    postponed: bool[{depth}][{actors}], actor: u32) -> bool {{
  mailbox_refinement::selection(order, occupied, postponed, actor)
}}
''', args, f'selection-{actors}-{depth}')
        row.update(actors=actors, depth=depth, quantification='all legal row states, masks and actor indices')
        results.append(row)
        print('PASS:', row['name'], row['quantification'], flush=True)
        row = prove(f'''pub fn contract(order: u8[{depth}], occupied: u8,
    postponed: bool[{depth}], operation: u5) -> bool {{
  mailbox_refinement::transition(order, occupied, postponed, operation)
}}
''', args, f'induction-{depth}')
        row.update(depth=depth, quantification='base and all invariant states/actions; unbounded metadata histories')
        results.append(row)
        print('PASS:', row['name'], row['quantification'], flush=True)
    for depth in (1, 3, 5):
        row = prove(f'''pub fn contract(order: u8[{depth}], occupied: u8,
    postponed: bool[{depth}], operation: u6) -> bool {{
  mailbox_refinement::committed_transition(order, occupied, postponed, operation)
}}
''', args, f'committed-induction-{depth}')
        row.update(depth=depth, quantification='all invariant rows and concurrent retirement/admission outcomes')
        results.append(row)
        print('PASS:', row['name'], row['quantification'], flush=True)
    for depth in (1, 24, 255):
        row = prove(f'''pub fn contract(used: bool[{depth}]) -> bool {{
  mailbox_refinement::allocation(used)
}}
''', args, f'allocation-{depth}')
        row.update(depth=depth, quantification='all physical occupancy bitmaps; exact lowest free slot')
        results.append(row)
        print('PASS:', row['name'], row['quantification'], flush=True)
    for actors, depth, stride, rows in ((1, 1, 1, 2), (6, 24, 32, 256),
                                      (5, 24, 24, 128), (5, 5, 5, 32), (3, 255, 256, 1024)):
        row = prove(f'''pub fn contract(actor: u32, index: u8, other: u32, other_index: u8) -> bool {{
  mailbox_refinement::row_addressing<u32:{actors}, u32:{depth}, u32:{stride}, u32:{rows}>(
    actor, index, other, other_index)
}}
''', args, f'addressing-{actors}-{depth}')
        row.update(actors=actors, depth=depth, stride=stride, rows=rows,
                   quantification='all legal actor/index pairs; unique addresses within unchanged RAM depth')
        results.append(row)
        print('PASS:', row['name'], row['quantification'], flush=True)
    # A latest-first selector must fail even though it still chooses valid mail.
    mutant = copy.copy(args)
    mutant.library = args.stage / 'wrong-priority'
    mutant.library.mkdir(exist_ok=True)
    original = (args.library / 'mailbox.x').read_text()
    wrong = original.replace('one_hot(requests, true)', 'one_hot(requests, false)')
    if wrong == original:
        raise AssertionError('missing priority encoder for negative control')
    (mutant.library / 'mailbox.x').write_text(wrong)
    negative = prove('''pub fn contract(order: u8[3][2], occupied: u8[2],
    postponed: bool[3][2], actor: u32) -> bool {
  mailbox_refinement::selection(order, occupied, postponed, actor)
}
''', mutant, 'negative-priority', expected='sat')
    print('PASS: reversed priority produces a counterexample', flush=True)
    # A retired slot left marked occupied must violate the inductive bitmap law.
    stuck = copy.copy(args)
    stuck.library = args.stage / 'stuck-used-bit'
    stuck.library.mkdir(exist_ok=True)
    wrong = original.replace('let used = if outcome.consume {', 'let used = if false {')
    if wrong == original:
        raise AssertionError('missing retirement bitmap update for negative control')
    (stuck.library / 'mailbox.x').write_text(wrong)
    negative_bitmap = prove('''pub fn contract(order: u8[3], occupied: u8,
    postponed: bool[3], operation: u6) -> bool {
  mailbox_refinement::committed_transition(order, occupied, postponed, operation)
}
''', stuck, 'negative-stuck-used-bit', expected='sat')
    print('PASS: missing bitmap retirement produces a counterexample', flush=True)
    # Ignoring postponement must fail readiness even if queue membership is valid.
    premature = copy.copy(args)
    premature.library = args.stage / 'postponed-ready'
    premature.library.mkdir(exist_ok=True)
    wrong = original.replace('!(postponed_row as uN[DEPTH])', 'all_ones!<uN[DEPTH]>()')
    if wrong == original:
        raise AssertionError('missing readiness mask for negative control')
    (premature.library / 'mailbox.x').write_text(wrong)
    negative_ready = prove('''pub fn contract(order: u8[3], occupied: u8,
    postponed: bool[3], operation: u6) -> bool {
  mailbox_refinement::committed_transition(order, occupied, postponed, operation)
}
''', premature, 'negative-postponed-ready', expected='sat')
    print('PASS: counting postponed messages as ready produces a counterexample', flush=True)
    if identities != {str(p): digest(p) for p in inputs}:
        raise AssertionError('formal inputs changed while proving')
    (args.stage / 'summary.json').write_text(json.dumps({'schema': 1,
        'inputs': identities, 'claims': results, 'negative_control': negative,
        'negative_occupancy_control': negative_bitmap,
        'negative_readiness_control': negative_ready,
        'limits': ['fixed parameter instances, not a machine-checked theorem for every depth',
                   'metadata transitions only; excludes RAM payloads, in-flight scheduling and liveness',
                   'trusts DSLX/IR/codegen, Yosys translation and SAT solver']}, indent=2) + '\n')


if __name__ == '__main__':
    main()
