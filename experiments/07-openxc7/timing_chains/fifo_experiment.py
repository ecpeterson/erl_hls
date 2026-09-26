#!/usr/bin/env python3
"""Isolate compiler-generated FIFO changes in a retained, cycle-checked application."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

MODULE = re.compile(r'^module\s+(\w+)\s*\(.*?^endmodule\b[^\n]*', re.M | re.S)


def sha(path: Path) -> str:
    """Fingerprint a compiler, patch or retained experiment input."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def ports(module: str) -> dict[str, str]:
    """Require simple named XLS wire ports and retain direction and bit width."""
    header = module.split(');', 1)[0].split('(', 1)[1]
    result = {}
    for declaration in header.split(','):
        match = re.fullmatch(r'\s*(input|output)\s+wire\s*(\[[0-9]+:[0-9]+\])?\s*(\w+)\s*', declaration)
        if match is None or match[3] in result:
            raise ValueError('unsupported or duplicate FIFO port declaration')
        result[match[3]] = match[1] + (match[2] or '[0:0]')
    return result


def prepare(args: argparse.Namespace) -> None:
    """Replace only selected FIFO definitions and verify all remaining RTL is identical."""
    baseline = (args.reference/'phi_decoder_profile.v').read_text()
    generated = args.generated.read_text()
    old = {m[1]: m[0] for m in MODULE.finditer(baseline)}
    new = {m[1]: m[0] for m in MODULE.finditer(generated)}
    selected = [name for name in old if name.startswith('fifo_for_depth_')]
    if args.depth is not None:
        selected = [n for n in selected if n.startswith(f'fifo_for_depth_{args.depth}_')]
    if args.payload_bits is not None:
        selected = [n for n in selected if ports(old[n]).get('push_data') == f'input[{args.payload_bits-1}:0]']
    if not selected:
        raise ValueError('no matching FIFOs')
    for name in selected:
        if name not in new or ports(old[name]) != ports(new[name]):
            raise ValueError(f'{name}: FIFO interface changed')
    candidate = MODULE.sub(lambda m: new[m[1]] if m[1] in selected else m[0], baseline)
    mask = lambda text: MODULE.sub(lambda m: f'<FIFO {m[1]}>' if m[1] in selected else m[0], text)
    if mask(candidate) != mask(baseline):
        raise AssertionError('non-FIFO RTL changed')
    args.stage.mkdir(parents=True, exist_ok=False)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(args.reference/name, args.stage/name)
    (args.stage/'phi_decoder_profile.v').write_text(candidate)
    source = json.loads((args.reference/'phi_decoder_profile.build.json').read_text())
    # This is a derived experiment, not an entry in the compiler artifact cache.
    manifest = {key: source[key] for key in ('schema', 'profile', 'tools', 'stdlib', 'ram_configuration')}
    manifest['tools'] = dict(source['tools'], codegen_main=sha(args.compiler))
    manifest['rtl'] = {name: sha(args.stage/name) for name in
                      ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')}
    manifest['fifo_experiment'] = {'reference_manifest_sha256': sha(args.reference/'phi_decoder_profile.build.json'),
        'generated_rtl_sha256': sha(args.generated), 'compiler_sha256': sha(args.compiler),
        'patch_sha256': sha(args.patch), 'unchanged_non_fifo_sha256': hashlib.sha256(mask(baseline).encode()).hexdigest(),
        'selected_modules': selected, 'changed_modules': [n for n in selected if old[n] != new[n]]}
    (args.stage/'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2)+'\n')
    compare(args.reference, args.stage, manifest['profile'])
    print('PASS: FIFO-only replacement and cycle-exact public outputs;', len(selected), 'selected modules')


def compare(reference: Path, stage: Path, profile: dict) -> None:
    """Check public events through long stalls and reset on both active planes."""
    if profile['planes'] != ['x', 'z']:
        raise ValueError('comparison requires both planes')
    text = '\n'.join((reference/name).read_text() for name in
                     ('phi_decoder_profile.v', 'phi_decoder_profile_top.v'))
    names = {m[1] for m in MODULE.finditer(text)}
    pattern = r'\b(?:'+'|'.join(map(re.escape, sorted(names)))+r')\b'
    (stage/'reference.v').write_text(re.sub(pattern, lambda m: 'baseline_'+m[0], text))
    bench = Path(__file__).resolve().parents[1]/'phi_compare_tb.sv'
    commands = [
        ['iverilog', '-g2012', '-s', 'phi_compare_tb', '-Pphi_compare_tb.CYCLE_EXACT=1',
         f'-Pphi_compare_tb.WIDTH={profile["width"]}', f'-Pphi_compare_tb.HEIGHT={profile["height"]}',
         '-o', 'compare.vvp', str(bench), 'reference.v', 'phi_decoder_profile.v',
         'phi_decoder_profile_top.v', 'hls_1r1w_ram.v'],
        ['vvp', 'compare.vvp']]
    for label, command in zip(('compile', 'simulation'), commands):
        with (stage/(label+'.log')).open('w') as log:
            subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1200)
    if 'PASS:' not in (stage/'simulation.log').read_text():
        raise ValueError('comparison did not finish')
    (stage/'comparison.json').write_text(json.dumps({'commands': commands, 'testbench_sha256': sha(bench),
        'log_sha256': sha(stage/'simulation.log'), 'cycle_exact': True}, indent=2)+'\n')
    (stage/'compare.vvp').unlink()
    (stage/'reference.v').unlink()


def main() -> None:
    """Require explicit baseline, generated candidate, compiler and patch provenance."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'generated', 'compiler', 'patch', 'stage'):
        parser.add_argument('--'+name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--depth', type=int)
    parser.add_argument('--payload-bits', type=int)
    prepare(parser.parse_args())


if __name__ == '__main__':
    main()
