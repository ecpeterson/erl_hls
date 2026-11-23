#!/usr/bin/env python3
"""Test GTX metadata safeguards and digital diagnostics without an analog GTX model."""

import argparse
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from gtx.prepare import audit_database, digest, fetch, install_metadata, validate_site
from gtx.coverage import compare, connectivity, enabled_features
from gtx.reference import CASES, source


class MetadataTests(unittest.TestCase):
    """Prevent logical metadata reuse from silently becoming bitstream evidence."""

    def test_structural_mismatch(self) -> None:
        """A changed physical site or direction is rejected before overlay creation."""
        physical = json.dumps({"site_pins": {"O": {"direction": "OUT"}}}).encode()
        logical = json.dumps({"IPAD": {"pins": {"O": {"dir": "OUTPUT"}}}}).encode()
        validate_site("IPAD", physical, physical, logical)
        with self.assertRaisesRegex(ValueError, "structural site"):
            validate_site("IPAD", physical, b"{}", logical)
        with self.assertRaisesRegex(ValueError, "metadata pins"):
            validate_site("IPAD", physical, physical, logical.replace(b'"O"', b'"X"'))
        with self.assertRaisesRegex(ValueError, "direction"):
            validate_site("IPAD", physical, physical, logical.replace(b"OUTPUT", b"INPUT"))

    def test_modified_cache(self) -> None:
        """Cached downloads are checked again, including on offline reuse."""
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            source = {"url": "https://example.invalid/unused", "sha256": digest(b"expected")}
            (cache / source["sha256"]).write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                fetch(source, cache)

    def test_overlay_identity(self) -> None:
        """Changes invalidate the overlay; corrupt immutable copies cannot be reused."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {"site_type_IPAD.json": b"first"}
            target = install_metadata(files, root)
            self.assertEqual(target, install_metadata(files, root))
            self.assertNotEqual(target, install_metadata({"site_type_IPAD.json": b"second"}, root))
            (target / "site_type_IPAD.json").write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "modified metadata"):
                install_metadata(files, root)

    def test_missing_configuration(self) -> None:
        """Structural GTX tiles alone do not imply usable frame/feature data."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "xc7z030").mkdir()
            grid = {"CHANNEL": {"type": "GTX_CHANNEL_1", "bits": {}},
                    "COMMON": {"type": "GTX_COMMON", "bits": {}}}
            (root / "xc7z030/tilegrid.json").write_text(json.dumps(grid))
            report = audit_database(root)
            self.assertFalse(report["assembly_data_present"])
            self.assertEqual(report["missing_frame_mapping"], ["CHANNEL", "COMMON"])
            fasm = root / "probe.fasm"
            fasm.write_text("# only the used channel\nCHANNEL.IN_USE\n")
            self.assertEqual(audit_database(root, fasm)["missing_frame_mapping"], ["CHANNEL"])
            # Presence alone must still not be presented as hardware qualification.
            grid["CHANNEL"]["bits"] = {"CLB_IO_CLK": {"baseaddr": "unverified"}}
            (root / "xc7z030/tilegrid.json").write_text(json.dumps(grid))
            (root / "segbits_gtx_channel_1.db").write_text("")
            self.assertFalse(audit_database(root, fasm)["assembly_data_present"])
            (root / "segbits_gtx_channel_1.db").write_text("feature 00_00\n")
            self.assertFalse(audit_database(root, fasm)["hardware_qualified"])
            fasm.write_text("# no GTX\n")
            with self.assertRaisesRegex(ValueError, "no GTX"):
                audit_database(root, fasm)

    def test_feature_expansion(self) -> None:
        """Literal zero extension, nonzero starts and repeated features remain exact."""
        self.assertEqual(enabled_features("T.X[7:2] = 4'b1010\nT.Y\nT.Y\nT.Z[0] # note\n"),
                         {"T.X[3]", "T.X[5]", "T.Y", "T.Z[0]"})
        self.assertEqual(enabled_features("T.X[7:0] = 8'b00000000"), set())
        for invalid in ("T.X[2:7] = 6'b101010", "T.X[1:0] = 3'b111", "T.X[2:0]", "T.X { unknown }"):
            with self.assertRaises(ValueError):
                enabled_features(invalid)

    def test_feature_coverage(self) -> None:
        """A fixed interface needs no frame mapping; an unknown feature still fails coverage."""
        grid = {"C": {"type": "GTX_CHANNEL_1", "bits": {}},
                "I": {"type": "GTX_INT_INTERFACE", "bits": {}}}
        donor = {"segbits_gtx_channel_1.db": b"GTX_CHANNEL_1.ATTR[0] 28_123\n",
                 "ppips_gtx_int_interface.db": b"GTX_INT_INTERFACE.FIXED always\nGTX_INT_INTERFACE.DEFAULT default\n"}
        report = compare(grid, "C.ATTR[3:0] = 4'b0001\nI.FIXED", donor)
        self.assertTrue(report["donor_covers_enabled_features"])
        self.assertEqual(report["missing_frame_mapping"], ["C"])
        self.assertFalse(report["encodings_validated_on_zynq"])
        missing = compare(grid, "C.ATTR[1]\nI.DEFAULT", donor)
        self.assertFalse(missing["donor_covers_enabled_features"])
        self.assertEqual(missing["coverage"]["GTX_CHANNEL_1"]["missing"], ["GTX_CHANNEL_1.ATTR[1]"])
        self.assertEqual(missing["coverage"]["GTX_INT_INTERFACE"]["missing"], ["GTX_INT_INTERFACE.DEFAULT"])

    def test_connectivity_not_timing(self) -> None:
        """Timing estimates may differ, but donor routing endpoints must agree."""
        pip = {"P": {"src_wire": "A", "dst_wire": "B", "src_to_dst": {"delay": 1}}}
        changed = {"P": {**pip["P"], "src_to_dst": {"delay": 2}}}
        self.assertEqual(connectivity(pip), connectivity(changed))
        changed["P"]["dst_wire"] = "C"
        self.assertNotEqual(connectivity(pip), connectivity(changed))

    def test_reference_variations(self) -> None:
        """Each paired reference changes only one attribute at a fixed bonded site."""
        for case in CASES.values():
            baseline = source(case, {})
            self.assertIn('LOC="'+case["site"]+'"', baseline)
            for change in case["changes"].values():
                variant = source(case, change)
                differences = [(a, b) for a, b in zip(baseline.splitlines(), variant.splitlines()) if a != b]
                self.assertEqual(len(differences), 1)
                self.assertIn("DO NOT PROGRAM", variant)


def run(yosys: Path | None) -> None:
    """Run portable metadata/RTL checks, adding mapped digital simulation with Yosys."""
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(MetadataTests))
    if not result.wasSuccessful():
        raise RuntimeError("GTX metadata tests failed")
    root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix="gtx-probe-") as directory:
        stage = Path(directory)
        sources = [root / "zynq_ps_probe.v", root / "gtx/gtx_probe_sample.v",
                   root / "gtx/gtx_probe_control.v", root / "gtx/gtx_probe_tb.sv"]
        for mapped in ([False, True] if yosys else [False]):
            arguments = ["iverilog", "-g2012", "-s", "gtx_probe_tb", "-o", str(stage / "test.vvp")]
            additions = []
            if mapped:
                for module in ("gtx_probe_control", "gtx_probe_sample"):
                    target = stage / f"{module}.v"
                    script = f'read_verilog "{root / "zynq_ps_probe.v"}" "{root / "gtx" / (module + ".v")}"; '
                    if module == "gtx_probe_control":
                        script += ("chparam -set BOOT_CYCLES 8 -set SETTLE_CYCLES 12 "
                                   "-set TIMEOUT_CYCLES 200 -set CLOCK_TIMEOUT 40 gtx_probe_control; ")
                    script += (f'synth_xilinx -noiopad -flatten -family xc7 -top {module}; '
                               f'check -assert; rename {module} {module}_mapped; '
                               f'write_verilog -noattr "{target}"')
                    subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / f"{module}.log"),
                                    "-p", script], check=True)
                    additions.append(target)
                config = yosys.with_name("yosys-config")
                data = (Path(subprocess.check_output([str(config), "--datdir"], text=True).strip())
                        if config.is_file() else yosys.parent.parent / "share/yosys")
                additions.append(data / "xilinx/cells_sim.v")
                arguments.append("-DMAPPED")
            subprocess.run([*arguments, *map(str, sources + additions)], check=True)
            subprocess.run(["vvp", str(stage / "test.vvp")], check=True, timeout=30)


def main() -> None:
    """Accept an optional synthesizer for mapped digital-controller validation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path)
    args = parser.parse_args()
    run(args.yosys.resolve() if args.yosys else None)


if __name__ == "__main__":
    main()
