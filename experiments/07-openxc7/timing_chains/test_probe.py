"""Reject arithmetic interfaces that could silently lose harness inputs."""
import unittest

from timing_chains.probe import harness


class HarnessTest(unittest.TestCase):
    """Require complete vector stimulus and explicit clock wiring."""

    def test_vector_and_clock_connections(self) -> None:
        """Partition stimulus once across all inputs and connect a pipeline clock."""
        rtl = "  input wire [31:0] a,\n  input wire [4:0] b,\n  input wire clk,\n  output wire [7:0] out\n"
        result = harness(rtl)
        self.assertIn('.a(stimulus[31:0])', result)
        self.assertIn('.b(stimulus[36:32])', result)
        self.assertIn('.clk(clock)', result)
        self.assertIn('reg [7:0] captured', result)

    def test_unsupported_scalar_is_not_dropped(self) -> None:
        """A scalar data input must fail instead of being tied off by synthesis."""
        rtl = "  input wire [31:0] a,\n  input wire enable,\n  output wire [7:0] out\n"
        with self.assertRaisesRegex(ValueError, 'scalar inputs'):
            harness(rtl)


if __name__ == '__main__':
    unittest.main()
