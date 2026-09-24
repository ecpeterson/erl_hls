"""Check replication equivalence, protected endpoints and rejected mutations."""
import copy
import unittest

from timing_chains.replicate import replicate, verify, top_module


def fixture() -> dict:
    """Provide a LUT-driven synchronous circuit with primitive declarations."""
    cells = {'gate': {'type': 'LUT2', 'parameters': {'INIT': '0110'}, 'attributes': {},
                      'port_directions': {'I0': 'input', 'I1': 'input', 'O': 'output'},
                      'connections': {'I0': [2], 'I1': [3], 'O': [4]}}}
    for index in range(7):
        cells[f'q{index}'] = {'type': 'FDRE', 'parameters': {'INIT': '0'}, 'attributes': {},
                             'port_directions': {'D': 'input', 'C': 'input', 'Q': 'output'},
                             'connections': {'D': [4], 'C': [1], 'Q': [10 + index]}}
    return {'modules': {'top': {'attributes': {'top': '1'}, 'cells': cells,
                               'ports': {'clock': {'direction': 'input', 'bits': [1]}},
                               'netnames': {'gate': {'bits': [4], 'attributes': {}}}},
                        'LUT2': {'attributes': {'blackbox': '1'}}}}


class ReplicationTest(unittest.TestCase):
    """Require exact logical substitution rather than merely matching cell counts."""

    def test_equivalent_consumers_and_truth_table(self) -> None:
        """Every original consumer sees the same Boolean value after replication."""
        original = fixture()
        design, record = replicate(original, 2)
        self.assertEqual(record['added_luts'], 3)
        self.assertEqual(original, fixture())
        cells = top_module(design)['cells']
        for a in (0, 1):
            for b in (0, 1):
                values = {1: 0, 2: a, 3: b}
                for cell in cells.values():
                    if cell['type'] == 'LUT2':
                        index = values[cell['connections']['I0'][0]] + 2 * values[cell['connections']['I1'][0]]
                        values[cell['connections']['O'][0]] = (int(cell['parameters']['INIT'], 2) >> index) & 1
                for cell in cells.values():
                    if cell['type'] == 'FDRE':
                        self.assertEqual(values[cell['connections']['D'][0]], a ^ b)

    def test_replica_and_state_mutations_fail(self) -> None:
        """Changed LUT contents, state parameters and original wires are rejected."""
        original = fixture()
        design, record = replicate(original, 2)
        clone = next(iter(record['replicas']))
        for name, section, key, wrong in ((clone, 'parameters', 'INIT', '1111'),
                                          ('q0', 'parameters', 'INIT', '1'),
                                          ('q0', 'connections', 'D', [2])):
            changed = copy.deepcopy(design)
            top_module(changed)['cells'][name][section][key] = wrong
            with self.assertRaises(ValueError):
                verify(original, changed, record['aliases'], record['replicas'])

    def test_clock_reset_and_locations_are_protected(self) -> None:
        """Clock/reset consumers and fixed placement prevent driver replication."""
        for port in ('C', 'R', 'CLR'):
            original = fixture()
            sink = top_module(original)['cells']['q0']
            sink['connections'][port] = [4]
            sink['port_directions'][port] = 'input'
            self.assertEqual(replicate(original, 2)[1]['added_luts'], 0)
        original = fixture()
        top_module(original)['cells']['gate']['attributes']['LOC'] = 'SLICE_X0Y0'
        self.assertEqual(replicate(original, 2)[1]['added_luts'], 0)

    def test_hierarchy_and_invalid_bound_fail(self) -> None:
        """Require flattened combinational logic and a meaningful consumer bound."""
        original = fixture()
        with self.assertRaises(ValueError):
            replicate(original, 1)
        original['modules']['LUT2']['cells'] = {'nested': {}}
        with self.assertRaisesRegex(ValueError, 'flattened'):
            replicate(original, 2)


if __name__ == '__main__':
    unittest.main()
