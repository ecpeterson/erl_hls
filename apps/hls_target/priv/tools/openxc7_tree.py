"""Recover named, directed nextpnr route trees from the frozen checkpoint and numeric fixed PIPs."""

import re
import struct
from collections import defaultdict
from pathlib import Path

from openxc7_chipdb import ChipGrid
from openxc7_endpoints import LutPermutations, lut_endpoint
from openxc7_frozen import verified

CONSTIDS_SHA = "a987029ea1a962804f69f26861cbad317a8c51a4aad7f28d38529b9ecc21778a"
NEXTPNR_COMMIT = "68aeeb39f92e39bfb239c7e4a44dd93451fc1889"


class WireNames:
    """Resolve canonical nextpnr IDs using the compiled architecture's exact ID table."""

    def __init__(self, grid: ChipGrid, constids: Path, commit: str) -> None:
        """Verify the pinned constant-name order before naming any chipdb wire."""
        if commit != NEXTPNR_COMMIT:
            raise ValueError("unsupported nextpnr wire-name ABI")
        verified(
            constids,
            {"bytes": constids.stat().st_size, "sha256": CONSTIDS_SHA},
            1 << 20,
        )
        self.grid = grid
        ids = [""] + re.findall(r"^X\(([^)]+)\)", constids.read_text(), re.M)
        info = grid.pointer(grid.pointer(0) + 44)
        if len(ids) != grid.word(info):
            raise ValueError("constids/chipdb ID count mismatch")
        base = grid.pointer(info + 8)
        self.ids = ids + [grid.name(base + 4 * i) for i in range(grid.word(info + 4))]
        self.by_key = {}

    def name(self, key: tuple[int, int]) -> str:
        """Return the saved canonical tile wire or site wire for a validated wire key."""
        if key not in self.by_key:
            grid = self.grid
            tile, wire = key
            if tile == -1:
                tile, wire = struct.unpack_from(
                    "<ii", grid.db, grid.pointer(grid.nodes + wire * 12 + 8)
                )
            inst = grid.tiles + tile * 24
            typ = grid.types + 32 * grid.word(inst + 4)
            record = grid.pointer(typ + 16) + 40 * wire
            site = struct.unpack_from("<h", grid.db, record + 32)[0]
            owner = (
                grid.tile_names[tile]
                if site == -1
                else "SITEWIRE/" + grid.name(grid.pointer(inst + 20) + 32 * site)
            )
            self.by_key[key] = owner + "/" + self.ids[grid.word(record)]
        return self.by_key[key]

    def local_key(self, wire: str) -> tuple[int, int]:
        """Resolve a zero-switch local net from its exact chipdb name when no PIP names its wire."""
        grid = self.grid
        parts = wire.split("/")
        owner = parts[1] if parts[0] == "SITEWIRE" else parts[0]
        tile = grid.tiles + grid.owners[owner] * 24
        typ = grid.types + 32 * grid.word(tile + 4)
        keys = {grid.wire_key(owner, i) for i in range(grid.word(typ + 12))}
        matches = [k for k in keys if self.name(k) == wire]
        if len(matches) != 1:
            raise ValueError(f"unbound zero-switch node: {wire}")
        return matches[0]


class RouteTree:
    """Require agreement between the net's named incoming PIPs and its numeric fixed routes."""

    def __init__(
        self, names: WireNames, decoder: LutPermutations, routing: str, switches: list
    ) -> None:
        """Reject duplicate or missing incoming fixed PIPs before tracing any branch."""
        self.parent, self.keys, self.candidates = {}, {}, defaultdict(list)
        rows = routing.split(";") if routing else []
        if len(rows) % 3:
            raise ValueError("invalid packed ROUTING triplets")
        self.bound = dict(zip(rows[::3], rows[1::3]))
        if len(self.bound) != len(rows) // 3:
            raise ValueError("duplicate bound wire")
        grid = names.grid
        for switch in switches:
            tile, pair = switch.rsplit("/", 1)
            local = tuple(map(int, pair.split(".")))
            src, dst = (grid.wire_key(tile, i) for i in local)
            start, end = names.name(src), names.name(dst)
            incoming = self.bound.get(end)
            if not incoming or end in self.parent:
                raise ValueError(f"fixed PIP lacks unique checkpoint binding: {switch}")
            if incoming.endswith("->" + end) and incoming != start + "->" + end:
                raise ValueError(f"fixed PIP source differs from checkpoint: {switch}")
            self.parent[end] = (start, switch, incoming, grid.owners[tile])
            self.keys.update(((start, src), (end, dst)))
            for key, wire in decoder.identify(tile, *local):
                if end == wire:
                    self.candidates[key].append((end, switch))
        if sum(bool(pip) for pip in self.bound.values()) != len(self.parent):
            raise ValueError("checkpoint contains unaccounted PIPs")

    def trace(self, start: str, end: str) -> tuple[list | None, str | None]:
        """Trace to the bound driver or identify the actual disconnected root of this sink subtree."""
        if start not in self.bound or end not in self.bound:
            return None, None
        seen, steps = set(), []
        while end != start:
            if end not in self.parent:
                return None, end
            if end in seen or len(steps) >= 4096:
                raise ValueError("cyclic or oversized fixed-route branch")
            seen.add(end)
            steps.append(end)
            end = self.parent[end][0]
        return steps[::-1], None

    def branch(
        self, top: dict, timing: dict, net: str, source: str, sink: str
    ) -> tuple:
        """Match both timed pins to packed net bits and qualify direct or permuted connectivity."""
        endpoints = []
        for pin, direction in ((source, "OUT"), (sink, "IN")):
            cell, port = pin.rsplit("/", 1)
            native = timing.get(cell, {}).get("ports", {}).get(port, {})
            packed = top["cells"].get(cell, {})
            if (
                native.get("direction") != direction
                or native.get("net") != net
                or packed.get("connections", {}).get(port)
                != top["netnames"][net]["bits"]
                or not native.get("wire")
            ):
                return "missing_endpoint", None, [], None, None
            endpoints.append(native["wire"])
        start, end = endpoints
        steps, root = self.trace(start, end)
        if steps is not None:
            return "direct", start, steps, None, None
        if native.get("bel_pin") == port:
            hit = lut_endpoint(top, net, cell, port, end, self.candidates)
            if hit:
                steps, root = self.trace(start, hit[0])
                if steps is not None:
                    return "lut_permutation", start, steps, end, None
        for kind in ("GND", "VCC"):
            if (
                source == f"$PACKER_{kind}_DRV/Y"
                and net == f"$PACKER_{kind}_NET"
                and start.endswith(f"/PSEUDO_{kind}_WIRE_GLBL")
                and root
                and root.endswith(f"/{kind}_WIRE")
            ):
                return "disconnected_constant", None, [], None, root
        return "unavailable", None, [], None, None
