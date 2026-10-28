"""Checked adaptation of AMD's standalone BSP to Trenz's exact TE0715 profile."""

import csv
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

SKU = "TE0715-05-71C33-A"
PROFILE = "04_30_1c_1gb"
PART = "xc7z030sbg485-1"

# These are the PS interfaces consumed by the FSBL or the register-probe PL.
EXPECTED_PS = {
    "C_PACKAGE_NAME": "sbg485",
    "PCW_DDR_RAM_BASEADDR": "0x00100000",
    "PCW_DDR_RAM_HIGHADDR": "0x3FFFFFFF",
    "PCW_PRESET_BANK0_VOLTAGE": "LVCMOS 3.3V",
    "PCW_PRESET_BANK1_VOLTAGE": "LVCMOS 1.8V",
    "PCW_UART0_PERIPHERAL_ENABLE": "1",
    "PCW_UART0_UART0_IO": "MIO 14 .. 15",
    "PCW_UART1_PERIPHERAL_ENABLE": "0",
    "PCW_I2C0_PERIPHERAL_ENABLE": "0",
    "PCW_I2C1_PERIPHERAL_ENABLE": "1",
    "PCW_I2C1_I2C1_IO": "MIO 48 .. 49",
    "PCW_SD0_PERIPHERAL_ENABLE": "1",
    "PCW_SD0_SD0_IO": "MIO 40 .. 45",
    "PCW_SD0_GRP_CD_ENABLE": "0",
    "PCW_SD0_GRP_WP_ENABLE": "0",
    "PCW_QSPI_GRP_SINGLE_SS_IO": "MIO 1 .. 6",
    "PCW_QSPI_GRP_SS1_ENABLE": "0",
    "PCW_SINGLE_QSPI_DATA_MODE": "x4",
    "C_USE_M_AXI_GP0": "1",
    "C_M_AXI_GP0_ID_WIDTH": "12",
    "C_M_AXI_GP0_ENABLE_STATIC_REMAP": "0",
    "PCW_FPGA_FCLK0_ENABLE": "1",
    "PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ": "100.000000",
}
EXPECTED_FREQ = {
    "APU": 666666687, "DDR": 533333374, "QSPI": 200000000,
    "SDIO": 100000000, "UART": 100000000, "I2C": 111111115,
    "FPGA0": 100000000,
}


def check_profile(board_csv: str, hwh: str, init_header: str) -> dict[str, int]:
    """Reject an incompatible module mapping, PS interface or clock configuration."""
    rows = [[cell.strip() for cell in row] for row in csv.reader(board_csv.splitlines())]
    matches = [row for row in rows if len(row) > 9 and row[1] == SKU]
    if len(matches) != 1 or [matches[0][i] for i in (2, 4, 7, 8, 9)] != [
            PART, PROFILE, "REV05", "1GB", "32MB"]:
        raise ValueError("Trenz module/profile mapping differs")
    modules = [m for m in ET.fromstring(hwh).iter("MODULE")
               if m.get("MODTYPE") == "processing_system7"]
    if len(modules) != 1:
        raise ValueError("expected one PS7 in XSA")
    ps = {p.get("NAME"): p.get("VALUE") for p in modules[0].iter("PARAMETER")}
    for name, value in EXPECTED_PS.items():
        if ps.get(name) != value:
            raise ValueError(f"PS setting {name}: {ps.get(name)!r}, expected {value!r}")
    frequencies = {name: int(value) for name, value in
                   re.findall(r"^#define (\w+)_FREQ\s+(\d+)$", init_header, re.M)}
    if any(frequencies.get(k) != v for k, v in EXPECTED_FREQ.items()):
        raise ValueError("generated PS clock frequencies differ")
    return EXPECTED_FREQ.copy()


def replace_once(text: str, old: str, new: str) -> str:
    """Apply one expected source edit; fail if the pinned input has drifted."""
    if text.count(old) != 1:
        raise ValueError(f"expected exactly one occurrence of {old!r}")
    return text.replace(old, new)


def bsp_parameters(template: str, frequencies: dict[str, int]) -> str:
    """Select UART0/I2C1/SD0 and copy checked PS frequencies into the standalone BSP."""
    text = template.replace("PS7_UART_1", "PS7_UART_0").replace("PS7_I2C_0", "PS7_I2C_1")
    values = {"STDIN_BASEADDRESS": "0xE0000000", "STDOUT_BASEADDRESS": "0xE0000000"}
    groups = [
        (("PS7_UART_0", "XUARTPS_0"), {
            "BASEADDR": "0xE0000000", "HIGHADDR": "0xE0000FFF",
            "UART_CLK_FREQ_HZ": str(frequencies["UART"])}),
        (("PS7_I2C_1", "XIICPS_0"), {
            "BASEADDR": "0xE0005000", "HIGHADDR": "0xE0005FFF",
            "I2C_CLK_FREQ_HZ": str(frequencies["I2C"])}),
        (("PS7_SD_0", "XSDPS_0"), {
            "HAS_CD": "0", "HAS_WP": "0", "MIO_BANK": "1",
            "SDIO_CLK_FREQ_HZ": str(frequencies["SDIO"])}),
    ]
    for prefixes, fields in groups:
        for prefix in prefixes:
            values.update({f"XPAR_{prefix}_{key}": value for key, value in fields.items()})
    for name, value in values.items():
        text, count = re.subn(rf"^#define {name}\s+\S+$", f"#define {name} {value}", text, flags=re.M)
        if count != 1:
            raise ValueError(f"missing or ambiguous BSP macro: {name}")
    return text


def prepare_fsbl(amd: Path, vendor: Path, xsa: Path) -> Path:
    """Stage the vendor FSBL hooks and exact PS initialization in AMD's build tree."""
    frequencies = check_profile(
        (vendor / "board_files/TE0715_board_files.csv").read_text(),
        (xsa / "zsys.hwh").read_text(), (xsa / "ps7_init.h").read_text())
    fsbl = amd / "lib/sw_apps/zynq_fsbl"
    shutil.copytree(vendor / "sw_lib/sw_apps/zynq_fsbl/src", fsbl / "src", dirs_exist_ok=True)
    board = fsbl / "misc/te0715"
    shutil.copytree(fsbl / "misc/zc702", board)
    for name in ("ps7_init.c", "ps7_init.h"):
        shutil.copyfile(xsa / name, board / name)
    parameters = board / "xparameters.h"
    parameters.write_text(bsp_parameters(parameters.read_text(), frequencies))
    drivers = board / "drivers.txt"
    drivers.write_text(drivers.read_text().rstrip() + "\niicps\n")
    hooks = fsbl / "src/te_fsbl_hooks_te0715.c"
    hooks.write_text(replace_once(hooks.read_text(), '#include "te_fsbl_hooks_te0715.h"',
                                 '#include "te_fsbl_hooks_te0715.h"\n#include "te_iic_platform.h"'))
    return fsbl / "src"
