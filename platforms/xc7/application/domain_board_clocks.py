"""Bind the independent-domain board's five clocks to actual flattened names.

Callers project one already-loaded top module and retain its input hash. Native
pack-only reports establish applied targets; only routed reports assess achieved
timing. These checks do not model BRAM timing, generated-clock relationships or
CDC settling, and never introduce false paths or multicycle exceptions.
"""

import math
import re
from typing import Any


CLOCKS = {
    "application.clk": 25.0,
    "clocks.tx_clock": 125.0,
    "clocks.tx_half_clock": 62.5,
    "clocks.rx_clock": 125.0,
    "clocks.rx_half_clock": 62.5,
}
MMCMS = {
    "clocks.tx.generator": "MMCME2_ADV_X1Y2/MMCME2_ADV",
    "clocks.rx.generator": "MMCME2_ADV_X1Y3/MMCME2_ADV",
}
PINS = {"ref_p": "U5", "ref_n": "V5", "gt_rx_p": "W8", "gt_rx_n": "Y8",
        "gt_tx_p": "W4", "gt_tx_n": "Y4"}
LEGACY = {"application.clk": "clock", **{name: name.removeprefix("clocks.")
                                          for name in CLOCKS if name != "application.clk"}}


def project(module: dict[str, Any]) -> dict[str, Any]:
    """Select clock bits and MMCM placement attributes without copying routing strings."""
    return {
        "clock_nets": {name: {"bits": module["netnames"][name]["bits"]}
                       for name in CLOCKS if name in module.get("netnames", {})},
        "mmcms": {name: {"type": module["cells"][name]["type"],
                         "attributes": {key: value for key, value in
                                        module["cells"][name].get("attributes", {}).items()
                                        if key in ("BEL", "NEXTPNR_BEL")}}
                  for name in MMCMS if name in module.get("cells", {})},
    }


def validate_names(projected: dict[str, Any], stage: str) -> None:
    """Reject missing/aliased clocks and absent or misplaced MMCMs for this board shell."""
    clocks = projected.get("clock_nets", {})
    if set(clocks) != set(CLOCKS):
        raise ValueError("expected exactly five named board clock nets")
    bits = []
    for name, row in clocks.items():
        value = row.get("bits", [])
        if len(value) != 1 or type(value[0]) is not int or value[0] < 0:
            raise ValueError("clock is not a scalar signal: " + name)
        bits.append(value[0])
    if len(set(bits)) != len(CLOCKS):
        raise ValueError("independent board clock outputs share a net")
    cells = projected.get("mmcms", {})
    if set(cells) != set(MMCMS):
        raise ValueError("expected the two named board MMCMs")
    if stage not in ("mapped", "packed", "routed"):
        raise ValueError("unknown clock evidence stage: " + stage)
    for name, expected in MMCMS.items():
        cell = cells[name]
        kind = "MMCME2_BASE" if stage == "mapped" else "MMCME2_ADV_MMCME2_ADV"
        if cell.get("type") != kind:
            raise ValueError("unexpected clock generator type: " + name)
        attributes = cell.get("attributes", {})
        key = {"packed": "BEL", "routed": "NEXTPNR_BEL"}.get(stage)
        if key is not None and attributes.get(key) != expected:
            raise ValueError("MMCM placement constraint missing or changed: " + name)
        if any(attributes[key] != expected for key in ("BEL", "NEXTPNR_BEL") if key in attributes):
            raise ValueError("conflicting MMCM placement evidence: " + name)


def render(mapped: dict[str, Any], original_xdc: str) -> str:
    """Replace only the five legacy clock selectors after verifying the mapped names.

The original six package pins, two MMCM sites and reference-clock target must
match the established Ethernet constraint file exactly. Additional commands,
duplicates or changed frequencies are rejected instead of silently inherited.
"""
    validate_names(mapped, "mapped")
    replacements = {
        f"create_clock -period {1000 / frequency:.3f} [get_nets {LEGACY[name]}]":
        f"create_clock -period {1000 / frequency:.3f} [get_nets {name}]"
        for name, frequency in CLOCKS.items()
    }
    expected = {
        *(f"set_property PACKAGE_PIN {pin} [get_ports {name}]" for name, pin in PINS.items()),
        *(f"set_property BEL {bel} [get_cells {name}]" for name, bel in MMCMS.items()),
        "create_clock -period 8.000 [get_ports ref_p]",
        *replacements,
    }
    commands = [line.split("#", 1)[0].strip().removesuffix(";") for line in original_xdc.splitlines()]
    commands = [line for line in commands if line]
    if len(commands) != len(expected) or set(commands) != expected:
        raise ValueError("original board constraints differ from the fixed pin/clock contract")
    lines = []
    for line in original_xdc.splitlines():
        command = line.split("#", 1)[0].strip().removesuffix(";")
        lines.append(replacements.get(command, line))
    return "\n".join(lines) + "\n"


def validate_log(log: str) -> None:
    """Reject dropped constraints and fatal parsing errors, not the known get_cells warning.

This backend warns about get_cells but still assigns the exact cell's BEL.
The callers separately require that assignment in actual packed/routed cells.
"""
    for line in log.splitlines():
        if re.search(r"\b(?:ERROR|FATAL):", line):
            raise ValueError("native clock evidence contains an error: " + line)
        lower = line.lower()
        if ("create_clock" in lower and ("warning:" in lower or "matched nothing" in lower)
                or "ignoring clock constraint" in lower
                or "ignoring virtual clock" in lower
                or "this target is ignored" in lower):
            raise ValueError("native clock constraint was not applied: " + line)


def validate_report(report: dict[str, Any], *, routed: bool) -> dict[str, Any]:
    """Require exact applied targets; report an actual routed miss separately from coverage."""
    rows = report.get("fmax", {})
    if set(rows) != set(CLOCKS):
        raise ValueError("native timing report does not cover exactly the five board clocks")
    achieved = {}
    for name, expected in CLOCKS.items():
        value = rows[name].get("constraint")
        if type(value) not in (int, float) or not math.isfinite(value) or value != expected:
            raise ValueError("native clock target missing or wrong: " + name)
        if routed:
            value = rows[name].get("achieved")
            if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
                raise ValueError("routed clock frequency missing or invalid: " + name)
            achieved[name] = value
    return {"clock_coverage_complete": True, "applied_targets_mhz": dict(CLOCKS),
            "modeled_targets_met": all(achieved[name] >= target for name, target in CLOCKS.items())
            if routed else None,
            "timing_qualified": False}


def validate_pack(packed: dict[str, Any], log: str, report: dict[str, Any]) -> dict[str, Any]:
    """Require real pack-only clock bindings and MMCM sites; ignore unplaced achieved timing."""
    validate_names(packed, "packed")
    validate_log(log)
    return validate_report(report, routed=False) | {"mmcm_sites": dict(MMCMS), "stage": "packed"}


def validate_routed(routed: dict[str, Any], log: str, report: dict[str, Any]) -> dict[str, Any]:
    """Require routed coverage and actual MMCM sites, keeping timing failure distinct."""
    validate_names(routed, "routed")
    validate_log(log)
    return validate_report(report, routed=True) | {"mmcm_sites": dict(MMCMS), "stage": "routed"}
