"""Check endpoint completeness, shared enables and uncovered primitive handling."""
import unittest

from control_frontier import analyze


def cell(kind: str, inputs: dict, output: int) -> dict:
    """Create a small mapped cell with explicit data/control pins."""
    return {'type': kind, 'connections': {**inputs, 'Q': [output]},
            'port_directions': {**{p: 'input' for p in inputs}, 'Q': 'output'}}


def report(cells: dict, names: dict | None = None, limit: int = 5) -> dict:
    """Analyze an unnamed storage frontier from a single named launch."""
    module = {'cells': cells, 'netnames': {'launch': {'bits': [1]}, **(names or {})}}
    return analyze(module, '^launch$', limit)['sources'][0]['groups']


class FrontierTests(unittest.TestCase):
    """New endpoints must count even when no hand-selected name identifies them."""

    def test_new_register_enable_is_found(self) -> None:
        """A new buffer's enable remains visible after the old endpoint disappears."""
        groups = report({'logic': cell('LUT1', {'I': [1]}, 2),
                         'buffer': cell('FDRE', {'D': [9], 'CE': [2]}, 3)})
        self.assertEqual(groups['register/CE']['max_levels'], 1)
        self.assertNotIn('register/D', groups)

    def test_shared_enable_counts_all_pins(self) -> None:
        """Truncating detailed rows must not truncate the load inventory."""
        groups = report({f'ff{i}': cell('FDRE', {'CE': [1], 'D': [99]}, i+2)
                         for i in range(12)}, limit=1)
        group = groups['register/CE']
        self.assertEqual((group['input_nets'], group['pins'], group['max_levels']), (1, 12, 0))
        self.assertEqual(group['deepest'][0]['consumer_count'], 12)

    def test_register_and_memory_stop_traversal(self) -> None:
        """Clocked storage separates subsequent-cycle logic from this frontier."""
        groups = report({'ff': cell('FDRE', {'D': [1]}, 2),
                         'ram': cell('RAMB18E1', {'ADDRARDADDR': [1]}, 3),
                         'later': cell('FDRE', {'D': [2, 3]}, 4)})
        self.assertEqual(groups['register/D']['pins'], 1)
        self.assertEqual(groups['ram/ADDRARDADDR']['pins'], 1)

    def test_unknown_boundary_is_explicit(self) -> None:
        """A DSP cannot silently become a one-level gate or a known register."""
        groups = report({'dsp': cell('DSP48E1', {'A': [1]}, 2),
                         'later': cell('FDRE', {'D': [2]}, 3)})
        self.assertEqual(groups['unsupported/A']['pins'], 1)
        self.assertNotIn('register/D', groups)

    def test_reconvergence_and_midpoint_landmark(self) -> None:
        """Recover the longest branch and locate the state-read selection boundary."""
        groups = report({'a': cell('LUT1', {'I': [1]}, 2),
                         'b': cell('LUT2', {'I': [1, 2]}, 3),
                         'ff': cell('FDRE', {'D': [3]}, 4)},
                        {'scheduler_2_state.rd_addr': {'bits': [2]}})
        path = groups['register/D']['deepest'][0]
        self.assertEqual(path['levels'], 2)
        self.assertEqual(path['landmarks'][0]['after_levels'], 1)

    def test_combinational_cycle_is_rejected(self) -> None:
        """A reachable combinational loop invalidates finite level counting."""
        with self.assertRaisesRegex(ValueError, 'combinational cycle'):
            report({'a': cell('LUT2', {'I': [1, 3]}, 2),
                    'b': cell('LUT1', {'I': [2]}, 3),
                    'ff': cell('FDRE', {'D': [3]}, 4)})

    def test_cycle_without_storage_is_rejected(self) -> None:
        """A dangling loop is not a successfully empty storage frontier."""
        with self.assertRaisesRegex(ValueError, 'combinational cycle'):
            report({'a': cell('LUT2', {'I': [1, 3]}, 2),
                    'b': cell('LUT1', {'I': [2]}, 3)})

    def test_external_output_is_retained(self) -> None:
        """An unregistered output is an external boundary, not absent timing work."""
        module = {'cells': {}, 'netnames': {'launch': {'bits': [1]}},
                  'ports': {'valid': {'direction': 'output', 'bits': [1]}}}
        groups = analyze(module, '^launch$')['sources'][0]['groups']
        self.assertEqual(groups['external/valid']['pins'], 1)

    def test_missing_launch_and_duplicate_driver_are_rejected(self) -> None:
        """Do not report empty success for misidentified or ambiguous inputs."""
        with self.assertRaisesRegex(ValueError, 'no scalar launch'):
            analyze({'cells': {}, 'netnames': {}}, '^launch$')
        with self.assertRaisesRegex(ValueError, 'multiple drivers'):
            report({'a': cell('LUT1', {'I': [1]}, 2), 'b': cell('LUT1', {'I': [1]}, 2)})


if __name__ == '__main__':
    unittest.main()
