"""Test report provenance, timing conventions and incomplete-path safeguards."""
from pathlib import Path
import tempfile
import unittest

from path_report import build, enrich, parse_native, parse_vivado, read_artifact, summarize
from schedule_report import analyze, annotate_paths, ir_graph
from architecture_physical import require_combinational_dsps


ROOT = Path(__file__).resolve().parents[1]


class PathReportTest(unittest.TestCase):
    """Exercise real retained path formats and reject misleading comparisons."""

    def vendor(self) -> str:
        """Return the archived shared-core path including RAM launch and clock skew."""
        return (ROOT / 'results/vendor-followup-2026-09-26/paths/mapping-controls-dsp/critical-path.rpt').read_text()

    def test_wrapped_arcs_and_clock_exclusion(self) -> None:
        """Account for wrapped DSP/carry arcs without including the destination clock."""
        path, = parse_vivado(self.vendor())
        self.assertAlmostEqual(path['period_ns'], 15.846)
        self.assertAlmostEqual(sum(a['delay_ns'] for a in path['arcs']), 15.806, delta=.01)
        self.assertEqual(sum(a.get('primitive') == 'DSP48E1' for a in path['arcs']), 3)
        self.assertFalse(any(a.get('primitive') in ('IBUF', 'BUFG') for a in path['arcs']))
        self.assertAlmostEqual(path['arcs'][0]['delay_ns'], 2.080)

    def test_native_precision(self) -> None:
        """Preserve the native text's rounding instead of inventing extra precision."""
        text = (ROOT / 'results/lut-arithmetic-2026-09-26/dsp-corrected-map-seed2/route-critical-path.txt').read_text()
        path, = parse_native(text)
        self.assertEqual(path['precision_ns'], .1)
        self.assertEqual(path['period_ns'], 38.8)
        self.assertTrue(any(a.get('grid_displacement', 0) > 50 for a in path['arcs']))

    def test_registered_dsp_launch(self) -> None:
        """Keep DSP clock-to-output delay in the data path after register absorption."""
        text = (ROOT / 'results/timing-feedback-2026-09-27/retimed/critical-path.rpt').read_text()
        path, = parse_vivado(text)
        self.assertAlmostEqual(path['period_ns'], 17.100)
        self.assertEqual(path['arcs'][0]['primitive'], 'DSP48E1')
        self.assertGreater(path['arcs'][0]['delay_ns'], 0)
        self.assertAlmostEqual(sum(a['delay_ns'] for a in path['arcs']), 16.872, delta=.01)

    def test_next_limit_unknown(self) -> None:
        """Removing the only sampled family must not predict a zero-period circuit."""
        result = summarize(parse_vivado(self.vendor()), 79.25, [14])
        self.assertIsNone(result['families'][0]['unmodified_sample_floor_ns'])
        self.assertFalse(result['all_path_families_covered'])
        self.assertAlmostEqual(result['added_cycle_budget'][0]['break_even_period_ns'], 13.4669758713)

    def test_other_family_limits_local_improvement(self) -> None:
        """A neighboring arithmetic family survives an optimistic single-family fix."""
        first, = parse_vivado(self.vendor())
        second, = parse_vivado(self.vendor())
        first['arithmetic_source_sites'] = ['field.x:21']
        second['arithmetic_source_sites'] = ['field.x:15']
        second['period_ns'] = 15.783
        groups = summarize([first, second], 79.25, [])['families']
        self.assertEqual(groups[0]['unmodified_sample_floor_ns'], 15.783)
        self.assertEqual(groups[1]['unmodified_sample_floor_ns'], 15.846)

    def test_registered_dsp_rejected_before_routing(self) -> None:
        """Retiming must not silently remove the multiplier's paths from native timing."""
        registers = 'AREG BREG CREG DREG ADREG MREG PREG ACASCREG BCASCREG ALUMODEREG CARRYINREG CARRYINSELREG INMODEREG OPMODEREG'.split()
        params = dict.fromkeys(registers, '0' * 32)
        mapped = {'modules': {'top': {'cells': {'product': {'type': 'DSP48E1', 'parameters': params}}}}}
        require_combinational_dsps(mapped)
        params['BREG'] = '0' * 31 + '1'
        with self.assertRaisesRegex(ValueError, 'product/BREG'):
            require_combinational_dsps(mapped)

    def test_reject_truncated_and_multicycle_paths(self) -> None:
        """Missing data and incompatible clock relations fail instead of yielding a speedup."""
        with self.assertRaises(ValueError):
            parse_vivado(self.vendor().replace('2.080     6.301', '0.000     6.301'))
        with self.assertRaises(ValueError):
            parse_vivado(self.vendor().replace('Requirement:            5.000ns', 'Requirement:            10.000ns'))

    def test_fingerprint_and_cycle_contract(self) -> None:
        """A report cannot silently consume changed reports or a different cycle measurement."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'paths.rpt').write_text(self.vendor())
            (root / 'cycles.json').write_text('{"cycles": 79.25}')
            spec = {'path': 'paths.rpt'}
            _, pin = read_artifact(spec, root)
            (root / 'paths.rpt').write_text(self.vendor() + '\n')
            with self.assertRaises(ValueError):
                read_artifact(pin, root)
            manifest = {'schema': 1, 'title': 'test', 'runs': [
                {'name': 'control', 'tool': 'vivado', 'stage': 'routed', 'constraint_ns': 5,
                 'paths': spec, 'cycle_evidence': {'path': 'cycles.json'},
                 'cycle_pointer': '/cycles', 'cycles_per_step': 80}]}
            with self.assertRaises(ValueError):
                build(manifest, root)
            manifest['runs'][0]['cycles_per_step'] = 79.25
            manifest['runs'][0]['path_sets'] = {'RAM': spec}
            result = build(manifest, root)['runs'][0]
            self.assertEqual(result['summary']['paths_reported'], 1)
            self.assertEqual(result['paths'][0]['reported_in'], ['global', 'RAM'])

    def test_schedule_and_source_link(self) -> None:
        """Keep physical net provenance separate from the scheduled node id space."""
        ir = '''package test
file_number 0 "field.x"
proc actor<input: bits[8] in>() {
  rx: bits[8] = receive(channel=input, id=1)
  product: bits[8] = smul(rx, rx, id=2, pos=[(0,9,0)])
  result: token = send(product, channel=output, id=3)
}
'''
        schedule = '''schedules {
  value {
    function: "actor"
    stages {
      stage: 0
      timed_nodes {\n        node: "rx"\n        path_delay_ps: 0\n      }
      timed_nodes {\n        node: "product"\n        path_delay_ps: 1000\n      }
    }
    stages {
      stage: 1
      timed_nodes {\n        node: "result"\n        path_delay_ps: 0\n      }
    }
  }
}
'''
        function, = analyze(ir, schedule, 'actor')
        self.assertEqual(function['state_reads'], 0)
        self.assertEqual(function['products'][0]['input_boundaries'][0]['name'], 'rx')
        self.assertEqual(function['products'][0]['dependent_state_updates'], [])
        paths = [{'arcs': [{'resource': 'actor.p0_smul_2[3]'}]}]
        annotate_paths(paths, ir, ['field.x'])
        self.assertEqual(paths[0]['arithmetic_source_sites'], ['field.x:10'])
        wrong_scope = [{'arcs': [{'resource': 'other.p0_smul_2[3]'}]}]
        annotate_paths(wrong_scope, ir, ['field.x'])
        self.assertEqual(wrong_scope[0]['arithmetic_source_sites'], [])

    def test_return_nodes_and_literal_tuples(self) -> None:
        """Function returns stay in the graph; literal tuples are not source positions."""
        graph = ir_graph('''package test
top fn example() -> (bits[32], bits[32], bits[32]) {
  ret value: (bits[32], bits[32], bits[32]) = literal(value=(1,2,3), id=1)
}
''')
        node = graph['example']['nodes']['value']
        self.assertEqual(node['op'], 'literal')
        self.assertEqual(node['locations'], [])

    def test_net_fanout_distinguishes_pins_cells_and_bits(self) -> None:
        """Do not report a whole bus's sinks as the load on one critical-path bit."""
        netlist = {'modules': {'top': {'netnames': {'bus': {'bits': [10, 11], 'offset': 4}},
            'cells': {'sink': {'type': 'LUT2', 'connections': {'I0': [11], 'I1': [11]},
                               'port_directions': {'I0': 'input', 'I1': 'input'}}}}}}
        path = {'arcs': [{'kind': 'net', 'resource': 'bus[5]'}, {'kind': 'net', 'resource': 'bus'}]}
        enrich([path], netlist)
        self.assertEqual(path['arcs'][0]['mapped_sink_pins'], 2)
        self.assertEqual(path['arcs'][0]['mapped_sink_cells'], 1)
        self.assertNotIn('mapped_sink_pins', path['arcs'][1])


if __name__ == '__main__':
    unittest.main()
