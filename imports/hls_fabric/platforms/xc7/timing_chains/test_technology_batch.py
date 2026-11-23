"""Check that interrupted or stale physical measurements cannot become cached evidence."""
from pathlib import Path
import json
import hashlib
import tempfile
import unittest
from unittest.mock import patch

from technology_batch import execute, main


class CompletedVivado:
    """Write representative reports as a successful vendor-tool stand-in."""

    def __init__(self, command: list[str], cwd: Path, stdout: object, **_kwargs: object) -> None:
        """Emit the reports required for a completed measurement."""
        stage = Path(command[command.index('-tclargs') + 5])
        stage.mkdir(parents=True)
        synthesis_only = command[command.index('-tclargs') + 7] == 'synthesis'
        reports = ('synthesis-timing', 'synthesis-utilization', 'synthesis-paths') if synthesis_only else (
            'timing', 'synthesis-timing', 'paths', 'utilization', 'route', 'coverage', 'drc')
        for name in reports:
            (stage / f'{name}.rpt').write_text('measurement\n')
        stdout.write('TECHNOLOGY_SYNTHESIS_COMPLETE\n' if synthesis_only else 'TECHNOLOGY_COMPARE_COMPLETE\n')

    def wait(self, timeout: int) -> int:
        """Complete successfully without consuming a hardware license."""
        return 0


class EvidenceCacheTests(unittest.TestCase):
    """Exercise the input/output boundary that distinguishes a rerun from reused evidence."""

    def setUp(self) -> None:
        """Create a portable fixture and a fresh measurement directory."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / 'inputs' / 'fixture'
        source.mkdir(parents=True)
        (source / 'top.v').write_text('module top; endmodule\n')
        (self.root / 'technology_compare.tcl').write_text('# fixture\n')
        self.job = {'name': 'control', 'fixture': 'fixture', 'part': 'device',
                    'top': 'top', 'clock': 'clk'}

    def run_job(self) -> dict:
        """Execute against the small stand-in while preserving runner behavior."""
        with patch('technology_batch.subprocess.check_output', return_value='Vivado fixture'), \
                patch('technology_batch.subprocess.Popen', CompletedVivado):
            return execute(self.root, self.job, 1)

    def test_reuses_only_unchanged_complete_reports(self) -> None:
        """A missing or edited result must not reuse a previously successful status."""
        initial = self.run_job()
        self.assertTrue(initial['complete'])
        self.assertEqual(initial, self.run_job())
        report = self.root / 'results/control/timing.rpt'
        report.write_text('different measurement\n')
        with self.assertRaisesRegex(ValueError, 'changed reports'):
            self.run_job()
        report.unlink()
        with self.assertRaisesRegex(ValueError, 'changed reports'):
            self.run_job()

    def test_first_run_checks_validated_release(self) -> None:
        """A mislabeled old RTL bundle fails before invoking the vendor tool."""
        self.job['rtl_sha256'] = {'top.v': hashlib.sha256(b'new RTL').hexdigest()}
        with patch('technology_batch.subprocess.check_output') as version, \
                patch('technology_batch.subprocess.Popen') as launch, \
                self.assertRaisesRegex(ValueError, 'declared validated release'):
            execute(self.root, self.job, 1)
        version.assert_not_called()
        launch.assert_not_called()

    def test_validated_release_names_every_rtl_input(self) -> None:
        """The expected set includes wrappers; extra unpinned RTL cannot slip in."""
        source = self.root / 'inputs/fixture'
        self.job['rtl_sha256'] = {'top.v': hashlib.sha256((source / 'top.v').read_bytes()).hexdigest()}
        self.assertTrue(self.run_job()['complete'])
        (source / 'wrapper.v').write_text('module wrapper; endmodule\n')
        with self.assertRaisesRegex(ValueError, 'declared validated release'):
            self.run_job()

    def test_thread_setting_is_recorded_and_invalidates_reuse(self) -> None:
        """An eight-thread run cannot silently reuse evidence from the local default."""
        self.assertEqual(self.run_job()['identity']['job']['max_threads'], 2)
        self.job['max_threads'] = 8
        with self.assertRaisesRegex(ValueError, 'changed inputs'):
            self.run_job()
        self.job['name'] = 'eight-thread'
        result = self.run_job()
        self.assertEqual(result['identity']['job']['max_threads'], 8)
        self.assertEqual(result['command'][-2:], ['route', '8'])

    def test_invalid_threads_cannot_launch(self) -> None:
        """Reject malformed or unsupported settings before invoking the vendor tool."""
        for value in (0, 9, True, '8', 2.5):
            with self.subTest(value=value), patch('technology_batch.subprocess.check_output') as launch:
                self.job['max_threads'] = value
                with self.assertRaisesRegex(ValueError, 'max_threads'):
                    execute(self.root, self.job, 1)
                launch.assert_not_called()

    def test_changed_rtl_cannot_reuse_a_run(self) -> None:
        """Changing the workload requires a new measurement identity."""
        self.run_job()
        (self.root / 'inputs/fixture/top.v').write_text('module changed; endmodule\n')
        with self.assertRaisesRegex(ValueError, 'changed inputs'):
            self.run_job()

    def test_incomplete_run_is_preserved(self) -> None:
        """A failed run stays evidence and cannot silently become a successful rerun."""
        with patch.object(CompletedVivado, 'wait', return_value=1):
            self.assertFalse(self.run_job()['complete'])
        with self.assertRaisesRegex(ValueError, 'incomplete run'):
            self.run_job()

    def test_duplicate_job_names_cannot_launch(self) -> None:
        """Parallel jobs must not race over the same status, log and reports."""
        plan = self.root / 'plan.json'
        plan.write_text(json.dumps({'jobs': [self.job, self.job]}))
        with patch('sys.argv', ['technology_batch.py', str(plan), '--jobs', '2']), \
                patch('technology_batch.execute') as launch, \
                self.assertRaises(SystemExit) as error:
            main()
        self.assertEqual(error.exception.code, 2)
        launch.assert_not_called()

    def test_synthesis_is_never_reused_as_routing(self) -> None:
        """A completed area screen qualifies only its explicit synthesis stage."""
        self.job['stop_after'] = 'synthesis'
        result = self.run_job()
        self.assertTrue(result['complete'])
        self.assertFalse((self.root / 'results/control/route.rpt').exists())
        self.job['stop_after'] = 'route'
        with self.assertRaisesRegex(ValueError, 'changed inputs'):
            self.run_job()


if __name__ == '__main__':
    unittest.main()
