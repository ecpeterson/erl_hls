"""Regression checks for the structural screen's attribution and clock boundaries."""
import json
from pathlib import Path
import tempfile
import unittest

from control_cones import analyze, compare


SOURCE = 'service.materialized_fifo_fifo__executor_result_.slots'
ENDPOINT = 'SharedService.p0_stage_done'


def cell(kind: str, inputs: list[int], output: int) -> dict:
    """Build an unambiguous single-output mapped primitive."""
    return {'type': kind, 'port_directions': {'I': 'input', 'O': 'output'},
            'connections': {'I': inputs, 'O': [output]}}


class ControlConesTest(unittest.TestCase):
    """Check source dependence rather than counting unrelated logic or register feedback."""

    def measure(self, cells: dict, endpoint: int = 4) -> list[dict]:
        """Analyze a fresh minimal Yosys-format netlist."""
        module = {'cells': cells, 'netnames': {
            SOURCE: {'bits': [1]}, ENDPOINT: {'bits': [endpoint]}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'core.json'
            path.write_text(json.dumps({'modules': {'phi_decoder_profile_top': module}}))
            return analyze(path)['paths']

    def test_reconvergence_uses_longest_source_dependent_chain(self) -> None:
        """A shorter parallel branch must not hide serial work before reconvergence."""
        paths = self.measure({'first': cell('LUT1', [1], 2),
                              'second': cell('LUT2', [2, 99], 3),
                              'join': cell('LUT2', [1, 3], 4)})
        self.assertEqual(paths[0]['levels'], 3)
        self.assertEqual([c['cell'] for c in paths[0]['chain']], ['first', 'second', 'join'])

    def test_register_cuts_feedback(self) -> None:
        """A registered loop must neither add combinational depth nor recurse forever."""
        self.assertEqual(self.measure({'register': cell('FDRE', [1, 4], 3),
                                       'next': cell('LUT1', [3], 4)}), [])

    def test_reachable_dsp_is_rejected(self) -> None:
        """Hard arithmetic must not silently count as one LUT level."""
        with self.assertRaisesRegex(ValueError, 'unsupported source-reachable primitive'):
            self.measure({'dsp': cell('DSP48E1', [1], 4)})

    def test_unrelated_dsp_does_not_pollute_control_cone(self) -> None:
        """Other endpoint inputs contribute no path from this particular launch."""
        paths = self.measure({'dsp': cell('DSP48E1', [99], 3),
                              'enable': cell('LUT2', [1, 3], 4)})
        self.assertEqual(paths[0]['levels'], 1)

    def test_multiple_drivers_are_rejected(self) -> None:
        """Ambiguous connectivity must fail before producing a comparison."""
        with self.assertRaisesRegex(ValueError, 'multiple drivers'):
            self.measure({'first': cell('LUT1', [1], 4), 'second': cell('LUT1', [2], 4)})


class CompareTests(unittest.TestCase):
    """Report new and removed cones without treating absent signals as success."""

    def test_cuts_require_opt_in(self) -> None:
        """Existing callers retain their strict matched-cone comparison."""
        before = {'sources': ['s'], 'endpoints': ['e'],
                  'paths': [{'source': 's', 'endpoint': 'e', 'levels': 24}]}
        after = {**before, 'paths': []}
        with self.assertRaises(ValueError):
            compare(before, after)
        self.assertEqual(compare(before, after, True)[0]['status'], 'cut')
        self.assertEqual(compare(after, before, True)[0]['status'], 'added')

    def test_missing_signal_is_not_a_cut(self) -> None:
        """Optimization or changed naming must not silently erase an observation."""
        before = {'sources': ['s'], 'endpoints': ['e'], 'paths': []}
        with self.assertRaises(ValueError):
            compare(before, {**before, 'endpoints': []}, True)


if __name__ == '__main__':
    unittest.main()
