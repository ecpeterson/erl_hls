#!/usr/bin/env python3
"""Simulate configurable routed streams and prove their public-port contracts."""
import argparse
from pathlib import Path
import os
import shutil
import subprocess

from topology_debug import quote

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / 'priv/rtl/fabric'


def run(command, log, timeout=120):
    with log.open('w') as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout)


def refinement_connections(direction):
    names = ('state', 'source', 'selected') if direction == 'ingress' else (
        'state', 'selected', 'next_port', 'destination', 'first')
    return ''.join(f'connect -set impl_{name} dut.{name}\n' for name in names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/frame-router')
    parser.add_argument('--yosys', default=os.environ.get('ERL_HLS_YOSYS') or shutil.which('yosys'))
    args = parser.parse_args()
    if not args.yosys:
        parser.error('Yosys required; set ERL_HLS_YOSYS or --yosys')
    args.stage.mkdir(parents=True, exist_ok=True)
    for ports in (1, 2, 3, 5, 8):
        for continuous in (0, 1):
            target = args.stage / f'simulation-{ports}-{continuous}'
            run(['iverilog', '-g2012', '-s', 'fabric_router_tb',
                 f'-Pfabric_router_tb.PORTS={ports}',
                 f'-Pfabric_router_tb.CONTINUOUS={continuous}', '-o', str(target),
                 str(ROOT / 'test/rtl/fabric_router_tb.sv'),
                 *map(str, RTL.glob('*.v'))], target.with_suffix('.compile.log'))
            run(['vvp', str(target)], target.with_suffix('.log'))
            print(target.with_suffix('.log').read_text().splitlines()[0], flush=True)
    invalid_configurations(args)
    for direction in ('ingress', 'egress'):
        for ports in (1, 2, 3, 5, 8):
            prove(args, direction, ports)
    # Counterexamples must be solver failures, not parse/elaboration errors.
    # Run the public-port monitor alone for mutation tests: an internal-state
    # correspondence mismatch is not enough to demonstrate fault detection.
    mutations = (
        ('ingress', 'corrupt', 'assign m_data = s_data;', 'assign m_data = s_data ^ 1;'),
        ('ingress', 'leak', 's_keep == 4\'hf && found ? FORWARD : DROP', 's_keep == 4\'hf ? FORWARD : DROP'),
        ('egress', 'early-release', 'if (m_last) begin', 'if (1) begin'),
        ('egress', 'wrong-source', 'ENDPOINTS[16*selected +: 16], destination', '16\'d65535, destination'),
        ('egress', 'starve', "next_port <= selected == PORTS - 1 ? 0 : selected + 1'b1;", 'next_port <= 0;'),
    )
    for direction, name, old, new in mutations:
        original = (RTL / f'hls_fabric_{direction}.v').read_text()
        assert original.count(old) == 1
        changed = args.stage / f'mutation-{name}.v'
        changed.write_text(original.replace(old, new))
        prove(args, direction, 3, changed, name)


def invalid_configurations(args):
    for direction in ('ingress', 'egress'):
        module = f'hls_fabric_{direction}'
        for name, parameters, message in (
                ('duplicate', [f'-P{module}.ENDPOINTS=32\'h00010001'], 'IDs must be unique'),
                ('empty', [f'-P{module}.PORTS=0'], 'PORTS must be')):
            target = args.stage / f'invalid-{direction}-{name}'
            run(['iverilog', '-g2012', '-s', module, *parameters, '-o', str(target),
                 str(RTL / f'{module}.v')], target.with_suffix('.compile.log'))
            with target.with_suffix('.log').open('w') as log:
                result = subprocess.run(['vvp', str(target)], stdout=log, stderr=subprocess.STDOUT, timeout=10)
            if result.returncode == 0 or message not in target.with_suffix('.log').read_text():
                raise RuntimeError(f'invalid configuration accepted: {target}')
    print('PASS: duplicate endpoint IDs and empty fabrics rejected', flush=True)


def prove(args, direction, ports, changed=None, mutation=None):
    top = f'fabric_{direction}_formal'
    target = args.stage / (f'mutation-{mutation}' if mutation else f'{direction}-{ports}')
    ids = sum((2 + p * 7) << (16*p) for p in range(ports))
    monitor = ROOT / f'test/rtl/{top}.sv'
    if mutation:
        monitor_text = monitor.read_text().replace('refinement && ', '')
        monitor = args.stage / f'{top}-{mutation}.sv'
        monitor.write_text(monitor_text)
    script = ('read_verilog -formal -sv ' + ' '.join(map(quote, [
        monitor, changed or RTL / f'hls_fabric_{direction}.v'])) + '\n'
        f'chparam -set PORTS {ports} -set ENDPOINTS {16*ports}\'d{ids} {top}\n'
        f'hierarchy -top {top}\nproc\nflatten\ncd {top}\n'
        + refinement_connections(direction) + 'cd ..\nopt\ncheck -assert\nscc -expect 0\n'
        'sat -verify -prove ok 1 -set legal 1 -set-at 1 reset 1 '
        '-set-def-inputs -timeout 60 '
        + ('-seq 12 ' if mutation else '-tempinduct -seq 4 -maxsteps 8 ')
        + f'-dump_vcd {quote(target.with_suffix(".vcd"))}\n')
    target.with_suffix('.ys').write_text(script)
    try:
        run([args.yosys, '-Q', '-T', '-s', str(target.with_suffix('.ys'))], target.with_suffix('.log'))
    except subprocess.CalledProcessError:
        if not mutation or 'proof did fail' not in target.with_suffix('.log').read_text():
            raise
        print(f'PASS: public-port monitor rejected {mutation}', flush=True)
    else:
        if mutation:
            raise RuntimeError(f'mutation escaped the monitor: {mutation}')
        if 'Induction step proven: SUCCESS!' not in target.with_suffix('.log').read_text():
            raise RuntimeError(f'induction did not complete: {target}')
        print(f'PASS: {direction}, {ports} ports, inductive safety and selection', flush=True)


if __name__ == '__main__':
    main()
