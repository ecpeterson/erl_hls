#!/usr/bin/env python3
"""Retain compact device-comparison evidence and use the shared timing-path reporter."""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import re
import tarfile
from typing import Callable

from path_report import build, markdown, parse_vivado, read_artifact


def resources(text: str) -> dict[str, int]:
    """Read top-level counts from Vivado's hierarchical utilization table."""
    columns = None
    for line in text.splitlines():
        cells = [cell.strip() for cell in line.split('|')[1:-1]]
        if 'Total LUTs' in cells:
            columns = cells
        elif columns is not None and len(cells) == len(columns) and cells[1] == '(top)':
            return {name: int(value) for name, value in zip(columns[2:], cells[2:])}
    raise ValueError('missing top-level utilization row')


def hierarchy(text: str, classify: Callable[[list[dict]], str] | None = None) -> dict:
    """Label exclusive rows with an optional lineage classifier; retain LUT reconciliation and conserved FF/memory totals."""
    columns, rows = None, []
    for line in text.splitlines():
        raw = line.split('|')[1:-1]
        cells = [cell.strip() for cell in raw]
        if 'Total LUTs' in cells:
            columns = cells
        elif columns is not None and len(cells) == len(columns):
            rows.append({'instance': cells[0], 'module': cells[1],
                         'depth': len(raw[0]) - len(raw[0].lstrip()),
                         'resources': {key: int(value) for key, value in zip(columns[2:], cells[2:])}})
    if not rows or rows[0]['module'] != '(top)':
        raise ValueError('native hierarchy requires its top-level total')
    groups, leaves, stack = {}, [], []
    for index, row in enumerate(rows):
        while stack and stack[-1]['depth'] >= row['depth']:
            stack.pop()
        lineage = [*stack, row]
        stack.append(row)
        if index + 1 < len(rows) and rows[index + 1]['depth'] > row['depth']:
            continue
        group = classify(lineage) if classify is not None else 'remaining'
        total = groups.setdefault(group, {key: 0 for key in row['resources']})
        for key, count in row['resources'].items():
            total[key] += count
        leaves.append({'path': '/'.join(value['instance'] for value in lineage), 'module': row['module'],
                       'group': group, 'resources': row['resources']})
    summed = {key: sum(group[key] for group in groups.values()) for key in rows[0]['resources']}
    reported = rows[0]['resources']
    reconciliation = {key: reported[key] - summed[key] for key in summed}
    if any(count for key, count in reconciliation.items() if key not in ('Total LUTs', 'Logic LUTs')):
        raise ValueError('exclusive hierarchy resources do not sum to the top-level total')
    return {'scope': 'Exclusive reported hierarchy rows; parent self rows retain directly owned logic. FF and memory counts partition the top total. LUT hierarchy counts need not partition physical sites: top minus row-sum remains explicit, without assigning a cause or distributing the difference. Categories are generated boundaries, not removable area or dynamic occupancy.',
            'groups': groups, 'leaves': leaves, 'row_sum': summed, 'reconciliation': reconciliation, 'total': reported}


def capacity(text: str) -> dict[str, int | float]:
    """Read device limits from the standard utilization report, in shared BRAM36-tile units."""
    names = {'Slice LUTs': 'lut_sites', 'CLB LUTs': 'lut_sites',
             'Slice Registers': 'registers', 'CLB Registers': 'registers',
             'Block RAM Tile': 'bram36_tiles'}
    column, result = None, {}
    for line in text.splitlines():
        cells = [cell.strip() for cell in line.split('|')[1:-1]]
        if 'Available' in cells:
            column = cells.index('Available')
        elif column is not None and len(cells) > column and cells[0].rstrip('*') in names:
            value = float(cells[column])
            if not math.isfinite(value) or value <= 0:
                raise ValueError('invalid native device capacity')
            result[names[cells[0].rstrip('*')]] = int(value) if value.is_integer() else value
    if set(result) != {'lut_sites', 'registers', 'bram36_tiles'}:
        raise ValueError('missing LUT/register/BRAM device capacity')
    return result


def audit(text: str) -> dict:
    """Keep setup, hold and pulse slacks; a derived setup period is not closure."""
    match = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([^\n]+)', text)
    if match is None:
        raise ValueError('missing timing summary')
    fields = match[1].split()
    if len(fields) != 12:
        raise ValueError('unexpected timing summary columns')
    return {'setup_slack_ns': float(fields[0]), 'hold_slack_ns': float(fields[4]),
            'pulse_slack_ns': float(fields[8]), 'setup_failing_endpoints': int(fields[2]),
            'hold_failing_endpoints': int(fields[6]), 'pulse_failing_endpoints': int(fields[10])}


def verify_reports(status: dict, reports: dict[str, dict]) -> str:
    """Check execution-time fingerprints when present; label older first-capture evidence."""
    expected = status.get('outputs')
    if expected is None:
        return 'first captured report bytes; execution-time output hashes unavailable'
    actual = {artifact['member']: artifact['sha256'] for artifact in reports.values()}
    if actual != expected:
        raise ValueError('missing, changed or unpinned reports relative to completed run status')
    return 'report hashes verified against execution status'


def qualify_replay(row: dict, fixture: dict) -> None:
    """Attach a cycle-derived replay proxy only for the two explicitly named replay fixtures."""
    if not row['complete'] or row['job']['fixture'] not in ('baseline-four', 'pipeline-four') or 'routed' not in row['timing']:
        return
    cycles = fixture.get('cycles_per_step')
    if cycles is None:
        return
    if isinstance(cycles, bool) or not isinstance(cycles, (int, float)) or not math.isfinite(cycles) or cycles <= 0:
        raise ValueError('invalid manifest replay cycle count')
    row['replay_cycles_per_step'] = cycles
    row['derived_replay_step_us'] = cycles * row['timing']['routed']['period_ns'] / 1000


def summary_markdown(summary: dict) -> str:
    """Render device, period and resource comparisons without turning setup estimates into closure."""
    lines = ['# Native device comparison', '', summary['scope'], '',
             'Setup-derived period = requested period − worst setup slack. Logic/routing detail is in [paths.md](paths.md).', '',
             '| Fixture | Part | Setup period: synth / route (ns) | LUT / FF | BRAM36 / BRAM18 / DSP | Derived replay (µs) | Seconds | Status |',
             '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |']
    for row in summary['runs']:
        job, timing = row['job'], row['timing']
        periods = ' / '.join(f'{timing[phase]["period_ns"]:.3f}' if phase in timing else '—'
                             for phase in ('synthesized', 'routed'))
        resources = row.get('resources', row.get('synthesis_resources', {}))
        logic = ' / '.join(str(resources.get(key, '—')) for key in ('Total LUTs', 'FFs'))
        hard = ' / '.join(str(resources.get(key, '—')) for key in ('RAMB36', 'RAMB18', 'DSP Blocks'))
        if 'resources' not in row and resources:
            logic += ' (synth)'
            hard += ' (synth)'
        replay = f'{row["derived_replay_step_us"]:.3f}' if 'derived_replay_step_us' in row else '—'
        seconds = f'{row["seconds"]:.0f}' if row.get('seconds') is not None else '—'
        status = row.get('execution_status') or ('finished' if row['complete'] else
                  f'failed ({row["exit"]})' if row.get('exit') is not None and row['exit'] != 0 else 'unfinished')
        lines.append(f'| {job["fixture"]} | {job["part"]} | {periods} | {logic} | {hard} | {replay} | {seconds} | {status} |')
    lines += ['', '“Finished” means the batch reached its requested final reports, not that setup, hold, pulse-width or design-rule checks passed. '
              '“Synthesis complete” includes no placement, routing or physical-fit result. '
              'Replay values use only the manifest’s pinned baseline-four/pipeline-four cycle counts and the routed setup-derived period. '
              'The full tile receives no derived step time: independent link clocks prevent scaling the entire mesh by this period. '
              'Resources are routed unless marked “synth”.', '']
    for row in summary['runs']:
        if 'device_capacity' in row:
            available = row['device_capacity']
            lines.append(f'- `{row["job"]["name"]}` device limits from utilization: '
                         f'{available["lut_sites"]:,} LUT sites, {available["registers"]:,} registers, '
                         f'{available["bram36_tiles"]:g} BRAM36 tiles (RAMB18 consumes half a tile).')
        for key, label in [('synthesis_audit', 'synthesis'), ('audit', 'route')]:
            if key not in row:
                continue
            check = row[key]
            lines.append(f'- `{row["job"]["name"]}` ({label}): setup / hold / pulse slack '
                         f'{check["setup_slack_ns"]:.3f} / {check["hold_slack_ns"]:.3f} / {check["pulse_slack_ns"]:.3f} ns; '
                         f'failing endpoints {check["setup_failing_endpoints"]} / {check["hold_failing_endpoints"]} / {check["pulse_failing_endpoints"]}.')
        for note in row.get('notes', []):
            lines.append(f'- `{row["job"]["name"]}`: {note}.')
    return '\n'.join(lines) + '\n'


def package(root: Path, output: Path) -> dict:
    """Freeze reports and statuses, excluding checkpoints and unfinished timing claims."""
    output.mkdir(parents=True, exist_ok=True)
    evidence = {}
    manifest = {'schema': 1, 'title': 'Matched native device comparison', 'runs': []}
    summary = {'scope': 'One synthesis or placement run for each fixture and target, as requested by its job; each fixture keeps its portable RTL and XLS schedule unchanged across device targets. '
                       'Native mapping differs by target. Setup-derived periods are not closure runs.',
               'runs': []}

    def keep(path: Path) -> dict:
        """Index each immutable report by content, relative to its evidence archive."""
        member = str(path.relative_to(root))
        if member not in evidence:
            evidence[member] = path.read_bytes()
        data = evidence[member]
        return {'path': 'evidence.tar.gz', 'member': member, 'sha256': hashlib.sha256(data).hexdigest()}

    def captured(artifact: dict) -> str:
        """Parse exactly the bytes retained in the evidence archive, including live-run snapshots."""
        return evidence[artifact['member']].decode()

    fixture_manifest = json.loads(captured(keep(root / 'manifest.json'))) if (root / 'manifest.json').exists() else {}

    for status_path in sorted(root.glob('*-status.json')):
        status_artifact = keep(status_path)
        status = json.loads(captured(status_artifact))
        job = status['identity']['job']
        stop_after = job.get('stop_after', 'route')
        if stop_after not in ('synthesis', 'route'):
            raise ValueError('unknown requested measurement stage')
        folder = root / 'results' / job['name']
        row = {'job': job, 'complete': status['complete'], 'exit': status.get('exit'),
               'seconds': status.get('seconds'), 'status': status_artifact, 'timing': {}, 'notes': [],
               'requested_stage': stop_after}
        if stop_after == 'synthesis':
            row['notes'].append('synthesis-only screen; no placement, routing or physical-fit conclusion')
            if status['complete']:
                row['execution_status'] = 'synthesis complete'
        if not status['complete'] and 'exit' in status and status['exit'] is None and status.get('seconds') is not None:
            row['execution_status'] = 'timed out'
            row['notes'].append('timeout provides no completed implementation or capacity conclusion')
        kept = {path.name: keep(path) for path in sorted(folder.glob('*.rpt'))}
        for path in folder.glob('version.txt'):
            keep(path)
        console = root / f'{job["name"]}-console.log'
        if console.is_file():
            keep(console)
        fixture = fixture_manifest.get('fixtures', {}).get(job['fixture'], {})
        if fixture.get('sources'):
            expected_inputs = {f'inputs/{job["fixture"]}/{name}': digest for name, digest in fixture['sources'].items()}
            if any(status['identity']['inputs'].get(name) != digest for name, digest in expected_inputs.items()):
                raise ValueError('run input identity disagrees with fixture manifest')
        if 'outputs' in status or status['complete']:
            row['notes'].append(verify_reports(status, kept))
        if 'synthesis-utilization.rpt' in kept:
            try:
                row['synthesis_resources'] = resources(captured(kept['synthesis-utilization.rpt']))
            except ValueError:
                if status['complete']:
                    raise
                row['notes'].append('partial synthesis utilization report omitted')
        if 'synthesis-capacity.rpt' in kept:
            try:
                row['device_capacity'] = capacity(captured(kept['synthesis-capacity.rpt']))
            except ValueError:
                if status['complete']:
                    raise
                row['notes'].append('partial device capacity report omitted')
        phases = [('synthesized', 'synthesis-paths.rpt')] if 'synthesis-paths.rpt' in kept else []
        # Failed/in-progress runs remain evidence but do not acquire a complete route result.
        if status['complete'] and stop_after == 'synthesis':
            required = {'synthesis-utilization.rpt', 'synthesis-timing.rpt', 'synthesis-paths.rpt'}
            if not required <= kept.keys():
                raise ValueError('completed synthesis is missing required reports')
            row['synthesis_audit'] = audit(captured(kept['synthesis-timing.rpt']))
        if status['complete'] and stop_after == 'route':
            required = {'utilization.rpt', 'timing.rpt', 'coverage.rpt', 'paths.rpt', 'route.rpt', 'drc.rpt'}
            if not required <= kept.keys():
                raise ValueError('completed run is missing required reports')
            row['resources'] = resources(captured(kept['utilization.rpt']))
            row['audit'] = audit(captured(kept['timing.rpt']))
            row['coverage'] = {name: int(count) for name, count in re.findall(
                r'checking (\w+) \((\d+)\)', captured(kept['coverage.rpt']))}
            phases.append(('routed', 'paths.rpt'))
        for phase, filename in phases:
            try:
                paths = parse_vivado(captured(kept[filename]))
            except ValueError:
                if status['complete']:
                    raise
                row['notes'].append(f'partial {phase} path report omitted')
                continue
            worst = max(paths, key=lambda p: p['period_ns'])
            phase_audit = row.get('audit' if phase == 'routed' else 'synthesis_audit')
            if phase_audit is not None and abs(worst['period_ns'] - (job['period_ns'] - phase_audit['setup_slack_ns'])) > .002:
                raise ValueError('worst path and setup timing summary disagree')
            row['timing'][phase] = {k: worst[k] for k in (
                'period_ns', 'logic_ns', 'route_ns', 'source', 'destination')}
            if not status['complete']:
                row['notes'].append(f'{phase} timing is a captured snapshot from an unfinished run')
            manifest['runs'].append({'name': job['name'], 'tool': 'vivado', 'stage': phase,
                'constraint_ns': job['period_ns'], 'paths': kept[filename], 'added_cycles': []})
        qualify_replay(row, fixture)
        summary['runs'].append(row)
    for leaf in ('plan.json', 'manifest.json'):
        if (root / leaf).exists():
            keep(root / leaf)
    with tarfile.open(output / 'evidence.tar.gz', 'w:gz') as archive:
        for name, data in sorted(evidence.items()):
            member = tarfile.TarInfo(name)
            member.size, member.mtime = len(data), 0
            archive.addfile(member, io.BytesIO(data))
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (output / 'summary.md').write_text(summary_markdown(summary))
    report = build(manifest, output)
    (output / 'paths.md').write_text(markdown(report))
    return summary


def screen_policy_sha256(policy: dict) -> str:
    """Hash sorted compact UTF-8 JSON, with ASCII escaping, finite numbers and no newline."""
    return hashlib.sha256(json.dumps(policy, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def screen_artifact(spec: dict, root: Path) -> tuple[str, dict]:
    """Read only explicitly hash-pinned evidence; never adopt live files' current hashes."""
    if not re.fullmatch(r'[0-9a-f]{64}', spec.get('sha256', '')):
        raise ValueError('screen evidence requires an existing SHA-256 pin')
    return read_artifact(spec, root)


def screen_run(reference: dict, root: Path, view: str) -> dict:
    """Read frozen synthesis evidence and its recorded boundary, retaining incomplete-run limits."""
    summary_text, summary_pin = screen_artifact(reference['summary'], root)
    summary = json.loads(summary_text)
    matches = [row for row in summary['runs'] if row['job']['name'] == reference['job']]
    if len(matches) != 1:
        raise ValueError('screen requires one explicitly named native job')
    row, = matches
    archive_root = (root / reference['summary']['path']).parent
    status_text, status_pin = screen_artifact(row['status'], archive_root)
    status = json.loads(status_text)
    identity, job = status['identity'], row['job']
    if identity['job'] != job or status['complete'] != row['complete']:
        raise ValueError('summary disagrees with frozen execution status')
    reports, pins = {}, {}
    for name in ('utilization', 'capacity', 'timing', 'paths'):
        member = f'results/{job["name"]}/synthesis-{name}.rpt'
        reports[name], pins[name] = screen_artifact({
            'path': row['status']['path'], 'member': member,
            'sha256': status.get('outputs', {}).get(member, '')}, archive_root)
    # Complete execution plus frozen reports qualifies this phase of a route run.
    audit(reports['timing'])
    paths = parse_vivado(reports['paths'])
    if not paths or any(abs(path['requirement_ns'] - job['period_ns']) > .002 for path in paths):
        raise ValueError('synthesis path constraints disagree with the native job')
    nodes = {}

    def retain(lineage: list[dict]) -> str:
        """Retain inclusive and parent-self rows without adding them to the exclusive partition."""
        for index, node in enumerate(lineage):
            path = '/'.join(value['instance'] for value in lineage[:index + 1])
            nodes[path] = {'module': node['module'], 'resources': node['resources']}
        return 'remaining'

    census = hierarchy(reports['utilization'], retain)
    boundary = reference['boundary_path']
    if boundary not in nodes:
        raise ValueError('explicit component boundary is absent from the utilization report')
    selected = boundary
    if view == 'own':
        children = [path for path in nodes if path.startswith(boundary + '/')]
        selected = boundary + '/(' + boundary.rsplit('/', 1)[-1] + ')' if children else boundary
    if selected not in nodes:
        raise ValueError('component self row is missing; own area cannot be inferred')
    rtl = {name: sha for name, sha in identity['inputs'].items() if name.endswith('.v')}
    if not rtl or any(not re.fullmatch(r'[0-9a-f]{64}', sha) for sha in rtl.values()):
        raise ValueError('native execution lacks pinned RTL input identities')
    return {'job': job, 'version': identity['version'],
            'flow_sha256': identity['inputs'].get('technology_compare.tcl'),
            'rtl_sha256': rtl, 'complete': status['complete'], 'exit': status.get('exit'),
            'boundary': {'path': boundary, 'view': view, **nodes[selected]},
            'device_capacity': capacity(reports['capacity']), 'hierarchy': census,
            'evidence': {'summary': summary_pin, 'status': status_pin, 'reports': pins}}


def screen(spec: dict, root: Path) -> dict:
    """Compare recorded identities and LUT budgets; incomplete/unregistered evidence is inconclusive."""
    result = {'status': 'inconclusive', 'reasons': [], 'runs': {},
              'analysis_sha256': {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                                  for name in ('technology_report.py', 'path_report.py')},
              'scope': 'Synthesis budget screen only; no placement, route-fit or throughput acceptance. '
                       'Configuration is an execution-recorded declaration, not inferred from RTL.'}
    try:
        policy = spec['policy']
        result.update(policy=policy, policy_sha256=screen_policy_sha256(policy))
        if spec.get('schema') != 1 or policy['scope'] not in ('full_design', 'isolated_component'):
            raise ValueError('unknown screen schema or scope')
        if policy['boundary']['view'] not in ('inclusive', 'own') or not policy['boundary']['id']:
            raise ValueError('screen requires an explicit boundary identity and view')
        if not isinstance(policy['config'], dict) or not policy['config']:
            raise ValueError('screen requires explicit row/fan-in and fixed configuration identity')
        config = policy['config']
        rows = config.get('controller_rows', [config.get('row_count')])
        fan_in = config.get('controller_fan_in', [config.get('fan_in')])
        if not isinstance(rows, list) or not isinstance(fan_in, list) or not rows or len(rows) != len(fan_in) or any(
                type(value) is not int or value <= 0 for value in rows + fan_in):
            raise ValueError('screen requires positive row/fan-in counts for every compared controller')
        if not policy['part'] or not policy['tool_version'] or not re.fullmatch(r'[0-9a-f]{64}', policy['flow_sha256']):
            raise ValueError('screen requires exact target, tool and flow identities')
        if isinstance(policy['period_ns'], bool) or not math.isfinite(policy['period_ns']) or policy['period_ns'] <= 0:
            raise ValueError('screen requires a finite positive clock constraint')
        if any(type(policy[name]) is not int or policy[name] < 0
               for name in ('max_lut_delta', 'max_candidate_luts')):
            raise ValueError('screen LUT allowances must be explicit nonnegative integers')
    except (KeyError, TypeError, ValueError) as error:
        result['reasons'].append(f'invalid policy: {error}')
        return result
    for role in ('baseline', 'candidate'):
        try:
            row = screen_run(spec[role], root, policy['boundary']['view'])
            result['runs'][role] = row
            job, registration = row['job'], row['job'].get('area_screen', {})
            if not isinstance(registration, dict):
                raise ValueError('invalid recorded area_screen identity')
            checks = {'part': job['part'], 'tool_version': row['version'],
                      'flow_sha256': row['flow_sha256'], 'period_ns': job['period_ns'],
                      'scope': registration.get('scope'), 'config': registration.get('config')}
            result['reasons'].extend(f'{role}: unmatched {key}' for key, value in checks.items()
                                     if value != policy[key])
            expected_boundary = {**policy['boundary'], 'path': spec[role]['boundary_path']}
            if registration.get('boundary') != expected_boundary:
                result['reasons'].append(f'{role}: missing or unmatched recorded boundary')
            if not row['complete'] or row['exit'] != 0 or job.get('stop_after', 'route') not in ('synthesis', 'route'):
                result['reasons'].append(f'{role}: native execution is incomplete; synthesis phase is not qualified')
            if role == 'candidate' and registration.get('policy_sha256') != result['policy_sha256']:
                result['reasons'].append('candidate: allowance policy was not pinned by execution')
        except (KeyError, TypeError, ValueError, OSError, tarfile.TarError) as error:
            result['reasons'].append(f'{role}: unavailable or invalid evidence: {error}')
    if len(result['runs']) == 2:
        baseline, candidate = (result['runs'][role] for role in ('baseline', 'candidate'))
        clocks = [row['job'].get('clock') for row in (baseline, candidate)]
        if any(not isinstance(clock, str) or not clock.strip() for clock in clocks) or clocks[0] != clocks[1]:
            result['reasons'].append('missing or unmatched execution clock ports')
        # Historical versions of this flow hard-coded two threads.
        threads = [row['job'].get('max_threads', 2) for row in (baseline, candidate)]
        if any(type(value) is not int or not 1 <= value <= 8 for value in threads) or threads[0] != threads[1]:
            result['reasons'].append('invalid or unmatched execution thread limits')
        if baseline['device_capacity'] != candidate['device_capacity']:
            result['reasons'].append('device capacities disagree')
        old, new = (row['boundary']['resources']['Total LUTs'] for row in (baseline, candidate))
        result['comparison'] = {'baseline_luts': old, 'candidate_luts': new, 'lut_delta': new - old,
                                'device_lut_sites': candidate['device_capacity']['lut_sites']}
        exceeded = new > policy['max_candidate_luts'] or new - old > policy['max_lut_delta']
        result['comparison']['exceeds_engineering_budget'] = exceeded
        if policy['scope'] == 'full_design':
            if any(row['boundary']['resources'] != row['hierarchy']['total'] or
                   row['boundary']['module'] != '(top)' or policy['boundary']['view'] != 'inclusive'
                   for row in (baseline, candidate)):
                result['reasons'].append('full_design boundary must be the inclusive top')
            exceeded = exceeded or new > candidate['device_capacity']['lut_sites']
        if not result['reasons']:
            result['status'] = 'budget exceeded' if exceeded else 'within screening budget'
    return result


def screen_markdown(result: dict) -> str:
    """Keep budget diagnostics visible even when identity gaps prevent a prospective gate result."""
    lines = ['# Native synthesis budget screen', '', result['scope'], '', f'Status: **{result["status"]}**.', '']
    if 'comparison' in result:
        values = result['comparison']
        lines += ['| Baseline LUTs | Candidate LUTs | Delta | Target LUT sites |',
                  '| ---: | ---: | ---: | ---: |',
                  f'| {values["baseline_luts"]:,} | {values["candidate_luts"]:,} | '
                  f'{values["lut_delta"]:+,} | {values["device_lut_sites"]:,} |', '']
    if 'comparison' in result:
        policy = result['policy']
        lines += [f'Engineering ceilings: candidate {policy["max_candidate_luts"]:,} LUTs; '
                  f'increase {policy["max_lut_delta"]:,} LUTs.', '']
    lines += [f'- {reason}' for reason in result['reasons']]
    lines += ['', 'Inclusive boundaries and their descendant rows must not be added together. '
              'The JSON retains the exclusive breakdown and any LUT reconciliation. '
              'Allowances are engineering ceilings, not routing-headroom guarantees.', '']
    return '\n'.join(lines)


def main() -> None:
    """Package native evidence or screen pinned reports against an explicit synthesis budget."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, nargs='?')
    parser.add_argument('--screen', type=Path, help='Compare two pinned packaged runs using an explicit budget policy.')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.screen:
        if args.root is not None:
            parser.error('screen mode reads packaged evidence; omit the live run root')
        result = screen(json.loads(args.screen.read_text()), args.screen.resolve().parent)
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'screen.json').write_text(json.dumps(result, indent=2) + '\n')
        (args.output / 'screen.md').write_text(screen_markdown(result))
        print(json.dumps({'status': result['status'], 'reasons': result['reasons']}))
        raise SystemExit(0 if result['status'] == 'within screening budget' else 1)
    if args.root is None:
        parser.error('a native run root or --screen is required')
    summary = package(args.root, args.output)
    print(json.dumps({row['job']['name']: row['complete'] for row in summary['runs']}))


if __name__ == '__main__':
    main()
