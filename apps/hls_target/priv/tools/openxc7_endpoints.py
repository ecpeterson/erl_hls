"""Qualify post-route Series-7 LUT inputs against the packed cell and its net's fixed PIPs."""

import re
import struct
from collections import defaultdict
from collections.abc import Iterator

from openxc7_chipdb import ChipGrid


class LutPermutations:
    """Decode the architecture's LUT_PERMUTATION pseudo-PIPs once per tile type."""

    def __init__(self, grid: ChipGrid) -> None:
        """Retain only type-level metadata across the chip grid."""
        self.grid = grid
        self.types = {}

    def identify(self, tile: str, src: int, dst: int) -> Iterator[tuple]:
        """Yield site, physical input and router wire for each matching numeric switch."""
        grid = self.grid
        if not grid.part.startswith("xc7") or not tile.startswith("CLB"):
            return
        inst = grid.tiles + grid.owners[tile] * 24
        typ = grid.types + grid.word(inst + 4) * 32
        if typ not in self.types:
            pips = defaultdict(list)
            start = grid.pointer(typ + 24)
            for i in range(grid.word(typ + 20)):
                s, d, _, _, flag, _, extra, _, _ = struct.unpack_from(
                    "<iiihhiihh", grid.db, start + i * 28
                )
                if flag == 4:
                    pips[s, d].append(extra)
            self.types[typ] = pips
        for extra in self.types[typ].get((src, dst), ()):
            slot, phys, router = (
                (extra >> 8) & 15,
                1 + ((extra >> 4) & 15),
                1 + (extra & 15),
            )
            sites = [
                grid.pointer(inst + 20) + 32 * i for i in range(grid.word(inst + 16))
            ]
            matches = [
                grid.name(s)
                for s in sites
                if grid.word(s + 16) == slot // 4 and grid.name(s).startswith("SLICE_")
            ]
            if len(matches) == 1 and max(phys, router) <= 6:
                site, letter = matches[0], "ABCD"[slot % 4]
                yield (site, letter, phys), f"SITEWIRE/{site}/{letter}{router}"


def lut_endpoint(
    top: dict, net: str, cell: str, port: str, wire: str, candidates: dict
) -> tuple | None:
    """Accept a unique net-owned permutation for this exact placed LUT input and packed bit."""
    packed = top["cells"].get(cell, {})
    site, _, loc = packed.get("attributes", {}).get("NEXTPNR_BEL", "").partition("/")
    if (
        packed.get("type") != "SLICE_LUTX"
        or not re.fullmatch("[ABCD][56]LUT", loc)
        or not re.fullmatch("A[1-6]", port)
        or int(port[1]) > int(loc[1])
        or wire != f"SITEWIRE/{site}/{loc[0]}{port[1]}"
        or packed.get("connections", {}).get(port) != top["netnames"][net]["bits"]
    ):
        return None
    hits = candidates.get((site, loc[0], int(port[1])), ())
    return hits[0] if len(hits) == 1 else None


def qualify_selected(grid: ChipGrid, top: dict, graph: dict) -> dict:
    """Upgrade only missing native attachments with unique owned PIPs on the driver's tree."""
    decoder = LutPermutations(grid)
    for net in graph["nets"]:
        candidates, parent = defaultdict(list), {}
        for pip in net["pips"]:
            if pip["direction_status"] != "directional" or not pip.get("native_switch"):
                continue
            tile, pair = pip["native_switch"].rsplit("/", 1)
            start, end = pip["from_node"], pip["to_node"]
            parent[end] = start if end not in parent else None
            for key, wire in decoder.identify(tile, *map(int, pair.split("."))):
                if end == wire:
                    candidates[key].append((end, pip["id"]))
        pins = net["pin_attachments"]
        drivers = [
            p["routing_node"]
            for p in pins
            if p["direction"] == "OUT" and p["status"] == "resolved"
        ]
        if len(drivers) != 1:
            continue
        fixed = set()
        for p in pins:
            if p["status"] != "unavailable" or p["direction"] != "IN":
                continue
            cell, port = p["cell"], p["port"]
            bel = top["cells"].get(cell, {}).get("attributes", {}).get("NEXTPNR_BEL")
            if p["bel_pins"] != [f"{bel}/{port}"]:
                continue
            hit = lut_endpoint(top, net["id"], cell, port, p["bel_wire"], candidates)
            if not hit:
                continue
            wire, pip = hit
            cursor, seen = wire, set()
            while cursor in parent and cursor not in seen and cursor != drivers[0]:
                seen.add(cursor)
                cursor = parent[cursor]
            if cursor == drivers[0]:
                p.update(status="resolved", routing_node=wire, lut_permutation_pip=pip)
                fixed.add(p["pin"])
        remaining = [
            i
            for i in net["issues"]
            if not (
                i["stage"] == "pin"
                and i["object"] in fixed
                and i["reason"] == "missing bound BEL-pin wire"
            )
        ]
        graph["unresolved"] -= len(net["issues"]) - len(remaining)
        graph["objects"] -= len(net["issues"]) - len(remaining)
        net.update(issues=remaining, status="partial" if remaining else "complete")
    return graph
