#!/usr/bin/env python3
"""Isolate work-conserving arbitration by replacing only the dedicated egress leaf."""
import argparse
import json
from pathlib import Path
import re
import shutil

from architecture import sha

HERE = Path(__file__).resolve().parent
MODULE = '__phi_halo_cell__DedicatedEgress_0_next'


def ports(text: str) -> list[str]:
    """Require identical bit-level interfaces before substituting an RTL leaf."""
    return sorted(re.findall(r'^  (?:input|output) wire[^\n]+', text, re.M))


def prepare(reference: Path, stage: Path) -> None:
    """Copy a verified application and preserve every byte outside the replaced module."""
    manifest = json.loads((reference / 'phi_decoder_profile.build.json').read_text())
    rtl = reference / 'phi_decoder_profile.v'
    if sha(rtl) != manifest['rtl'][rtl.name]:
        raise ValueError('reference RTL changed')
    text = rtl.read_text()
    pattern = rf'^module {MODULE}\(.*?^endmodule'
    matches = list(re.finditer(pattern, text, re.M | re.S))
    if len(matches) != 1:
        raise ValueError('expected one shared dedicated egress definition')
    match = matches[0]
    candidate = (HERE / 'dedicated_egress.v').read_text()
    candidate = candidate[candidate.index('module '):].strip()
    if ports(candidate) != ports(match[0]):
        raise ValueError('egress interface changed')
    changed = text[:match.start()] + candidate + text[match.end():]
    if changed.replace(candidate, match[0], 1) != text:
        raise AssertionError('non-egress RTL changed')
    stage.mkdir(parents=True, exist_ok=False)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(reference / name, stage / name)
    (stage / rtl.name).write_text(changed)
    evidence = {'reference': str(reference), 'reference_rtl_sha256': sha(rtl),
                'replacement_sha256': sha(HERE / 'dedicated_egress.v'),
                'rtl_sha256': sha(stage / rtl.name), 'unchanged_other_modules': True}
    manifest['egress_experiment'] = evidence
    manifest['rtl'][rtl.name] = evidence['rtl_sha256']
    (stage / 'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (stage / 'egress.json').write_text(json.dumps(evidence, indent=2) + '\n')


def main() -> None:
    """Require an unused stage and an unchanged compiled dedicated fixture."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    prepare(args.reference, args.stage)


if __name__ == '__main__':
    main()
