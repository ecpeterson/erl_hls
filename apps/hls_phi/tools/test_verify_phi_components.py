#!/usr/bin/env python3
"""Reject circuit changes while permitting only generated names and direct wrappers."""
import phi_tool_paths  # Resolve shared tooling for this application.
import unittest

from phi_mesh_components import modules
from verify_phi_components import canonical, transparent

LEAF = '''module leaf(
  input wire clk,
  input wire [3:0] a,
  output wire [3:0] b
);
  reg [3:0] held;
  always @(posedge clk) begin
    held <= a + 4'd1;
  end
  assign b = held;
endmodule
'''
WRAPPER = '''module wrapper(
  input wire clk,
  input wire [3:0] a,
  output wire [3:0] b
);
  wire [3:0] temporary;
  leaf inner (
    .clk(clk),
    .a(a),
    .b(temporary)
  );
  assign b = temporary;
endmodule
'''


def normalized(text: str, top: str) -> str:
    """Compare all reachable logic while preserving interface names."""
    return canonical(modules(text), top, {}, set())


class CircuitComparisonTest(unittest.TestCase):
    """Changed arithmetic, state timing, ports and wrapper wiring must remain visible."""

    def test_local_names_and_wrapper(self) -> None:
        """A generated internal name and one purely wired hierarchy level are immaterial."""
        expected = normalized(LEAF, 'leaf')
        self.assertEqual(expected, normalized(LEAF.replace('held', 'temporary_912'), 'leaf'))
        self.assertEqual(expected, normalized(LEAF+WRAPPER, 'wrapper'))
        self.assertEqual(expected, normalized((LEAF+WRAPPER).replace('leaf', 'other_type'), 'wrapper'))

    def test_changed_behavior(self) -> None:
        """Never normalize constants, operators, clock edges, widths or public port names."""
        expected = normalized(LEAF, 'leaf')
        for source in (LEAF.replace("4'd1", "4'd2"), LEAF.replace('+', '-'),
                       LEAF.replace('posedge', 'negedge'), LEAF.replace('[3:0]', '[4:0]'),
                       LEAF.replace(' a', ' renamed').replace('<= a', '<= renamed')):
            with self.subTest(source=source):
                self.assertNotEqual(expected, normalized(source, 'leaf'))

    def test_nontransparent_wrappers(self) -> None:
        """Constants, altered named connections, extra logic and wrong widths are not wrappers."""
        for wrapper in (WRAPPER.replace('.a(a)', '.a(temporary)'),
                        WRAPPER.replace('.b(temporary)', '.a(temporary)'),
                        WRAPPER.replace('b = temporary;', 'b = temporary + 1;'),
                        WRAPPER.replace('wire [3:0] temporary', 'wire [4:0] temporary'),
                        WRAPPER.replace('endmodule', "  always @(posedge clk) $display(\"side effect\");\nendmodule")):
            with self.subTest(wrapper=wrapper):
                self.assertIsNone(transparent(modules(LEAF+wrapper), 'wrapper'))
                self.assertNotEqual(normalized(LEAF, 'leaf'), normalized(LEAF+wrapper, 'wrapper'))


if __name__ == '__main__':
    unittest.main()
