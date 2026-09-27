#!/usr/bin/env python3
"""Prove generated shared completion equivalent for every input bit pattern."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(argv: list[str], stage: Path, name: str) -> None:
    """Bound each proof phase and retain its command, output and diagnostics."""
    (stage / (name + '.command.json')).write_text(json.dumps(argv) + '\n')
    with (stage / name).open('w') as out, (stage / (name + '.stderr')).open('w') as err:
        subprocess.run(argv, cwd=ROOT, stdout=out, stderr=err, check=True, timeout=180)


def main() -> None:
    """Compile an independent reference dispatch and SAT-check the complete result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/shared-completion-proof')
    args = parser.parse_args()
    xls, stage = args.xls.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    run(['rebar3', 'as', 'test', 'compile'], stage, 'compile.log')
    run(['erl', '-noshell', '-pa', str(ROOT / '_build/test/lib/erl_hls/ebin'),
         '-eval', 'io:put_chars(xls_parse:to_xls('
         '"test_data/hls_statem_reduction_lower_fixture.erl", '
         '#{shared_service => aggregate_only})), halt().'], stage, 'generated.x')
    generated = (stage / 'generated.x').read_text()
    execute = re.search(r'^pub fn shared_execute\(.*?^}', generated, re.M | re.S)[0]
    start, end = execute.index('  let completion_machine = '), execute.index('  let entered = ')
    reference = execute[:start] + '  let dispatched = reference_dispatch(machine, request);\n' + execute[end:]
    reference = reference.replace('pub fn shared_execute(', 'fn reference_execute(', 1)
    source = stage / 'completion.x'
    helpers, miter = (ROOT / 'test_data/shared_completion_reference.inc.x').read_text().split(
        '// Compare all output bits', 1)
    source.write_text(generated + '\n' + helpers + '\n' + reference + '\n' +
                      '// Compare all output bits' + miter)
    run([str(xls / 'ir_converter_main'), '--top=completion_equivalent', '--warnings_as_errors=false',
         '--dslx_path=' + str(ROOT / 'priv/xls/lib'),
         '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), str(source)], stage, 'completion.ir')
    run([str(xls / 'opt_main'), str(stage / 'completion.ir')], stage, 'completion.opt.ir')
    run([str(xls / 'codegen_main'), '--generator=combinational', '--module_name=completion',
         '--use_system_verilog=false', str(stage / 'completion.opt.ir')], stage, 'completion.v')
    script = stage / 'proof.ys'
    script.write_text(f'read_verilog "{stage / "completion.v"}"\n'
                      'prep -top completion -flatten\nopt\n'
                      'sat -verify -prove out 1 -set-def-inputs -show-inputs\n')
    run([args.yosys, '-Q', '-T', '-s', str(script)], stage, 'proof.log')
    print('PASS: shared executor outputs match for all machine/request bits, '
          'including internal priority, rejected aggregates, failures and entry stalls')


if __name__ == '__main__':
    main()
