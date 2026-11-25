"""Bind nextpnr's inserted identity LUTs to the exact sampled signal driving I0."""

import re
import struct
from pathlib import Path

from pin_activity import read_asset
from pack import ChipGrid, asset, observe_ids, require


def identity_input(cell: dict, output: str) -> int | None:
    """Return the unique functional input bit for a packed LUT implementing the identity."""
    attrs = cell["attributes"]
    if (
        cell["type"] != "SLICE_LUTX"
        or attrs.get("X_ORIG_TYPE") != "LUT1"
        or attrs.get("X_ORIG_PORT_" + output) != "O"
        or int(cell["parameters"]["INIT"], 2) != 2
    ):
        return None
    bits = [
        bit
        for pin, bits in cell["connections"].items()
        if attrs.get("X_ORIG_PORT_" + pin) == "I0"
        for bit in bits
    ]
    require(len(bits) <= 1, "ambiguous packed identity input")
    return bits[0] if bits else None


def folded_ground(cells: dict, grid: ChipGrid, config: Path) -> set[str]:
    """Identify input-elided 5-LUT buffers whose explicit physical O5 truth table is all zero."""
    features = {}
    for name, cell in cells.items():
        attrs = cell["attributes"]
        if (
            cell["type"] != "SLICE_LUTX"
            or attrs.get("X_ORIG_TYPE") != "LUT1"
            or attrs.get("X_ORIG_PORT_O5") != "O"
            or int(cell["parameters"]["INIT"], 2) != 2
            or any(attrs.get(f"X_ORIG_PORT_A{i}") for i in range(1, 7))
        ):
            continue
        site, bel = attrs["NEXTPNR_BEL"].split("/")
        if not re.fullmatch(r"[ABCD]5LUT", bel):
            continue
        tile = grid.location(site)["tile"]
        half = int(site.split("_X")[1].split("Y")[0]) % 2
        kind = "SLICEM" if tile.startswith("CLBLM_") and half == 0 else "SLICEL"
        features[f"{tile}.{kind}_X{half}.{bel[0]}LUT.INIT[63:0]"] = name
    result = set()
    seen = set()
    with config.open() as stream:
        for line in stream:
            feature, _, value = line.strip().partition(" = ")
            if feature in features:
                require(feature not in seen, "duplicate LUT configuration feature")
                seen.add(feature)
                if re.fullmatch(r"64'b[01]{32}0{32}", value):
                    result.add(features[feature])
    return result


def input_sources(
    cells: dict, names: list[str], ground: frozenset[str] | set[str] = frozenset()
) -> dict:
    """Resolve each inserted buffer to an observed bit or a routed/configured constant in cell order."""
    ids = {name: i for i, name in enumerate(cells)}
    observed = observe_ids(names, cells, ids)
    drivers = {
        bit: (name, pin)
        for name, cell in cells.items()
        for pin, bits in cell["connections"].items()
        if cell["port_directions"][pin] == "output"
        for bit in bits
    }
    buffers = {}
    for name, cell in cells.items():
        if ids[name] in observed or cell["attributes"].get("X_ORIG_TYPE") != "LUT1":
            continue
        outputs = [
            pin
            for pin, bits in cell["connections"].items()
            if bits and cell["port_directions"][pin] == "output"
        ]
        if len(outputs) == 1:
            signal = identity_input(cell, outputs[0])
            if signal in drivers:
                buffers[name] = drivers[signal]
    sources = {name: None for name in ground if ids[name] not in observed}
    for name in buffers:
        src, pin = buffers[name]
        seen = {name}
        while src in buffers:
            require(
                src not in seen
                and cells[src]["attributes"].get("X_ORIG_PORT_" + pin) == "O",
                "invalid upstream identity LUT",
            )
            seen.add(src)
            src, pin = buffers[src]
        if ids[src] in observed:
            sources[name] = observed[ids[src]], pin
        elif src in ground or cells[src]["type"] in ("PSEUDO_GND", "PSEUDO_VCC"):
            sources[name] = None
    return {name: sources[name] for name in cells if name in sources}


def append_buffers(
    gallery: Path,
    replay: dict,
    cells: dict,
    grid: ChipGrid,
    samples: dict,
    sources: dict | None = None,
) -> list[str]:
    """Append physical buffers in packed order, deriving settled masks from their input bits.

    Samples maps multi-output (original index, packed pin) pairs to per-cycle
    known-toggle and unknown-comparison bytes. Single-output masks copy exactly.
    """
    b = replay["backends"]["openxc7"]
    names = read_asset(gallery, b["names"]).decode().splitlines()
    if sources is None:
        sources = input_sources(cells, names)
    catalogue = bytearray(read_asset(gallery, b["catalogue"]))
    require(len(sources) <= b["placementOnly"].get("LUT1", 0), "buffer inventory")
    if not sources:
        return names
    if "LUT1" not in b["kinds"]:
        b["kinds"].append("LUT1")
    kind = b["kinds"].index("LUT1")
    scalar, pins, constant = [], [], []
    for j, (name, src) in enumerate(sources.items(), len(names)):
        site = cells[name]["attributes"]["NEXTPNR_BEL"].split("/")[0]
        catalogue.extend(struct.pack("<iBh", grid.owners[site], kind, -1))
        if src is None:
            constant.append(j)
        elif src in samples:
            pins.append((j, samples[src]))
        else:
            idx, pin = src
            obj = cells[names[idx]]
            require(
                obj["attributes"]["X_ORIG_TYPE"].startswith(("LUT", "FD"))
                and obj["attributes"]["X_ORIG_PORT_" + pin] in ("O", "Q"),
                "missing scalar input observation",
            )
            scalar.append((j, idx))
    width = (len(names) + 7) // 8
    names.extend(sources)
    step = (len(names) + 7) // 8
    b["cells"] = len(names)
    b["mapped"] += len(sources)
    b["placementOnly"]["LUT1"] -= len(sources)
    if not b["placementOnly"]["LUT1"]:
        del b["placementOnly"]["LUT1"]
    b["names"] = asset(gallery, "openxc7-names", "\n".join(names).encode())
    b["catalogue"] = asset(gallery, "openxc7-cells", catalogue)
    totals = [0, 0]
    for chunk, ref in enumerate(b["chunks"]):
        old = read_asset(gallery, ref)
        new = bytearray()
        require(len(old) == 2 * width * replay["chunk"], "input mask size")
        for offset in range(replay["chunk"]):
            cycle = chunk * replay["chunk"] + offset
            for flag, counter in enumerate(("changed", "unknown")):
                start = (2 * offset + flag) * width
                mask = bytearray(old[start : start + width]) + bytearray(step - width)
                for j, i in scalar:
                    mask[j // 8] |= ((mask[i // 8] >> (i % 8)) & 1) << (j % 8)
                for j, flags in pins:
                    mask[j // 8] |= ((flags[cycle] >> flag) & 1) << (j % 8)
                if cycle == 0 and flag:
                    for j in constant:
                        mask[j // 8] |= 1 << (j % 8)
                value = int.from_bytes(mask, "little")
                b[counter][cycle] = value.bit_count()
                if cycle:
                    totals[flag] |= value
                new.extend(mask)
        b["chunks"][chunk] = asset(gallery, f"openxc7-{chunk * replay['chunk']}", new)
    b["entire"] = asset(
        gallery, "openxc7-entire", b"".join(v.to_bytes(step, "little") for v in totals)
    )
    b["everChanged"] = totals[0].bit_count()
    return names
