#!/usr/bin/env python3
"""Prove automatic clause-IR cancellation through ordinary lowering, DSLX and XLS."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    """Bind exact source, compiled code and tool bytes to this check."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], stage: Path, label: str, output: str | None = None) -> int:
    """Retain each command and diagnostics; keep generated IR separate from stderr."""
    (stage / f'{label}.command.json').write_text(json.dumps(command) + '\n')
    with (stage / f'{label}.log').open('x') as log:
        if output is None:
            return subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                                  timeout=120, check=False).returncode
        with (stage / output).open('x') as generated:
            return subprocess.run(command, cwd=stage, stdout=generated, stderr=log,
                                  timeout=120, check=False).returncode


def equivalent(stage: Path, xls: Path, yosys: str, reject: bool) -> None:
    """Check all binary inputs and complete outputs; a negative must yield a counterexample."""
    for name in ['reference', 'candidate']:
        assert run([str(xls / 'ir_converter_main'), '--top=probe', '--warnings_as_errors=false',
                    f'--dslx_path={ROOT / "priv/xls/lib"}',
                    f'--dslx_stdlib_path={xls / "xls/dslx/stdlib"}', f'{name}.x'],
                   stage, f'{name}-convert', f'{name}.ir') == 0
        assert run([str(xls / 'opt_main'), f'{name}.ir'], stage,
                   f'{name}-opt', f'{name}.opt.ir') == 0
        assert run([str(xls / 'codegen_main'), '--generator=combinational',
                    '--use_system_verilog=true', f'--module_name={name}',
                    f'--output_verilog_path={name}.sv', f'{name}.opt.ir'],
                   stage, f'{name}-codegen') == 0
    script = stage / 'proof.ys'
    script.write_text('read_verilog -sv reference.sv candidate.sv\nproc\n'
                      'miter -equiv -flatten reference candidate miter\n'
                      'hierarchy -top miter\nflatten\nopt\ncheck -assert\ntechmap\nopt\n'
                      'sat -verify -prove trigger 0 -set-def-inputs -show-inputs\n')
    code = run([yosys, '-s', str(script)], stage, 'proof')
    log = (stage / 'proof.log').read_text()
    assert (code != 0 and 'proof did fail' in log) if reject else (code == 0 and 'SUCCESS!' in log)


def main() -> None:
    """Generate fresh fixtures with this checkout's compiled frontend and publish only complete success."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage, xls = args.stage.resolve(), args.xls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    ebin = ROOT / '_build/test/lib/erl_hls/ebin'
    tests = ROOT / '_build/test/lib/erl_hls/test'
    assert (tests / 'xls_ir_control_dslx.beam').is_file(), 'Run rebar3 eunit first.'
    expression = 'ok=xls_ir_control_dslx:write(hd(init:get_plain_arguments())), halt().'
    assert run(['erl', '+S', '2:2', '-noshell', '-pa', str(ebin), str(tests),
                '-eval', expression, '-extra', str(stage)], stage, 'lower') == 0
    rows = []
    for metadata in sorted(stage.glob('*/case.json')):
        case = json.loads(metadata.read_text())
        equivalent(metadata.parent, xls, args.yosys, case['rejecting'])
        rows.append(dict(case, passed=True))
    assert len(rows) == 43 and sum(row['rejecting'] for row in rows) == 1
    tools = [xls / name for name in ['ir_converter_main', 'opt_main', 'codegen_main']]
    tools.append(Path(shutil.which(args.yosys) or args.yosys).resolve())
    sources = sorted((ROOT / 'src').rglob('*.erl')) + sorted((ROOT / 'src').rglob('*.hrl'))
    sources += sorted((ROOT / 'priv/xls/lib').rglob('*.x'))
    sources += [ROOT / 'test/xls_ir_control_dslx.erl', Path(__file__).resolve()]
    beams = sorted(ebin.glob('*.beam')) + [tests / 'xls_ir_control_dslx.beam']
    (stage / 'summary.json').write_text(json.dumps({
        'passed': True, 'cases': rows,
        'domain': 'All binary a/b inputs for signed and unsigned add/sub/xor at widths '
                  '1, 2, 8, 12, 32, 64 and 699; full arithmetic value and eq/ne in both orders.',
        'evidence': 'Finite combinational equivalence proofs, plus one rejected wrong predicate. '
                    'Not an all-width theorem, sequential proof or timing/area measurement.',
        'trust': 'Source classification/lowering, DSLX typing, XLS optimization/code generation, '
                 'Yosys translation and SAT solver.',
        'identities': {str(p): digest(p) for p in [*sources, *beams, *tools]},
    }, indent=2) + '\n')
    print('42 finite circuits pass; wrong comparison rejected.')


if __name__ == '__main__':
    main()
