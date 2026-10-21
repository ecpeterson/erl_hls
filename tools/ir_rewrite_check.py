"""Compile an explicit IR rewrite and check finite combinational result equality."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    """Hash exact input, output, executable or selected BEAM bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], stage: Path, label: str, env: dict[str, str] | None = None) -> int:
    """Retain a bounded command and its diagnostics, including rejecting checks."""
    (stage / f'{label}.command.json').write_text(json.dumps(command) + '\n')
    with (stage / f'{label}.log').open('x') as log:
        return subprocess.run(command, cwd=stage, env=env, stdout=log,
                              stderr=subprocess.STDOUT, timeout=120, check=False).returncode


def compile_passes(stage: Path, modules: list[str]) -> Path:
    """Compile only the selected checkout's modules into a fresh private directory."""
    ebin = stage / 'ebin'
    ebin.mkdir()
    sources = [ROOT / 'src/backend/xls' / f'{module}.erl' for module in modules]
    assert run(['erlc', '-Werror', '+debug_info', '-o', str(ebin),
                *map(str, sources)], stage, 'compile') == 0
    (stage / 'sources.json').write_text(json.dumps({str(p): digest(p) for p in sources}, indent=2))
    return ebin


def rewrite(stage: Path, ebin: Path, module: str) -> dict:
    """Run a fixed test-selected module; require its loaded BEAM and audit hashes to match."""
    env = dict(os.environ, IR_INPUT=str(stage / 'input.ir'), IR_OUTPUT=str(stage / 'candidate.ir'),
               IR_MODULE=module, IR_EBIN=str(ebin))
    expression = ('M=list_to_existing_atom(os:getenv("IR_MODULE")), '
                  'Expected=filename:join(os:getenv("IR_EBIN"),atom_to_list(M)++".beam"), '
                  'Expected=code:which(M), '
                  'ok=M:write(os:getenv("IR_INPUT"),os:getenv("IR_OUTPUT")), halt().')
    # Loading first also interns the fixed module atom without accepting arbitrary input atoms.
    expression = f'code:ensure_loaded({module}), ' + expression
    assert run(['erl', '+S', '2:2', '-noshell', '-pa', str(ebin), '-eval', expression],
               stage, 'rewrite', env) == 0
    audit = json.loads((stage / 'candidate.ir.json').read_text())
    assert audit['input_sha256'] == digest(stage / 'input.ir')
    assert audit['output_sha256'] == digest(stage / 'candidate.ir')
    if not audit['changes']:
        assert (stage / 'input.ir').read_bytes() == (stage / 'candidate.ir').read_bytes()
    return audit


def equivalent(stage: Path, xls: Path, yosys: str, candidate: str = 'candidate.ir',
               *, reject: bool = False) -> None:
    """Prove complete outputs equal for all binary inputs, or require a real counterexample."""
    for name, source in [('reference', 'input.ir'), ('candidate', candidate)]:
        assert run([str(xls / 'codegen_main'), '--generator=combinational',
                    '--use_system_verilog=true', f'--module_name={name}',
                    f'--output_verilog_path={name}.sv', source], stage, f'{name}-codegen') == 0
    script = stage / 'proof.ys'
    script.write_text('read_verilog -sv reference.sv candidate.sv\nproc\n'
                      'miter -equiv -flatten reference candidate miter\n'
                      'hierarchy -top miter\nflatten\nopt\ncheck -assert\ntechmap\nopt\n'
                      'sat -verify -prove trigger 0 -set-def-inputs -show-inputs\n')
    code = run([yosys, '-s', str(script)], stage, 'proof')
    log = (stage / 'proof.log').read_text()
    assert (code != 0 and 'proof did fail' in log) if reject else (code == 0 and 'SUCCESS!' in log)


def finish(stage: Path, ebin: Path, xls: Path, yosys: str, cases: list[dict], domain: str) -> None:
    """Publish success only after all proof and negative gates, binding tools and loaded code."""
    executable = Path(shutil.which(yosys) or yosys).resolve()
    paths = [xls / 'codegen_main', executable, *sorted(ebin.glob('*.beam'))]
    (stage / 'summary.json').write_text(json.dumps({
        'passed': True, 'cases': cases, 'domain': domain,
        'evidence': 'Combinational proofs at the listed widths; no sequential horizon or all-width theorem.',
        'trust': 'Valid fixture IR, XLS code generation, Yosys translation and SAT solver. No timing or area claim.',
        'identities': {str(p): digest(p) for p in paths},
    }, indent=2) + '\n')
