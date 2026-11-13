#!/usr/bin/env python3
"""Exercise real FSBL staging without compiling firmware or downloading sources."""

import argparse
from pathlib import Path
import tempfile
import unittest

from boot.board import prepare_fsbl
from test_te0715_boot import sample_profile


VENDOR_CALL = "  Status = te_read_IDCODE(); // general include to display Device ID of the zynq"
OMITTED_CALL = "  /* Keep PCAP idle for Linux: omit the optional diagnostic IDCODE read. */"
GENERAL_HOOK = """u32 TE_FsblHookBeforeHandoff(void)
{
  u32 Status = XST_SUCCESS;
  Status = te_read_IDCODE(); // general include to display Device ID of the zynq
  #if defined(ENABLE_TE_HOOKS_BH)
    Status = TE_FsblHookBeforeHandoff_Custom();
  #endif
  return Status;
}
"""


def stage_fixture(root: Path, general_hook: str) -> Path:
    """Stage one supplied hook through prepare_fsbl with a minimal valid board profile."""
    amd, vendor, xsa = (root / name for name in ("amd", "vendor", "xsa"))
    csv, hwh, header = sample_profile()
    macros = ["STDIN_BASEADDRESS", "STDOUT_BASEADDRESS"]
    for prefixes, fields in (
        (("PS7_UART_0", "XUARTPS_0"), ("BASEADDR", "HIGHADDR", "UART_CLK_FREQ_HZ")),
        (("PS7_I2C_1", "XIICPS_0"), ("BASEADDR", "HIGHADDR", "I2C_CLK_FREQ_HZ")),
        (("PS7_SD_0", "XSDPS_0"), ("HAS_CD", "HAS_WP", "MIO_BANK", "SDIO_CLK_FREQ_HZ")),
    ):
        macros.extend(f"XPAR_{prefix}_{field}" for prefix in prefixes for field in fields)
    files = {
        vendor / "board_files/TE0715_board_files.csv": csv,
        vendor / "sw_lib/sw_apps/zynq_fsbl/src/te_fsbl_hooks.c": general_hook,
        vendor / "sw_lib/sw_apps/zynq_fsbl/src/te_fsbl_hooks_te0715.c":
            '#include "te_fsbl_hooks_te0715.h"\n/* custom clock hooks */\n',
        amd / "lib/sw_apps/zynq_fsbl/misc/zc702/xparameters.h":
            "\n".join(f"#define {name} 0" for name in macros) + "\n",
        amd / "lib/sw_apps/zynq_fsbl/misc/zc702/drivers.txt": "devcfg\n",
        xsa / "zsys.hwh": hwh,
        xsa / "ps7_init.h": header,
        xsa / "ps7_init.c": "/* PS initialization retained verbatim. */\n",
    }
    for path, contents in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
    return prepare_fsbl(amd, vendor, xsa)


class FsblStagingTests(unittest.TestCase):
    """Require the common staging path to omit only the unsafe optional diagnostic."""

    def test_omits_diagnostic_and_retains_custom_handoff(self) -> None:
        """Keep the custom hook and PS initialization while removing the diagnostic call."""
        with tempfile.TemporaryDirectory() as directory:
            output = stage_fixture(Path(directory), GENERAL_HOOK)
            self.assertEqual(
                (output / "te_fsbl_hooks.c").read_text(),
                GENERAL_HOOK.replace(VENDOR_CALL, OMITTED_CALL),
            )
            self.assertEqual(
                (output / "te_fsbl_hooks_te0715.c").read_text(),
                '#include "te_fsbl_hooks_te0715.h"\n#include "te_iic_platform.h"\n'
                '/* custom clock hooks */\n',
            )
            self.assertEqual(
                (output.parent / "misc/te0715/ps7_init.c").read_text(),
                "/* PS initialization retained verbatim. */\n",
            )

    def test_rejects_missing_changed_or_duplicated_diagnostic(self) -> None:
        """Vendor drift must fail staging instead of retaining an unchecked PCAP call."""
        invalid = {
            "missing": GENERAL_HOOK.replace(VENDOR_CALL, ""),
            "changed": GENERAL_HOOK.replace("te_read_IDCODE();", "te_read_IDCODE(1);"),
            "duplicated": GENERAL_HOOK.replace(VENDOR_CALL, VENDOR_CALL + "\n" + VENDOR_CALL),
        }
        for reason, hook in invalid.items():
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, "expected exactly one occurrence"):
                    stage_fixture(Path(directory), hook)


def verify_qualified_hook(vendor_hook: Path, qualified_hook: Path) -> None:
    """Compare real staging of retained vendor bytes with the hardware-qualified hook."""
    with tempfile.TemporaryDirectory() as directory:
        output = stage_fixture(Path(directory), vendor_hook.read_text())
        emitted = (output / "te_fsbl_hooks.c").read_bytes()
        if emitted != qualified_hook.read_bytes():
            raise ValueError("staged hook differs from the hardware-qualified source")
    print("QUALIFIED_HOOK_BYTES_MATCH")


def main() -> None:
    """Run the focused fixture, or compare an explicitly supplied qualification pair."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor-hook", type=Path)
    parser.add_argument("--qualified-hook", type=Path)
    args = parser.parse_args()
    if bool(args.vendor_hook) != bool(args.qualified_hook):
        parser.error("supply both --vendor-hook and --qualified-hook")
    if args.vendor_hook:
        verify_qualified_hook(args.vendor_hook, args.qualified_hook)
    else:
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(FsblStagingTests))
        raise SystemExit(not result.wasSuccessful())


if __name__ == "__main__":
    main()
