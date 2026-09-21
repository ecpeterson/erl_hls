#!/usr/bin/env python3
"""Exercise clock profile constraints, FSBL hooks and all bounded transport fault paths."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_clock_fsbl as builder
from clocking.profile import audit, read_rows, render, vendor_rows

ROOT = Path(__file__).resolve().parent
CLOCK = ROOT / "clocking"


class ProfileTests(unittest.TestCase):
    """Reject electrical/divider drift and disconnected boot hooks before cross compilation."""

    def test_profile(self) -> None:
        """The fixed table round-trips and independently decodes to both required outputs."""
        rows = read_rows(CLOCK / "profile.h")
        self.assertEqual((CLOCK / "profile.h").read_text(), render(rows))
        self.assertEqual(len(rows), 236)
        self.assertEqual(audit(rows)["clk2_hz"], 125000000)
        self.assertEqual(audit(rows)["clk3_hz"], 50000000)
        for address in (27, 28, 33, 34, 35, 75, 86, 97, 230):
            with self.subTest(address=address), self.assertRaises(ValueError):
                audit([(a, v ^ (1 if a == address else 0), m) for a, v, m in rows])
        with self.assertRaisesRegex(ValueError, "profile changed"):
            vendor_rows(b"not the pinned Trenz table")

    def test_hook_installation(self) -> None:
        """Require exact generated content and an enabled before-load and before-handoff hook."""
        rows = read_rows(CLOCK / "profile.h")
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            (stage / "te_Si5338-Registers.h").write_bytes(b"fixture")
            hooks = stage / "te_fsbl_hooks.h"
            hooks.write_text("// #define ENABLE_TE_HOOKS_BD\n#define ENABLE_TE_HOOKS_BH\n")
            with patch.object(builder, "vendor_rows", return_value=rows):
                builder.install_hooks(stage)
                self.assertTrue(hooks.read_text().startswith("#define ENABLE_TE_HOOKS_BD\n"))
                self.assertEqual((stage / "te_fsbl_hooks_te0715.c").read_bytes(),
                                 (CLOCK / "clock_fsbl.c").read_bytes())
                with self.assertRaises(ValueError):
                    builder.install_hooks(stage)
                hooks.write_text("// #define ENABLE_TE_HOOKS_BD\n")
                with self.assertRaisesRegex(ValueError, "before-handoff"):
                    builder.install_hooks(stage)


def check_c(stage: Path) -> None:
    """Build the real clock drivers/client and exercise deterministic chip, bus and boot failures."""
    for name, sources in {"test_si5338": ["test_si5338.c", "si5338.c"],
                          "test_ps_i2c": ["test_ps_i2c.c", "ps_i2c.c"],
                          "test_clock_fsbl": ["test_clock_fsbl.c", "clock_fsbl.c"],
                          "probe_clock": ["probe_clock.c", "si5338.c"]}.items():
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        "-I", str(CLOCK / "test_bsp"), *(str(CLOCK / name) for name in sources),
                        "-o", str(stage / name)], check=True)
        if name.startswith("test_"):
            subprocess.run([str(stage / name)], check=True, timeout=5)
    inert = stage / "inert"
    inert.write_bytes(b"not an I2C device")
    for args, expected in (([], 2), ([str(stage / "missing")], 1), ([str(inert)], 1)):
        result = subprocess.run([str(stage / "probe_clock"), *args], capture_output=True, timeout=2)
        assert result.returncode == expected, result.stderr
        assert inert.read_bytes() == b"not an I2C device"


def run() -> None:
    """Run without an SDK, network, hardware access or external model dependencies."""
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ProfileTests))
    if not result.wasSuccessful():
        raise RuntimeError("clock profile/hook checks failed")
    with tempfile.TemporaryDirectory(prefix="clock-startup-") as directory:
        check_c(Path(directory))


if __name__ == "__main__":
    run()
