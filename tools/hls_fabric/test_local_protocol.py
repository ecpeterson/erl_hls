"""Check source-bound receipt/callback composition with finite-width SAT contracts."""
from pathlib import Path
import argparse
import json
import shutil
import time

from compiler_paths import compiler_root, compiler_source_root
from backend_paths import ROOT, erlang_environment
from test_local_actor import manifest
from backend_commands import digest, run


def prove(args: argparse.Namespace, stage: Path, raw: Path, module: str,
          prop: str, positive: bool) -> dict:
    """Prove a Boolean circuit or require an explicit counterexample for a broken contract."""
    stem = module + '__' + prop
    optimized, circuit = stage / (stem + '.opt.ir'), stage / (stem + '.v')
    started = time.monotonic()
    run([args.xls / 'opt_main', '--top=__' + module + '__' + prop, raw], stage, stem + '-opt', optimized)
    run([args.xls / 'codegen_main', '--generator=combinational', '--use_system_verilog=false',
         '--module_name=contract', '--output_verilog_path=' + str(circuit), optimized], stage, stem + '-codegen')
    script = stage / (stem + '.ys')
    # CI's Yosys 0.33 rejects XLS's unpacked SystemVerilog array assignment patterns.
    # Generate plain Verilog and parse without -sv to check that boundary locally too.
    script.write_text(f'read_verilog "{circuit}"\nhierarchy -top contract\nproc\nflatten\nopt\n'
                      'techmap\nopt\nabc -g AND\nopt_clean\n'
                      'sat -prove out 1 -set-def-inputs -show-inputs -timeout 180\n')
    run([args.yosys, '-Q', '-T', '-s', script], stage, stem + '-sat')
    expected = 'no model found: SUCCESS!' if positive else 'model found: FAIL!'
    assert 'SAT proof finished - ' + expected in (stage / (stem + '-sat.log')).read_text(), stem
    print(stem, 'proved' if positive else 'counterexample found', flush=True)
    return {'module': module, 'property': prop, 'verdict': 'unsat' if positive else 'sat',
            'seconds': time.monotonic() - started, 'circuit_sha256': digest(circuit)}


def main() -> None:
    """Use the public builder for selected source shapes, retaining quantified domains and negative controls."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--case', choices=['all', 'plain', 'scalar', 'gather'], default='all',
                        help='Select one source shape for a focused contract check')
    args = parser.parse_args()
    args.yosys = Path(shutil.which(args.yosys) or args.yosys).resolve()
    stage = args.stage
    stage.mkdir()
    run(['rebar3', 'compile'], stage, 'compile-backend')
    public = compiler_root('default')
    options = stage / 'options.term'
    options.write_text('[].\n')
    properties = ROOT / 'test/local_protocol_properties.x.in'
    cases = [('plain', ROOT / 'test/hls_local_actor_fixture.erl', ['protocol_drop_internal']),
             ('scalar', public / 'test_data/hls_statem_reduction_lower_fixture.erl',
              ['protocol_wrong_state', 'protocol_drop_internal']),
             ('gather', public / 'test_data/xls_statem_gather_fixture.erl',
              ['protocol_wrong_state', 'protocol_stale_completion', 'protocol_drop_internal'])]
    cases = [case for case in cases if args.case == 'all' or case[0] == args.case]
    inputs = [Path(__file__), properties, ROOT / 'tools/emit_local_actor.escript', *[source for _, source, _ in cases],
              args.yosys, *[args.xls / p for p in ['ir_converter_main', 'opt_main', 'codegen_main']]]
    for base, pattern in [(ROOT / 'src', '*.erl'), (ROOT / 'apps/hls_lowering/src', '*.erl'),
                          (ROOT / 'apps/hls_lowering/priv/xls', '*.x*'),
                          (public / 'src', '*.erl'), (compiler_source_root(public) / 'apps/hls_runtime/src', '*.erl'),
                          (public / 'priv/xls', '*.x*'),
                          (args.xls / 'xls/dslx/stdlib', '*.x')]:
        inputs.extend(sorted(base.rglob(pattern)))
    bindings = {str(p): digest(p) for p in inputs}
    positive = ['protocol_receipt_equal', 'protocol_completion_equal', 'protocol_slow_equal',
                'protocol_publication_retry']
    plan = {'method': 'combinational SAT', 'properties': positive,
            'domain': 'All machine/frame bits, received/effects_reserved Booleans and 32-bit slots for each emitted fixture; receipt eligibility and slow-path preconditions are expressed in the properties. Publication retry retains the same action and actor slot with no intervening activation.',
            'trust': 'Source extraction, DSLX/XLS lowering and optimization, Yosys/ABC/SAT; assumes declared fixed-width interfaces.',
            'excludes': ['general theorem for arbitrary source programs', 'runtime ownership', 'temporal progress', 'routed timing'],
            'inputs': bindings}
    (stage / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    results, actors = [], []
    for name, source, negatives in cases:
        built = stage / (name + '.x')
        run(['escript', ROOT / 'tools/emit_local_actor.escript', source, options, built],
            stage, name + '-build', env=erlang_environment('default', compiler=public))
        report = manifest(built)
        assert report['receipt_result_fields'] == ['handled', 'deferred_completion', 'private_machine', 'dispatched', 'directive']
        assert {'local_protocol_at', 'local_slow_step_at', 'local_action_at', 'local_enter_at'} <= set(report['function_ports'])
        assert report['action_result_fields'] == ['private_machine', 'dispatched', 'directive', 'phase_boundary']
        negatives += ['protocol_stale_action', 'protocol_drop_action_disposition']
        actors.append({'name': name, 'manifest': report})
        module = name + '_properties'
        proof = stage / (module + '.x')
        # Import the emitted public types/functions across the real module boundary.
        proof.write_bytes(f'import {name} as actor;\n\n'.encode() + properties.read_bytes())
        raw = stage / (module + '.ir')
        paths = ':'.join(map(str, [stage, ROOT / 'apps/hls_lowering/priv/xls/lib', ROOT / 'apps/hls_lowering/priv/xls/fabric',
                                  public / 'priv/xls/lib', public / 'priv/xls/fabric']))
        run([args.xls / 'ir_converter_main', '--warnings_as_errors=false', '--dslx_path=' + paths,
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), proof], stage, name + '-convert', raw)
        for prop, expected in [(p, True) for p in positive] + [(p, False) for p in negatives]:
            results.append(prove(args, stage, raw, module, prop, expected))
            (stage / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    assert bindings == {str(p): digest(p) for p in inputs}, 'formal inputs changed'
    (stage / 'result.json').write_text(json.dumps({'passed': True, 'actors': actors, 'results': results,
        'inputs_unchanged': True, 'plan_sha256': digest(stage / 'plan.json')}, indent=2) + '\n')


if __name__ == '__main__':
    main()
