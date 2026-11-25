"""Attach nextpnr's placement-only pin timing to a matched four-Phi gallery."""

import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

from flow import ROW, arrivals, asset, digest, inventory, require
from openxc7 import logic_arc
from pack import observe_ids
from packed_buffers import identity_input

ESCAPE = re.compile(r"\\(.)")
DELAY = re.compile(r"\(([\d.]+):([\d.]+):([\d.]+)\) \(([\d.]+):([\d.]+):([\d.]+)\)\)")


def launch_pin(cell: dict, pin: str) -> bool:
    """Identify a storage clock pin whose launch requires the observed global clock."""
    if cell["type"].startswith("RAMB"):
        return re.fullmatch(r"(CLKARDCLK|CLKBWRCLK)[LU]?", pin) is not None
    if cell["type"] == "SLICE_FFX":
        return pin == "CK"
    return pin == "CLK" and (
        "X_LUT_AS_SRL" in cell["attributes"] or cell["type"] == "DSP48E1_DSP48E1"
    )


def modeled_arc(cell: dict, src: str, dst: str) -> bool:
    """Keep functional carry lanes and only the reported shift-register clock-to-Q launch."""
    attrs = cell["attributes"]
    if "X_LUT_AS_SRL" in attrs:
        return src == "CLK" and attrs.get("X_ORIG_PORT_" + dst) == "Q"
    if "X_LUT_AS_DRAM" in attrs:
        return False
    return cell["type"] != "CARRY4" or logic_arc(cell, src, dst)


def placed_rows(
    placed: dict,
    sdf: Path,
    names: list[str],
    *,
    routed: bool = False,
    selected_ps: dict | None = None,
) -> tuple:
    """Check SDF nets against packed bits; accumulate modeled delays from real launch pins in ps."""
    cells = placed["cells"]
    ids = {n: i for i, n in enumerate(cells)}
    objects = list(cells.values())
    observed = observe_ids(names, cells, ids)
    drivers = {}
    for i, obj in enumerate(objects):
        for port, bits in obj["connections"].items():
            if obj["port_directions"][port] == "output" and bits:
                require(
                    len(bits) == 1
                    and isinstance(bits[0], int)
                    and bits[0] not in drivers,
                    "expected one packed scalar driver",
                )
                drivers[bits[0]] = (i, port)
    expected_sinks = {
        (i, port)
        for i, obj in enumerate(objects)
        for port, bits in obj["connections"].items()
        if obj["port_directions"][port] != "output"
        and len(bits) == 1
        and bits[0] in drivers
    }
    require(
        any(n["attributes"]["ROUTING"].strip() for n in placed["netnames"].values())
        == routed
        and bool(int(placed.get("settings", {}).get("route", "0"), 2)) == routed,
        "SDF and checkpoint routing stage",
    )
    (clock,) = [ids[n] for n, c in cells.items() if c["type"] == "BUFGCTRL"]
    nets, arcs, sources, sinks, seeds = [], [], set(), set(), {}
    stats = Counter()
    dsp_clocks = set()
    registered_products = set()
    seen = set()
    cell = None
    kind = None
    scale = False

    def endpoint(text: str) -> tuple:
        """Decode the last hierarchy separator and nextpnr's escaped cell and port characters."""
        name, port = ESCAPE.sub(r"\1", text).rsplit("/", 1)
        return ids[name], sys.intern(port)

    with sdf.open() as stream:
        for line in stream:
            s = line.strip()
            if s.startswith("(TIMESCALE "):
                require(s == "(TIMESCALE 1ps)", "unexpected SDF time unit")
                scale = True
            elif s.startswith("(CELLTYPE "):
                kind = s.split('"')[1]
            elif s.startswith("(INSTANCE "):
                name = ESCAPE.sub(r"\1", s[10:-1])
                cell = ids[name] if name else None
                if cell is not None:
                    require(
                        objects[cell]["type"] == kind and cell not in seen,
                        "SDF cell identity",
                    )
                    seen.add(cell)
            elif s.startswith(("(INTERCONNECT ", "(IOPATH ")):
                tag, src, dst, delays = s[1:].split(maxsplit=3)
                match = DELAY.fullmatch(delays)
                require(scale and match is not None, "unrecognized pin delay record")
                ps = max(float(match[3]), float(match[6]))
                if tag == "INTERCONNECT":
                    require(cell is None, "expected absolute packed endpoints")
                    a, b = endpoint(src), endpoint(dst)
                    bits = objects[b[0]]["connections"][b[1]]
                    require(
                        b in expected_sinks
                        and b not in sinks
                        and drivers[bits[0]] == a,
                        "packed signal mismatch",
                    )
                    sources.add(a)
                    sinks.add(b)
                    if a == (clock, "O"):
                        stats["clockLoads"] += 1
                        target, pin = objects[b[0]], b[1]
                        if launch_pin(target, pin):
                            if target["type"] == "DSP48E1_DSP48E1":
                                dsp_clocks.add(b)
                            else:
                                seeds[b] = 0
                    else:
                        nets.append((a, b, ps))
                else:
                    require(cell is not None, "missing cell for IOPATH")
                    stats["reportedCellArcs"] += 1
                    a, b = (cell, sys.intern(src)), (cell, sys.intern(dst))
                    if (
                        a in sinks
                        and b in sources
                        and (
                            not launch_pin(objects[cell], src)
                            or a in seeds
                            or a in dsp_clocks
                        )
                        and modeled_arc(objects[cell], src, dst)
                    ):
                        arcs.append((a, b, ps))
                        if a in dsp_clocks and re.fullmatch(r"P[0-9]+", dst):
                            seeds[a] = 0
                            params = objects[cell]["parameters"]
                            if cell in observed and all(
                                int(params.get(p, "0"), 2) == 1
                                for p in ("MREG", "PREG")
                            ):
                                registered_products.add(observed[cell])
    require(
        len(seen) == len(cells) and sinks == expected_sinks and seeds,
        "incomplete placed SDF",
    )
    if selected_ps is not None:
        queries = {}
        for source, sink in selected_ps:
            a, ap = source
            b, bp = sink
            queries[(ids[a], ap), (ids[b], bp)] = (source, sink)
        for edges in (nets, arcs):
            for a, b, ps in edges:
                if (a, b) in queries:
                    key = queries[a, b]
                    require(selected_ps[key] is None, "duplicate selected delay")
                    selected_ps[key] = ps
        require(None not in selected_ps.values(), "missing pin delay on selected path")
    times = arrivals(nets + arcs, seeds)
    rows, ports, pin_ids = bytearray(), {}, bytearray()
    stats.update(
        placedNetRecords=len(placed["netnames"]),
        clockPins=len(seeds),
        nonclockConnections=len(nets),
        usedCellArcs=len(arcs),
    )
    omitted = Counter()
    origins = {}

    def launch_origin(pin: tuple) -> str:
        """Classify a missing driver by its actual primitive, following packed identity LUT inputs."""
        path = set()
        while pin not in origins and pin not in path:
            path.add(pin)
            obj = objects[pin[0]]
            kind = obj["attributes"].get("X_ORIG_TYPE", obj["type"])
            if kind in ("PSEUDO_GND", "PSEUDO_VCC"):
                origins[pin] = "constant"
            elif kind in ("IBUF", "OBUF"):
                origins[pin] = "io"
            else:
                upstream = drivers.get(identity_input(obj, pin[1]))
                if upstream is None:
                    break
                pin = upstream
        label = origins.get(pin, "other")
        origins.update(dict.fromkeys(path, label))
        return label

    for key, edges in (("Connections", nets), ("CellArcs", arcs)):
        for a, b, ps in edges:
            if a not in times:
                stats["unreached" + key] += 1
                if key == "Connections":
                    omitted[launch_origin(a)] += 1
                continue
            if a[0] not in observed or b[0] not in observed:
                stats["unobserved" + key] += 1
                continue
            pair = a[1], b[1]
            pid = ports.setdefault(pair, len(ports))
            pin_ids.extend(struct.pack("<H", pid))
            rows.extend(
                ROW.pack(
                    observed[a[0]],
                    observed[b[0]],
                    times[a] / 1000,
                    (times[a] + ps) / 1000,
                )
            )
            stats["timed" + key] += 1
    coverage = dict(stats)
    if omitted:
        coverage["omittedLaunches"] = dict(omitted)
    if registered_products:
        coverage["registeredProducts"] = sorted(registered_products)
    return rows, list(ports), pin_ids, coverage


def publish(gallery: Path, run: Path, router: Path, chipdb: Path, output: Path) -> None:
    """Run the pinned SDF writer on the existing placement and add a separately identified timing layer."""
    work = json.loads((gallery / "workload.json").read_bytes())
    receipt = json.loads((run / "capture.json").read_bytes())
    checkpoint = run / "native/placed.json"
    require(
        work["flow"]["schema"] == 1
        and receipt["nativeStage"] == "placed"
        and digest(checkpoint)
        == receipt["files"]["native/placed.json"]
        == work["checkpoints"]["openxc7"]
        and digest(router) == receipt["tools"]["nextpnr"]
        and digest(chipdb) == receipt["tools"]["chipdb"],
        "placement or tool identity",
    )
    require(not output.exists(), "output exists")
    with tempfile.TemporaryDirectory(dir=output.parent) as temp:
        stage = Path(temp)
        sdf = stage / "placed.sdf"
        subprocess.run(
            [
                router,
                "--chipdb",
                chipdb,
                "--json",
                checkpoint,
                "--no-pack",
                "--no-place",
                "--no-route",
                "--freq",
                str(1000 / work["period"]),
                "--seed",
                str(receipt["seed"]),
                "--timing-allow-fail",
                "--sdf",
                sdf,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        names = inventory(gallery, work["backends"]["openxc7"]["names"])
        rows, ports, pins, coverage = placed_rows(
            json.loads(checkpoint.read_bytes())["modules"]["top"], sdf, names
        )
        dest = stage / "gallery"
        shutil.copytree(gallery, dest)
        work["flow"]["openxc7"]["estimate"] = dict(
            **coverage,
            sdf=digest(sdf),
            checkpoint=work["checkpoints"]["openxc7"],
            edges=asset(dest, "openxc7-placed-edges", rows),
            ports=ports,
            pins=asset(dest, "openxc7-placed-pins", pins),
        )
        (dest / "workload.json").write_text(
            json.dumps(work, separators=(",", ":")) + "\n"
        )
        dest.rename(output)
        print(json.dumps(coverage, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("gallery", "run", "router", "chipdb", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    publish(**vars(parser.parse_args()))
