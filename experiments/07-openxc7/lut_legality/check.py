"""Check XC7 LUT placement and emitted truth tables independently of nextpnr."""

import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


def module(path: Path) -> dict[str, Any]:
    """Read the sole top module in a packed or routed nextpnr JSON export."""
    modules = json.loads(path.read_text())["modules"]
    if len(modules) != 1:
        raise ValueError("expected one flattened module")
    return next(iter(modules.values()))


def nets(design: dict[str, Any]) -> dict[int | str, str]:
    """Name net bits independently of JSON numbering, including constant drivers."""
    names: dict[int | str, str] = {"0": "0", "1": "1"}
    for name, net in sorted(design["netnames"].items()):
        for index, bit in enumerate(net["bits"]):
            names.setdefault(bit, f"{name}[{index}]")
    for cell in design["cells"].values():
        if cell["type"] in ("PSEUDO_GND", "PSEUDO_VCC"):
            value = "1" if cell["type"] == "PSEUDO_VCC" else "0"
            for port, direction in cell["port_directions"].items():
                if direction == "output":
                    for bit in cell["connections"][port]:
                        names[bit] = value
    return names


def logical_ports(cell: dict[str, Any], names: dict[int | str, str]) -> dict[str, str | None]:
    """Recover original LUT port connectivity after physical input permutation."""
    result = {}
    for pin, bits in cell["connections"].items():
        original = cell["attributes"].get("X_ORIG_PORT_" + pin, "")
        if original:
            if len(bits) > 1:
                raise ValueError("expected a scalar LUT port")
            for port in original.split():
                result[port] = names[bits[0]] if bits else None
    return result


def check(packed: Path, routed: Path, fasm: Path, tilegrid: Path,
          *, require_origins: bool = True) -> dict[str, Any]:
    """Reject lost LUTs, incompatible sites, rewired functions or wrong FASM INIT.

    Truth tables cover combinational LUT1..LUT6 cells, including split LUT6_2
    halves and carry helpers. RAM/SRL cells receive placement/connectivity
    checks; this is not a sequential memory or route-connectivity proof.
    Disabling origin checks isolates physical truth-table failures from bad
    router metadata; truth expectations always use the packed net connections.
    """
    before, after = module(packed), module(routed)
    before_nets, after_nets = nets(before), nets(after)
    originals = {n: c for n, c in before["cells"].items() if c["type"] == "SLICE_LUTX"}
    luts = {n: c for n, c in after["cells"].items() if c["type"] == "SLICE_LUTX"}
    if originals.keys() != luts.keys():
        raise ValueError("LUT population changed after packing")
    sites = {site: (tile, kind) for tile, info in json.loads(tilegrid.read_text()).items()
             for site, kind in info.get("sites", {}).items()}
    init = {name: int(bits, 2) for name, bits in re.findall(
        r"(?m)^(\S+\.INIT)\[63:0\] = 64'b([01]{64})$", fasm.read_text())}
    placement: Counter[str] = Counter()
    checked_rows = 0
    elided_constants = 0
    elided_logic_constants = 0
    occupants: dict[str, dict[str, Any]] = {}
    for name, cell in luts.items():
        orig = originals[name]
        kind = cell["attributes"].get("X_ORIG_TYPE", "")
        if cell["parameters"] != orig["parameters"] or kind != orig["attributes"].get("X_ORIG_TYPE", ""):
            raise ValueError(f"{name}: LUT function changed")
        original_ports = logical_ports(orig, before_nets)
        final_ports = logical_ports(cell, after_nets)
        # The pinned router can erase a memory's constant-pin origin when
        # permuting another LUT in its tile. Require the same physical pin
        # still tied to the same constant before recovering that metadata.
        if kind.startswith(("RAM", "SRL")):
            for pin, bits in orig["connections"].items():
                label = orig["attributes"].get("X_ORIG_PORT_" + pin, "")
                value = before_nets[bits[0]] if bits else None
                final_bits = cell["connections"].get(pin, [])
                if (label and label not in final_ports and value in ("0", "1")
                        and final_bits and after_nets[final_bits[0]] == value
                        and not cell["attributes"].get("X_ORIG_PORT_" + pin)):
                    final_ports[label] = value
                    elided_constants += 1
        elif re.fullmatch(r"LUT[1-6]", kind):
            # A constant input's annotation can also disappear after sharing
            # and permuting LUT pins. Require a retained physical constant;
            # the independent FASM check below still proves the whole function.
            physical_constants = {after_nets[bits[0]] for pin, bits in cell["connections"].items()
                                  if bits and re.fullmatch(r"A[1-6]", pin)} & {"0", "1"}
            for label, value in original_ports.items():
                if (label not in final_ports and re.fullmatch(r"I[0-5]", label)
                        and value in physical_constants):
                    final_ports[label] = value
                    elided_logic_constants += 1
        if require_origins and final_ports != original_ports:
            raise ValueError(f"{name}: logical port connectivity changed")
        site, bel = cell["attributes"]["NEXTPNR_BEL"].split("/")
        location = site + "/" + bel
        if location in occupants:
            raise ValueError(f"{name}: multiply occupied LUT site")
        occupants[location] = cell
        if orig["attributes"].get("BEL", location) != location:
            raise ValueError(f"{name}: fixed placement moved")
        tile, site_kind = sites[site]
        placement[bel[1:]] += 1
        if bel.endswith("5LUT"):
            if cell["connections"].get("O6") or cell["attributes"].get("X_ORIG_PORT_A6"):
                raise ValueError(f"{name}: sixth logical input or O6 on a five-input site")
            # Post-route pin permutation copies shared physical inputs to both
            # halves. A6=VCC selects O6's upper half; O5 never reads that pin.
            a6 = cell["connections"].get("A6", [])
            if a6 and after_nets[a6[0]] != "1":
                raise ValueError(f"{name}: nonconstant shared A6 on a five-input site")
        if kind.startswith(("RAM", "SRL")) and site_kind != "SLICEM":
            raise ValueError(f"{name}: memory in a non-memory slice")
        if not re.fullmatch(r"LUT[1-6]", kind):
            continue
        half = int(re.fullmatch(r"SLICE_X(\d+)Y\d+", site)[1]) % 2
        prefix = f"{tile}.{site_kind}_X{half}.{bel[0]}LUT.INIT"
        programmed = init.get(prefix, 0)
        expected = int(cell["parameters"]["INIT"], 2)
        cell_rows = 0
        # Enumerate physical pin values; discard unreachable assignments to
        # constants or repeated nets. O5 addresses the lower 32 INIT entries.
        for address in range(32 if bel.endswith("5LUT") else 64):
            values: dict[str, int] = {"0": 0, "1": 1}
            reachable = True
            for pin_index in range(5 if bel.endswith("5LUT") else 6):
                pin = f"A{pin_index+1}"
                bits = cell["connections"].get(pin, [])
                if not bits:
                    continue
                value = (address >> pin_index) & 1
                net = after_nets[bits[0]]
                if net in values and values[net] != value:
                    reachable = False
                    break
                values[net] = value
            if reachable:
                logical_index = 0
                for i in range(int(kind[-1])):
                    net = original_ports[f"I{i}"]
                    if net not in values:
                        raise ValueError(f"{name}: original input I{i} has no physical value")
                    logical_index |= values[net] << i
                if ((programmed >> address) & 1) != ((expected >> logical_index) & 1):
                    raise ValueError(f"{name}: wrong programmed truth table at {address}")
                cell_rows += 1
        if not cell_rows:
            raise ValueError(f"{name}: no reachable truth-table rows")
        checked_rows += cell_rows
    for location, cell in occupants.items():
        if not location.endswith("5LUT"):
            continue
        companion = occupants.get(location[:-4] + "6LUT")
        if companion is None:
            continue
        for pin in ("A1", "A2", "A3", "A4", "A5"):
            left, right = cell["connections"].get(pin, []), companion["connections"].get(pin, [])
            if left and right and after_nets[left[0]] != after_nets[right[0]]:
                raise ValueError(f"{location}: incompatible shared input {pin}")
    return {"luts": len(luts), "placement": dict(placement), "truth_table_rows": checked_rows,
            "elided_memory_constant_origins": elided_constants,
            "elided_logic_constant_origins": elided_logic_constants}
