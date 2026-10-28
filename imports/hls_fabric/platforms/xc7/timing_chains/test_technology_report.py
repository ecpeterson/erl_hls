"""Keep period, completion and provenance qualifications in device-comparison summaries."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from path_report import parse_vivado
from technology_report import audit, capacity, package, qualify_replay, resources, summary_markdown, verify_reports


ROOT = Path(__file__).resolve().parents[1]


def timing_summary(slack: float) -> str:
    """Provide the same twelve-column summary format as the completed XC7 reports."""
    return ('WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns) '
            'THS Failing Endpoints THS Total Endpoints WPWS(ns) TPWS(ns) TPWS Failing Endpoints TPWS Total Endpoints\n'
            '------- ------- --------------------- ------------------- ------- ------- --------------------- ------------------- -------- -------- ---------------------- --------------------\n'
            f'{slack} -181554.205 58684 100000 0.047 0.000 0 100000 1.720 0.000 0 2000\n')


def utilization() -> str:
    """Retain the hierarchical table's distinction between top and child counts."""
    return ('| Instance | Module | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs | RAMB36 | RAMB18 | DSP Blocks |\n'
            '| harness | (top) | 52884 | 52881 | 0 | 3 | 26895 | 28 | 4 | 16 |\n'
            '| decoder | decoder | 50000 | 49997 | 0 | 3 | 26000 | 28 | 4 | 16 |\n')


def device_capacity() -> str:
    """Distinguish available target resources from this design's mapped usage."""
    return ('| Site Type | Used | Fixed | Prohibited | Available | Util% |\n'
            '| Slice LUTs* | 52884 | 0 | 0 | 78600 | 67.28 |\n'
            '| Slice Registers | 26895 | 0 | 0 | 157200 | 17.10 |\n'
            '| Block RAM Tile | 30 | 0 | 0 | 265 | 11.32 |\n')


class TechnologyReportTest(unittest.TestCase):
    """A completed batch and a setup-derived period must not imply physical timing closure."""

    def vendor_path(self) -> str:
        """Use an existing retained single-cycle routed path as a parser fixture."""
        return (ROOT / 'timing_chains/fixtures/dsp-chain.rpt').read_text()

    def test_audit_and_derived_period_use_setup_slack(self) -> None:
        """Include setup/skew in the period while keeping hold and pulse failures independent."""
        path, = parse_vivado(self.vendor_path())
        checked = audit(timing_summary(-10.846))
        self.assertAlmostEqual(path['period_ns'], 5 - checked['setup_slack_ns'])
        self.assertAlmostEqual(checked['hold_slack_ns'], .047)
        self.assertEqual(checked['setup_failing_endpoints'], 58684)
        self.assertEqual(checked['hold_failing_endpoints'], 0)
        self.assertEqual(resources(utilization())['Total LUTs'], 52884)
        self.assertEqual(capacity(device_capacity()), {'lut_sites': 78600, 'registers': 157200, 'bram36_tiles': 265})

    def test_report_fingerprints_cannot_be_replaced_by_fresh_hashes(self) -> None:
        """An archive hash does not excuse disagreement with the execution-time identity."""
        reports = {'paths.rpt': {'member': 'results/run/paths.rpt', 'sha256': 'known'}}
        self.assertIn('verified', verify_reports({'outputs': {'results/run/paths.rpt': 'known'}}, reports))
        self.assertIn('unavailable', verify_reports({}, reports))
        with self.assertRaisesRegex(ValueError, 'changed or unpinned'):
            verify_reports({'outputs': {'results/run/paths.rpt': 'different'}}, reports)

    def test_full_tile_never_acquires_scaled_mesh_time(self) -> None:
        """Only a completed replay with pinned cycles receives a derived step-time proxy."""
        row = {'job': {'fixture': 'baseline-four'}, 'complete': True, 'timing': {'routed': {'period_ns': 14.585}}}
        qualify_replay(row, {'cycles_per_step': 120})
        self.assertAlmostEqual(row['derived_replay_step_us'], 1.7502)
        for fixture, complete in [('full-tile', True), ('pipeline-four', False)]:
            row = {'job': {'fixture': fixture}, 'complete': complete, 'timing': {'routed': {'period_ns': 14.585}}}
            qualify_replay(row, {'cycles_per_step': 247.3875})
            self.assertNotIn('derived_replay_step_us', row)

    def test_partial_run_remains_visible_without_a_route_claim(self) -> None:
        """A truncated live synthesis report must not prevent completed results being packaged."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'results' / 'partial'
            folder.mkdir(parents=True)
            (folder / 'synthesis-paths.rpt').write_text('Slack (VIOLATED) : -1.0ns\n')
            status = {'identity': {'job': {'name': 'partial', 'fixture': 'full-tile', 'part': 'xc7z030sbg485-1', 'period_ns': 5}},
                      'complete': False, 'exit': 1, 'seconds': 12}
            (root / 'partial-status.json').write_text(json.dumps(status))
            report = package(root, root / 'packaged')
            row, = report['runs']
            self.assertEqual(row['timing'], {})
            self.assertIn('partial synthesized path report omitted', row['notes'])
            text = (root / 'packaged/summary.md').read_text()
            self.assertIn('failed (1)', text)
            self.assertIn('full-tile', text)
            status.update(exit=None, seconds=2400)
            (root / 'partial-status.json').write_text(json.dumps(status))
            timed_out = package(root, root / 'timeout')
            self.assertEqual(timed_out['runs'][0]['execution_status'], 'timed out')
            self.assertIn('no completed implementation or capacity conclusion', summary_markdown(timed_out))

    def test_packaged_reports_pin_worst_path_and_cycle_manifest(self) -> None:
        """Archive one real path and reject disagreement with its paired timing summary."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'results' / 'done'
            folder.mkdir(parents=True)
            files = {'paths.rpt': self.vendor_path(), 'synthesis-paths.rpt': self.vendor_path(),
                     'utilization.rpt': utilization(), 'timing.rpt': timing_summary(-10.846),
                     'coverage.rpt': 'checking no_clock (0)\nchecking unconstrained_internal_endpoints (0)\n',
                     'route.rpt': 'fully routed', 'drc.rpt': 'no errors'}
            for name, text in files.items():
                (folder / name).write_text(text)
            status = {'identity': {'job': {'name': 'done', 'fixture': 'baseline-four', 'part': 'xc7z030sbg485-1', 'period_ns': 5}},
                      'complete': True, 'exit': 0,
                      'outputs': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in folder.iterdir()}}
            (root / 'done-status.json').write_text(json.dumps(status))
            (root / 'manifest.json').write_text(json.dumps({'fixtures': {'baseline-four': {'cycles_per_step': 120}}}))
            summary = package(root, root / 'packaged')
            self.assertAlmostEqual(summary['runs'][0]['derived_replay_step_us'], 1.90152)
            self.assertIn('15.846 / 15.846', summary_markdown(summary))
            (folder / 'timing.rpt').write_text(timing_summary(-9.585))
            status['outputs']['results/done/timing.rpt'] = hashlib.sha256((folder / 'timing.rpt').read_bytes()).hexdigest()
            (root / 'done-status.json').write_text(json.dumps(status))
            with self.assertRaisesRegex(ValueError, 'summary disagree'):
                package(root, root / 'mismatched')

    def test_synthesis_completion_has_no_route_or_replay_claim(self) -> None:
        """A successful area screen stays useful without inventing placement or route evidence."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'results' / 'synth'
            folder.mkdir(parents=True)
            files = {'synthesis-paths.rpt': self.vendor_path(),
                     'synthesis-utilization.rpt': utilization(),
                     'synthesis-capacity.rpt': device_capacity(),
                     'synthesis-timing.rpt': timing_summary(-10.846),
                     'paths.rpt': 'unqualified extra route artifact'}
            for name, text in files.items():
                (folder / name).write_text(text)
            status = {'identity': {'job': {'name': 'synth', 'fixture': 'baseline-four',
                      'part': 'xc7z030sbg485-1', 'period_ns': 5, 'stop_after': 'synthesis'}},
                      'complete': True, 'exit': 0, 'seconds': 42,
                      'outputs': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in folder.iterdir()}}
            (root / 'synth-status.json').write_text(json.dumps(status))
            (root / 'manifest.json').write_text(json.dumps({'fixtures': {'baseline-four': {'cycles_per_step': 120}}}))
            summary = package(root, root / 'packaged')
            row, = summary['runs']
            self.assertTrue(row['complete'])
            self.assertEqual(row['execution_status'], 'synthesis complete')
            self.assertEqual(row['synthesis_resources']['Total LUTs'], 52884)
            self.assertEqual(row['device_capacity']['lut_sites'], 78600)
            self.assertEqual(set(row['timing']), {'synthesized'})
            self.assertAlmostEqual(row['timing']['synthesized']['period_ns'], 15.846)
            self.assertEqual(row['synthesis_audit']['hold_failing_endpoints'], 0)
            self.assertNotIn('resources', row)
            self.assertNotIn('audit', row)
            self.assertNotIn('derived_replay_step_us', row)
            text = summary_markdown(summary)
            self.assertIn('15.846 / —', text)
            self.assertIn('52884 / 26895 (synth)', text)
            self.assertIn('no placement, routing or physical-fit', text)
            self.assertIn('78,600 LUT sites', text)
            retained = json.loads((root / 'packaged/manifest.json').read_text())
            self.assertEqual([run['stage'] for run in retained['runs']], ['synthesized'])
            (folder / 'synthesis-capacity.rpt').write_text(device_capacity().replace('78600', '90000'))
            with self.assertRaisesRegex(ValueError, 'changed or unpinned'):
                package(root, root / 'changed-capacity')
            (folder / 'synthesis-capacity.rpt').write_text(device_capacity())
            (folder / 'synthesis-timing.rpt').write_text(timing_summary(-9.0))
            status['outputs']['results/synth/synthesis-timing.rpt'] = hashlib.sha256(
                (folder / 'synthesis-timing.rpt').read_bytes()).hexdigest()
            (root / 'synth-status.json').write_text(json.dumps(status))
            with self.assertRaisesRegex(ValueError, 'summary disagree'):
                package(root, root / 'disagrees')
            (folder / 'synthesis-timing.rpt').unlink()
            del status['outputs']['results/synth/synthesis-timing.rpt']
            (root / 'synth-status.json').write_text(json.dumps(status))
            with self.assertRaisesRegex(ValueError, 'completed synthesis is missing'):
                package(root, root / 'missing')


if __name__ == '__main__':
    unittest.main()
