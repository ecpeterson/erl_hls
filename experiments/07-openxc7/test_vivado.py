#!/usr/bin/env python3
"""Check reference evidence without requiring a Vivado installation."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from vivado import evidence


class EvidenceTests(unittest.TestCase):
    """Reject ambiguous bit mappings and incomplete or misleading timing evidence."""

    def test_timing(self) -> None:
        """Preserve negative slack and endpoint failures; absent data is not success."""
        header = "WNS(ns) other columns TPWS Total Endpoints\n-------\n"
        result = evidence.timing(header + " -7.663 -132534.875 61574 91715 0.047 0 0 91715 4.22 0 0 29842\n")
        self.assertEqual(result["wns_ns"], -7.663)
        self.assertEqual(result["setup_failing"], 61574)
        self.assertEqual(result["hold_failing"], 0)
        for incomplete in ("", header + "1 2 3\n"):
            with self.assertRaises(ValueError):
                evidence.timing(incomplete)

    def test_mapping(self) -> None:
        """Require a single independent change and matching intra-word position."""
        base = {(0x10, 1, 1)}
        result = evidence.locate(base, base | {(0x44249C, 38, 11)}, (28, 523))
        self.assertEqual((result["baseaddr"], result["word_offset"]), ("0x00442480", 22))
        for variant, relative in ((base, (28, 523)), (set(), (28, 523)),
                                  (base | {(0x44249C, 38, 10)}, (28, 523))):
            with self.assertRaises(ValueError):
                evidence.locate(base, variant, relative)

    def test_sparse_bits(self) -> None:
        """Reject malformed coordinates instead of silently shrinking the evidence."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bits"
            for bad in ("bit_001_101_00\n", "bit_001_001_32\n", "unexpected\n"):
                path.write_text(bad)
                with self.assertRaises(ValueError):
                    evidence.bitset(path)
            path.write_text("bit_0044249e_045_16\n")
            self.assertEqual(evidence.bitset(path), {(0x44249E, 45, 16)})

    def test_cdc(self) -> None:
        """Only the explicitly reviewed asynchronous reset boundary is exempt."""
        report = ("CDC Report\nID Severity Count Description\nCDC-10 Critical 3 Combinational logic\n"
                  " 1 CDC-10 Critical False Path source packets/tr/release_sync_reg[0]/CLR\n"
                  " 2 CDC-10 Critical Timed source packets/tr/release_sync_reg[0]/CLR\n"
                  " 3 CDC-1 Critical False Path source unrecognized/D\n")
        result = evidence.cdc(report)
        self.assertEqual(result["reviewed_reset_alerts"], 1)
        self.assertEqual(len(result["unreviewed_critical"]), 2)
        with self.assertRaises(ValueError):
            evidence.cdc("")

    def test_known_bit_comparison(self) -> None:
        """Check zero bits too, union overlapping tile masks, and identify omitted defaults."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "gtx").mkdir()
            definitions = {
                "channel_1": "GTX_CHANNEL_1.USED 0_0 !0_1\n",
                "common": "GTX_COMMON.OVERLAP 0_0\nGTX_COMMON.DEFAULT[0] 0_2\n"}
            lock = {}
            for kind, content in definitions.items():
                digest = hashlib.sha256(content.encode()).hexdigest()
                (root / digest).write_text(content)
                lock[f"segbits_gtx_{kind}.db"] = {"sha256": digest}
            (root / "gtx/configuration.lock.json").write_text(json.dumps(lock))
            fasm, bits = root / "probe.fasm", root / "probe.bits"
            fasm.write_text("GTX_CHANNEL_1_X0Y0.USED\n")
            bits.write_text("bit_00000100_000_00\nbit_00000100_000_02\n")
            locations = {k: {"baseaddr": "0x100", "word_offset": 0} for k in ("channel", "common")}
            with patch.object(evidence, "ROOT", root):
                result = evidence.compare_configuration(fasm, bits, root, locations)
                self.assertEqual(result["missing_enabled_features"], [])
                self.assertEqual(result["extra_known_bits"], [[256, 0, 2]])
                self.assertEqual(list(result["extra_bit_features"]), ["GTX_COMMON.DEFAULT[0]"])
                bits.write_text(bits.read_text() + "bit_00000100_000_01\n")
                self.assertEqual(evidence.compare_configuration(fasm, bits, root, locations)
                                 ["missing_enabled_features"], ["GTX_CHANNEL_1.USED"])
                (root / next(iter(lock.values()))["sha256"]).write_text("modified")
                with self.assertRaises(ValueError):
                    evidence.compare_configuration(fasm, bits, root, locations)


if __name__ == "__main__":
    unittest.main()
