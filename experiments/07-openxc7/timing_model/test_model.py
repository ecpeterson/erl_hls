"""Regressions for calibration import integrity and bounded delay prediction."""
import json
from pathlib import Path
import tempfile
import unittest
from analyze import checked_path, estimate, summarize, shape_estimate, index_family, composed_estimate, operation_estimate, measured_row
from connectivity import check, check_parameters, parameter_value, unused_dsp_pins
from characterize import operation
from batch import measure
import hashlib
from sdf import extract
from application import schedule_summary


class ModelTests(unittest.TestCase):
    """Reject corrupted evidence and unsupported interpolation rather than guessing."""

    def test_carry_bit_order(self) -> None:
        """A CO[0]/CO[3] import swap must fail even with identical cell counts."""
        data = {'modules': {'probe_top': {'ports': {}, 'cells': {
            'lo': {'type': 'CARRY4', 'parameters': {}, 'connections': {'CO': [2, 3, 4, 5]}},
            'hi': {'type': 'CARRY4', 'parameters': {}, 'connections': {'CI': [5]}}}}}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'mapped').write_text(json.dumps(data))
            good = ''.join(f'lo\tCARRY4\tCO[{i}]\tn{i}\n' for i in range(4)) + 'hi\tCARRY4\tCI\tn3\n'
            (root / 'linked').write_text(good)
            self.assertEqual(check(root / 'mapped', root / 'linked')['nets'], 1)
            (root / 'linked').write_text(good.replace('CI\tn3', 'CI\tn0'))
            with self.assertRaisesRegex(ValueError, 'pin graph'):
                check(root / 'mapped', root / 'linked')

    def test_prepared_circuit_identity(self) -> None:
        """An internally consistent route cannot substitute a different prepared circuit."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'probe').mkdir()
            (root/'probe/mapped.json').write_text('{}')
            row = {'name': 'probe', 'files': {'mapped.json': 'wrong'}}
            with self.assertRaisesRegex(ValueError, 'prepared manifest'):
                measured_row((root, row))

    def test_postroute_audit_is_required(self) -> None:
        """Import integrity alone cannot qualify a measurement changed by placement."""
        data = {'modules': {'probe_top': {'ports': {}, 'cells': {
            'inv': {'type': 'INV', 'parameters': {}, 'connections': {'I': [1], 'O': [2]}}}}}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root/'vivado'
            report.mkdir()
            (root/'mapped.json').write_text(json.dumps(data))
            (report/'connectivity.tsv').write_text('inv\tLUT1\tI0\tn1\ninv\tLUT1\tO\tn2\n')
            (report/'parameters.tsv').write_text("inv\tINIT\t2'h1\n")
            with self.assertRaises(FileNotFoundError):
                checked_path(root)
            (report/'routed-connectivity.tsv').write_text(
                (report/'connectivity.tsv').read_text()+'clone\tLUT1\tO\tn2\n')
            with self.assertRaisesRegex(ValueError, 'primitive population'):
                checked_path(root)

    def test_parameter_changes(self) -> None:
        """LUT truth tables and DSP registers are part of the imported circuit."""
        data = {'modules': {'probe_top': {'cells': {
            'lut': {'parameters': {'INIT': '1001'}},
            'dsp': {'parameters': {'PREG': '0', 'USE_DPORT': 'FALSE'}}}}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'parameters'
            good = "lut\tINIT\t4'h9\ndsp\tPREG\t0\ndsp\tUSE_DPORT\t0\n"
            path.write_text(good)
            self.assertEqual(check_parameters(data, path), 3)
            for changed in (good.replace("4'h9", "4'h6"), good.replace('PREG\t0', 'PREG\t1')):
                path.write_text(changed)
                with self.assertRaises(ValueError):
                    check_parameters(data, path)

    def test_parameter_representations(self) -> None:
        """Normalize encodings without confusing bit strings with decimal values."""
        self.assertEqual(parameter_value('100', binary=True), 4)
        self.assertEqual(parameter_value('100'), 100)
        self.assertEqual(parameter_value("8'hff"), 255)
        self.assertEqual(parameter_value('READ_FIRST'), 'READ_FIRST')

    def test_inverter_alias(self) -> None:
        """Allow the exact INV alias, while rejecting an incorrect LUT truth table."""
        data = {'modules': {'probe_top': {'ports': {}, 'cells': {
            'inv': {'type': 'INV', 'parameters': {}, 'connections': {'I': [1], 'O': [2]}}}}}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'mapped').write_text(json.dumps(data))
            (root / 'linked').write_text('inv\tLUT1\tI0\tn1\ninv\tLUT1\tO\tn2\n')
            (root / 'parameters').write_text("inv\tINIT\t2'h1\n")
            self.assertEqual(check(root / 'mapped', root / 'linked', root / 'parameters')['parameters'], 1)
            (root / 'parameters').write_text("inv\tINIT\t2'h2\n")
            with self.assertRaises(ValueError):
                check(root / 'mapped', root / 'linked', root / 'parameters')

    def test_dsp_control_exceptions(self) -> None:
        """Ignore only absent, bypassed controls; never waive present or uncertain ones."""
        cell = {'type': 'DSP48E1', 'parameters': {'PREG': '0', 'AREG': '0', 'ACASCREG': '1'},
                'connections': {'RSTP': ['0']}}
        data = {'modules': {'probe_top': {'cells': {'dsp': cell}}}}
        ignored = unused_dsp_pins(data)
        self.assertIn(('dsp', 'CEP'), ignored)
        for pin in ('RSTP', 'RSTM', 'RSTA', 'CEA2'):
            self.assertNotIn(('dsp', pin), ignored)
        cell['parameters']['PREG'] = '1'
        self.assertNotIn(('dsp', 'CEP'), unused_dsp_pins(data))

    def test_error_directions(self) -> None:
        """Equal optimistic and pessimistic errors must not look like an accurate model."""
        stats = summarize([-400, 0, 400])
        self.assertEqual(stats['mean_ps'], 0)
        self.assertEqual(stats['underestimation'], {'count': 1, 'mean_ps': 400, 'worst_ps': 400})
        self.assertEqual(stats['overestimation']['worst_ps'], 400)
        with self.assertRaisesRegex(ValueError, 'empty'):
            summarize([])

    def test_probe_shape(self) -> None:
        """A wide constant multiply requires the exact declared operand/result shape."""
        ir, ports, result = operation('smul_const_37_39_76_183251937963', 76)
        self.assertEqual((ports, result), ([('a', 37)], 76))
        self.assertIn('bits[39] = literal', ir)
        with self.assertRaisesRegex(ValueError, 'shape'):
            operation('smul_const_37_39_76_183251937963', 64)

    def test_measurement_reuse(self) -> None:
        """A completion marker is reusable only with identical evidence inputs."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            probe = root / 'probe'
            output = probe / 'vivado'
            output.mkdir(parents=True)
            inputs = [probe / 'mapped.edf', probe / 'mapped.json',
                      root / 'measure.tcl', root / 'connectivity.py', root / 'circuit_audit.tcl']
            for path in inputs:
                path.write_text('evidence')
            (output / 'inputs.json').write_text(json.dumps([
                hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs]))
            (output / 'console.log').write_text('CHARACTERIZATION_COMPLETE')
            (output / 'path-properties.rpt').write_text('timed')
            self.assertEqual(measure(root, root / 'measure.tcl', 'probe')['status'], 'complete')
            inputs[0].write_text('changed evidence')
            with self.assertRaisesRegex(ValueError, 'changed'):
                measure(root, root / 'measure.tcl', 'probe')

    def test_bounded_envelope(self) -> None:
        """A fortunate placed sample cannot make wider operations appear cheaper."""
        samples = [{'width': 8, 'cell_ps': 100}, {'width': 16, 'cell_ps': 80},
                   {'width': 32, 'cell_ps': 300}]
        self.assertEqual(estimate(samples, 4, 'cell_ps'), 100)
        self.assertEqual(estimate(samples, 12, 'cell_ps'), 100)
        self.assertEqual(estimate(samples, 24, 'cell_ps'), 200)
        with self.assertRaisesRegex(ValueError, 'support'):
            estimate(samples, 33, 'cell_ps')

    def test_width_and_fanin_bounds(self) -> None:
        """Interpolate both dimensions and reject an unsupported width or fan-in."""
        training = {('mux', 2): [{'width': 8, 'routed_ps': 100}, {'width': 32, 'routed_ps': 300}],
                    ('mux', 8): [{'width': 8, 'routed_ps': 200}, {'width': 32, 'routed_ps': 500}]}
        self.assertEqual(shape_estimate(training, 'mux', 20, 5, 'routed_ps'), 275)
        for width, count in [(33, 2), (8, 9)]:
            with self.assertRaisesRegex(ValueError, 'support'):
                shape_estimate(training, 'mux', width, count, 'routed_ps')

    def test_index_rounding_and_nested_reads(self) -> None:
        """Nested reads sum dynamic mux layers; constant dimensions add no delay."""
        training = {('array_index_s8', 8): [{'width': 128, 'routed_ps': 500}],
                    ('array_index_s32', 8): [{'width': 128, 'routed_ps': 700}]}
        self.assertEqual(index_family(training, 'array_index_s', 12), 'array_index_s32')
        with self.assertRaisesRegex(ValueError, 'support'):
            index_family(training, 'array_index_s', 33)
        row = {'op': 'array_index_s12', 'width': 24, 'count': 3}
        self.assertEqual(operation_estimate(training, row, 'routed_ps'), 700)
        row = {'op': 'array2_s32_s8_n4_n5', 'width': 8}
        self.assertEqual(composed_estimate(training, row, 'routed_ps'), 1200)
        row['op'] = 'array2_s32_c0_n4_n5'
        self.assertEqual(composed_estimate(training, row, 'routed_ps'), 700)
        row['op'] = 'array2_c0_s8_n4_n5'
        self.assertEqual(composed_estimate(training, row, 'routed_ps'), 500)
        row.update(op='array2_s32_s8_n4_n5', width=32)
        with self.assertRaisesRegex(ValueError, 'support'):
            composed_estimate(training, row, 'routed_ps')

    def test_matching_shift_width(self) -> None:
        """Use the ordinary shift family when data and amount widths match XLS's rule."""
        training = {('shll', 2): [{'width': 32, 'routed_ps': 100}],
                    ('shll_s32', 2): [{'width': 32, 'routed_ps': 200}]}
        self.assertEqual(operation_estimate(training,
            {'op': 'shll_s24', 'width': 24, 'count': 2}, 'routed_ps'), 100)
        self.assertEqual(operation_estimate(training,
            {'op': 'shll_s24', 'width': 16, 'count': 2}, 'routed_ps'), 200)

    def test_package_schedule_summary(self) -> None:
        """Keep per-proc bounds distinct from the largest timed stage path."""
        schedule = '''schedules {
  key: "worker"
  value {
    function: "worker"
    stages {
      timed_nodes { path_delay_ps: 1200 }
      timed_nodes { path_delay_ps: 2200 }
    }
    min_clock_period_ps: 2100
    target_clock_period_ps: 2500
    length: 2
  }
}
schedules {
  key: "router"
  value {
    function: "router"
    stages { timed_nodes { path_delay_ps: 500 } }
    length: 2
  }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'schedule.textproto'
            path.write_text(schedule)
            rows = schedule_summary(path)
            self.assertEqual(rows[0], {'function': 'worker', 'min_clock_period_ps': 2100,
                'target_clock_period_ps': 2500, 'length': 2, 'max_stage_path_ps': 2200})
            self.assertEqual(rows[1], {'function': 'router', 'length': 2, 'max_stage_path_ps': 500})
            path.write_text('')
            with self.assertRaisesRegex(ValueError, 'no scheduled'):
                schedule_summary(path)

    def test_sdf_clock_arcs(self) -> None:
        """Preserve negative holds, bus indices and the picosecond unit."""
        text = '''(DELAYFILE (TIMESCALE 1ps)
          (CELL (CELLTYPE "RAMB36E1") (INSTANCE memory)
            (DELAY (ABSOLUTE (IOPATH (posedge CLKBWRCLK) DOBDO\\[1\\] (400:700:748) (401:701:746))))
            (TIMINGCHECK (SETUPHOLD (posedge ADDRBWRADDR\\[0\\]) (posedge CLKBWRCLK) (10:20:30) (-30:-20:-10))))
          (CELL (CELLTYPE "probe_top") (INSTANCE) (DELAY (ABSOLUTE))))'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'timing.sdf'
            path.write_text(text)
            arcs = extract(path)[0]['arcs']
            self.assertEqual(arcs[0]['to'], 'DOBDO[1]')
            self.assertEqual([a['ps'] for a in arcs], [748, 30, -10])
            path.write_text(text.replace('1ps', '1ns'))
            with self.assertRaisesRegex(ValueError, 'picosecond'):
                extract(path)


if __name__ == '__main__':
    unittest.main()
