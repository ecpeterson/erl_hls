"""Pin and inspect the exact Trenz 2023.2 Si5338 clock register profile."""
import hashlib
import re
from pathlib import Path

VENDOR_SHA256 = "91a2a1cc55a8524cdf2f5760303ec468e3a1639184aa6c031e421afab8907ab2"


def vendor_rows(source: bytes) -> list[tuple[int, int, int]]:
    """Convert the pinned paged table to absolute addresses, omitting zero write masks."""
    if hashlib.sha256(source).hexdigest() != VENDOR_SHA256:
        raise ValueError("Trenz clock profile changed")
    rows = re.findall(r"\{\s*(\d+),\s*(0x[\da-fA-F]+|\d+),\s*(0x[\da-fA-F]+|\d+)\}", source.decode())
    if len(rows) != 350:
        raise ValueError("unexpected register count")
    page, result = 0, []
    for a, v, m in rows:
        address, value, mask = int(a), int(v, 0), int(m, 0)
        if address == 255:
            page = value
        elif mask:
            result.append((page * 256 + address, value, mask))
    if page != 0 or len(result) != 236:
        raise ValueError("unexpected register pages")
    return result


def render(rows: list[tuple[int, int, int]]) -> str:
    """Emit the compact, unchanged value/mask table shared by FSBL and Linux tests."""
    lines = ["// Generated from Trenz 2023.2 te_Si5338-Registers.h; see profile.py and docs/clock-startup.md.",
             "// Absolute address, value, write mask; zero-mask rows and page-switch commands are omitted.",
             "static const struct si_register si_profile[] = {"]
    for start in range(0, len(rows), 4):
        lines.append("    " + " ".join(f"{{{a:3}, 0x{v:02x}, 0x{m:02x}}}," for a, v, m in rows[start:start+4]))
    return "\n".join([*lines, "};", ""])


def read_rows(path: Path) -> list[tuple[int, int, int]]:
    """Read our generated literal table without compiling it."""
    return [(int(a), int(v, 16), int(m, 16)) for a, v, m in
            re.findall(r"\{\s*(\d+), 0x([\da-f]+), 0x([\da-f]+)\}", path.read_text())]


def audit(rows: list[tuple[int, int, int]]) -> dict:
    """Decode the fixed integer dividers and require the board's input/output electrical settings."""
    values = {a: v for a, v, _ in rows}
    # Si5338-RM §§3, 9: IN3/25 MHz, internal feedback, /1 R dividers;
    # unused drivers down, CLK2 LVDS18, CLK3 CMOS18. Reg27 preserves address 0x70.
    expected = {27: 0x70, 28: 0x0b, 29: 0x08, 30: 0xb0, 31: 0xe3, 32: 0xe3,
                33: 0xc0, 34: 0xc0, 35: 0xa0, 38: 0x06, 39: 0x01, 230: 3}
    if any(values.get(a) != v for a, v in expected.items()):
        raise ValueError("clock input, driver voltage/format or output enable differs")
    ratios = []
    for base in (97, 75, 86):
        p1 = values[base] | values[base+1] << 8 | (values[base+2] & 3) << 16
        p2 = values[base+2] >> 2 | values[base+3] << 6 | values[base+4] << 14 | values[base+5] << 22
        p3 = values[base+6] | values[base+7] << 8 | values[base+8] << 16 | (values[base+9] & 0x3f) << 24
        if p2 or p3 != 1 or (p1 + 512) % 128:
            raise ValueError("expected integer MultiSynth profile")
        ratios.append((p1 + 512) // 128)
    if ratios != [100, 20, 50]:
        raise ValueError("PLL/output dividers differ")
    return {"input_hz": 25000000, "vco_hz": 2500000000, "clk2_hz": 125000000, "clk3_hz": 50000000,
            "clk2_format": "LVDS18", "clk3_format": "CMOS18", "unused_outputs_disabled": [0, 1]}
