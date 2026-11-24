#!/usr/bin/env python3
"""Run the compiler's CI checks locally, serially, with retained per-command logs.

This composes existing Erlang, XLS, RTL and audit commands; it neither installs
external tools nor invokes a remote host. CI calls the same group recipes.
"""
import argparse
from dataclasses import replace
import json
from pathlib import Path
import shutil
import sys
import time

from regression_inventory import load_inventory
from regression_steps import Case, Command, Rows, Step
from run_regression import describe, make_cases, require_fresh, run_case

ROOT = Path(__file__).resolve().parents[1]
GROUPS = ('quality', 'test', 'topology')


def feature_cases(raw: str | None) -> list[str]:
    """Use all routine CI features by default; reject unknown or non-test CI selections."""
    inventory = load_inventory(ROOT)
    routine = sorted(name for name, row in inventory['cases'].items() if row['group'] == 'test')
    if raw is None:
        return routine
    names = json.loads(raw)
    if not isinstance(names, list) or any(not isinstance(name, str) or name not in routine for name in names):
        raise ValueError('--cases-json must contain routine test-group feature names')
    return list(dict.fromkeys(names))


def prefix_steps(name: str, steps: list[Step]) -> list[Step]:
    """Name feature commands while preserving lazy generated rows and individual timeouts."""
    result = []
    for step in steps:
        if isinstance(step, Command):
            result.append(replace(step, name=name + '/' + step.name))
        elif isinstance(step, Rows):
            def expand(row: list[str], source: Rows = step) -> list[Command]:
                """Expand only after the fixture has produced its variant table."""
                return [replace(command, name=name + '/' + command.name) for command in source.expand(row)]
            result.append(replace(step, expand=expand))
        else:
            result.append(step)
    return result


def features_into(case: Case, names: list[str]) -> None:
    """Compose the existing recipes directly, without timing or spawning another runner."""
    for name, child in make_cases(names, load_inventory(ROOT), ROOT, case.xls,
                                  case.path('features'), case.placements):
        case.steps.extend(prefix_steps(name, child.steps))


def recipe(group: str, xls: Path, stage: Path, features: list[str],
           placements: tuple[str, ...], base: str | None) -> Case:
    """Build one CI group's command plan without running commands or creating files."""
    c = Case(ROOT, xls, stage, placements)
    def py(name: str, script: str, *args: object, timeout: int = 300) -> None:
        """Use this interpreter for existing repository checks and retain their own limits."""
        c.command(name, [sys.executable, ROOT / 'tools' / script, *args], timeout=timeout)

    if group == 'quality':
        for script in ('test_check.py', 'test_ci_plan.py', 'test_ci_diagnostics.py', 'test_source_contracts.py'):
            py(Path(script).stem, script)
        py('source-contracts', 'check_source_contracts.py', *(['--base', base] if base else []))
        c.command('format', ['rebar3', 'fmt', '--check'])
        c.command('dialyzer', ['rebar3', 'dialyzer'], timeout=900)
        py('package-auditor', 'test_package_boundaries.py')
        c.command('spacetime-compile', ['rebar3', 'as', 'spacetime', 'compile'])
        py('application-boundaries', 'hls_fabric/check_application_boundaries.py',
           '--profile', 'default', '--profile', 'spacetime')
        py('runtime-boundaries', 'check_package_boundaries.py',
           '--runtime', 'hls_core', '--runtime', 'hls_runtime')
    elif group == 'test':
        for script in ('test_compact_build.py', 'test_hls_profile.py', 'test_xls_goldens.py'):
            py(Path(script).stem, script)
        c.command('eunit', ['bash', 'tools/test_umbrella_eunit.sh', 'default'], timeout=300)
        c.command('release-compiler', ['rebar3', 'release', '-n', 'erl_hls'])
        c.command('release-facade', ['rebar3', 'release', '-n', 'hls'])
        c.command('release-workloads', ['rebar3', 'release', '-n', 'hls_workloads'])
        py('installed-toolchain', 'test_source_toolchain.py')
        c.command('source-build-executor', [sys.executable, '-m', 'unittest', 'tools.test_source_build_executor'])
        py('source-diagnostics', 'test_source_diagnostics.py')
        source_maps = c.path('source-maps')
        c.compile()
        c.erl('ok = xls_source_map_dslx:write(hd(init:get_plain_arguments())), halt().',
              source_maps, name='source-map-fixtures')
        py('source-maps', 'test_source_maps.py', '--xls', xls, '--stage', source_maps)
        py('portable-host-sources', 'test_portable_host_sources.py', timeout=180)
        py('IR-census', 'test_xls_ir_census.py')
        py('regression-runner', 'test_regression.py')
        simulation = c.path('simulation')
        c.command('simulation-inputs', ['bash', 'tools/prepare_xls_sim.sh', simulation])
        c.command('DSLX-golden', ['bash', 'tools/xls_goldens.sh', 'check', simulation])
        py('function-differential-runner', 'test_compiler_differential.py')
        py('actor-differential-runner', 'test_actor_differential.py')
        py('function-differential-native', 'test_compiler_differential.py', '--xls-root', xls,
           '--stage', c.path('differential-self-test'))
        py('function-differential', 'compiler_differential.py', xls, '--stage', c.path('function-differential'),
           '--count', '16', '--depth', '3', '--inputs', '20', '--rtl-batches', '2', '--shrink-budget', '40')
        py('actor-differential', 'actor_differential.py', xls, '--stage', c.path('actor-differential'),
           '--count', '1', '--skip-compile', '--shrink-budget', '0')
        features_into(c, features)
        for script in ('test_sim_bridge.py', 'test_topology_debug.py', 'test_direct_actor_debug.py',
                       'test_debug_memories.py', 'test_actor_snapshot_formal.py'):
            stage_args = ['--stage', c.path(Path(script).stem)] if script in (
                'test_debug_memories.py', 'test_actor_snapshot_formal.py') else []
            py(Path(script).stem, script, *stage_args)
        py('incremental-build', 'test_compile_xls.py', '--xls-root', xls)
        py('arbitration', 'test_arbitration.py', xls, '--stage', c.path('arbitration'))
        py('fabric-router', 'test_fabric_router.py', '--stage', c.path('fabric-router'))
        c.command('RTL-and-bridge', ['bash', 'tools/remote_xls_sim.sh', simulation, xls], timeout=600)
        for script in ('test_fabric_services.py', 'test_debug_trace_integration.py', 'test_debug_sampling.py'):
            py(Path(script).stem, script, simulation, '--stage', c.path(Path(script).stem))
        py('topology-debug', 'test_topology_debug_integration.py',
           '--top', '__ordered_egress_topology__Top_0_next', '--stage', c.path('topology-debug'),
           simulation / 'ordered_egress_topology.v')
    elif group == 'topology':
        features_into(c, ['mixed_topology'])
    else:
        raise ValueError('unknown check group: ' + group)
    return c


def preflight(groups: list[str], xls: Path | None) -> None:
    """Reject missing local prerequisites before spending time compiling or creating a run."""
    required = ['git', 'rebar3', 'erl']
    if any(group != 'quality' for group in groups):
        required += ['erlc', 'iverilog', 'iverilog-vpi', 'vvp', 'yosys', 'gcc']
        if xls is None:
            raise ValueError('XLS_ROOT is required for test/topology checks; use --group quality for native audits')
        for name in ('interpreter_main', 'ir_converter_main', 'opt_main', 'codegen_main'):
            if not (xls / name).is_file():
                raise ValueError('missing XLS tool: ' + str(xls / name))
        if not (xls / 'xls/dslx/stdlib').is_dir():
            raise ValueError('missing XLS standard library: ' + str(xls))
    missing = [name for name in required if shutil.which(name) is None]
    if missing:
        raise ValueError('missing tools on PATH: ' + ', '.join(missing))


def main(argv: list[str] | None = None) -> None:
    """Run all CI groups by default, or select the same bounded subsets used by CI jobs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', nargs='?', type=Path, help='local XLS installation (not needed for quality only)')
    parser.add_argument('--stage', type=Path, help='fresh output root; defaults to a unique _build/checks directory')
    parser.add_argument('--group', action='append', choices=GROUPS, help='repeat to select groups; default: all')
    parser.add_argument('--cases-json', help='CI-selected compiler features; default: all routine features')
    parser.add_argument('--placements', nargs='+', choices=('direct', 'ingress_direct'),
                        default=['direct', 'ingress_direct'])
    parser.add_argument('--base', help='source-contract audit comparison revision')
    parser.add_argument('--dry-run', action='store_true', help='print all commands without executing or writing')
    args = parser.parse_args(argv)
    try:
        groups = list(dict.fromkeys(args.group or GROUPS))
        features = feature_cases(args.cases_json)
        stage = (args.stage or ROOT / '_build/checks' / str(time.time_ns())).resolve()
        xls = args.xls.resolve() if args.xls is not None else ROOT
        cases = [(group, recipe(group, xls, stage / group, features, tuple(args.placements), args.base))
                 for group in groups]
        if args.dry_run:
            print(json.dumps([{'group': group, 'stage': str(case.stage),
                               'steps': [describe(step) for step in case.steps]} for group, case in cases], default=str, indent=2))
            return
        preflight(groups, args.xls.resolve() if args.xls is not None else None)
        for _, case in cases:
            require_fresh(case.stage)
        print('Check outputs: ' + str(stage), flush=True)
        for group, case in cases:
            run_case('check-' + group, case)
    except (ValueError, OSError, RuntimeError, TimeoutError) as error:
        parser.exit(1, f'check failed: {error}\n')


if __name__ == '__main__':
    main()
