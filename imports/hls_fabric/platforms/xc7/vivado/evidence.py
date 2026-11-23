#!/usr/bin/env python3
"""Extract bounded timing/CDC evidence and compare independent GTX configuration bits."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from gtx.coverage import enabled_features


def identity(path: Path) -> str:
    """Return a source or artifact content identity."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def timing(text: str) -> dict:
    """Extract design-wide setup, hold and pulse-width slack; reject absent summaries."""
    match = re.search(r"WNS\(ns\).*?TPWS Total Endpoints\s*\n[^\n]+\n\s*([^\n]+)", text)
    if not match:
        raise ValueError("missing timing summary")
    values = match[1].split()
    if len(values) != 12:
        raise ValueError("unexpected timing columns")
    return dict(zip(("wns_ns", "tns_ns", "setup_failing", "setup_endpoints", "whs_ns", "ths_ns",
                     "hold_failing", "hold_endpoints", "wpws_ns", "tpws_ns", "pulse_failing", "pulse_endpoints"),
                    [int(v) if i % 4 in (2, 3) else float(v) for i, v in enumerate(values)]))


def cdc(text: str) -> dict:
    """Separate reviewed reset-synchronizer alerts from other critical crossings."""
    if "CDC Report" not in text or not ("All paths are Safely Timed." in text or
                                        re.search(r"^ID\s+Severity\s+Count", text, re.M)):
        raise ValueError("missing CDC summary")
    counts = {code: int(count) for code, count in
              re.findall(r"^(CDC-\d+)\s+(?:Info|Warning|Critical)\s+(\d+)\s", text, re.M)}
    critical = [line.strip() for line in text.splitlines()
                if re.match(r"\s*\d+\s+CDC-\d+\s+Critical\s", line)]
    reviewed = [line for line in critical if "CDC-10" in line and
                re.search(r"/release_sync_reg\[0\]/CLR$", line) and "False Path" in line]
    return {"counts": counts, "reviewed_reset_alerts": len(reviewed),
            "unreviewed_critical": [line for line in critical if line not in reviewed]}


def primitives(text: str) -> list[dict]:
    """Read explicit primitive modes from a routed simulation netlist."""
    result = []
    for kind, body in re.findall(r"(RAMB36E1|RAMB18E1|DSP48E1)\s*#\((.*?)\)\s+\S+\s*\(", text, re.S):
        names = ("DOA_REG", "DOB_REG", "READ_WIDTH_A", "READ_WIDTH_B", "WRITE_MODE_A", "WRITE_MODE_B")
        if kind == "DSP48E1":
            names = ("AREG", "BREG", "MREG", "PREG", "USE_MULT", "USE_SIMD")
        params = {key: value.strip() for key, value in re.findall(r"\.(\w+)\(([^()]*)\)", body)}
        result.append({"kind": kind, "parameters": {k: params[k] for k in names if k in params}})
    return result


def bitset(path: Path) -> set[tuple[int, int, int]]:
    """Read sparse bitread output, rejecting malformed configuration coordinates."""
    result = set()
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"bit_([0-9a-fA-F]+)_(\d+)_(\d+)", line)
        if not match:
            raise ValueError(f"invalid bitread line: {line}")
        frame, word, bit = int(match[1], 16), int(match[2]), int(match[3])
        if not 0 <= word < 101 or not 0 <= bit < 32:
            raise ValueError(f"out-of-frame bit: {line}")
        result.add((frame, word, bit))
    return result


def locate(base: set, variant: set, relative: tuple[int, int]) -> dict:
    """Infer a frame origin/word offset only from a single independently changed bit."""
    delta = base ^ variant
    if len(delta) != 1:
        raise ValueError(f"expected one changed bit, found {len(delta)}")
    frame, word, bit = next(iter(delta))
    rel_frame, rel_bit = relative
    if bit != rel_bit % 32:
        raise ValueError("reference and donor bit positions disagree")
    offset = word - rel_bit // 32
    if offset < 0 or frame < rel_frame:
        raise ValueError("invalid inferred mapping")
    return {"baseaddr": f"0x{frame-rel_frame:08x}", "word_offset": offset,
            "changed_bit": [f"0x{frame:08x}", word, bit]}


def reference_locations(root: Path) -> dict:
    """Require both independent attribute pairs to agree for each selected tile."""
    result = {}
    for kind, changes in {"channel": {"align": (28, 523), "lock": (30, 56)},
                          "common": {"divider": (30, 1456), "bias": (30, 1520)}}.items():
        base = bitset(root / (kind + "-base/design.bits"))
        observations = {name: locate(base, bitset(root / f"{kind}-{name}/design.bits"), bit)
                        for name, bit in changes.items()}
        mappings = {(v["baseaddr"], v["word_offset"]) for v in observations.values()}
        if len(mappings) != 1:
            raise ValueError(f"independent {kind} mappings disagree")
        result[kind] = {"baseaddr": next(iter(mappings))[0], "word_offset": next(iter(mappings))[1],
                        "observations": observations}
    return result


def encoded_coordinate(token: str, base: int, offset: int) -> tuple[int, int, int]:
    """Translate a donor-relative bit into the independently measured Zynq frame."""
    frame, bit = map(int, token.lstrip("!").split("_"))
    return base + frame, offset + bit // 32, bit % 32


def compare_configuration(fasm: Path, bits: Path, donor: Path, locations: dict) -> dict:
    """Compare both asserted and absent known GTX bits, without installing an overlay.

    Bits outside the donor's known mask are unqualified. Other tiles, routing,
    analog operation and the complete native bitstream are outside this check.
    """
    actual = bitset(bits)
    features = enabled_features(fasm.read_text())
    lock = json.loads((ROOT / "gtx/configuration.lock.json").read_text())
    expected, mask, missing, definitions = set(), set(), [], {}
    enabled_count = 0
    for kind, mapping in (("GTX_CHANNEL_1", locations["channel"]), ("GTX_COMMON", locations["common"])):
        filename = f"segbits_{kind.lower()}.db"
        path = donor / lock[filename]["sha256"]
        if identity(path) != lock[filename]["sha256"]:
            raise ValueError("modified donor")
        base, offset = int(mapping["baseaddr"], 16), mapping["word_offset"]
        used = {kind + "." + f.split(".", 1)[1] for f in features if f.startswith(kind + "_X")}
        for line in path.read_text().splitlines():
            name, *tokens = line.split()
            coords = {encoded_coordinate(t, base, offset) for t in tokens}
            mask.update(coords)
            definitions[name] = [encoded_coordinate(t, base, offset) for t in tokens if not t.startswith("!")]
            if name not in used:
                continue
            enabled_count += 1
            for token in tokens:
                coord = encoded_coordinate(token, base, offset)
                if not token.startswith("!"):
                    expected.add(coord)
                if (coord in actual) == token.startswith("!"):
                    missing.append(name)
    extra = (actual & mask) - expected
    explaining = {name: [list(bit) for bit in coordinates if bit in extra]
                  for name, coordinates in definitions.items() if set(coordinates) & extra}
    return {"enabled_features": enabled_count, "expected_set_bits": len(expected),
            "known_bit_mask": len(mask), "missing_enabled_features": sorted(set(missing)),
            "extra_known_bits": [list(bit) for bit in sorted(extra)], "extra_bit_features": explaining,
            "fasm_sha256": identity(fasm), "bits_sha256": identity(bits),
            "complete_native_bitstream_qualified": False}


def main() -> None:
    """Summarize one retained implementation directory as machine-readable evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    root = args.directory
    report = {"timing": timing((root / "timing.rpt").read_text()),
              "cdc": cdc((root / "cdc.rpt").read_text()),
              "primitives": primitives((root / "routed.v").read_text()),
              "hardware_qualified": False}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
