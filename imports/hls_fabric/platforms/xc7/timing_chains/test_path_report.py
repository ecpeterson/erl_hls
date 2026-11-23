"""Test report provenance, timing conventions and incomplete-path safeguards."""
import copy
import gzip
import json
from pathlib import Path
import tempfile
import unittest

from path_report import build, enrich, family, parse_native, parse_vivado, read_artifact, summarize
from shared_subchains import arc_keys, sensitivity, summarize as summarize_subchains, service
from dependency_report import build as build_dependencies, selectors, summarize as summarize_dependencies, markdown
from shared_subchains import fingerprint
from schedule_report import analyze, annotate_paths, ir_graph
from architecture_physical import require_combinational_dsps


ROOT = Path(__file__).resolve().parents[1]


class PathReportTest(unittest.TestCase):
    """Exercise real retained path formats and reject misleading comparisons."""

    def vendor(self) -> str:
        """Return the archived shared-core path including RAM launch and clock skew."""
        return (ROOT / 'timing_chains/fixtures/dsp-chain.rpt').read_text()

    def test_wrapped_arcs_and_clock_exclusion(self) -> None:
        """Account for wrapped DSP/carry arcs without including the destination clock."""
        path, = parse_vivado(self.vendor())
        self.assertAlmostEqual(path['period_ns'], 15.846)
        self.assertAlmostEqual(sum(a['delay_ns'] for a in path['arcs']), 15.806, delta=.01)
        self.assertEqual(sum(a.get('primitive') == 'DSP48E1' for a in path['arcs']), 3)
        self.assertFalse(any(a.get('primitive') in ('IBUF', 'BUFG') for a in path['arcs']))
        self.assertAlmostEqual(path['arcs'][0]['delay_ns'], 2.080)

    def test_lutram_endpoint_excludes_capture_clock(self) -> None:
        """Stop at a distributed RAM data pin before adding the destination clock tree."""
        text = (Path(__file__).resolve().parent / 'fixtures/lutram-data-endpoint.rpt').read_text()
        path, = parse_vivado(text)
        self.assertEqual(path['destination_primitive'], 'RAMD32')
        self.assertAlmostEqual(path['period_ns'], 7.191)
        self.assertAlmostEqual(sum(arc['delay_ns'] for arc in path['arcs']), 7.248, delta=.01)
        self.assertFalse(any(arc.get('primitive') == 'BUFGCE' for arc in path['arcs']))
        self.assertFalse(any(arc['resource'].endswith('/WCLK') for arc in path['arcs']))

    def test_native_precision(self) -> None:
        """Preserve the native text's rounding instead of inventing extra precision."""
        text = (ROOT / 'timing_chains/fixtures/native-dsp-path.txt').read_text()
        path, = parse_native(text)
        self.assertEqual(path['precision_ns'], .1)
        self.assertEqual(path['period_ns'], 38.8)
        self.assertTrue(any(a.get('grid_displacement', 0) > 50 for a in path['arcs']))

    def test_cross_device_carry_and_ram_classification(self) -> None:
        """Native Vivado RAM names and UltraScale carry chains must remain visible."""
        root = ROOT / 'timing_chains/fixtures'
        ram, = parse_vivado((root / 'bram-endpoint.rpt').read_text())
        carry, = parse_vivado((root / 'ultrascale-carry.rpt').read_text())
        self.assertEqual(ram['destination_primitive'], 'RAMB36E1')
        self.assertTrue(family(ram).endswith('mailbox RAM'))
        self.assertEqual(sum(a.get('primitive') == 'CARRY8' for a in carry['arcs']), 8)
        self.assertIn('carry arithmetic', family(carry))
        self.assertAlmostEqual(carry['period_ns'], 5.621)

    def test_native_dotted_dsp_pin(self) -> None:
        """Recognize a native DSP pin without confusing scope dots or whole output buses."""
        netlist = {'modules': {'top': {
            'netnames': {'product_bit': {'bits': [37]}, 'other_bit': {'bits': [38]}},
            'cells': {'actor.product.slice[0]': {'type': 'DSP48E1',
                'connections': {'P': list(range(10, 58))}, 'port_directions': {'P': 'output'}}}}}}
        path = {'arcs': [{'kind': 'cell', 'resource': 'actor.product.slice[0].P27'}]}
        enrich([path], netlist)
        self.assertEqual(path['arcs'][0]['primitive'], 'DSP48E1')
        self.assertEqual(path['arcs'][0]['aliases'], ['product_bit'])

    def test_registered_dsp_launch(self) -> None:
        """Keep DSP clock-to-output delay in the data path after register absorption."""
        text = (ROOT / 'timing_chains/fixtures/registered-dsp.rpt').read_text()
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


def path(destination: str, period: float = 10.0, prefix: str = 'common') -> dict:
    """Construct a small timing witness with shared launch and a distinct final branch."""
    return {'source': 'launch/C', 'destination': destination, 'clock': 'clock',
            'period_ns': period, 'arcs': [
                {'kind': 'cell', 'resource': prefix+'/Q', 'timing_arc': 'C_Q', 'delay_ns': .1},
                {'kind': 'net', 'resource': prefix+'_wire', 'delay_ns': .2},
                {'kind': 'cell', 'resource': 'gate/O', 'timing_arc': 'I0_O', 'delay_ns': .3},
                {'kind': 'net', 'resource': 'fanout', 'delay_ns': .4}]}


def metadata(endpoints: int, alternatives: int, limit: int = 50) -> dict:
    """Provide a complete extraction contract for the synthetic witnesses."""
    return {'endpoint_paths': endpoints, 'alternative_paths': alternatives,
            'requirement_ns': 5.0, 'worst_slack_ns': -5.0, 'clock': 'clock',
            'limit': limit, 'band_ns': 1.0, 'alternatives_per_endpoint': 4}


class SharedSubchainsTest(unittest.TestCase):
    """Distinguish common branches from common names and bounded samples from limits."""

    def test_shared_prefix_and_distinct_fanout_branches(self) -> None:
        """Fanout branch identity must include its destination, unlike the common prefix."""
        a, b = path('r0/D'), path('r1/D', 9.9)
        self.assertEqual(arc_keys(a)[:3], arc_keys(b)[:3])
        self.assertNotEqual(arc_keys(a)[-1], arc_keys(b)[-1])
        report = summarize_subchains([a, b], [a, b], metadata(2, 2))
        first = report['shared_segments_by_coverage'][0]
        self.assertEqual(first['endpoints'], 2)
        self.assertEqual(len(first['arcs']), 3)
        self.assertAlmostEqual(first['census_delay_ns'], .6)

    def test_input_arc_is_part_of_identity(self) -> None:
        """Different inputs to the same LUT output are different physical timing arcs."""
        a = path('r0/D')
        b = copy.deepcopy(a)
        b['arcs'][2]['timing_arc'] = 'I1_O'
        self.assertNotEqual(arc_keys(a)[1:3], arc_keys(b)[1:3])
        fixture = Path(__file__).with_name('fixtures')/'dsp-chain.rpt'
        actual, = parse_vivado(fixture.read_text())
        self.assertTrue(all(a['timing_arc'].startswith('Prop_') for a in actual['arcs'] if a['kind'] == 'cell'))

    def test_alternative_path_limits_sample_gain(self) -> None:
        """A competing route into an affected endpoint is still an unaffected path."""
        a, b = path('r0/D'), path('r1/D', 9.9)
        alternate = path('r0/D', 9.95, 'other')
        report = summarize_subchains([a, b], [a, b, alternate, alternate], metadata(2, 4))
        first = report['shared_segments_by_coverage'][0]
        self.assertEqual(report['distinct_sample_paths'], 3)
        self.assertEqual(first['endpoints'], 2)
        self.assertEqual(first['sensitivity'][-1]['sample_period_ns'], 9.95)

    def test_no_untouched_path_is_not_a_zero_floor(self) -> None:
        """All affected samples say nothing about the absent competing paths."""
        result = sensitivity([path('r/D')], {0: .6}, 1.)
        self.assertIsNone(result['untouched_sample_period_ns'])
        self.assertAlmostEqual(result['sample_period_ns'], 9.4)

    def test_instance_group_excludes_endpoint_register(self) -> None:
        """A physical instance group must not fragment into one row per endpoint bit."""
        self.assertEqual(service('core/service_inst/reg[0]/D'), 'core/service_inst')
        self.assertEqual(service('core/gather/memory_0/SP/WE'), 'core/gather')

    def test_counts_clock_and_limit(self) -> None:
        """Reject truncated/mixed-clock evidence and flag a saturated census."""
        a, b = path('r0/D'), path('r1/D', 9.9)
        self.assertTrue(summarize_subchains([a, b], [a, b], metadata(2, 2, 2))['census_limit_reached'])
        with self.assertRaisesRegex(ValueError, 'parsed'):
            summarize_subchains([a, b], [a, b], metadata(3, 2))
        b['clock'] = 'other'
        with self.assertRaisesRegex(ValueError, 'mixed clock'):
            summarize_subchains([a, b], [a, b], metadata(2, 2))


class DependencyReportTest(unittest.TestCase):
    """Exercise overlapping change scopes and competitors outside their coverage."""

    def plan(self) -> dict:
        """Name two reviewed dependencies in distinct replicated service instances."""
        return {'schema': 1, 'dependencies': [
            {'id': name, 'reason': 'reviewed dependency',
             'selectors': [{'scope': scope, 'source': '/launch'}]}
            for name, scope in [('a', 'core/a_inst$'), ('b', 'core/b_inst$')]],
            'changes': [{'id': n, 'dependencies': ds}
                        for n, ds in [('only-a', ['a']), ('both', ['a', 'b'])]]}

    def paths(self) -> list[dict]:
        """Place equally limiting launch dependencies in two physical instances."""
        a, b = path('core/a_inst/r/D'), path('core/b_inst/r/D', 9.99)
        a['source'], b['source'] = 'core/a_inst/launch/C', 'core/b_inst/launch/C'
        return [a, b]

    def test_union_exposes_remaining_competitor(self) -> None:
        """Covering both dependencies improves the sample; one alone barely helps."""
        ps = self.paths()
        report = summarize_dependencies(ps, ps, metadata(2, 2), self.plan())
        a, both = report['changes']
        self.assertEqual(a['scenarios'][1]['sample_period_ns'], 9.99)
        self.assertEqual(both['scenarios'][1]['sample_period_ns'], 9.5)
        self.assertEqual(both['instances'], ['core/a_inst', 'core/b_inst'])
        self.assertIsNone(both['untouched_worst_ns'])
        self.assertIn('none sampled', markdown(report))

    def test_overlap_does_not_double_count_savings(self) -> None:
        """Two labels matching one path give one conditional reduction, never two."""
        plan = self.plan()
        plan['dependencies'][1]['selectors'] = [{'scope': 'core/.*_inst$', 'source': '/launch'}]
        ps = self.paths()
        both = summarize_dependencies(ps, ps, metadata(2, 2), plan)['changes'][1]
        self.assertEqual(both['overlap_endpoints'], 1)
        self.assertEqual(both['census_endpoints'], 2)
        self.assertEqual(both['sample_paths'], 2)
        self.assertEqual(both['scenarios'][1]['sample_period_ns'], 9.5)

    def test_same_endpoint_alternative_remains_limiting(self) -> None:
        """A destination match cannot erase an alternate unmatched launch path."""
        ps = self.paths()
        alternate = copy.deepcopy(ps[0])
        alternate.update(source='core/a_inst/other/C', period_ns=9.98)
        both = summarize_dependencies(ps, ps+[alternate], metadata(2, 3), self.plan())['changes'][1]
        self.assertEqual(both['untouched_worst_ns'], 9.98)
        self.assertEqual(both['scenarios'][1]['sample_period_ns'], 9.98)
        self.assertEqual(both['remaining_examples'][0]['source'], alternate['source'])

    def test_band_caps_and_unmatched_labels(self) -> None:
        """Do not forecast beyond a bounded census or silently accept empty coverage."""
        ps, plan = self.paths(), self.plan()
        plan['dependencies'][1]['selectors'][0]['scope'] = 'missing'
        report = summarize_dependencies(ps, ps, metadata(2, 2, 2), plan, (2.,))
        self.assertTrue(report['endpoint_cap_reached'])
        self.assertTrue(report['alternative_cap_reached'])
        self.assertEqual(report['changes'][1]['unmatched_dependencies'], ['b'])
        report = summarize_dependencies(ps, ps, metadata(2, 2), self.plan(), (2.,))
        scenario = report['changes'][1]['scenarios'][0]
        self.assertEqual(scenario['sample_period_ns'], 8.)
        self.assertEqual(scenario['band_limited_period_ns'], 9.)
        self.assertTrue(scenario['reaches_band_edge'])

    def test_scopes_and_plan_validation(self) -> None:
        """Fail malformed plans; require through, source and destination conjunctively."""
        plan, ps = self.plan(), self.paths()
        plan['dependencies'][0]['selectors'][0].update(through='absent', destination='r/D$')
        report = summarize_dependencies(ps, ps, metadata(2, 2), plan)
        self.assertEqual(report['changes'][0]['census_endpoints'], 0)
        plan['changes'][0]['dependencies'] = ['unknown']
        with self.assertRaisesRegex(ValueError, 'unknown'):
            selectors(plan)
        plan = self.plan()
        del plan['dependencies'][0]['selectors'][0]['scope']
        with self.assertRaisesRegex(ValueError, 'scope'):
            selectors(plan)

    def test_pinned_inputs_stream_real_report(self) -> None:
        """Consume gzip evidence and reject stale source labels or extraction metadata."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = (ROOT/'timing_chains/fixtures/dsp-chain.rpt').read_bytes()
            for name in ['endpoints', 'alternatives']:
                (root/(name+'.rpt.gz')).write_bytes(gzip.compress(fixture))
            meta = metadata(1, 1)
            p, = parse_vivado(fixture.decode())
            meta.update(clock=p['clock'], worst_slack_ns=5-p['period_ns'])
            (root/'extraction.json').write_text(json.dumps(meta))
            (root/'source.x').write_text('// source evidence')
            plan = self.plan()
            plan.update(extraction_sha256=fingerprint(root/'extraction.json'),
                        source_evidence=[{'path': 'source.x', 'sha256': fingerprint(root/'source.x')}])
            manifest = root/'plan.json'
            manifest.write_text(json.dumps(plan))
            report = build_dependencies(root, manifest)
            self.assertEqual(report['distinct_sample_paths'], 1)
            self.assertEqual(report['inputs']['plan'], fingerprint(manifest))
            (root/'source.x').write_text('// changed source')
            with self.assertRaisesRegex(ValueError, 'source evidence changed'):
                build_dependencies(root, manifest)
            plan['extraction_sha256'] = 'stale'
            manifest.write_text(json.dumps(plan))
            with self.assertRaisesRegex(ValueError, 'another extraction'):
                build_dependencies(root, manifest)


if __name__ == '__main__':
    unittest.main()
