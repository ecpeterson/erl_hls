#!/usr/bin/env python3
"""Check link-kit selection, PRBS diagnostics, and optionally the packaged ARM userspace."""

import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import prepare_link_probe as kit
from gtx.compose_external_prbs import (ADDED, REMOVED, derive_bits, normalize_bit_header,
                                       parse_frame_dump, patch_frames)
from gtx.check_backend import top_cells
from prepare_te0715_boot import digest
from test_te0715_qemu import INIT, run as check_linux
from test_te0715_boot import CandidateTests


class InputTests(unittest.TestCase):
    """Fail before packaging an altered image or a mismatched control clock."""

    def test_profile_binding(self) -> None:
        """Profile selection is an exact digest check, not a permissive .bit target check."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "candidate.bit"
            image.write_bytes(b"exact-image")
            reference = root / "reference.json"
            reference.write_text(json.dumps({"profiles": {
                name: {"artifacts_sha256": {"candidate.bit": digest(image) if name == "prbs" else "other"}}
                for name in kit.PROFILES}}))
            with patch.object(kit, "REFERENCE", reference), patch("boot.reference.bit_payload") as parse:
                kit.verify_reference("prbs", image)
                self.assertEqual(parse.call_count, 1)
                for profile in ("ethernet-loopback", "ethernet-external", "missing"):
                    with self.subTest(profile=profile), self.assertRaises(ValueError):
                        kit.verify_reference(profile, image)
                image.write_bytes(b"changed-image")
                with self.assertRaisesRegex(ValueError, "differs"):
                    kit.verify_reference("prbs", image)
                self.assertEqual(parse.call_count, 1)

    def test_clock_binding(self) -> None:
        """Reject the 100-MHz FSBL, changed binaries and drift in its recorded source inputs."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fsbl.elf").write_bytes(b"25-MHz FSBL")
            (root / "source.py").write_bytes(b"source")
            original = {"fclk0_hz": 25000000, "fsbl_sha256": digest(root / "fsbl.elf"),
                        "inputs": {"source.py": digest(root / "source.py")}}
            with patch.object(kit, "ROOT", root):
                for frequency in (25000000, 100000000):
                    (root / "manifest.json").write_text(json.dumps({**original, "fclk0_hz": frequency}))
                    if frequency == 25000000:
                        kit.verify_clock(root)
                    else:
                        with self.assertRaisesRegex(ValueError, "25-MHz"):
                            kit.verify_clock(root)
                (root / "manifest.json").write_text(json.dumps(original))
                (root / "source.py").write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "source changed"):
                    kit.verify_clock(root)
                (root / "fsbl.elf").write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "25-MHz"):
                    kit.verify_clock(root)


class CompositionTests(unittest.TestCase):
    """Bind external PRBS to the measured eight-bit retained-image delta."""

    def test_exact_delta(self) -> None:
        """Apply only the six removals and two additions to an otherwise unchanged PRBS set."""
        common = {"bit_00000001_000_00", "bit_00000002_001_01"}
        loopback = common | REMOVED
        external = common | ADDED
        prbs = common | REMOVED | {"bit_00000003_002_02"}
        self.assertEqual(derive_bits(loopback, external, prbs),
                         (prbs - REMOVED) | ADDED)
        with self.assertRaisesRegex(ValueError, "delta changed"):
            derive_bits(loopback | {"bit_00000004_003_03"}, external, prbs)
        with self.assertRaisesRegex(ValueError, "loopback-side"):
            derive_bits(loopback, external, prbs - {next(iter(REMOVED))})

    def test_frame_patch(self) -> None:
        """Parse complete frames and reproduce the expected hard-GTX bit values."""
        addresses = {int(name.split("_")[1], 16) for name in REMOVED | ADDED}
        frames = {address: [0] * 101 for address in addresses}
        for name in REMOVED:
            _, frame, word, bit = name.split("_")
            frames[int(frame, 16)][int(word)] |= 1 << int(bit)
        dump = "\n".join(
            f".frame 0x{address:08x}\n" + " ".join(f"0x{word:08x}" for word in words)
            for address, words in frames.items())
        parsed = parse_frame_dump(dump)
        patch_frames(parsed)
        for name in REMOVED | ADDED:
            _, frame, word, bit = name.split("_")
            expected = int(name in ADDED)
            self.assertEqual((parsed[int(frame, 16)][int(word)] >> int(bit)) & 1, expected)
        with self.assertRaisesRegex(ValueError, "final frame"):
            parse_frame_dump(".frame 0x00442494\n0x00000000")

    def test_header_normalization(self) -> None:
        """Remove clock variance without changing the structured design or payload fields."""
        def field(key: bytes, value: bytes) -> bytes:
            """Encode one length-prefixed synthetic .bit header field."""
            return key + struct.pack(">H", len(value)) + value

        data = (struct.pack(">H", 9) + b"\x0f\xf0" * 4 + b"\0" + b"\0\1" +
                field(b"a", b"candidate.frames;Generator=xc7frames2bit\0") +
                field(b"b", b"xc7z030sbg485-1\0") + field(b"c", b"2026/10/09\0") +
                field(b"d", b"22:43:06\0") + b"e" + struct.pack(">I", 4) + b"data")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidate.bit"
            path.write_bytes(data)
            self.assertEqual(normalize_bit_header(path), {
                "design": "candidate.frames;Generator=xc7frames2bit",
                "date": "2000/01/01", "time": "00:00:00"})
            normalized = path.read_bytes()
            self.assertIn(b"2000/01/01\0", normalized)
            self.assertIn(b"00:00:00\0", normalized)
            self.assertTrue(normalized.endswith(b"data"))

    def test_gtx_owner_selection(self) -> None:
        """Select the unique GTX-owning module without depending on its generated top name."""
        owner = {"clock": {"type": "IBUFDS_GTE2"}, "lane": {"type": "GTXE2_CHANNEL"}}
        netlist = {"modules": {"wrapper": {"cells": {}}, "generated_top": {"cells": owner}}}
        self.assertIs(top_cells(netlist), owner)
        netlist["modules"]["second"] = {"cells": {"other": {"type": "IBUFDS_GTE2"}}}
        with self.assertRaises(ValueError):
            top_cells(netlist)


def check_driver(stage: Path) -> None:
    """Test PRBS fault sequencing and the real CLI over an inert, file-backed MMIO page."""
    root = Path(__file__).resolve().parent
    for name in ("probe_gtx", "test_probe_gtx"):
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        str(root / "gtx" / f"{name}.c"), "-o", str(stage / name)], check=True)
    subprocess.run([str(stage / "test_probe_gtx")], check=True, timeout=5)
    device = stage / "fake-uio"
    for identity, abi, run, expected in ((0, 1, True, 1), (0x47545837, 2, True, 1),
                                        (0x47545837, 1, False, 0), (0x47545837, 1, True, 1)):
        device.write_bytes(struct.pack("=9I", identity, abi, 0x55, 100, 0, 0x176, 500, 0, 500).ljust(4096, b"\0"))
        result = subprocess.run([str(stage / "probe_gtx"), str(device), *(["--run"] if run else [])],
                                capture_output=True, text=True, timeout=2)
        assert result.returncode == expected, result.stdout + result.stderr
        expected_control = 0 if identity == 0x47545837 and abi == 1 and run else 0x55
        assert struct.unpack_from("=I", device.read_bytes(), 8)[0] == expected_control
    for args in ([], [str(device), "--typo"]):
        assert subprocess.run([str(stage / "probe_gtx"), *args], capture_output=True).returncode == 2


def check_arm(candidate: Path) -> Path:
    """Boot the matched DTB, run ARM diagnostics without PL access, and retain the UART log."""
    manifest = kit.check_candidate(candidate)
    # Reuse the independent Bootgen corruption cases with each real PL payload.
    suite = unittest.TestSuite()
    for name in ("test_source_payloads", "test_checksums", "test_payload_corruption", "test_ranges_and_destinations"):
        test = CandidateTests(name)
        test.candidate = candidate
        suite.addTest(test)
    if not unittest.TextTestRunner().run(suite).wasSuccessful():
        raise RuntimeError("link-kit boot corruption checks failed")
    program = manifest["configuration"]["program"]
    init = INIT.replace(b"erl-hls-probe", manifest["configuration"]["uio"].encode())
    init = init.replace(b"probe_zynq_ps", program.encode())
    identity = b"a GTX7" if manifest["profile"] == "prbs" else b"an ETH7"
    init = init.replace(b"unexpected identity/ABI; no writes attempted",
                        b"not " + identity + b" ABI-1 register bank")
    if manifest["profile"] != "prbs":
        init = init.replace(b"/test_probe_ethernet\n", b"")
    if manifest.get("fsbl_programs_si5338"):
        # Kernel/ARM ABI check only: QEMU has no Si5338 or analog clock model.
        init = init.replace(b"echo 'PASS:", b"""/test_si5338
/test_ps_i2c
modprobe i2c-dev
test -c /dev/i2c-0
case "$(readlink -f /sys/class/i2c-dev/i2c-0/device)" in
  */e0005000.i2c/i2c-0) ;; *) exit 1 ;; esac
status=0
/probe_clock || status=$?
test "$status" -eq 2
status=0
/probe_clock /tmp/inert-page || status=$?
test "$status" -eq 1
echo 'PASS:""")
    return check_linux(candidate, 45, programs=tuple(manifest["programs"]), init=init)


def run() -> None:
    """Run offline packaging/host tests with no SDK, retained images or QEMU dependency."""
    suite = unittest.TestSuite()
    for case in (InputTests, CompositionTests):
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(case))
    result = unittest.TextTestRunner().run(suite)
    if not result.wasSuccessful():
        raise RuntimeError("link-kit input checks failed")
    with tempfile.TemporaryDirectory(prefix="link-driver-") as directory:
        check_driver(Path(directory))


def main() -> None:
    """Optionally add a real packaged candidate's ARM Linux smoke test."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    args = parser.parse_args()
    run()
    if args.candidate:
        print(check_arm(args.candidate.resolve()))


if __name__ == "__main__":
    main()
