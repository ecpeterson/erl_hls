#!/usr/bin/env python3
"""Check generated ordinary/prefix routers with a real depth-one ownership arbiter.

Run after the test compiler build (normally through test_effect_window.sh).
Five finite RTL witnesses check exact per-lane content/order, held outputs, reset
and covered lookahead handoffs. They do not require internal cycle equality.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from compiler_paths import compiler_root
from backend_paths import erlang_paths

ROOT = Path(__file__).resolve().parents[1]


def interface(prefix: bool) -> tuple[str, dict[str, tuple[str, int]]]:
    """Describe the fixture ABI and bind one DUT; reject packing/direction drift later."""
    ports = {'clk': ('input', 1), 'reset': ('input', 1),
        '_scheduled': ('input', 585), '_scheduled_vld': ('input', 1), '_scheduled_rdy': ('output', 1)}
    wires = {'clk': 'clk', 'reset': 'reset', '_scheduled': 'scheduled',
        '_scheduled_vld': 'scheduled_vld', '_scheduled_rdy': 'scheduled_rdy'}
    for name, signal, width in [('credit', 'credit', 161), ('left', 'left_data', 128),
            ('right', 'right_data', 128), *([('prefix_out', 'prefix_data', 288)] if prefix else [])]:
        stem = 'prefix' if name == 'prefix_out' else name
        ports.update({f'_{name}': ('output', width), f'_{name}_vld': ('output', 1), f'_{name}_rdy': ('input', 1)})
        wires.update({f'_{name}': signal, f'_{name}_vld': stem + '_vld', f'_{name}_rdy': stem + '_rdy'})
    instance = 'effect_router dut(\n    ' + ',\n    '.join(f'.{port}({wires[port]})' for port in ports) + '\n  );'
    if not prefix:
        instance += "\n  assign prefix_data = 288'd0;\n  assign prefix_vld = 1'b0;"
    return instance, ports


def bindings(rtl: str, expected: dict[str, tuple[str, int]]) -> str:
    """Check the complete top ABI and bind source-named coverage predicates afresh."""
    tops = list(re.finditer(r'\bmodule\s+effect_router\s*\((.*?)\);', rtl, re.S))
    if len(tops) != 1:
        raise ValueError('missing unique effect_router top')
    ports = {name: (direction, int(high) - int(low) + 1 if high else 1)
        for direction, high, low, name in re.findall(
            r'\b(input|output)\s+(?:wire\s+|reg\s+)?(?:\[(\d+)\s*:\s*(\d+)\]\s*)?([A-Za-z_][A-Za-z_0-9]*)', tops[0][1])}
    if ports != expected:
        raise ValueError(f'fixture interface changed: {ports}')
    routers = list(re.finditer(r'(__\w*SchedulerRouter0\w*)\s+(\w+)\s*\(', rtl))
    if len(routers) != 1:
        raise ValueError('missing unique generated router instance')
    module, instance = routers[0].groups()
    body = re.search(r'\bmodule\s+' + re.escape(module) + r'\s*\(.*?endmodule', rtl, re.S)
    if body is None:
        raise ValueError('missing generated router module')
    for signal in ('carry_lookahead', 'grant_usable'):
        if not re.search(r'\bwire\s+' + signal + r'\s*;', body[0]):
            raise ValueError('coverage predicate changed: ' + signal)
    signals = [('request_data', '_window_request_out'), ('request_vld', '_window_request_out_vld'),
        ('request_rdy', '_window_request_out_rdy'), ('grant_vld', '_window_grant_in_vld'),
        ('grant_rdy', '_window_grant_in_rdy'), ('release_data', '_window_release_out'),
        ('release_vld', '_window_release_out_vld'), ('release_rdy', '_window_release_out_rdy'),
        ('probe_carry', 'carry_lookahead'), ('probe_grant_usable', 'grant_usable')]
    return '\n  '.join(f'assign {wire} = dut.{instance}.{signal};' for wire, signal in signals)


def main() -> None:
    """Generate current production routers and run five sequential bounded RTL oracles."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/effect_window/router')
    args = parser.parse_args()
    xls, stage = args.xls.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    ebin = stage / 'ebin'
    ebin.mkdir(exist_ok=True)
    fixture = ROOT / 'test/rtl'
    sources = [ROOT / 'apps/hls_lowering/src/backend/xls/scheduler' / name for name in
        ('xls_topology_scheduler_dslx.erl', 'xls_topology_source_fragment_dslx.erl')]
    sources += [ROOT / 'test/xls_effect_router_testgen.erl', fixture / 'router_probe_actor.x',
        fixture / 'effect_router_top.x.in', fixture / 'effect_router_tb.sv.in',
        ROOT / 'apps/hls_lowering/priv/xls/lib/effect_window.x', ROOT / 'apps/hls_lowering/priv/xls/templates/parallel_effect_router.x.in',
        ROOT / 'apps/hls_lowering/src/backend/xls/scheduler/xls_parallel_effect_router_dslx.erl', ROOT / 'apps/hls_lowering/src/backend/xls/xls_template.erl', Path(__file__)]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    commands = []

    def run(name: str, argv: list[str | Path], output: Path | None = None) -> None:
        """Retain diagnostics and fail on a tool error or the finite 60-second wall bound."""
        command = list(map(str, argv))
        commands.append({'name': name, 'argv': command, 'cwd': str(ROOT)})
        with (stage / (name + '.log')).open('w') as log:
            if output is None:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True)
            else:
                with output.open('w') as stream:
                    subprocess.run(command, cwd=ROOT, stdout=stream, stderr=log, timeout=60, check=True)

    # Test-local exports call the exact private production route emitters without
    # widening the production API or retaining a copied implementation.
    run('fixture-compile', ['erlc', '+export_all', '-o', ebin, *(p for p in sources if p.suffix == '.erl')])
    stdlib = xls / 'xls/dslx/stdlib'
    options = ['--warnings_as_errors=false', f'--dslx_path={fixture}:{ROOT / "apps/hls_lowering/priv/xls/lib"}:{compiler_root('test') / "priv/xls/lib"}',
        f'--dslx_stdlib_path={stdlib}']
    for mode in ('ordinary', 'prefix', 'parallel2', 'parallel3', 'parallel6'):
        folder = stage / mode
        folder.mkdir(exist_ok=True)
        source, ir, optimized, rtl = [folder / ('effect_router.' + suffix) for suffix in ('x', 'ir', 'opt.ir', 'v')]
        run(mode + '-emit', ['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths("test"), ebin, '-eval',
            '[Mode, Output] = init:get_plain_arguments(), ok = xls_effect_router_testgen:write(Mode, Output), halt().',
            '-extra', mode, source])
        run(mode + '-convert', [xls / 'ir_converter_main', '--top=Top', *options, source], ir)
        run(mode + '-opt', [xls / 'opt_main', ir], optimized)
        run(mode + '-codegen', [xls / 'codegen_main', '--pipeline_stages=2', '--worst_case_throughput=1',
            '--delay_model=unit', '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
            '--reset=reset', '--reset_active_low=false', '--reset_asynchronous=false', '--reset_data_path=true',
            '--fifo_module=', '--module_name=effect_router', optimized], rtl)
        instance, ports = interface(mode == 'prefix')
        bench = (fixture / 'effect_router_tb.sv.in').read_text().replace('@@PREFIX@@', str(int(mode == 'prefix')))
        bench = bench.replace('@@PARALLEL@@', str(int(mode.startswith('parallel'))))
        bench = bench.replace('@@INSTANCE@@', instance).replace('@@COVERAGE_BINDINGS@@', bindings(rtl.read_text(), ports))
        if '@@' in bench:
            raise ValueError('unexpanded testbench template')
        tb, simulator = folder / 'testbench.sv', folder / 'test.vvp'
        tb.write_text(bench)
        run(mode + '-iverilog', ['iverilog', '-g2012', '-s', 'effect_router_tb', '-o', simulator, tb, rtl])
        run(mode + '-simulate', ['vvp', simulator])
        log = (stage / (mode + '-simulate.log')).read_text()
        if f'PASS mode={int(mode == "prefix")}' not in log:
            raise ValueError('missing bounded router oracle completion: ' + mode)
        print(log.strip())
    if before != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}:
        raise ValueError('router fixture or production source changed during the test')
    (stage / 'result.json').write_text(json.dumps({'sources_sha256': before, 'commands': commands,
        'scope': 'Five finite 16-batch witnesses, 40-cycle partial-send reset prelude, at most 2000 post-reset cycles each. One contender, depth-one ownership channels; no fairness or cycle-equivalence claim.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
