"""Build a four-Phi connection gallery from the matched SDF, routed DCP and Yosys port bits."""

import argparse
import gzip
import json
import mmap
import os
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
from collections import Counter, defaultdict, deque
from pathlib import Path

from pack import ChipGrid, VENDOR, asset, digest, require
from capture import ARCHIVE
from measure import DEVICE_DATA, RAPIDWRIGHT

# Frozen member of the same September archive as the authenticated routed checkpoint.
SDF_SHA = "3a360208ca9b32e89c943c66c2e4bb095fb9f22d1400b1ded903e7dbf66566b6"
CLOCK = "clock_IBUF_BUFG_inst/O"
DELAYS = re.compile(r"\(([\d.]+):([\d.]+):([\d.]+)\)")
ROW = struct.Struct("<IIff")


def arrivals(edges, seeds):
    """Propagate longest additive weights in topological order from qualified launches only."""
    children, pending = defaultdict(list), Counter()
    for a, b, weight in edges:
        children[a].append((b, weight))
        pending[b] += 1
    values = dict(seeds)
    queue = deque(n for n in children if not pending[n])
    while queue:
        n = queue.popleft()
        for dest, weight in children[n]:
            if n in values:
                values[dest] = max(values.get(dest, 0), values[n] + weight)
            pending[dest] -= 1
            if not pending[dest]:
                queue.append(dest)
    require(not any(pending.values()), "cycle in within-clock graph")
    return values


def bus(pin):
    """Expand a Vivado bus-wide IOPATH to the scalar pins named by INTERCONNECT."""
    m = re.fullmatch(r"(\w+)\[(\d+):(\d+)\]", pin)
    if not m:
        return [pin]
    low, high = sorted(map(int, m.groups()[1:]))
    return [f"{m[1]}[{n}]" for n in range(low, high + 1)]


def vivado(sdf, names):
    """Compute pin arrival envelopes in ns using absolute max SDF values and local clock-pin origins."""
    indices = {name: n for n, name in enumerate(names)}
    cell_arcs, nets, clocks, connected = [], [], {}, set()
    instance = None
    records = Counter()
    with sdf.open() as src:
        for line in src:
            s = line.strip().replace("\\[", "[").replace("\\]", "]")
            if s.startswith("(INSTANCE "):
                instance = s[10:-1]
            if not s.startswith(("(IOPATH ", "(INTERCONNECT ")):
                continue
            kind, a, b, times = s[1:].split(maxsplit=3)
            triples = DELAYS.findall(times)
            require(len(triples) == 2, "unrecognized SDF delay pair")
            delay = max(float(t[2]) for t in triples) / 1000
            records[kind] += 1
            if kind == "IOPATH":
                cell_arcs.append((indices[instance], a, b, delay))
                continue
            require(instance == "", "expected absolute top-level interconnect")
            ap, bp = (p.rsplit("/", 1) for p in (a, b))
            srcpin, dstpin = (indices[ap[0]], ap[1]), (indices[bp[0]], bp[1])
            if a == CLOCK:
                clocks[dstpin] = 0
            else:
                nets.append((srcpin, dstpin, delay))
            connected.update([srcpin, dstpin])
    logic = [
        ((cell, i), (cell, o), d)
        for cell, ip, op, d in cell_arcs
        for i in bus(ip)
        if (cell, i) in connected
        for o in bus(op)
        if (cell, o) in connected
    ]
    times = arrivals(nets + logic, clocks)
    routed = [(a, b, times[a], times[a] + d) for a, b, d in nets if a in times]
    arcs = [(a, b, times[a], times[a] + d) for a, b, d in logic if a in times]
    return (
        routed,
        arcs,
        dict(
            records,
            dataConnections=len(nets),
            timedConnections=len(routed),
            localSpans=len(arcs),
            clockPins=len(clocks),
        ),
    )


def native(synth, names):
    """Compute cell-level logic depth from actual Yosys bit drivers, cutting clocked boundaries."""
    cells = json.loads(synth.read_bytes())["modules"]["phi_timing_harness"]["cells"]
    drivers, sinks, roots, combinational = {}, [], {}, set()
    for i, name in enumerate(names):
        c = cells[name]
        kind = c["type"]
        if kind in {"FDRE", "RAMB18E1", "RAMB36E1", "SRL16E", "SRLC32E"}:
            roots[i] = 0
        elif kind.startswith(("LUT", "MUXF")) or kind in {"CARRY4", "INV", "OBUF"}:
            combinational.add(i)
        elif kind == "DSP48E1":
            require(
                c["connections"]["CLK"] == ["0"]
                and all(
                    int(c["parameters"][p], 2) == 0
                    for p in ("AREG", "BREG", "CREG", "MREG", "PREG")
                ),
                "unsupported DSP register configuration",
            )
            combinational.add(i)
        for pin, bits in c["connections"].items():
            if c["port_directions"][pin] == "output":
                for bit in bits:
                    if isinstance(bit, int):
                        require(bit not in drivers, "multiple Yosys bit drivers")
                        drivers[bit] = i
            elif pin not in {"CLK", "CLKARDCLK", "CLKBWRCLK"} and (kind, pin) != (
                "FDRE",
                "C",
            ):
                sinks.extend((bit, i) for bit in bits if isinstance(bit, int))
    pairs = sorted({(drivers[bit], sink) for bit, sink in sinks if bit in drivers})
    depth = arrivals([(a, b, 1) for a, b in pairs if b in combinational], roots)
    rows = [
        (a, b, depth[a], depth[b] if b in combinational else depth[a] + 1)
        for a, b in pairs
        if a in depth
    ]
    return rows, dict(cellPairs=len(pairs), locatedDepthPairs=len(rows))


def inventory(gallery, ref):
    """Use the same authenticated primitive order as the per-cycle bit masks."""
    p = gallery / ref["file"]
    require(digest(p) == ref["sha256"], "gallery inventory digest")
    return gzip.decompress(p.read_bytes()).decode().splitlines()


def vendor_model(
    sdf: Path,
    dcp: Path,
    edif: Path,
    java: Path,
    jar: Path,
    names: list[str],
    grid: ChipGrid,
    stage: Path,
    gallery: Path,
    *,
    timing: tuple | None = None,
) -> dict:
    """Export timed arcs and sink-specific switch tiles in the replay's primitive order."""
    nets, logic, vendor = timing if timing is not None else vivado(sdf, names)
    queries, traces = stage / "pins.tsv", stage / "branches.txt"
    with queries.open("w") as f:
        for (a, ap), (b, bp), _, _ in nets:
            print(names[a], ap, names[b], bp, sep="\t", file=f)
    subprocess.run(
        [
            str(java),
            "-Xmx3g",
            "-cp",
            str(jar),
            str(Path(__file__).with_name("FlowRoutes.java")),
            str(dcp),
            str(edif),
            str(queries),
            str(traces),
        ],
        check=True,
    )
    geometry, rows, coverage = bytearray(), bytearray(), Counter()
    site_muxes = {}
    require(grid.count < 65535, "tile index width")
    with traces.open() as f:
        for ((a, _), (b, _), start, end), line in zip(nets, f, strict=True):
            route = line.strip()
            tiles = []
            if route.startswith("@"):
                site_muxes[len(rows) // ROW.size] = route[1:]
                kind = "siteMux"
            elif route in {"?", "="}:
                kind = "direct" if route == "=" else "unresolved"
            else:
                require(route, "empty Vivado route")
                tiles = [grid.owners[t] for t in route.split()]
                kind = "pipBranches"
            coverage[kind] += 1
            rows.extend(ROW.pack(a, b, start, end))
            geometry.extend(struct.pack("<H", 65535 if route == "?" else len(tiles)))
            geometry.extend(struct.pack(f"<{len(tiles)}H", *tiles))
    vendor.update(coverage)
    for (a, _), (b, _), start, end in logic:
        rows.extend(ROW.pack(a, b, start, end))
    ports, pin_ids = {}, bytearray()
    for records in (nets, logic):
        for (_, ap), (_, bp), _, _ in records:
            pair = ap, bp
            if pair not in ports:
                ports[pair] = len(ports)
            pin_ids.extend(struct.pack("<H", ports[pair]))
    vendor.update(
        siteMuxes=site_muxes,
        ports=list(ports),
        pins=asset(gallery, "vivado-flow-pins", pin_ids),
        edges=asset(gallery, "vivado-flow", rows),
        routes=asset(gallery, "vivado-switches", geometry),
    )
    return vendor


def build(args, stage):
    """Join bounded local tool outputs and publish a complete copy only after all inputs agree."""
    live = json.loads((args.gallery / "workload.json").read_text())
    receipt = json.loads((args.run / "capture.json").read_text())
    dcp = args.run / VENDOR / "routed.dcp"
    sdf = stage / "routed.sdf"
    require(
        digest(args.archive) == receipt["archive"] == ARCHIVE, "Vivado archive identity"
    )
    with tarfile.open(args.archive, "r|gz") as archive:
        for member in archive:
            if Path(member.name) == VENDOR / "routed.sdf":
                require(member.isfile() and member.size <= 256 << 20, "SDF member")
                with sdf.open("xb") as out:
                    shutil.copyfileobj(archive.extractfile(member), out)
                break
    rw = Path(os.environ["RAPIDWRIGHT_PATH"]) / "data"
    require(
        digest(args.jar) == RAPIDWRIGHT
        and all(digest(rw / name) == sha for name, sha in DEVICE_DATA.items()),
        "RapidWright release and device data",
    )
    synth = args.run / "native/synth.json"
    require(
        digest(dcp) == live["checkpoints"]["vivado"]
        and digest(sdf) == SDF_SHA
        and digest(synth) == receipt["files"]["native/synth.json"]
        and digest(args.run / "native/placed.json") == live["checkpoints"]["openxc7"]
        and digest(args.chipdb) == receipt["tools"]["chipdb"],
        "implementation identity",
    )
    gallery = stage / "gallery"
    shutil.copytree(args.gallery, gallery)
    names = inventory(gallery, live["backends"]["vivado"]["names"])
    with (
        args.chipdb.open("rb") as f,
        mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        require(grid.width == live["width"], "tile grid width")
        vendor = vendor_model(
            sdf, dcp, args.edif, args.java, args.jar, names, grid, stage, gallery
        )
    native_rows, xc7 = native(
        synth, inventory(gallery, live["backends"]["openxc7"]["names"])
    )
    xc7["edges"] = asset(
        gallery, "openxc7-flow", b"".join(ROW.pack(*r) for r in native_rows)
    )
    live["flow"] = dict(schema=1, sdf=SDF_SHA, vivado=vendor, openxc7=xc7)
    (gallery / "workload.json").write_text(
        json.dumps(live, separators=(",", ":")) + "\n"
    )
    index = json.loads((gallery / "index.json").read_text())
    index["flow"] = 1
    (gallery / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    require(not args.output.exists(), "output already exists")
    gallery.rename(args.output)
    print(
        json.dumps(
            {
                b: {k: v for k, v in live["flow"][b].items() if isinstance(v, int)}
                for b in ("vivado", "openxc7")
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("gallery", "run", "archive", "edif", "java", "jar", "chipdb", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        build(args, Path(tmp))
