#!/usr/bin/env python3
"""Check PS kit selection, clock/mapping contracts and optional real boot containers."""

import argparse
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_ps_probe as kit
import prepare_te0715_dma as dma
from test_te0715_boot import CandidateTests


class InputTests(unittest.TestCase):
    """Reject incompatible clocks, drivers and output reuse without an SDK or board."""

    def test_clock_binding(self) -> None:
        """A coherent 25-MHz boot image is still wrong for these 100-MHz vendor probes."""
        with tempfile.TemporaryDirectory() as directory:
            reference = Path(directory) / "boot.json"
            reference.write_text(json.dumps({"boot_partitions": [{"sha256": "100MHz"}],
                                             "ps_init_sha256": "Trenz"}))
            with patch.object(kit, "BOOT_REFERENCE", reference):
                kit.verify_clock([{"sha256": "100MHz"}], "Trenz")
                for payload, init in (("25MHz", "Trenz"), ("100MHz", "other-DDR")):
                    with self.subTest(payload=payload), self.assertRaisesRegex(ValueError, "100-MHz"):
                        kit.verify_clock([{"sha256": payload}], init)

    def test_required_inputs(self) -> None:
        """Reject mixed profile arguments before opening files or invoking a builder."""
        unused = Path("absent")
        for profile, runtime, kernel in (("prbs", None, None), ("dma", None, None),
                                          ("dma", unused, None), ("dma", None, unused),
                                          ("register", unused, None), ("register", None, unused)):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, "select register"):
                kit.build(profile, unused, unused, unused, runtime, kernel)

    def test_preserve_output(self) -> None:
        """An explicit DMA output cannot replace an existing kit or its staging files."""
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "stage"
            marker.write_text("preserve")
            manifests = {"base_runtime_manifest_sha256": "hash", "base_boot_manifest_sha256": "hash",
                         "base_kernel_sha256": "hash", "inputs": {}}
            with patch.object(dma, "validate_candidate", return_value={}), \
                    patch.object(dma, "check_manifest", return_value=manifests), \
                    patch.object(dma, "digest", return_value="hash"), \
                    self.assertRaises(FileExistsError):
                dma.build(output, output, output, output / "probe.bit", 1, output_root=output)
            self.assertEqual(marker.read_text(), "preserve")

    def test_dma_mapping(self) -> None:
        """Wrong interrupt, direction channels or aperture fail even with valid image hashes."""
        node = "/amba_pl/dma-mailbox@40000000"
        values = {
            ("/axi/slcr@f8000000/clkc@100", "phandle"): "1",
            ("/axi/slcr@f8000000/clkc@100", "fclk-enable"): "1",
            ("/axi/dma-controller@f8003000", "phandle"): "7",
            ("/axi/interrupt-controller@f8f01000", "phandle"): "4",
            (node, "compatible"): "erl-hls,dma-mailbox-v1", (node, "reg"): "40000000 3000",
            (node, "interrupt-parent"): "4", (node, "interrupts"): "0 1d 4",
            (node, "dmas"): "7 0 7 1", (node, "dma-names"): "tx rx",
            (node, "clocks"): "1 f", ("/aliases", "hlsdma0"): node,
        }
        with patch.object(kit, "fdt", side_effect=lambda tree, path, prop, kind: values[(path, prop)]):
            kit.check_mapping(Path("tree"), "dma")
            for prop, bad in (("interrupts", "0 1e 4"), ("dmas", "7 1 7 0"),
                               ("reg", "40000000 1000"), ("compatible", "generic-uio")):
                key = (node, prop)
                original = values[key]
                values[key] = bad
                with self.subTest(prop=prop), self.assertRaisesRegex(ValueError, "mapping differs"):
                    kit.check_mapping(Path("tree"), "dma")
                values[key] = original


def check_containers(candidate: Path) -> None:
    """Test independent Bootgen corruption checks and kit metadata against actual artifacts."""
    manifest = kit.check_candidate(candidate)
    suite = unittest.TestSuite()
    names = ["test_source_payloads", "test_checksums", "test_payload_corruption", "test_ranges_and_destinations"]
    if manifest["profile"] == "register":
        names += ["test_linux_startup_layout", "test_manifest_and_mapping"]
    for name in names:
        case = CandidateTests(name)
        case.candidate = candidate
        suite.addTest(case)
    if not unittest.TextTestRunner().run(suite).wasSuccessful():
        raise RuntimeError("PS kit boot corruption checks failed")
    for key, bad in (("fclk0_hz", 25000000), ("programs", []), ("root_partition", {"number": 1})):
        altered = copy.deepcopy(manifest)
        altered[key] = bad
        with patch.object(kit, "check_manifest", return_value=altered):
            try:
                kit.check_candidate(candidate)
            except ValueError:
                continue
        raise AssertionError(f"accepted altered {key}")


def main() -> None:
    """Run portable input checks; optionally validate one complete retained kit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(InputTests))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.candidate:
        check_containers(args.candidate.resolve())


if __name__ == "__main__":
    main()
