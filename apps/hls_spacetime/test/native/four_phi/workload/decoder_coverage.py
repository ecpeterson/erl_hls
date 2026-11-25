"""Publish clock-launched Phi paths, packed buffer activity and measured hard-block outputs together."""

import argparse
from collections import defaultdict
import json
import mmap
from pathlib import Path
import shutil
import struct
import tempfile

from pack import ChipGrid, asset, digest, require
from packed_buffers import append_buffers, folded_ground, input_sources
from pin_activity import attach_pins, bindings, native_pins, read_asset, replay_pins
from placed_flow import placed_rows
from routed_flow import NEXTPNR_COMMIT, ROW, WireNames, geometry


def direct_operand(gallery: Path, replay: dict, backend: str, model: dict) -> dict:
    """Index the verified transaction's RAM clock through its first DSP operand on a single clock interval."""
    path = json.loads((gallery / f"{backend}.json").read_bytes())["hardwarePath"]
    require(
        path["checkpoint"] == replay["checkpoints"][backend], "transaction checkpoint"
    )
    capture = replay["backends"][backend]
    names = read_asset(gallery, capture["names"]).decode().splitlines()
    ids = {name: i for i, name in enumerate(names)}
    cells = read_asset(gallery, capture["catalogue"])
    required = []
    for src, sink in zip(path["steps"], path["steps"][1:]):
        a, z = ids[src["cell"]], ids[sink["cell"]]
        kind = capture["kinds"][cells[a * 7 + 4]]
        require(
            kind.startswith("RAMB") if not required else kind.startswith(("LUT", "MUX", "CARRY")),
            "storage boundary on direct operand path",
        )
        pin = src["input"] or model["selected"][0]["cellInput"]
        required.extend(
            ((a, pin, a, src["output"]), (a, src["output"], z, sink["input"]))
        )
        if capture["kinds"][cells[z * 7 + 4]] == "DSP48E1":
            break
    else:
        raise ValueError("missing DSP on selected path")
    lookup = dict.fromkeys(required)
    pins = read_asset(gallery, model["pins"])
    edges = read_asset(gallery, model["edges"])
    for i, (a, z, _, _) in enumerate(ROW.iter_unpack(edges)):
        src, sink = model["ports"][struct.unpack_from("<H", pins, 2 * i)[0]]
        key = a, src, z, sink
        if key in lookup:
            require(lookup[key] is None, "ambiguous selected timing row")
            lookup[key] = i
    rows = [lookup[key] for key in required]
    require(all(row is not None for row in rows), "incomplete selected timing rows")
    activity = model["outputActivity"]
    lanes = read_asset(gallery, activity["rows"])
    changes = read_asset(gallery, activity["changes"])
    stride = (activity["count"] + 7) // 8
    transitions = {}
    for label, row in (("ram", rows[1]), ("dsp", rows[-1])):
        (lane,) = struct.unpack_from("<h", lanes, 2 * row)
        require(lane >= 0, "selected path endpoint has no pin replay")
        transitions[label] = [
            cycle
            for cycle in range(replay["cycles"])
            if changes[cycle * stride + lane // 8] & (1 << (lane % 8))
        ]
    return dict(rows=rows, transitions=transitions)


def routed_assets(
    args: argparse.Namespace,
    gallery: Path,
    top: dict,
    grid: ChipGrid,
    names: list[str],
    edges: bytes,
    ports: list,
    pins: bytes,
    count: int,
    previous: dict,
    path: dict,
) -> dict:
    """Retrace each drawn branch and compare its SDF increment with the exported wire/PIP sum."""
    require(
        args.fixed
        and args.constids
        and args.wire_delays
        and previous.get("routedLutTiming")
        and digest(args.fixed) == previous["fixed"]
        and digest(args.sdf) == previous["sdf"],
        "routed delay and switch capture",
    )
    bound = defaultdict(dict)
    with args.wire_delays.open() as stream:
        for line in stream:
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "S":
                continue  # Earlier probes also recorded a sink-query cross-check.
            tag, net, wire, ps = fields
            require(tag == "W" and wire not in bound[net], "wire delay identity")
            bound[net][wire] = int(ps)
    sums = bytearray(4 * count)

    def measure(i: int, net: str, steps: list | None) -> None:
        """Store the sum in row order, allowing one ps for SDF serialization."""
        require(steps is not None, "unresolved routed branch on " + net)
        ps = sum(bound[net][wire] for wire in steps)
        _, _, start, end = ROW.unpack_from(edges, ROW.size * i)
        require(abs(round((end - start) * 1000) - ps) <= 1, "switch sum on " + net)
        struct.pack_into("<I", sums, 4 * i, ps)

    routes, classes, coverage, selected = geometry(
        top,
        WireNames(grid, args.constids, NEXTPNR_COMMIT),
        args.fixed,
        names,
        edges,
        ports,
        pins,
        count,
        path,
        previous["routeResult"],
        measure,
    )
    for actual, saved in zip(selected, previous["selected"], strict=True):
        require(
            all(
                json.loads(json.dumps(value)) == saved[key]
                for key, value in actual.items()
            ),
            "selected physical route changed",
        )
    return dict(
        routedLutTiming=True,
        selected=previous["selected"],
        fixed=previous["fixed"],
        routeResult=previous["routeResult"],
        coverage=coverage,
        routes=asset(gallery, "openxc7-switches", routes),
        delayClass=asset(gallery, "openxc7-route-class", classes),
        switchSumPs=asset(gallery, "openxc7-switch-sums-ps", sums),
    )


def rebuild_timing(
    args: argparse.Namespace,
    gallery: Path,
    top: dict,
    grid: ChipGrid,
    names: list[str],
    previous: dict,
    flow: dict,
    replay: dict,
    ground: set[str],
) -> dict:
    """Replace native timing and its row-indexed assets as a unit on the same checkpoint."""
    routed = "routed" in flow
    rows, ports, pins, stats = placed_rows(
        top, args.sdf, names, routed=routed, ground=ground
    )
    stage = "routed" if routed else "placed"
    model = dict(
        **stats,
        sdf=digest(args.sdf),
        checkpoint=previous["checkpoint"],
        edges=asset(gallery, f"openxc7-{stage}-edges", rows),
        ports=ports,
        pins=asset(gallery, f"openxc7-{stage}-pins", pins),
    )
    if args.sdf_build:
        receipt = json.loads(args.sdf_build.read_bytes())
        model["sdfProducer"] = dict(
            revision=receipt["commit"],
            executable=receipt["sha256"]["nextpnr-spacetime"],
            buildReceipt=digest(args.sdf_build),
        )
    if args.lut_config:
        model["foldedGround"] = dict(
            cells=len(ground), configuration=digest(args.lut_config)
        )
    if routed:
        model.update(
            routed_assets(
                args,
                gallery,
                top,
                grid,
                names,
                rows,
                ports,
                pins,
                stats["timedConnections"],
                previous,
                replay["selectedPath"],
            )
        )
    flow["routed" if routed else "estimate"] = model
    return model


def publish(args: argparse.Namespace) -> None:
    """Join a timing export in synthesis-then-buffer order to the matching settled pin replays."""
    require(not args.output.exists(), "output exists")
    capture = json.loads(args.capture.read_bytes())
    require(digest(args.chipdb) == capture["tools"]["chipdb"], "chip database identity")
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        gallery = Path(tmp) / "gallery"
        shutil.copytree(args.gallery, gallery)
        manifest = gallery / "workload.json"
        replay = json.loads(manifest.read_bytes())
        checkpoint = digest(args.checkpoint)
        require(
            checkpoint
            == replay["checkpoints"]["openxc7"]
            == capture["files"]["native/" + capture["nativeStage"] + ".json"],
            "native checkpoint identity",
        )
        top = json.loads(args.checkpoint.read_bytes())["modules"]["top"]
        cells = top["cells"]
        ground = set()
        if args.lut_config:
            require(
                capture["nativeStage"] == "routed"
                and digest(args.lut_config) == capture.get("lutConfigurationSha256"),
                "routed LUT configuration identity",
            )
            with (
                args.chipdb.open("rb") as fp,
                mmap.mmap(fp.fileno(), 0, access=mmap.ACCESS_READ) as db,
            ):
                ground = folded_ground(cells, ChipGrid(db), args.lut_config)
        for backend, folder in (
            ("openxc7", args.native_pins),
            ("vivado", args.vivado_pins),
        ):
            flow, b = replay["flow"][backend], replay["backends"][backend]
            names = read_asset(gallery, b["names"]).decode().splitlines()
            native = backend == "openxc7"
            model = flow.get("routed", flow.get("estimate")) if native else flow
            packed = cells if native else None
            if native:
                require(checkpoint == model["checkpoint"], "native timing checkpoint")
                sources = input_sources(cells, names, ground)
                expected = native_pins(names, cells)
            else:
                sources = {}
                _, expected, _ = bindings(gallery, b, model, None)
            receipt = json.loads((folder / "checked.json").read_bytes())
            require(
                receipt["checkpoint"] == replay["checkpoints"][backend]
                and receipt["publicClocks"] == replay["cycles"]
                and receipt["pins"] == digest(folder / "pins.json")
                and receipt["samples"] == digest(folder / "pins.txt"),
                "pin replay identity",
            )
            pins = [
                tuple(row) for row in json.loads((folder / "pins.json").read_bytes())
            ]
            require(
                len(pins) == len(expected) and set(pins) == set(expected),
                "functional monitor pin inventory",
            )
            values, changes = replay_pins(
                gallery,
                replay,
                backend,
                pins,
                folder / "pins.txt",
                set(sources.values()),
            )
            if native:
                with (
                    args.chipdb.open("rb") as fp,
                    mmap.mmap(fp.fileno(), 0, access=mmap.ACCESS_READ) as db,
                ):
                    grid = ChipGrid(db)
                    require(
                        grid.part == replay["part"] and grid.width == replay["width"],
                        "grid identity",
                    )
                    physical = append_buffers(
                        gallery, replay, cells, grid, values, sources
                    )
                    model = rebuild_timing(
                        args, gallery, top, grid, physical, model, flow, replay, ground
                    )
                model["identityBuffers"] = len(sources)
            attach_pins(
                gallery, b, model, packed, replay["checkpoints"][backend], pins, changes
            )
            selected = replay.get("selectedPath", {}).get("steps", [])
            if selected and "routed" in replay["flow"]["openxc7"] and all(
                step["kind"] != "SLICE_FFX" for step in selected
            ):
                model["directOperand"] = direct_operand(gallery, replay, backend, model)
        manifest.write_text(json.dumps(replay, separators=(",", ":")) + "\n")
        gallery.rename(args.output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in (
        "gallery",
        "sdf",
        "capture",
        "checkpoint",
        "chipdb",
        "native-pins",
        "vivado-pins",
        "output",
    ):
        parser.add_argument("--" + option, type=Path, required=True)
    for option in ("fixed", "wire-delays", "constids", "sdf-build", "lut-config"):
        parser.add_argument("--" + option, type=Path)
    publish(parser.parse_args())
