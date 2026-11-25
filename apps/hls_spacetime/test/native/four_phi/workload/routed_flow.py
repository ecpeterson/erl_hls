"""Attach sink-specific XC7 switch tiles and native post-route SDF to a matched four-Phi replay."""

import argparse
import json
import mmap
import re
import shutil
import struct
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

from flow import ROW, asset, digest, inventory, native, require
from pack import ChipGrid, VENDOR
from placed_flow import observe_ids, placed_rows
from openxc7_endpoints import LutPermutations
from openxc7_tree import NEXTPNR_COMMIT, RouteTree, WireNames


def route_result(log: str) -> dict:
    """Require a converged router2 iteration, a completed switch export and no skipped arcs."""
    iterations = re.findall(
        r"^Info: +iter=(\d+) wires=(\d+) overused=(\d+) overuse=(\d+) archfail=(\w+)$",
        log,
        re.M,
    )
    exported = re.findall(
        r"^Info: Wrote (\d+) fixed-route pips across (\d+) nets to ", log, re.M
    )
    require(
        iterations
        and iterations[-1][2:] == ("0", "0", "0")
        and len(exported) == 1
        and "SKIP_FAILED_ARCS" not in log
        and "Info: Router2 time " in log,
        "incomplete native route",
    )
    return dict(
        iteration=int(iterations[-1][0]),
        usedWires=int(iterations[-1][1]),
        fixedPips=int(exported[0][0]),
        fixedNets=int(exported[0][1]),
    )


def trace(
    top: dict, names: WireNames, tree: RouteTree, net: str, source: tuple, sink: tuple
) -> tuple:
    """Check packed endpoints against their net bit, then trace exact or permuted BEL-pin wires."""
    bits = top["netnames"][net]["bits"]
    wires = []
    for (cell, port), direction in ((source, "output"), (sink, "input")):
        obj = top["cells"][cell]
        require(
            obj["connections"][port] == bits
            and obj["port_directions"][port] == direction,
            "wrong packed pin on routed branch",
        )
        wires.append(names.bel_wire(obj["attributes"]["NEXTPNR_BEL"], port))
    start, end = wires
    steps, permuted, _ = tree.pin_steps(top, net, *sink, start, end, sink[1])
    if steps is not None:
        return ("permuted" if permuted else "routed"), steps
    return "unresolved", None


def geometry(
    top: dict,
    names: WireNames,
    fixed: Path,
    observed: list,
    edges: bytes,
    ports: list,
    pins: bytes,
    n: int,
    path: dict,
    result: dict,
) -> tuple:
    """Reconcile fixed PIPs on demanded nets, preserving row order and the independently selected path."""
    require(0 < n <= 500_000 and len(path["steps"]) <= 512, "branch count limit")
    cells = list(top["cells"])
    packed = {
        j: cells[i]
        for i, j in observe_ids(
            observed, top["cells"], {name: i for i, name in enumerate(cells)}
        ).items()
    }
    by_bit = {}
    for net, obj in top["netnames"].items():
        (bit,) = obj["bits"]
        require(bit not in by_bit, "ambiguous packed net")
        by_bit[bit] = net
    demand = defaultdict(list)
    for i in range(n):
        a, b, _, _ = ROW.unpack_from(edges, ROW.size * i)
        ap, bp = ports[struct.unpack_from("<H", pins, 2 * i)[0]]
        src, sink = (packed[a], ap), (packed[b], bp)
        (bit,) = top["cells"][sink[0]]["connections"][bp]
        demand[by_bit[bit]].append((i, src, sink))
    selected = []
    for a, b in zip(path["steps"], path["steps"][1:]):
        demand[b["net"]].append(
            (n + len(selected), (a["cell"], a["output"]), (b["cell"], b["input"]))
        )
        selected.append(None)
    switches = defaultdict(list)
    fixed_nets = set()
    fixed_count = 0
    with fixed.open() as stream:
        require(
            stream.readline().startswith("# nextpnr-xilinx fixed-routes:"),
            "fixed-route header",
        )
        for i, row in enumerate(stream):
            require(i < 2_000_000, "fixed PIP limit")
            net, switch = row.rstrip("\n").rsplit(" ", 1)
            fixed_nets.add(net)
            fixed_count += 1
            if net in demand:
                switches[net].append(switch)
    require(
        fixed_count == result["fixedPips"] and len(fixed_nets) == result["fixedNets"],
        "incomplete fixed routes",
    )
    decoder = LutPermutations(names.grid)
    counts = Counter()
    rows, classes = [None] * n, bytearray(n)
    for net, queries in demand.items():
        tree = RouteTree(
            names,
            decoder,
            top["netnames"][net]["attributes"]["ROUTING"],
            switches.pop(net, []),
        )
        for i, src, sink in queries:
            status, steps = trace(top, names, tree, net, src, sink)
            if i >= n:
                selected[i - n] = dict(
                    net=net,
                    source=src,
                    sink=sink,
                    status=status,
                    switches=None
                    if steps is None
                    else [tree.parent[end][1] for end in steps],
                    tiles=None
                    if steps is None
                    else [tree.parent[end][3] for end in steps],
                )
                continue
            counts[status] += 1
            if steps is None:
                classes[i], rows[i] = 2, b"\xff\xff"
            else:
                classes[i] = int(status == "permuted")
                tiles = [tree.parent[end][3] for end in steps]
                rows[i] = struct.pack("<" + "H" * (1 + len(tiles)), len(tiles), *tiles)
                counts["switchVisits"] += len(tiles)
                counts["zeroSwitch"] += not tiles
    require(
        sum(counts[k] for k in ("routed", "permuted", "unresolved")) == n,
        "missing branch row",
    )
    return b"".join(rows), classes, dict(counts), selected


def flow_model(
    paths: dict,
    top: dict,
    observed: list,
    path: dict,
    grid: ChipGrid,
    constids: Path,
    dest: Path,
) -> dict:
    """Join one routed implementation's directed switches and SDF to its ordered replay cell inventory."""
    result = route_result(paths["routing.log"].read_text())
    depth, native_info = native(paths["synth.json"], observed)
    steps = path["steps"]
    require(1 < len(steps) <= 512, "selected path length")
    net_keys = [
        ((a["cell"], a["output"]), (b["cell"], b["input"]))
        for a, b in zip(steps, steps[1:])
    ]
    arc_keys = [
        (
            (
                a["cell"],
                "CK" if a["kind"] == "SLICE_FFX" else a["input"] or "CLKARDCLK",
            ),
            (a["cell"], a["output"]),
        )
        for a in steps[:-1]
    ]
    delays = dict.fromkeys(net_keys + arc_keys)
    edges, ports, pins, stats = placed_rows(
        top, paths["routed.sdf"], observed, routed=True, selected_ps=delays
    )
    require(grid.count < 65535, "switch tile encoding")
    routes, classes, counts, selected = geometry(
        top,
        WireNames(grid, constids, NEXTPNR_COMMIT),
        paths["fixed-routes.txt"],
        observed,
        edges,
        ports,
        pins,
        stats["timedConnections"],
        path,
        result,
    )
    for item, net_key, arc_key in zip(selected, net_keys, arc_keys, strict=True):
        item.update(
            netPs=delays[net_key], cellPs=delays[arc_key], cellInput=arc_key[0][1]
        )
    native_info["edges"] = asset(
        dest, "openxc7-flow", b"".join(ROW.pack(*r) for r in depth)
    )
    native_info["routed"] = dict(
        **stats,
        coverage=counts,
        routeResult=result,
        checkpoint=digest(paths["routed.json"]),
        sdf=digest(paths["routed.sdf"]),
        fixed=digest(paths["fixed-routes.txt"]),
        ports=ports,
        edges=asset(dest, "openxc7-routed-edges", edges),
        pins=asset(dest, "openxc7-routed-pins", pins),
        routes=asset(dest, "openxc7-switches", routes),
        delayClass=asset(dest, "openxc7-route-class", classes),
        selected=selected,
    )
    return native_info


def publish(
    paired: Path, vendor: Path, run: Path, chipdb: Path, constids: Path, output: Path
) -> None:
    """Publish only compatible Vivado sidecars and XC7 routes bound to this implementation and replay."""
    live = json.loads((paired / "workload.json").read_bytes())
    old = json.loads((vendor / "workload.json").read_bytes())
    receipt = json.loads((run / "capture.json").read_bytes())
    files = receipt["files"]
    require(
        live["checkpoints"]["vivado"]
        == old["checkpoints"]["vivado"]
        == files[str(VENDOR / "routed.dcp")]
        and live["backends"]["vivado"] == old["backends"]["vivado"]
        and live["logical"] == old["logical"]
        and all(
            live[k] == old[k] for k in ("part", "period", "width", "height", "cycles")
        ),
        "Vivado replay identity",
    )
    require(
        receipt["nativeStage"] == "routed"
        and receipt.get("routedGeometry")
        and receipt["tools"]["chipdb"] == digest(chipdb)
        and not output.exists(),
        "native capture or output",
    )
    paths = {
        k: run / "native" / k
        for k in (
            "synth.json",
            "routed.json",
            "routed.sdf",
            "fixed-routes.txt",
            "routing.log",
        )
    }
    for k, p in paths.items():
        require(
            p.stat().st_size <= 512 << 20 and digest(p) == files["native/" + k],
            "capture file " + k,
        )
    checkpoint = files["native/routed.json"]
    transaction = json.loads((paired / "openxc7.json").read_bytes())
    path = transaction["hardwarePath"]
    require(
        path["checkpoint"] == live["checkpoints"]["openxc7"] == checkpoint,
        "routed replay checkpoint",
    )
    observed = inventory(paired, live["backends"]["openxc7"]["names"])
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        dest = Path(tmp) / "gallery"
        shutil.copytree(paired, dest)
        vendor_info = old["flow"]["vivado"]
        for key in ("edges", "pins", "routes"):
            ref = vendor_info[key]
            require(digest(vendor / ref["file"]) == ref["sha256"], "Vivado " + key)
            shutil.copyfile(vendor / ref["file"], dest / ref["file"])
        top = json.loads(paths["routed.json"].read_bytes())["modules"]["top"]
        with (
            chipdb.open("rb") as f,
            mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as db,
        ):
            grid = ChipGrid(db)
            require(
                grid.part == live["part"] and grid.width == live["width"],
                "grid identity",
            )
            native_info = flow_model(paths, top, observed, path, grid, constids, dest)
        selected = native_info["routed"]["selected"]
        live["flow"] = dict(
            schema=1, sdf=old["flow"]["sdf"], vivado=vendor_info, openxc7=native_info
        )
        (dest / "workload.json").write_text(
            json.dumps(live, separators=(",", ":")) + "\n"
        )
        index = json.loads((dest / "index.json").read_bytes())
        detail = dest / "openxc7.json"
        (entry,) = [e for e in index["examples"] if e["file"] == detail.name]
        require(digest(detail) == entry["sha256"], "transaction identity")
        resolved = sum(item["switches"] is not None for item in selected)
        predicted = sum(item["status"] == "permuted" for item in selected)
        cell_ns = sum(item["cellPs"] for item in selected) / 1000
        net_ns = sum(item["netPs"] for item in selected) / 1000
        path["description"] += (
            f" The post-route SDF gives {cell_ns:.3f} ns in cells and {net_ns:.3f} ns in interconnect "
            f"from the RAM clock pin to this DSP input. {resolved} of {len(selected)} branches have "
            f"switch geometry. {predicted} use a placement delay for a permuted LUT input."
        )
        detail.write_text(json.dumps(transaction, separators=(",", ":")) + "\n")
        entry.update(bytes=detail.stat().st_size, sha256=digest(detail))
        index["flow"] = 1
        (dest / "index.json").write_text(json.dumps(index, indent=2) + "\n")
        dest.rename(output)
    print(json.dumps(native_info["routed"]["coverage"], indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("paired", "vendor", "run", "chipdb", "constids", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    publish(**vars(parser.parse_args()))
