"""Census installed net, tile-wire and switch memberships from a frozen XC7 route."""

import argparse
from collections import Counter, defaultdict
import json
import mmap
from pathlib import Path

from openxc7_chipdb import ChipGrid
from openxc7_endpoints import LutPermutations
from openxc7_frozen import capture_manifest, verified
from openxc7_tree import RouteTree, WireNames


def census(
    capture: Path, implementation: str, chipdb: Path, constids: Path, bin_size: int
) -> dict:
    """Check every fixed switch against its net and count every bound wire's chipdb footprint."""
    if not 1 <= bin_size <= 4096:
        raise ValueError("invalid region bin size")
    manifest = capture_manifest(capture, implementation, chipdb)

    def source(name: str) -> Path:
        """Admit only files bound by the recording's implementation manifest."""
        return verified(capture / name, manifest["files"][name], 384 << 20)

    by_net = defaultdict(list)
    with source("fixed-routes.txt").open() as stream:
        if not stream.readline().startswith("# nextpnr-xilinx fixed-routes:"):
            raise ValueError("unsupported fixed route format")
        for i, row in enumerate(stream):
            if i >= 2_000_000:
                raise ValueError("regional switch limit")
            net, switch = row.rstrip("\n").rsplit(" ", 1)
            by_net[net].append(switch)
    nets = json.loads(source("routed.json").read_bytes())["modules"]["top"]["netnames"]
    if len(nets) > 100_000 or not by_net.keys() <= nets.keys():
        raise ValueError("invalid packed net census")
    rows = []
    total_wires = 0
    with (
        chipdb.open("rb") as stream,
        mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        names = WireNames(
            grid, constids, manifest["tools"]["nextpnr"]["build"]["commit"]
        )
        decoder = LutPermutations(grid)
        for name, net in nets.items():
            switches = by_net.pop(name, [])
            tree = RouteTree(
                names, decoder, net["attributes"].get("ROUTING", ""), switches
            )
            wire_bins = Counter()
            for wire in tree.bound:
                key = tree.keys.get(wire)
                if key is None:
                    key = names.local_key(wire)
                for member in grid.wires(key, 65536):
                    wire_bins[member["x"] // bin_size, member["y"] // bin_size] += 1
            total_wires += wire_bins.total()
            if total_wires > 16_000_000:
                raise ValueError("regional wire membership limit")
            rows.append(
                [name, switches, [[x, y, n] for (x, y), n in sorted(wire_bins.items())]]
            )
        return dict(
            checkpoint=manifest["files"]["routed.json"]["sha256"],
            width=grid.width,
            tiles=grid.tile_names,
            nets=rows,
            wireMemberships=total_wires,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("implementation")
    parser.add_argument("chipdb", type=Path)
    parser.add_argument("constids", type=Path)
    parser.add_argument("bin_size", type=int)
    args = parser.parse_args()
    print(json.dumps(census(**vars(args)), separators=(",", ":")))
