"""Reject collector-output dependencies that cross the registered ownership cut."""
import unittest

from test_direct_collection import check_output_boundary

DSLX = '''struct Actor {
  phase: u8,
  slots: u8[4],
}
struct Bank {
  status: u8,
}
type DirectCollection = Bank;
struct DirectCollectionState {
  machine: Actor,
  collection: DirectCollection,
  control: u8,
  pending: u8[2],
}
'''
RTL = '''module __fixture__CollectionService_0__2_1_next(
 input wire _egress_out_rdy
);
 reg ____state_0;
 reg ____state_1;
 reg ____state_2;
 reg ____state_3;
 reg ____state_4;
 wire active_outputs_ready_0;
 assign active_outputs_ready_0 = _egress_out_rdy | ~(____state_0 & ____state_2);
endmodule
'''


class DirectBoundaryTests(unittest.TestCase):
    """Check source-mapped register ownership, not a hardcoded register number."""

    def test_committed_actor_and_bank_are_allowed(self) -> None:
        """Committed phase and collector status may govern actor publication."""
        rows = check_output_boundary(RTL, DSLX)
        self.assertEqual(rows[0]['registered_dependencies']['____state_2'], 'state.collection.status')

    def test_input_command_and_mailbox_are_rejected(self) -> None:
        """Each would reintroduce current selected-input or callback dependencies."""
        for field in ('____state_1', '____state_3', '____state_4'):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'readiness crosses'):
                check_output_boundary(RTL.replace('____state_0 &', field+' &'), DSLX)

    def test_unknown_combinational_leaf_is_rejected(self) -> None:
        """Missing generated nets must not silently shorten the reported cone."""
        with self.assertRaisesRegex(ValueError, 'unknown combinational leaf'):
            check_output_boundary(RTL.replace('____state_0 &', 'unknown &'), DSLX)

    def test_array_index_participates_in_dependency(self) -> None:
        """Indirect selection through a command register still crosses ownership."""
        changed = RTL.replace('assign active_outputs_ready_0',
                              'assign chosen[____state_3] = ____state_2;\n assign active_outputs_ready_0')
        with self.assertRaisesRegex(ValueError, 'state.control'):
            check_output_boundary(changed.replace('____state_0 &', 'chosen &'), DSLX)


if __name__ == '__main__':
    unittest.main()
