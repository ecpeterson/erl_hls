#!/usr/bin/env python3
"""Check a built candidate and reject corrupted boot headers, payloads and board settings."""

import argparse
import json
import struct
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from boot.board import EXPECTED_FREQ, EXPECTED_PS, bsp_parameters, check_profile
from build_regsvc_fsbl import divide_fclk0
from check_zynq_boot import bit_payload, check, check_linux_elf, elf_segments
from prepare_te0715_boot import digest, fdt


def sample_profile() -> tuple[str, str, str]:
    """Provide a small PS description for exercising profile rejection independently of downloads."""
    csv = "47,TE0715-05-71C33-A,xc7z030sbg485-1,board,04_30_1c_1gb,qspi,flash,REV05,1GB,32MB\n"
    root = ET.Element("SYSTEM")
    module = ET.SubElement(root, "MODULE", MODTYPE="processing_system7")
    for name, value in EXPECTED_PS.items():
        ET.SubElement(module, "PARAMETER", NAME=name, VALUE=value)
    header = "\n".join(f"#define {name}_FREQ {value}" for name, value in EXPECTED_FREQ.items())
    return csv, ET.tostring(root, encoding="unicode"), header


class BoardTests(unittest.TestCase):
    """Pin compatibility checks that prevent selecting another module's DDR/MIO setup."""

    def test_profile(self) -> None:
        """Accept the exact SKU and reject changed module, clock and GP0 settings."""
        inputs = sample_profile()
        self.assertEqual(check_profile(*inputs), EXPECTED_FREQ)
        for index, old, new in ((0, "REV05", "REV04"), (0, "1GB", "512MB"),
                                (1, "MIO 14 .. 15", "MIO 10 .. 11"),
                                (1, 'VALUE="12"', 'VALUE="6"'),
                                (2, "100000000", "50000000")):
            with self.subTest(old=old), self.assertRaises(ValueError):
                changed = list(inputs)
                changed[index] = changed[index].replace(old, new)
                check_profile(*changed)

    def test_missing_bsp_macro(self) -> None:
        """An incomplete upstream BSP must fail rather than silently retain board defaults."""
        with self.assertRaisesRegex(ValueError, "BSP macro"):
            bsp_parameters("#define STDIN_BASEADDRESS 0\n", EXPECTED_FREQ)

    def test_routed_clock(self) -> None:
        """Change every silicon table's FCLK0 divider, rejecting drift or a second patch."""
        old = "EMIT_MASKWRITE(0XF8000170, 0x03F03F30U ,0x00200500U)"
        source = "DDR untouched\n" + (old + "\n") * 3 + "MIO untouched\n"
        expected = source.replace("0x00200500U", "0x00800500U")
        self.assertEqual(divide_fclk0(source), expected)
        for invalid in (source.replace(old, "", 1), source + old, expected):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                divide_fclk0(invalid)

    def test_malformed_inputs(self) -> None:
        """Truncated ELF and .bit containers fail before payload interpretation."""
        for reader in (elf_segments, bit_payload):
            with self.subTest(reader=reader.__name__), self.assertRaises(ValueError):
                reader(b"\0" * 64)

    def test_bit_part_names(self) -> None:
        """Accept the two tool spellings of this chip/package, never another target."""
        for part in (b"xc7z030sbg485-1\0", b"7z030sbg485\0", b"7z020clg484\0",
                     b"7z030ffg676\0", b"xc7z030sbg485-2\0", b"7z030sbg485"):
            data = bytes.fromhex("00090ff00ff00ff00ff0000001")
            for tag, field in zip(b"abcd", (b"design\0", part, b"date\0", b"time\0")):
                data += bytes([tag]) + len(field).to_bytes(2, "big") + field
            data += b"e\0\0\0\4test"
            if part in (b"xc7z030sbg485-1\0", b"7z030sbg485\0"):
                self.assertEqual(bit_payload(data), b"test")
            else:
                with self.subTest(part=part), self.assertRaisesRegex(ValueError, "wrong .bit target"):
                    bit_payload(data)


class CandidateTests(unittest.TestCase):
    """Exercise the independent verifier on real Bootgen output and targeted corruptions."""

    candidate: Path

    def setUp(self) -> None:
        """Load the checked image and its independent source payloads for each corruption test."""
        self.inputs = [(self.candidate / name).read_bytes() for name in
                       ("BOOT.bin", "fsbl.elf", "probe.bit", "u-boot.elf", "system.dtb")]
        self.pht = struct.unpack_from("<I", self.inputs[0], 0x9c)[0]

    def verify(self, image: bytes | bytearray) -> list[dict]:
        """Compare a candidate image against the unmodified build inputs."""
        return check(bytes(image), *self.inputs[1:])

    def change_partition(self, partition: int, word: int, value: int) -> bytes:
        """Change one header field while preserving its checksum, testing structural validation."""
        image = bytearray(self.inputs[0])
        offset = self.pht + partition * 64
        words = list(struct.unpack_from("<16I", image, offset))
        words[word] = value
        words[-1] = ~sum(words[:-1]) & 0xffffffff
        struct.pack_into("<16I", image, offset, *words)
        return bytes(image)

    def test_source_payloads(self) -> None:
        """Require all four partitions, including FSBL OCM bounds and exact PL word swapping."""
        self.assertEqual(len(self.verify(self.inputs[0])), 4)

    def test_checksums(self) -> None:
        """Reject a changed boot header and each changed partition header."""
        for offset in [0x48] + [self.pht + i * 64 + 60 for i in range(4)]:
            with self.subTest(offset=offset), self.assertRaisesRegex(ValueError, "checksum"):
                image = bytearray(self.inputs[0])
                image[offset] ^= 1
                self.verify(image)

    def test_linux_startup_layout(self) -> None:
        """Require mapped ELF headers; the bare-metal default crashed musl before main."""
        for name in ("probe_zynq_ps", "test_probe_zynq_ps"):
            data = (self.candidate / name).read_bytes()
            check_linux_elf(data)
            broken = bytearray(data)
            offset = struct.unpack_from("<I", broken, 28)[0]
            count = struct.unpack_from("<H", broken, 44)[0]
            for i in range(count):
                header = offset + i * 32
                if struct.unpack_from("<I", broken, header)[0] == 1:
                    # Move each file mapping past the ELF headers without changing code.
                    struct.pack_into("<I", broken, header + 4, 4096)
            with self.subTest(name=name), self.assertRaises(ValueError):
                check_linux_elf(bytes(broken))

    def test_payload_corruption(self) -> None:
        """Detect a byte changed inside each payload, independently of header checksums."""
        for partition in range(4):
            with self.subTest(partition=partition), self.assertRaisesRegex(ValueError, "payload differs"):
                image = bytearray(self.inputs[0])
                start = struct.unpack_from("<I", image, self.pht + partition * 64 + 20)[0] * 4
                image[start] ^= 1
                self.verify(image)

    def test_ranges_and_destinations(self) -> None:
        """Reject overlapping, truncated, redirected and unexpectedly authenticated partitions."""
        for partition, word, value in ((1, 5, 0), (2, 5, len(self.inputs[0]) // 4),
                                        (3, 3, 0x200000), (1, 6, 0x10), (0, 10, 1)):
            with self.subTest(partition=partition, word=word), self.assertRaises(ValueError):
                self.verify(self.change_partition(partition, word, value))
        with self.assertRaisesRegex(ValueError, "truncated"):
            self.verify(self.inputs[0][:-1])

    def test_manifest_and_mapping(self) -> None:
        """Check published file digests and the Linux address/clock contract."""
        manifest = json.loads((self.candidate / "manifest.json").read_text())
        self.assertFalse(manifest["hardware_validated"])
        for name, info in manifest["files"].items():
            self.assertEqual(digest(self.candidate / name), info["sha256"], name)
        tree = self.candidate / "system.dtb"
        node = "/amba_pl/probe@40000000"
        self.assertEqual(fdt(tree, node, "reg", "x"), "40000000 1000")
        self.assertEqual(fdt(tree, node, "compatible"), "generic-uio")
        self.assertEqual(fdt(tree, "/axi/slcr@f8000000/clkc@100", "fclk-enable", "x"), "1")


def main() -> None:
    """Run profile tests and, when supplied, corruption tests against a built candidate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    args = parser.parse_args()
    suite = unittest.TestLoader().loadTestsFromTestCase(BoardTests)
    if args.candidate:
        CandidateTests.candidate = args.candidate.resolve()
        suite.addTests(unittest.TestLoader().loadTestsFromTestCase(CandidateTests))
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
