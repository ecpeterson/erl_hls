"""Publish shared native nodes, fixed PIPs and arc-indexed branches for the recording interval."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import mmap
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "hls_target/priv/tools"))
from openxc7_chipdb import ChipGrid
from openxc7_endpoints import LutPermutations
from openxc7_frozen import capture_manifest, verified
from openxc7_tree import CONSTIDS_SHA, RouteTree, WireNames


def encoded(value: object) -> bytes:
    """Encode the exact portable JSON representation used in every descriptor."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode()


def write(path: Path, data: bytes) -> dict:
    """Create a fresh part and return its relative byte identity."""
    with path.open("xb") as stream:
        stream.write(data)
    return {
        "file": path.name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def rows(base: Path, manifest: dict, table: str) -> list:
    """Read ordered rows from verified parts of an already validated preparation."""
    result = []
    for part in manifest["parts"]:
        if part["table"] == table:
            if Path(part["file"]).name != part["file"]:
                raise ValueError("invalid table path")
            data = json.loads(
                verified(base / part["file"], part, 32 << 20).read_bytes()
            )
            if len(data) != part["rows"]:
                raise ValueError("part row count mismatch")
            result.extend(data)
    if len(result) != manifest["totals"][table]:
        raise ValueError("table row count mismatch")
    return result


def demand(base: Path, entry: dict) -> tuple:
    """Collect distinct net arcs traversed by every write in the selected half-open cycle window."""

    def member(ref: dict, limit: int) -> tuple:
        """Resolve and verify a member of the selected publication."""
        path = (base / ref["file"]).resolve()
        if not path.is_relative_to(base.resolve()):
            raise ValueError("publication path outside root")
        return json.loads(verified(path, ref, limit).read_bytes()), path.parent

    view, _ = member(entry, 128 << 20)
    render, rb = member(entry["render"], 4 << 20)
    source, sb = member(entry["computations"], 4 << 20)
    identity = {k: entry[k] for k in ("bytes", "sha256")}
    if (
        source["view"] != identity
        or render["view"] != identity
        or render["source"] != entry["computations"]
        or source["checkpoint"] != view["catalogue"]["checkpoint"]
        or source["build"] != view["bundle"]["build"]
    ):
        raise ValueError("publication identities differ")
    selection = view["selection"]
    lo, hi = selection["firstCycle"], selection["endCycle"]
    if not isinstance(lo, int) or not isinstance(hi, int) or lo >= hi:
        raise ValueError("invalid recording interval")
    writes = {
        e["id"]
        for e in view["bundle"]["events"]
        if lo <= e["cycle"] < hi and (e.get("access") or {}).get("kind") == "write"
    }
    selected = [w for w in rows(rb, render, "writes") if w["event"] in writes]
    if len(selected) != len(writes) or {w["event"] for w in selected} != writes:
        raise ValueError("interval write population mismatch")
    active = {i for w in selected for i in w["cones"]}
    cones = rows(rb, render, "cones")
    arcs = rows(sb, source, "arcs")
    ids = sorted(
        {a for i in active for a in cones[i]["arcIndices"] if arcs[a]["kind"] == "net"}
    )
    if len(ids) > 1_000_000:
        raise ValueError("interval branch limit")
    pins, nets = rows(sb, source, "pins"), rows(sb, source, "nets")
    by_net = defaultdict(list)
    for i in ids:
        a = arcs[i]
        by_net[nets[a["net"]]["id"]].append(
            (i, a["from"], a["to"], pins[a["from"]]["id"], pins[a["to"]]["id"])
        )
    return by_net, source, selection, len(writes)


class Shards:
    """Emit nonoverlapping ID ranges bounded by both decoded bytes and row count."""

    def __init__(self, out: Path, table: str) -> None:
        """Start an empty, monotonically indexed geometry table."""
        self.out, self.table = out, table
        self.parts, self.buffer = [], []
        self.size, self.count, self.last = 2, 0, -1

    def add(self, key: int, data: list) -> None:
        """Append one row in increasing key order. Reject even a single oversized row."""
        body = encoded([key, *data])
        if key <= self.last or len(body) + 2 > 1 << 20:
            raise ValueError("invalid shard row order or size")
        if self.size + len(body) + 1 > 128 << 10 or len(self.buffer) >= 1024:
            self.flush()
        if not self.buffer:
            self.first = key
        self.last = key
        self.buffer.append(body)
        self.size += len(body) + 1
        self.count += 1

    def flush(self) -> None:
        """Seal a complete part before publishing its range and digest."""
        if self.buffer:
            path = self.out / f"{self.table}-{len(self.parts)}.json"
            part = write(path, b"[" + b",".join(self.buffer) + b"]")
            self.parts.append(
                dict(part, first=self.first, last=self.last, rows=len(self.buffer))
            )
            self.buffer, self.size = [], 2


def publish(
    base: Path, entry: dict, capture: Path, chipdb: Path, constids: Path
) -> dict:
    """Attach a complete demand census to a fresh render publication before its index becomes visible."""
    demand_by_net, source, selection, writes = demand(base, entry)
    meta = capture_manifest(capture, source["build"]["implementation"], chipdb)
    if source["checkpoint"] != meta["files"]["routed.json"]["sha256"]:
        raise ValueError("route checkpoint mismatch")

    def sidecar(name: str) -> Path:
        """Require the implementation manifest’s exact input bytes."""
        return verified(capture / name, meta["files"][name], 384 << 20)

    top = json.loads(sidecar("routed.json").read_bytes())["modules"]["top"]
    timing = json.loads(sidecar("timing.json").read_bytes())["cells"]
    switches = defaultdict(list)
    with sidecar("fixed-routes.txt").open() as stream:
        if not stream.readline().startswith("# nextpnr-xilinx fixed-routes:"):
            raise ValueError("unsupported fixed route format")
        for n, row in enumerate(stream):
            if n >= 2_000_000:
                raise ValueError("fixed PIP limit")
            net, switch = row.rstrip("\n").rsplit(" ", 1)
            if net in demand_by_net:
                switches[net].append(switch)
    out = base / "geometry"
    out.mkdir()
    nodes, pips, branches = (Shards(out, k) for k in ("nodes", "pips", "branches"))
    node_ids, pip_ids, branch_rows = {}, {}, {}
    counts, missing = Counter(), Counter()
    memberships = 0
    with (
        chipdb.open("rb") as stream,
        mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        names = WireNames(grid, constids, meta["tools"]["nextpnr"]["build"]["commit"])
        decoder = LutPermutations(grid)
        for net, demands in sorted(demand_by_net.items()):
            tree = RouteTree(
                names,
                decoder,
                top["netnames"][net]["attributes"].get("ROUTING", ""),
                switches.pop(net, []),
            )

            def node(wire: str) -> int:
                """Intern a proven node and every native constituent tile wire once."""
                if wire not in node_ids:
                    key = tree.keys.get(wire)
                    if key is None:
                        key = names.local_key(wire)
                    footprint = [
                        [grid.owners[w["tile"]], w["id"]]
                        for w in grid.wires(key, 65536)
                    ]
                    node_ids[wire] = nodes.count
                    nodes.add(nodes.count, [wire, footprint])
                return node_ids[wire]

            for arc, src, dst, driver, sink in demands:
                status, start, steps, physical, local_tie = tree.branch(
                    top, timing, net, driver, sink
                )
                memberships += len(steps)
                if memberships > 16_000_000:
                    raise ValueError("interval PIP membership limit")
                counts[status] += 1
                edges = []
                if start is None:
                    missing[net] += 1
                for end in steps:
                    before, switch, incoming, tile = tree.parent[end]
                    identity = (node(before), node(end), tile, switch, incoming)
                    if switch not in pip_ids:
                        pip_ids[switch] = (pips.count, identity)
                        pips.add(pips.count, list(identity))
                    edge_id, bound = pip_ids[switch]
                    if bound != identity:
                        raise ValueError(f"conflicting fixed switch identity: {switch}")
                    edges.append(edge_id)
                branch_rows[arc] = [
                    src,
                    dst,
                    status,
                    node(start) if start else None,
                    edges,
                    physical,
                    local_tie,
                ]
        for arc, row in sorted(branch_rows.items()):
            branches.add(arc, row)
        for table in (branches, nodes, pips):
            table.flush()
        manifest = dict(
            format="spacetime-openxc7-geometry",
            schema=1,
            build=source["build"],
            checkpoint=source["checkpoint"],
            selection=selection,
            width=grid.width,
            tiles=grid.count,
            view=entry["sha256"],
            source=entry["computations"]["sha256"],
            render=entry["render"]["sha256"],
            chipdb=meta["chipdb"]["sha256"],
            constids=CONSTIDS_SHA,
            writes=writes,
            nets=len(demand_by_net),
            branches=branches.count,
            counts=counts,
            unavailableByNet=missing,
            parts={t.table: t.parts for t in (branches, nodes, pips)},
        )
    body = encoded(manifest)
    if len(body) > 4 << 20:
        raise ValueError("geometry manifest exceeds 4 MiB")
    desc = write(out / "manifest.json", body)
    return dict(desc, file="geometry/manifest.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("publication", "capture", "chipdb", "constids"):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    print(
        json.dumps(
            publish(
                args.publication,
                json.load(sys.stdin),
                args.capture,
                args.chipdb,
                args.constids,
            )
        )
    )
