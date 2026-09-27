#!/usr/bin/env python3
"""Replace selected modules in a frozen core, preserving all other RTL and ports."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from architecture import sha
from egress_experiment import ports


def substitute(reference: Path, generated: Path, stage: Path, selector: str) -> None:
    """Reject missing modules, changed interfaces or edits outside the requested modules."""
    original = reference / 'phi_decoder_profile.v'
    manifest = json.loads((reference / 'phi_decoder_profile.build.json').read_text())
    if sha(original) != manifest['rtl'][original.name]:
        raise ValueError('baseline differs from its manifest')
    old, new = original.read_text(), generated.read_text()
    names = [n for n in re.findall(r'^module (\w+)\(', old, re.M) if re.fullmatch(selector, n)]
    if not names:
        raise ValueError('no baseline modules match selector')
    pattern = re.compile(r'^module (' + '|'.join(map(re.escape, names)) + r')\(.*?^endmodule', re.M | re.S)
    replacements = {m[1]: m[0] for m in pattern.finditer(new)}
    if set(replacements) != set(names):
        raise ValueError('replacement modules missing')
    changes = []

    def replace(match: re.Match) -> str:
        """Check each module interface and record both implementations' identities."""
        before, after = match[0], replacements[match[1]]
        if ports(before) != ports(after):
            raise ValueError('module interface changed: ' + match[1])
        changes.append({'module': match[1], 'before': hashlib.sha256(before.encode()).hexdigest(),
                        'after': hashlib.sha256(after.encode()).hexdigest()})
        return after

    result = pattern.sub(replace, old)
    if pattern.sub('', result) != pattern.sub('', old):
        raise AssertionError('unselected RTL changed')
    stage.mkdir(parents=True, exist_ok=False)
    (stage / original.name).write_text(result)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(reference / name, stage / name)
    evidence = {'selector': selector, 'modules': changes, 'unchanged_other_modules': True,
                'unchanged_ports': True, 'inputs': {str(p): sha(p) for p in (original, generated)},
                'output': sha(stage / original.name)}
    manifest['module_substitution'] = evidence
    manifest['rtl'][original.name] = evidence['output']
    (stage / 'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (stage / 'substitution.json').write_text(json.dumps(evidence, indent=2) + '\n')


def main() -> None:
    """Require an explicit name pattern and fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'generated', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--modules', required=True, help='full-match regular expression for module names')
    args = parser.parse_args()
    substitute(args.reference, args.generated, args.stage, args.modules)


if __name__ == '__main__':
    main()
