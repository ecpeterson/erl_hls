#!/usr/bin/env python3
"""Audit routed GTX features against a pinned donor without installing its bits."""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from gtx.prepare import digest, fetch


def enabled_features(text: str) -> set[str]:
    """Expand nextpnr's scalar/binary FASM subset into enabled single-bit features.

    Unsupported syntax fails rather than silently understating missing coverage.
    Zero-valued fields set no features; repeated routing declarations coalesce.
    """
    result = set()
    pattern = r"([\w.]+)(?:\[(\d+)(?::(\d+))?\])?(?:\s*=\s*(\d+)'b([01]+))?"
    for raw in text.splitlines():
        line = raw.partition("#")[0].strip()
        if not line:
            continue
        match = re.fullmatch(pattern, line)
        if not match:
            raise ValueError(f"unsupported FASM declaration: {line}")
        name, high, low, width, value = match.groups()
        if value is None:
            if low is not None:
                raise ValueError(f"range without value: {line}")
            result.add(name if high is None else f"{name}[{int(high)}]")
            continue
        first = int(low or high or 0)
        last = int(high or 0)
        if last < first or int(width) > last - first + 1 or len(value) > int(width):
            raise ValueError(f"inconsistent FASM width: {line}")
        for bit, enabled in enumerate(reversed(value), first):
            if enabled == "1":
                result.add(name if high is None else f"{name}[{bit}]")
    return result


def definitions(text: str, pseudo: bool = False) -> set[str]:
    """Read defined features; only unconditional pseudo-PIPs need no encoding."""
    result = set()
    for raw in text.splitlines():
        words = raw.partition("#")[0].split()
        if not words:
            continue
        if len(words) < 2:
            raise ValueError(f"incomplete database definition: {raw}")
        if not pseudo or words[1:] == ["always"]:
            result.add(words[0])
    return result


def compare(grid: dict, fasm: str, donor: dict[str, bytes]) -> dict:
    """Report encoding coverage separately from device-specific frame locations."""
    selected: dict[str, set[str]] = {}
    used_tiles = set()
    for feature in enabled_features(fasm):
        tile, suffix = feature.split(".", 1)
        kind = grid[tile]["type"]
        if "GTX" in kind:
            used_tiles.add(tile)
            selected.setdefault(kind, set()).add(kind + "." + suffix)
    if not selected:
        raise ValueError("no enabled GTX features")
    coverage = {}
    address_tiles = set()
    for kind, used in sorted(selected.items()):
        encoded = definitions(donor.get(f"segbits_{kind.lower()}.db", b"").decode())
        fixed = definitions(donor.get(f"ppips_{kind.lower()}.db", b"").decode(), pseudo=True)
        coverage[kind] = {"enabled": len(used), "encoded": len(used & encoded),
                          "fixed_connections": len(used & fixed), "missing": sorted(used - encoded - fixed)}
        if used - fixed:
            address_tiles.update(tile for tile in used_tiles if grid[tile]["type"] == kind)
    return {"coverage": coverage,
            "missing_frame_mapping": sorted(tile for tile in address_tiles if not grid[tile].get("bits")),
            "donor_covers_enabled_features": all(not entry["missing"] for entry in coverage.values()),
            "encodings_validated_on_zynq": False, "hardware_qualified": False}


def audit(database: Path, fasm: Path, output: Path) -> dict:
    """Check logical tile compatibility and retain a reproducible, read-only audit."""
    lock = json.loads(Path(__file__).with_name("configuration.lock.json").read_text())
    donor = {name: fetch(source, output / "sources") for name, source in lock.items()}
    compatibility = {}
    for name, data in donor.items():
        if not name.startswith("tile_type_"):
            continue
        local = json.loads((database / name).read_text())
        other = json.loads(data)
        # Wire RC estimates differ by family. Only graph identity is compared;
        # neither timing values nor physical addresses are copied into Zynq.
        same = (connectivity(local["pips"]) == connectivity(other["pips"]) and local["sites"] == other["sites"]
                and local["wires"].keys() == other["wires"].keys())
        compatibility[local["tile_type"]] = same
        if not same:
            raise ValueError(f"donor connectivity differs: {name}")
    grid_path = database / "xc7z030/tilegrid.json"
    report = compare(json.loads(grid_path.read_text()), fasm.read_text(), donor)
    report.update({"sources": lock, "tile_connectivity_matches": compatibility,
                   "fasm_sha256": digest(fasm.read_bytes()), "tilegrid_sha256": digest(grid_path.read_bytes())})
    output.mkdir(parents=True, exist_ok=True)
    (output / "coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def connectivity(pips: dict) -> dict:
    """Retain PIP endpoints/directionality while excluding family timing estimates."""
    return {name: {key: value for key, value in pip.items() if key not in ("src_to_dst", "dst_to_src")}
            for name, pip in pips.items()}


def main() -> None:
    """Choose a Z7030 database, routed FASM and independent audit directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("fasm", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(audit(args.database, args.fasm, args.output), indent=2))


if __name__ == "__main__":
    main()
