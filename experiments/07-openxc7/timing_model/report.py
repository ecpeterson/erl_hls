#!/usr/bin/env python3
"""Collect audited timing comparisons into compact, portable measurement evidence."""
import argparse
import json
from pathlib import Path
from typing import Any
from analyze import checked_path
from characterize import sha
from sdf import extract


def pipelines(corpora: list[Path]) -> list[dict[str, Any]]:
    """Report routed period, area and verified stream latency for each generated schedule."""
    rows = []
    for corpus in corpora:
        manifest = json.loads((corpus / 'manifest.json').read_text())
        for probe in manifest['probes']:
            root = corpus / probe['name']
            path, audit = checked_path(root)
            if 'PASS ' not in (root / 'simulation.log').read_text():
                raise ValueError(f'{root}: no passing streamed RTL test')
            rows.append({key: probe[key] for key in ('name', 'model', 'latency', 'initiation_interval', 'counts')} |
                        {'period_ps': round(1000 * (float(path['REQUIREMENT']) - float(path['SLACK']))),
                         'datapath_ps': round(1000 * float(path['DATAPATH_DELAY'])),
                         'cell_ps': round(1000 * float(path['DATAPATH_LOGIC_DELAY'])),
                         'wire_ps': round(1000 * float(path['DATAPATH_NET_DELAY'])),
                         'audit': audit, 'table_sha256': manifest['table_sha256'],
                         'codegen_sha256': manifest['codegen_sha256'],
                         'mapped_sha256': sha(root / 'mapped.json'),
                         'sdf_sha256': sha(root / 'vivado/routed.sdf')})
    return rows


def primitive_arcs(corpora: list[Path]) -> list[dict[str, Any]]:
    """Retain mode parameters and per-kind worst arcs for RAM/DSP calibration evidence."""
    rows = []
    for corpus in corpora:
        manifest = json.loads((corpus / 'manifest.json').read_text())
        for probe in manifest['probes']:
            root = corpus / probe['name']
            _, audit = checked_path(root)
            cells = json.loads((root / 'mapped.json').read_text())['modules']['probe_top']['cells']
            for measured in extract(root / 'vivado/routed.sdf'):
                if not measured['cell'].startswith(('RAMB', 'DSP48')):
                    continue
                params = cells[measured['instance']]['parameters']
                rows.append({'probe': probe['name'], 'cell': measured['cell'],
                             'mode': {k: v for k, v in params.items() if not k.startswith(('INIT', 'SRVAL'))},
                             'worst_ps': {kind: max(a['ps'] for a in measured['arcs'] if a['kind'] == kind)
                                          for kind in sorted({a['kind'] for a in measured['arcs']})},
                             'audit': audit, 'sdf_sha256': sha(root / 'vivado/routed.sdf')})
    return rows


def main() -> None:
    """Write reviewable summaries without checkpoints, host paths or full netlists."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('calibration', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--pipelines', type=Path, nargs='+', required=True)
    parser.add_argument('--hard-blocks', type=Path, nargs='+', required=True)
    parser.add_argument('--native', type=Path, required=True)
    args = parser.parse_args()
    calibration = json.loads(args.calibration.read_text())
    native = json.loads(args.native.read_text())
    result = {'schema': 1, 'part': calibration['part'], 'design_wide_clock_validated': False,
              'operation_tools': [{Path(key).name: value for key, value in tools.items()}
                                  for tools in calibration['tools']],
              'operations': [{k: row[k] for k in ('name', 'op', 'width', 'count', 'split',
                                                 'cell_ps', 'routed_ps', 'wire_ps', 'launch_ps', 'audit')} |
                             {'mapped_sha256': row['files']['mapped.json']}
                             for row in calibration['measurements']],
              'validation': calibration['validation'], 'errors': calibration['errors'],
              'pipelines': pipelines(args.pipelines), 'primitive_arcs': primitive_arcs(args.hard_blocks),
              'native_tools': native['tools'], 'native_seed': native['seed'],
              'native': [{'mode': row['mode'], 'variants': {
                  model: {'fmax_mhz': data['fmax']['clock']['achieved'],
                          'required_endpoints_covered': data['coverage']['endpoint_requirements_met']}
                  for model, data in row['variants'].items()}} for row in native['runs']]}
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
