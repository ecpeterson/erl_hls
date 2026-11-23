#!/usr/bin/env python3
"""Export a preserved mapped application for the vendor timing harness."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
from characterize import run, sha


def prepare(mapped: Path, top: str, stage: Path, yosys: Path) -> None:
    """Rename the top, remove scope metadata, and explicitly choose unspecified INIT bits."""
    source = json.loads(mapped.read_text())
    module = deepcopy(source['modules'][top])
    if 'clock' not in module['ports']:
        raise ValueError('the measurement harness requires a clock port named clock')
    stage.mkdir(parents=True, exist_ok=False)
    removed = [name for name, cell in module['cells'].items() if cell['type'] == '$scopeinfo']
    for name in removed:
        del module['cells'][name]
    defined = []
    for name, cell in module['cells'].items():
        for key, value in cell['parameters'].items():
            if key.startswith(('INIT', 'SRVAL')) and isinstance(value, str) and 'x' in value:
                defined.append([name, key, value])
                cell['parameters'][key] = value.replace('x', '0')
    data = dict(source, modules={'probe_top': module})
    (stage/'mapped.json').write_text(json.dumps(data, separators=(',', ':'))+'\n')
    # INIT includes both startup values and LUT don't-care truth-table entries.
    # Choosing their unspecified bits makes the imported graph unambiguous;
    # it does not establish equivalence outside the original defined behavior.
    (stage/'normalization.json').write_text(json.dumps({
        'source_sha256': sha(mapped), 'source_top': top,
        'removed_scope_markers': removed, 'defined_initialization_fields': defined,
        'yosys_sha256': sha(yosys)}, indent=2)+'\n')
    command = [str(yosys), '-Q', '-q', '-p',
        'read_verilog -lib +/xilinx/cells_sim.v; read_json mapped.json; write_edif -pvector bra mapped.edf']
    (stage/'command.json').write_text(json.dumps(command, indent=2)+'\n')
    run(command, stage, 'edif', timeout=900)


def main() -> None:
    """Prepare one mapped top without resynthesis or flattening."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mapped', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    parser.add_argument('--top', required=True)
    parser.add_argument('--yosys', type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    prepare(args.mapped, args.top, args.stage, args.yosys)


if __name__ == '__main__':
    main()
