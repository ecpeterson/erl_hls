#!/usr/bin/env python3
"""Freeze boundary comparisons and feed their paths into the standard timing report."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile

from path_report import build, enrich, markdown, parse_vivado


def variants() -> dict[str, str]:
    """Map measured names to successful source fixtures, excluding failed attempts."""
    return {f'no-{cut}-{size}': f'no-{cut}-{size}' +
            ('-v3' if (cut, size) == ('loader', 'four') else
             '-v2' if (cut, size) == ('committed', 'four') else '')
            for size in ('two', 'four')
            for cut in ('loader', 'completion', 'request', 'committed', 'load-boundaries')}


def census(directory: Path) -> dict:
    """Keep the exact interval and all scheduler populations, without renderer bindings."""
    data = json.loads((directory/'fullness.json').read_text())
    return {k: v for k, v in data.items() if k != 'schedulers'} | {
        'schedulers': [{k: s[k] for k in ('module', 'actors', 'counts', 'histograms')}
                       for s in data['schedulers']]}


def package(root: Path, output: Path, references: Path) -> dict:
    """Require complete checked runs and retain compact, hash-indexed evidence."""
    output.mkdir(parents=True, exist_ok=True)
    entries = {}
    def keep(path: Path, member: str) -> dict:
        """Pin a regular artifact to its relocatable archive member."""
        data = path.read_bytes()
        if member in entries and entries[member] != data:
            raise ValueError('duplicate evidence member: ' + member)
        entries[member] = data
        return {'path': 'evidence.tar.gz', 'member': member,
                'sha256': hashlib.sha256(data).hexdigest()}
    old = json.loads((references/'summary.json').read_text())
    manifest = {'schema': 1, 'title': 'Scheduler boundary removals: matched timing and feedback', 'runs': []}
    summary = {'reference_evidence_sha256': hashlib.sha256((references/'evidence.tar.gz').read_bytes()).hexdigest(),
               'part': 'xc7z030sbg485-1', 'constraint_ns': 5, 'placement': 'Default',
               'placements_per_variant': 1, 'runs': {}, 'references': {}}
    for name, fullname in (('two', 'independent'), ('four', 'pipeline-four')):
        for kind, ref in (('full', fullname), ('baseline', 'baseline' if name == 'two' else 'baseline-four')):
            summary['references'][f'{kind}-{name}'] = old['runs'][ref]
        folder = root/('full-four-fullness' if name == 'four' else 'full-two-fullness-v2')
        summary['references'][f'full-{name}']['fullness'] = census(folder)
        for path in folder.glob('fullness*'):
            keep(path, f'full-{name}/fullness/{path.name}')
    for name, fixture in variants().items():
        source, physical = root/fixture, root/'physical'/name
        status = json.loads((root/'physical'/f'{name}-status.json').read_text())
        if len(status) != 1 or status[0]['status'] != 'complete':
            raise ValueError('incomplete vendor measurement: '+name)
        validation = json.loads((source/'ablation.json').read_text())
        samples = validation['samples']
        if [s['stalled'] for s in samples] != [False, True]:
            raise ValueError('missing oracle readiness pattern: '+name)
        cycles = {('stalled' if s['stalled'] else 'normal'):
                  float(re.search(r'cycles_per_step=([\d.]+)', s['metrics'][0])[1]) for s in samples}
        mapping = json.loads((root/(name+'-map')/'mapping.json').read_text())
        cells = mapping['decoder_cells']
        folder = root/(f'fullness-{name}' if 'load-boundaries' in name else f'{name}-fullness')
        row = {'removed': validation['remove'], 'cycles': cycles,
               'events_per_run': samples[0]['events'], 'fullness': census(folder),
               'resources': {'LUT1-6': sum(cells.get('LUT'+str(i), 0) for i in range(1, 7)),
                             'FF': sum(v for k, v in cells.items() if k.startswith('FD'))} |
                            {k: v for k, v in cells.items() if k.startswith(('RAMB', 'DSP'))},
               'timing': {}}
        # Pin endpoint attribution before disposable flattened netlists are pruned.
        attribution = root/(name+'-endpoints.json')
        fingerprints = {'netlist_sha256': mapping['netlist_sha256'],
            'parser_sha256': hashlib.sha256(Path(__file__).with_name('path_report.py').read_bytes()).hexdigest(),
            'reports': {str(p.relative_to(physical)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for phase in ('linked', 'routed') for p in (physical/(phase+'-paths')).glob('*.rpt')}}
        cached = json.loads(attribution.read_text()) if attribution.exists() else None
        if cached is not None and cached.get('inputs') != fingerprints:
            cached = None
        netlist = None
        if cached is None:
            data = (root/(name+'-map')/'mapped.json').read_bytes()
            if hashlib.sha256(data).hexdigest() != mapping['netlist_sha256']:
                raise ValueError('mapped netlist changed after measurement: '+name)
            netlist = json.loads(data)
        if netlist is not None:
            netlist['modules'] = {'phi_timing_harness': netlist['modules']['phi_timing_harness']}
        worst_paths = {}
        for phase in ('linked', 'routed'):
            queries = {}
            worst_paths[phase] = {}
            for label in ('global', 'ram_read', 'ram_response', 'ram_write', 'register_control'):
                leaf = 'paths.rpt' if label == 'global' else f'paths-{label}.rpt'
                path = physical/(phase+'-paths')/leaf
                worst = max(parse_vivado(path.read_text()), key=lambda p: p['period_ns'])
                row['timing'].setdefault(phase, {})[label] = {
                    k: worst[k] for k in ('period_ns', 'logic_ns', 'route_ns')}
                queries[label] = keep(path, f'{name}/{phase}/{leaf}')
                if cached is None:
                    worst_paths[phase][label] = worst
            manifest['runs'].append({'name': name, 'tool': 'vivado',
                'stage': 'linked estimate' if phase == 'linked' else phase, 'constraint_ns': 5,
                'paths': queries.pop('global'), 'path_sets': queries,
                'cycles_per_step': cycles['normal'], 'added_cycles': []})
            keep(physical/(phase+'-paths')/'coverage.tsv', f'{name}/{phase}/coverage.tsv')
        if cached is None:
            enrich([path for phase in worst_paths.values() for path in phase.values()], netlist)
            attribution.write_text(json.dumps({'inputs': fingerprints, 'paths': worst_paths}, indent=2)+'\n')
        keep(attribution, f'{name}/endpoint-attribution.json')
        row['step_ns'] = row['timing']['routed']['global']['period_ns'] * cycles['normal']
        ref = summary['references']['full-'+name.rsplit('-', 1)[1]]
        row['step_change_percent'] = 100*(row['step_ns']/ref['step_ns']-1)
        summary['runs'][name] = row
        for path in (source/'ablation.json', root/(name+'-map')/'mapping.json',
                     root/(name+'-map')/'core-stat.json', physical/'normalization.json', physical/'command.json'):
            keep(path, f'{name}/provenance/{path.name}')
        for leaf in ('audit.json', 'routed-audit.json', 'inputs.json', 'version.txt', 'coverage.rpt', 'timing.rpt', 'route.rpt'):
            keep(physical/'vivado'/leaf, f'{name}/physical/{leaf}')
        for path in source.glob('*.x'):
            keep(path, f'{name}/source/{path.name}')
        for path in (source/'compiled').iterdir():
            if path.name.endswith(('.json', '.schedule', 'options.txt')):
                keep(path, f'{name}/compiler/{path.name}')
        for path in folder.glob('fullness*'):
            keep(path, f'{name}/fullness/{path.name}')
    for path in root.glob('*.log'):
        if path.name in ('contracts.log', 'dialyzer.log', 'tests.log', 'profile-tests.log'):
            keep(path, 'checks/'+path.name)
    with tarfile.open(output/'evidence.tar.gz', 'w:gz') as archive:
        for name, data in entries.items():
            member = tarfile.TarInfo(name)
            member.size, member.mtime = len(data), 0
            archive.addfile(member, io.BytesIO(data))
    (output/'evidence-index.json').write_text(json.dumps({n: {'bytes': len(b),
        'sha256': hashlib.sha256(b).hexdigest()} for n, b in entries.items()}, indent=2)+'\n')
    (output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    report = build(manifest, output)
    (output/'paths.md').write_text(markdown(report))
    for run in report['runs']:
        del run['paths']
    (output/'paths.json').write_text(json.dumps(report, indent=2)+'\n')
    return summary


def main() -> None:
    """Package completed local/vendor runs without rerunning synthesis or simulation."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'output', 'references'):
        parser.add_argument('--'+name, required=True, type=Path)
    args = parser.parse_args()
    summary = package(args.root, args.output, args.references)
    for name, row in summary['runs'].items():
        print(name, f"{row['step_ns']/1000:.3f} us, {row['step_change_percent']:+.1f}%")


if __name__ == '__main__':
    main()
