#!/usr/bin/env python3
"""Map one executor and substitute its primitives for application-level simulation."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

from architecture import sha
from module_substitution import substitute
from staged_reciprocal import dsp_depth


def ansi(mapped: str, original: str, module: dict) -> str:
    """Require unchanged mapped ports before restoring their ANSI declarations."""
    header = original[:original.index(');') + 2]
    declarations = re.findall(r'(input|output) wire (?:\[(\d+):0\] )?(\w+)', header)
    expected = {name: (direction, int(msb) + 1 if msb else 1)
                for direction, msb, name in declarations}
    actual = {name: (port['direction'], len(port['bits'])) for name, port in module['ports'].items()}
    if expected != actual:
        raise ValueError('mapped executor ports differ')
    mapped = re.sub(r'^module .*?\);', header, mapped, count=1, flags=re.M | re.S)
    mapped = re.sub(r'^  (?:input|output) .*?;\n', '', mapped, flags=re.M)
    for name in expected:
        mapped = re.sub(r'^  wire (?:\[\d+:0\] )?' + re.escape(name) + r';\n', '', mapped, flags=re.M)
    return mapped


def main() -> None:
    """Check a scoped mapping policy without changing any other proc's RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage', 'yosys'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--fabric-registers', action='store_true',
                        help='disable DSP packing in this executor only')
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=False)
    source = args.reference / 'executor.v'
    text = source.read_text()
    names = re.findall(r'^module (\w+)\(', text, re.M)
    if len(names) != 1:
        raise ValueError('require one executor module')
    top = names[0]
    cells = args.yosys.parent.parent / 'share/yosys/xilinx/cells_sim.v'
    policy = 'scratchpad -set xilinx_dsp.multonly 1\n' if args.fabric_registers else ''
    script = f'read_verilog {source}\n' + policy + (
        f'synth_xilinx -flatten -abc9 -nosrl -family xc7 -noiopad -noclkbuf -top {top}\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n'
        'write_verilog -noattr mapped.v\n')
    (args.stage / 'map.ys').write_text(script)
    command = [str(args.yosys), '-Q', '-T', '-s', 'map.ys']
    with (args.stage / 'map.log').open('w') as log:
        subprocess.run(command, cwd=args.stage, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=600)
    data = json.loads((args.stage / 'mapped.json').read_text())
    module = data['modules'][top]
    counts = Counter(c['type'] for c in module['cells'].values())
    summary = {'source': {str(source): sha(source)}, 'yosys': {str(args.yosys): sha(args.yosys)},
               'simulation_models': {str(cells): sha(cells)},
               'fabric_registers': args.fabric_registers, 'cells': dict(counts),
               'serial_dsps_upper_bound': dsp_depth(module),
               'dsp_registers': Counter(','.join(f'{k}={int(v, 2)}' for k, v in c['parameters'].items()
                                       if k in ('AREG', 'BREG', 'MREG', 'PREG'))
                                        for c in module['cells'].values() if c['type'] == 'DSP48E1')}
    # Keep compact evidence; the tech-library definitions are not part of the design.
    data['modules'] = {top: module}
    (args.stage / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    (args.stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    # Yosys emits a non-ANSI module declaration; substitution checks ANSI ports.
    mapped = (args.stage / 'mapped.v').read_text()
    mapped = ansi(mapped, text, module)
    (args.stage / 'mapped-ansi.v').write_text(mapped)
    substitute(args.reference, args.stage / 'mapped-ansi.v', args.stage / 'compiled', re.escape(top))
    # Include primitive simulation models only in this simulation artifact.
    rtl = args.stage / 'compiled/phi_decoder_profile.v'
    rtl.write_text(f'`include "{cells}"\n' + rtl.read_text())
    manifest_path = args.stage / 'compiled/phi_decoder_profile.build.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['rtl'][rtl.name] = sha(rtl)
    manifest['executor_mapping'] = summary
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()
