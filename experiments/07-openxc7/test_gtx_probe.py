#!/usr/bin/env python3
"""Test GTX metadata safeguards and digital diagnostics without an analog GTX model."""

import argparse
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from gtx.prepare import audit_database, digest, fetch, install_metadata, validate_site


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
