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
from dma import routed_image
from test_te0715_boot import CandidateTests


class InputTests(unittest.TestCase):
    """Reject incompatible clocks, drivers and output reuse without an SDK or board."""

    def test_routed_manifest_roots(self) -> None:
        """Physical inputs bind to the private experiment independently of compiler location."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "experiment"
            regsvc = Path(directory) / "regsvc"
            stage = Path(directory) / "physical"
            for path in (root, regsvc / "rtl", regsvc / "fsbl", stage):
                path.mkdir(parents=True)
            names = ("run_zynq_regsvc.sh", "openxc7_common.sh", "zynq_ps_probe.v", "zynq_ps_probe.xdc",
                     "dma/zynq_dma_mailbox.v", "dma/zynq_dma_pair.v", "dma/zynq_regsvc_core.sv",
                     "dma/zynq_dma_top.v", "dma/routed_image.py")
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
            for name in (f"{routed_image.PART}.bit", "stats.json", "netlist.json"):
                (stage / name).write_text(name)
            (stage / f"{routed_image.PART}-report.json").write_text(json.dumps(
                {"fmax": {"clock": {"constraint": 25, "achieved": 26}}}))
            (regsvc / "rtl/manifest.json").write_text("{}")
            (regsvc / "fsbl/fsbl.elf").write_text("boot")
            (regsvc / "fsbl/manifest.json").write_text(json.dumps({
                "fclk0_hz": routed_image.FCLK0_HZ, "inputs": {},
                "fsbl_sha256": routed_image.digest(regsvc / "fsbl/fsbl.elf")}))
            with patch.object(routed_image, "ROOT", root), patch.object(routed_image, "sources"):
                routed_image.physical_manifest(regsvc / "rtl", stage)
                bitstream = stage / f"{routed_image.PART}.bit"
                fsbl, _ = routed_image.routed_inputs(regsvc, bitstream)
                self.assertEqual(fsbl, regsvc / "fsbl/fsbl.elf")
                (root / names[0]).write_text("changed")
                with self.assertRaisesRegex(ValueError, "input/output changed"):
                    routed_image.routed_inputs(regsvc, bitstream)

    def test_clock_binding(self) -> None:
        """A coherent 25-MHz boot image is still wrong for these 100-MHz vendor probes."""
        with tempfile.TemporaryDirectory() as directory:
            reference = Path(directory) / "boot.json"
            reference.write_text(json.dumps({"fsbl_partition_sha256": "100MHz",
                                             "ps_init_sha256": "Trenz", "fclk0_hz": 100000000}))
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

    def test_register_mapping_requires_uio_bootarg(self) -> None:
        """Reject a register image that loads UIO before supplying its dynamic match."""
        node = "/amba_pl/probe@40000000"
        values = {
            ("/chosen", "bootargs"): "console=ttyPS0,115200 uio_pdrv_genirq.of_id=generic-uio",
            ("/axi/slcr@f8000000/clkc@100", "phandle"): "1",
            ("/axi/slcr@f8000000/clkc@100", "fclk-enable"): "1",
            (node, "compatible"): "generic-uio", (node, "linux,uio-name"): "erl-hls-probe",
            (node, "reg"): "40000000 1000", (node, "clocks"): "1 f",
        }
        with patch.object(kit, "fdt", side_effect=lambda tree, path, prop, kind: values[(path, prop)]):
            kit.check_mapping(Path("tree"), "register")
            values[("/chosen", "bootargs")] = "console=ttyPS0,115200"
            with self.assertRaisesRegex(ValueError, "UIO module option"):
                kit.check_mapping(Path("tree"), "register")


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
