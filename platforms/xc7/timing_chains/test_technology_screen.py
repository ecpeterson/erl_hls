"""Check prospective LUT budgets and retrospective diagnostics without running native tools."""
import copy
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from technology_report import hierarchy, screen, screen_markdown, screen_policy_sha256
from test_technology_report import timing_summary


def policy() -> dict:
    """Declare a full-design engineering ceiling independently of device capacity."""
    return {'part': 'xc7fixture', 'tool_version': 'Vivado fixture', 'flow_sha256': 'a' * 64,
            'period_ns': 5.0, 'scope': 'full_design',
            'config': {'controller_rows': [6, 6], 'controller_fan_in': [19, 22]},
            'boundary': {'id': 'whole', 'view': 'inclusive'},
            'max_lut_delta': 30, 'max_candidate_luts': 140}


def utilization(total: int) -> str:
    """Expose controller self, child and sibling rows; their FF counts partition the total."""
    return ('| Instance | Module | Total LUTs | FFs | RAMB36 | RAMB18 |\n'
            f'| top | (top) | {total} | 80 | 0 | 0 |\n'
            '|   (top) | (top) | 0 | 0 | 0 | 0 |\n'
            f'|   controller | service | {total - 20} | 60 | 0 | 0 |\n'
            f'|     (controller) | service | {total - 50} | 40 | 0 | 0 |\n'
            '|     child | executor | 30 | 20 | 0 | 0 |\n'
            '|   queue | fifo | 20 | 20 | 0 | 0 |\n')


def native(root: Path, name: str, total: int, expected: dict, *, registered: bool = True,
           complete: bool = True, stage: str = 'synthesis', change: str = '') -> dict:
    """Freeze reports and execution status; deliberate changes model identity/evidence defects."""
    folder = root / name
    folder.mkdir()
    boundary = 'top/controller' if expected['scope'] == 'isolated_component' else 'top'
    registration = {'scope': expected['scope'], 'config': copy.deepcopy(expected['config']),
                    'boundary': {**expected['boundary'], 'path': boundary},
                    'policy_sha256': screen_policy_sha256(expected)}
    if change == 'config':
        registration['config']['controller_fan_in'][0] += 1
    if change == 'policy':
        registration['policy_sha256'] = '0' * 64
    job = {'name': name, 'fixture': 'fixture', 'top': 'top', 'clock': 'clk',
           'part': expected['part'], 'period_ns': expected['period_ns'], 'stop_after': stage}
    if change == 'threads':
        job['max_threads'] = 8
    if change == 'target':
        job['part'] = 'other-target'
    if change == 'clock':
        job['clock'] = 'different_clock'
    if change == 'missing_clock':
        del job['clock']
    if change == 'boundary_identity':
        registration['boundary']['id'] = 'different-boundary'
    if registered:
        job['area_screen'] = registration
    files = {'synthesis-utilization.rpt': utilization(total),
             'synthesis-capacity.rpt': '| Site Type | Available |\n| CLB LUTs | 1000 |\n'
                 '| CLB Registers | 2000 |\n| Block RAM Tile | 10 |\n',
             'synthesis-timing.rpt': timing_summary(-10.846),
             'synthesis-paths.rpt': (Path(__file__).parent / 'fixtures/dsp-chain.rpt').read_text()}
    files = {f'results/{name}/{leaf}': text.encode() for leaf, text in files.items()}
    status = {'identity': {'job': job, 'version': 'other tool' if change == 'tool' else expected['tool_version'],
              'inputs': {'technology_compare.tcl': 'b' * 64 if change == 'flow' else expected['flow_sha256'],
                         f'inputs/fixture/{name}.v': hashlib.sha256(name.encode()).hexdigest()}},
              'complete': complete, 'exit': 0 if complete else 1,
              'outputs': {leaf: hashlib.sha256(data).hexdigest() for leaf, data in files.items()}}
    if change == 'capacity':
        del files[f'results/{name}/synthesis-capacity.rpt']
    if change == 'tamper':
        files[f'results/{name}/synthesis-utilization.rpt'] += b'changed\n'
    status_bytes = json.dumps(status).encode()
    files['status.json'] = status_bytes
    with tarfile.open(folder / 'evidence.tar.gz', 'w:gz') as archive:
        for leaf, data in files.items():
            item = tarfile.TarInfo(leaf)
            item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
    summary = {'runs': [{'job': job, 'complete': complete,
                'status': {'path': 'evidence.tar.gz', 'member': 'status.json',
                           'sha256': hashlib.sha256(status_bytes).hexdigest()}}]}
    data = json.dumps(summary).encode()
    (folder / 'summary.json').write_bytes(data)
    return {'summary': {'path': f'{name}/summary.json', 'sha256': hashlib.sha256(data).hexdigest()},
            'job': name, 'boundary_path': boundary}


class TechnologyScreenTest(unittest.TestCase):
    """A budget screen cannot silently substitute labels for frozen native evidence."""

    def test_hierarchy_counts_self_and_children_once(self) -> None:
        """Inclusive parents are omitted from the additive partition; LUT reconciliation stays visible."""
        value = hierarchy(utilization(100))
        self.assertEqual(value['row_sum'], value['total'])
        self.assertEqual([leaf['resources']['Total LUTs'] for leaf in value['leaves']], [0, 50, 30, 20])
        changed = hierarchy(utilization(100).replace('| 100 | 80 |', '| 97 | 80 |'))
        self.assertEqual(changed['reconciliation']['Total LUTs'], -3)
        with self.assertRaisesRegex(ValueError, 'do not sum'):
            hierarchy(utilization(100).replace('| 100 | 80 |', '| 100 | 81 |'))

    def test_registered_budget_pass_and_exceed_allow_different_rtl(self) -> None:
        """Engineering ceilings, not RTL equality or spare-device capacity, determine the screen."""
        for total, allowance, status in [(120, 30, 'within screening budget'), (135, 30, 'budget exceeded'), (150, 100, 'budget exceeded')]:
            with self.subTest(total=total), tempfile.TemporaryDirectory() as temporary:
                root, expected = Path(temporary), policy()
                expected['max_lut_delta'] = allowance
                spec = {'schema': 1, 'policy': expected,
                        'baseline': native(root, 'base', 100, expected),
                        'candidate': native(root, 'candidate', total, expected)}
                result = screen(spec, root)
                self.assertEqual(result['status'], status, result['reasons'])
                self.assertNotEqual(result['runs']['baseline']['rtl_sha256'], result['runs']['candidate']['rtl_sha256'])
                self.assertNotIn('timing', result)
                self.assertIn('no placement, route-fit or throughput acceptance', screen_markdown(result))

    def test_identity_mismatches_preserve_verified_diagnostics(self) -> None:
        """Matching user labels cannot replace actual tool/flow checks or the prior policy pin."""
        for change in ('threads', 'config', 'tool', 'flow', 'policy', 'target', 'clock', 'missing_clock', 'boundary_identity'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                root, expected = Path(temporary), policy()
                result = screen({'schema': 1, 'policy': expected,
                    'baseline': native(root, 'base', 100, expected),
                    'candidate': native(root, 'candidate', 120, expected, change=change)}, root)
                self.assertEqual(result['status'], 'inconclusive')
                self.assertEqual(result['comparison']['lut_delta'], 20)
                self.assertTrue(result['reasons'])

    def test_unregistered_historical_and_incomplete_runs_do_not_pass(self) -> None:
        """Frozen numbers remain visible when execution lacks configuration or phase completion."""
        for registered, complete in [(False, True), (True, False)]:
            with self.subTest(registered=registered), tempfile.TemporaryDirectory() as temporary:
                root, expected = Path(temporary), policy()
                result = screen({'schema': 1, 'policy': expected,
                    'baseline': native(root, 'base', 100, expected, registered=registered),
                    'candidate': native(root, 'candidate', 120, expected, complete=complete, stage='route')}, root)
                self.assertEqual(result['status'], 'inconclusive')
                self.assertEqual(result['comparison']['candidate_luts'], 120)

    def test_missing_or_changed_evidence_is_inconclusive(self) -> None:
        """Missing capacity, changed reports and missing summary pins cannot acquire fresh identities."""
        for change in ('capacity', 'tamper', 'unpin', 'boundary'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                root, expected = Path(temporary), policy()
                candidate = native(root, 'candidate', 120, expected, change=change)
                if change == 'unpin':
                    del candidate['summary']['sha256']
                if change == 'boundary':
                    candidate['boundary_path'] = 'missing'
                result = screen({'schema': 1, 'policy': expected,
                    'baseline': native(root, 'base', 100, expected), 'candidate': candidate}, root)
                self.assertEqual(result['status'], 'inconclusive')
                self.assertNotIn('comparison', result)

    def test_completed_route_supplies_frozen_synthesis_only(self) -> None:
        """A completed full route may contribute its hashed synthesis phase without a throughput claim."""
        with tempfile.TemporaryDirectory() as temporary:
            root, expected = Path(temporary), policy()
            result = screen({'schema': 1, 'policy': expected,
                'baseline': native(root, 'base', 100, expected, stage='route'),
                'candidate': native(root, 'candidate', 120, expected, stage='route')}, root)
            self.assertEqual(result['status'], 'within screening budget', result['reasons'])
            self.assertEqual(result['comparison']['candidate_luts'], 120)

    def test_explicit_own_boundary_excludes_children(self) -> None:
        """An isolated controller's own logic is not inflated by its nested executor."""
        with tempfile.TemporaryDirectory() as temporary:
            root, expected = Path(temporary), policy()
            expected.update(scope='isolated_component', boundary={'id': 'controller', 'view': 'own'})
            result = screen({'schema': 1, 'policy': expected,
                'baseline': native(root, 'base', 100, expected),
                'candidate': native(root, 'candidate', 120, expected)}, root)
            self.assertEqual(result['status'], 'within screening budget', result['reasons'])
            self.assertEqual(result['comparison']['baseline_luts'], 50)
            self.assertEqual(result['comparison']['candidate_luts'], 70)

    def test_policy_requires_quantified_configuration(self) -> None:
        """Arbitrary matching labels cannot replace row counts and producer fan-in identity."""
        for config in ({'label': 'same'}, {'controller_rows': [6], 'controller_fan_in': [19, 22]},
                       {'row_count': True, 'fan_in': 19}):
            expected = policy()
            expected['config'] = config
            result = screen({'schema': 1, 'policy': expected}, Path('.'))
            self.assertEqual(result['status'], 'inconclusive')
            self.assertIn('positive row/fan-in', result['reasons'][0])

    def test_policy_hash_uses_canonical_json(self) -> None:
        """Key ordering and pretty-print whitespace do not change the pre-execution policy identity."""
        expected = policy()
        self.assertEqual(screen_policy_sha256(expected), hashlib.sha256(
            json.dumps(expected, sort_keys=True, separators=(',', ':')).encode()).hexdigest())
        self.assertEqual(screen_policy_sha256(expected), screen_policy_sha256(json.loads(json.dumps(expected, indent=4))))


if __name__ == '__main__':
    unittest.main()
