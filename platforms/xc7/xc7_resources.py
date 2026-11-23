#!/usr/bin/env python3
"""Inventory a flattened XC7 image without confusing mapped functions with fit.

Mapped RAM/SRL footprints are conservative LUT-site demand, before packing.
Optional nextpnr placement counts deduplicate O5/O6 occupants of the same LUT.
Neither inventory supplies timing, routing legality, or board qualification.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
from typing import Any

# XC7 distributed-memory primitive footprints (AMD UG953), in SLICEM LUTs.
RAM_LUTS = {
    "RAM32M": 4, "RAM64M": 4,
    "RAM32X1S": 1, "RAM32X1S_1": 1, "RAM32X2S": 1,
    "RAM64X1S": 1, "RAM64X1S_1": 1,
    "RAM128X1S": 2, "RAM256X1S": 4,
    "RAM32X1D": 2, "RAM64X1D": 2, "RAM128X1D": 4,
}
SRLS = {"SRL16E", "SRL16E_1", "SRLC16E", "SRLC16E_1", "SRLC32E"}
FFS = {name + suffix for name in ("FD", "FDE", "FDR", "FDS", "FDRE", "FDSE",
                                "FDCE", "FDPE", "FDCP", "FDCPE")
       for suffix in ("", "_1")}
LATCHES = {"LDCE", "LDPE", "LDCE_1", "LDPE_1"}
HARD = {
    "PS7", "GTXE2_CHANNEL", "GTXE2_COMMON", "IBUFDS_GTE2",
    "MMCME2_BASE", "MMCME2_ADV", "PLLE2_BASE", "PLLE2_ADV",
    "BUFG", "BUFGCTRL", "BUFGCE", "BUFH", "BUFHCE", "BUFIO", "BUFR", "BUFMR", "BUFMRCE",
    "IBUF", "OBUF", "OBUFT", "IOBUF", "IBUFDS", "OBUFDS", "OBUFTDS", "IOBUFDS",
    "IDELAYE2", "ODELAYE2", "IDELAYCTRL", "ISERDESE2", "OSERDESE2", "IDDR", "ODDR",
    "BSCANE2", "STARTUPE2", "DNA_PORT", "XADC", "DCIRESET", "ICAPE2", "FRAME_ECCE2",
}
RESOURCE_KEYS = (
    "lut_primitive_cells", "lut_output_functions", "logic_lut_site_upper_bound",
    "inverter_lut_site_upper_bound",
    "distributed_ram_lut_sites", "srl_lut_site_upper_bound", "lut_site_upper_bound",
    "slicem_lut_site_upper_bound", "ff", "bram18", "bram36", "bram18_equivalents",
    "dsp", "latches", "carry4", "muxf7", "muxf8",
)


def digest(path: Path) -> str:
    """Hash one supplied source or report without interpreting its provenance."""
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def module(netlist: dict[str, Any], top: str) -> dict[str, Any]:
    """Require the explicit top; never sum library definitions as instances."""
    modules = netlist["modules"]
    names = [name for name in (top, "\\" + top) if name in modules]
    if len(names) != 1:
        raise ValueError(f"expected one top module {top!r}, found {names}")
    return modules[names[0]]


def counts(primitives: dict[str, int]) -> dict[str, Any]:
    """Count recognized XC7 primitives; retain unknown types as incomplete evidence."""
    resources = dict.fromkeys(RESOURCE_KEYS, 0)
    hard, other, logical, unknown = {}, {}, {}, {}
    for kind, amount in sorted(primitives.items()):
        if type(amount) is not int or amount < 0:
            raise ValueError(f"invalid primitive population: {kind}={amount!r}")
        if not amount:
            continue
        if re.fullmatch(r"LUT[1-6](?:_2)?", kind) and ("_" not in kind or kind == "LUT6_2"):
            resources["lut_primitive_cells"] += amount
            resources["lut_output_functions"] += amount * (2 if kind == "LUT6_2" else 1)
            resources["logic_lut_site_upper_bound"] += amount
        elif kind == "INV":
            # Packing can absorb an inversion into a pin or neighbouring LUT.
            # Before packing, conservatively reserve one LUT for every inverter.
            resources["inverter_lut_site_upper_bound"] += amount
            resources["logic_lut_site_upper_bound"] += amount
        elif kind in {"$buf", "$scopeinfo"}:
            # Yosys connection aliases and flattened-source metadata are not gates.
            logical[kind] = amount
        elif kind in RAM_LUTS:
            resources["distributed_ram_lut_sites"] += RAM_LUTS[kind] * amount
        elif kind in SRLS:
            resources["srl_lut_site_upper_bound"] += amount
        elif kind in FFS:
            resources["ff"] += amount
        elif kind in LATCHES:
            resources["latches"] += amount
        elif kind in {"RAMB18E1", "RAMB36E1"}:
            resources["bram18" if kind == "RAMB18E1" else "bram36"] += amount
        elif kind == "DSP48E1":
            resources["dsp"] += amount
        elif kind in {"CARRY4", "MUXF7", "MUXF8"}:
            resources[kind.lower()] += amount
        elif kind in HARD:
            hard[kind] = amount
        elif kind in {"VCC", "GND"}:
            other[kind] = amount
        else:
            unknown[kind] = amount
    resources["slicem_lut_site_upper_bound"] = (
        resources["distributed_ram_lut_sites"] + resources["srl_lut_site_upper_bound"])
    resources["lut_site_upper_bound"] = (
        resources["logic_lut_site_upper_bound"] + resources["slicem_lut_site_upper_bound"])
    resources["bram18_equivalents"] = resources["bram18"] + 2 * resources["bram36"]
    return {"complete": not unknown, "resources": resources,
            "primitive_counts": dict(sorted(primitives.items())),
            "hard_primitives": hard, "constant_primitives": other,
            "logical_annotations": logical, "unknown_primitives": unknown}


def mapped(netlist: dict[str, Any], top: str,
           groups: dict[str, str] | None = None) -> dict[str, Any]:
    """Partition one flattened image by longest instance-name prefix, without duplication."""
    prefixes = groups or {}
    if "unattributed" in prefixes or any(not prefix for prefix in prefixes.values()):
        raise ValueError("group names must exclude unattributed; prefixes must be nonempty")
    if len(set(prefixes.values())) != len(prefixes):
        raise ValueError("duplicate ownership prefixes")
    totals: Counter[str] = Counter()
    grouped = {name: Counter() for name in [*prefixes, "unattributed"]}
    for name, cell in module(netlist, top)["cells"].items():
        kind = cell["type"]
        if not isinstance(kind, str):
            raise ValueError(f"invalid primitive type at {name}")
        if kind == "$scopeinfo" and cell.get("connections"):
            raise ValueError(f"scope metadata has signal connections at {name}")
        if kind == "$buf":
            ports = cell.get("connections", {})
            if set(ports) != {"A", "Y"} or not ports["A"] or len(ports["A"]) != len(ports["Y"]):
                raise ValueError(f"invalid wire buffer at {name}")
        matches = [(len(prefix), owner) for owner, prefix in prefixes.items()
                   if name.startswith(prefix)]
        owner = max(matches)[1] if matches else "unattributed"
        totals[kind] += 1
        grouped[owner][kind] += 1
    result = counts(totals)
    result["groups"] = {name: counts(population) for name, population in grouped.items()}
    result["group_prefixes"] = prefixes
    result["attribution"] = "Instance-name association; shared/merged logic may remain unattributed."
    return result


def placed_luts(netlist: dict[str, Any], top: str) -> dict[str, Any]:
    """Count unique placed LUT sites; pack-only or missing BELs cannot establish occupancy.

    This inspects nextpnr SLICE_LUTX cells, not a vendor placement format. It
    checks duplicate BELs but leaves LUT compatibility and routing to their
    dedicated validators. RAM/SRL origins identify memory-demanding sites.
    """
    cells = module(netlist, top)["cells"]
    luts = {name: cell for name, cell in cells.items() if cell["type"] == "SLICE_LUTX"}
    if not luts:
        raise ValueError("placement contains no nextpnr SLICE_LUTX cells")
    sites, memory, bels, missing = set(), set(), set(), []
    for name, cell in luts.items():
        attrs = cell.get("attributes", {})
        bel = attrs.get("NEXTPNR_BEL")
        if not bel:
            missing.append(name)
            continue
        match = re.fullmatch(r"(SLICE_X[0-9]+Y[0-9]+)/([ABCD])[56]LUT", bel)
        if match is None:
            raise ValueError(f"unrecognized placed LUT BEL: {name}={bel}")
        if bel in bels:
            raise ValueError(f"multiply occupied LUT BEL: {bel}")
        bels.add(bel)
        site = match.group(1) + "/" + match.group(2)
        sites.add(site)
        if attrs.get("X_ORIG_TYPE", "").startswith(("RAM", "SRL")):
            memory.add(site)
    return {"complete": not missing, "packed_lut_cells": len(luts),
            "physical_lut_sites": len(sites) if not missing else None,
            "observed_placed_lut_sites": len(sites),
            "memory_lut_sites": len(memory) if not missing else None,
            "unplaced_cells": sorted(missing),
            "placement_legality_verified": False}


def bounds(resources: dict[str, int], limits: dict[str, int]) -> dict[str, Any]:
    """Apply caller-provided ceilings to mapped demand; passing is only an area screen."""
    unknown = limits.keys() - resources.keys()
    if unknown:
        raise ValueError(f"unknown resource limits: {sorted(unknown)}")
    if any(type(value) is not int or value < 0 for value in limits.values()):
        raise ValueError("resource limits must be nonnegative integers")
    checks = {name: {"used": resources[name], "limit": limit,
                     "passes": resources[name] <= limit}
              for name, limit in limits.items()}
    return {"passes": all(check["passes"] for check in checks.values()), "checks": checks,
            "physical_fit_established": False}


def report(netlist: dict[str, Any], top: str, groups: dict[str, str] | None = None,
           limits: dict[str, int] | None = None,
           placement: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build a complete/incomplete resource report from one explicit image top."""
    inventory = mapped(netlist, top, groups)
    return {"schema": "hls_xc7_resources_v1", "top": top, "mapped": inventory,
            "placed_luts": placed_luts(placement, top) if placement is not None else None,
            "bounds": bounds(inventory["resources"], limits) if limits is not None else None,
            "timing_qualified": False, "hardware_qualified": False,
            "scope": "Supplied top only; caller must identify full board image versus component."}


def main() -> None:
    """Read JSON artifacts, preserve a report, and fail on unknown cells or exceeded limits."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlist", type=Path)
    parser.add_argument("--top", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--groups", type=Path, help="JSON owner -> instance prefix map")
    parser.add_argument("--bounds", type=Path, help="JSON resource -> maximum count map")
    parser.add_argument("--placed", type=Path, help="Optional nextpnr placed JSON for this top")
    args = parser.parse_args()
    paths = {name: path for name, path in (("netlist", args.netlist), ("groups", args.groups),
              ("bounds", args.bounds), ("placement", args.placed)) if path is not None}
    contents = {name: json.loads(path.read_text()) for name, path in paths.items()}
    result = report(contents["netlist"], args.top, contents.get("groups"),
                    contents.get("bounds"), contents.get("placement"))
    result["inputs"] = {name: {"path": str(path.resolve()), "sha256": digest(path)}
                        for name, path in paths.items()}
    with args.output.open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    if not result["mapped"]["complete"] or result["bounds"] and not result["bounds"]["passes"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
