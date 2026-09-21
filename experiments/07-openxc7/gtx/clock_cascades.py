#!/usr/bin/env python3
"""Restore missing Zynq clock cascades only from agreeing, pinned database tables."""

import json
from pathlib import Path

from gtx.coverage import connectivity
from prepare_zynq7030 import checked

# These files are already in the experiment's pinned openXC7 installation.
PINS = {
    "zynq7/segbits_clk_hrow_bot_r.db": "dc4fc20f5ffdddefde25b7490dfc03d4b19785de3b8d2dc3ab7a02107eb5ab26",
    "zynq7/segbits_clk_hrow_top_r.db": "4c9c9effdaa6039eaa0df3c44056be0ceeaa1a34eab9134821f9f3e85f46738c",
    "artix7/segbits_clk_hrow_bot_r.db": "5b22e19775dfa493f75bb3edbfccc06709a50b829e89857dc20aee1cbc8f6794",
    "zynq7/tile_type_CLK_HROW_BOT_R.json": "18ca6b73966bd313a063ba52d0780a77c247b5aca6e0f8b2475422b1f40a4d3d",
    "artix7/tile_type_CLK_HROW_BOT_R.json": "441944cdae73c1d861ddee278f751a6ca372a75efb81802abd26b8db8087c445"}


def extend(local: bytes, donor: bytes, upper: bytes) -> tuple[bytes, dict]:
    """Require all shared entries and all 32 added cascades to agree across tables.

    This is structural/database corroboration, not a new vendor bit-location
    measurement. No tile address, timing value or existing encoding is replaced.
    """
    def table(data: bytes) -> dict[str, set[str]]:
        """Read unique encoded features; reject duplicate or empty definitions."""
        result = {}
        for line in data.decode().splitlines():
            name, *bits = line.split()
            if not bits or name in result:
                raise ValueError("ambiguous clock database definition")
            result[name] = set(bits)
        return result
    known, other, top = map(table, (local, donor, upper))
    prefix = "CLK_HROW_BOT_R"
    additions = {f"{prefix}.{prefix}_CK_BUFG_CASCO{i}.{prefix}_CK_BUFG_CASCIN{i}" for i in range(32)}
    if other.keys() - known.keys() != additions or known.keys() - other.keys():
        raise ValueError("clock donor differs beyond missing cascades")
    if any(other[k] != v for k, v in known.items()):
        raise ValueError("clock donor contradicts existing Zynq encoding")
    for name in additions:
        if top.get(name.replace("CLK_HROW_BOT_R", "CLK_HROW_TOP_R")) != other[name]:
            raise ValueError("upper/lower clock cascade encodings disagree")
    extra = "\n".join(name + " " + " ".join(sorted(other[name])) for name in sorted(additions))
    return local.rstrip() + b"\n" + extra.encode() + b"\n", {
        "matching_existing_encodings": len(known), "added_cascades": 32,
        "all_additions_match_zynq_top_half": True, "independent_vendor_location_measurement": False}


def prepare(database: Path) -> tuple[bytes, dict]:
    """Check the installed Artix/Zynq sources and identical bottom-half tile graphs."""
    root = (database / "segbits_clk_hrow_bot_r.db").resolve(strict=True).parent.parent
    files = {name: checked((root / name).read_bytes(), sha, name) for name, sha in PINS.items()}
    zynq, artix = (json.loads(files[family + "/tile_type_CLK_HROW_BOT_R.json"]) for family in ("zynq7", "artix7"))
    if (zynq["sites"] != artix["sites"] or zynq["wires"].keys() != artix["wires"].keys()
            or connectivity(zynq["pips"]) != connectivity(artix["pips"])):
        raise ValueError("clock donor tile connectivity differs")
    result, evidence = extend(files["zynq7/segbits_clk_hrow_bot_r.db"], files["artix7/segbits_clk_hrow_bot_r.db"],
                              files["zynq7/segbits_clk_hrow_top_r.db"])
    return result, {**evidence, "sources_sha256": PINS, "tile_connectivity_matches": True}
