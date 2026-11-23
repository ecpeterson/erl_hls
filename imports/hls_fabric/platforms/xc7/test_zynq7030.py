#!/usr/bin/env python3
"""Check package joins and resource-smoke behavior without downloading toolchains."""

import copy
import subprocess
import tempfile
import unittest
from pathlib import Path

from check_zynq7030_bitstream import check, frame_bits
from prepare_zynq7030 import checked, map_pins, read_vendor


class PackageTests(unittest.TestCase):
    """Reject ambiguous or incomplete package mappings before any tool consumes them."""

    def setUp(self) -> None:
        """Provide a small package with one placeable pin and one dedicated pin."""
        self.reference = [dict(pin="A1", bank="13", site="IOB_X0Y1", tile="T", pin_function="IO_L1_13")]
        self.vendor = [{"Pin": "A1", "Bank": "13", "Pin Name": "IO_L1_13", "I/O Type": "HR"},
                       {"Pin": "B1", "Bank": "0", "Pin Name": "TCK_0", "I/O Type": "CONFIG"}]
        self.target = copy.deepcopy(self.vendor)
        self.target[0]["Pin"] = "Y14"
        self.grid = {"T": {"sites": {"IOB_X0Y1": "IOB33"}}}

    def mapped(self) -> list[dict[str, str]]:
        """Run the join on this test's editable inputs."""
        return map_pins(self.reference, self.vendor, self.target, self.grid)

    def test_rebonding(self) -> None:
        """A different package pin preserves the function's physical fabric site."""
        self.assertEqual(self.mapped(), [dict(self.reference[0], pin="Y14")])

    def test_wrong_reference_bank(self) -> None:
        """A bank disagreement cannot be hidden by a matching function name."""
        self.reference[0]["bank"] = "34"
        with self.assertRaisesRegex(ValueError, "disagreement"):
            self.mapped()

    def test_missing_site(self) -> None:
        """Unknown sites cannot enter a chip database."""
        self.grid = {}
        with self.assertRaisesRegex(ValueError, "missing site"):
            self.mapped()

    def test_missing_programmable_pin(self) -> None:
        """Missing HR/HP pins are errors, even when the reference omits them."""
        self.reference = []
        with self.assertRaisesRegex(ValueError, "unmapped function"):
            self.mapped()

    def test_unknown_target_function(self) -> None:
        """A target-only dedicated function needs explicit investigation."""
        self.target[1]["Pin Name"] = "UNKNOWN"
        with self.assertRaisesRegex(ValueError, "unmapped function"):
            self.mapped()

    def test_duplicate_site(self) -> None:
        """Two target pins may not claim the same site."""
        self.target.append(dict(self.target[0], Pin="Y15"))
        with self.assertRaisesRegex(ValueError, "duplicate target site"):
            self.mapped()

    def test_duplicate_reference(self) -> None:
        """Duplicate reference functions are rejected instead of overwritten."""
        self.reference.append(dict(self.reference[0]))
        with self.assertRaisesRegex(ValueError, "duplicate reference"):
            self.mapped()

    def test_changed_input(self) -> None:
        """An unexpected source revision fails closed."""
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            checked(b"changed", "0" * 64, "input")

    def test_vendor_parser(self) -> None:
        """Check package identity, pin uniqueness and the vendor's declared total."""
        header = "Device/Package example DATE\n\nPin,Pin Name,Bank,I/O Type\n"
        body = "A1,IO_L1_13,13,HR\nTotal Number of Pins,1,,\n"
        self.assertEqual(len(read_vendor(header + body, "example")), 1)
        with self.assertRaisesRegex(ValueError, "wrong vendor package"):
            read_vendor(header + body, "other")
        with self.assertRaisesRegex(ValueError, "pin total"):
            read_vendor(header + body.replace("Pins,1", "Pins,2"), "example")
        duplicate = "A1,IO_L1_13,13,HR\nA1,IO_L2_13,13,HR\nTotal Number of Pins,2,,\n"
        with self.assertRaisesRegex(ValueError, "duplicate vendor pin"):
            read_vendor(header + duplicate, "example")



    def test_bitstream_round_trip(self) -> None:
        """Extra/lost bits fail, including high bits of the frame's ECC word."""
        words = [0] * 101
        words[1] = 0x80000001
        words[50] = 0x2001
        frames = "0x00000080 " + ",".join(map(hex, words)) + "\n"
        decoded = "bit_00000080_001_00\nbit_00000080_001_31\nbit_00000080_050_13\n"
        self.assertEqual(check(frames, decoded), 3)
        with self.assertRaisesRegex(ValueError, "2 missing"):
            check(frames, decoded.splitlines()[0])
        with self.assertRaisesRegex(ValueError, "1 extra"):
            check(frames, decoded + "bit_00000080_002_00\n")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            frame_bits(frames + frames)
        with self.assertRaisesRegex(ValueError, "empty"):
            frame_bits("")


def expected_activity(cycles: int) -> list[int]:
    """Compute observable parity across RAM wraps with the three-stage pipeline."""
    history = [0] * 512
    noise, read_data, product, digest = 0, 0, 0, 0
    result = []
    for cycle in range(cycles):
        digest = (((digest << 1) | (digest >> 31)) ^ product ^ (product >> 32) ^ read_data) & 0xffffffff
        product = (read_data & 0x3ffff) * (noise & 0x1ffff)
        address = cycle % 512
        read_data, history[address] = history[address], noise
        feedback = (~((noise >> 31) ^ (noise >> 21) ^ (noise >> 1) ^ noise)) & 1
        noise = ((noise << 1) | feedback) & 0xffffffff
        result.append(digest.bit_count() % 2)
    if len(set(result[1024:])) != 2:
        raise AssertionError("resource witness must exercise both output levels")
    return result


def simulate() -> None:
    """Compare 4096 visible RTL output bits, spanning eight memory sweeps."""
    root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix="zynq7030-test-") as directory:
        stage = Path(directory)
        (stage / "expected.mem").write_text("\n".join(map(str, expected_activity(4096))) + "\n")
        (stage / "tb.v").write_text('''
module tb;
  reg clock = 0;
  wire activity;
  reg expected [0:4095];
  integer cycle;
  zynq7030_smoke dut(clock, activity);
  initial begin
    $readmemb("expected.mem", expected);
    for (cycle = 0; cycle < 4096; cycle = cycle + 1) begin
      #5; clock = 1; #5;
      if (activity !== expected[cycle])
        $fatal(1, "cycle %0d: got %b, expected %b", cycle, activity, expected[cycle]);
      clock = 0;
    end
    $display("PASS: 4096 resource-smoke cycles");
    $finish;
  end
endmodule
''')
        sources = [str(root / "zynq7030_smoke.v")]
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", "sim", "tb.v", *sources], cwd=stage, check=True)
        subprocess.run(["vvp", "sim"], cwd=stage, check=True, timeout=30)


def main() -> None:
    """Run fast mapping tests and the resource smoke simulation."""
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PackageTests)
    if not unittest.TextTestRunner().run(suite).wasSuccessful():
        raise SystemExit(1)
    simulate()


if __name__ == "__main__":
    main()
