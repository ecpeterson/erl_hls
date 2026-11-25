"""Attach observed output-bit transitions to timed rows of a routed, paired Phi gallery."""

import argparse
import gzip
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from collections.abc import Iterator

from pack import asset, digest, require
from measure import check_models

HERE = Path(__file__).resolve().parent
OUTPUT = re.compile(r"(CO|O|P|PCOUT|ACOUT|BCOUT|DOADO|DOBDO|DOPADOP|DOPBDOP)\[\d+\]")


def sampled_output(kind: str, pin: str | None) -> bool:
    """Select the consumed output bit of a multi-output hard block or shift register."""
    if kind in ("SRL16E", "SRLC32E"):
        return pin == "Q" or (kind == "SRLC32E" and pin == "Q31")
    return kind.startswith(("DSP48", "RAMB", "CARRY4")) and bool(pin and OUTPUT.fullmatch(pin))


def read_asset(gallery: Path, ref: dict) -> bytes:
    """Read the exact compressed asset identified by the gallery manifest."""
    path = gallery / ref["file"]
    require(digest(path) == ref["sha256"], "gallery asset digest")
    return gzip.decompress(path.read_bytes())


def bindings(gallery: Path, backend: dict, model: dict, packed: dict | None) -> tuple:
    """Bind the driving output of each net and the result of each cell arc to a scalar model pin."""
    names = read_asset(gallery, backend["names"]).decode().splitlines()
    catalogue = read_asset(gallery, backend["catalogue"])
    pins = read_asset(gallery, model["pins"])
    edges = read_asset(gallery, model["edges"])
    require(
        len(catalogue) == len(names) * 7 and len(edges) == 8 * len(pins),
        "row inventory",
    )
    selected, mapping = {}, bytearray()
    for i, (a, b, _, _) in enumerate(struct.iter_unpack("<IIff", edges)):
        ap, bp = model["ports"][struct.unpack_from("<H", pins, i * 2)[0]]
        cell, port = (a, ap) if i < model["timedConnections"] else (b, bp)
        kind = backend["kinds"][catalogue[cell * 7 + 4]]
        lane = -1
        if kind.startswith(("DSP48", "RAMB", "CARRY4", "SRL")):
            name, logical = names[cell], port
            hierarchy = name.split("/")
            if packed is not None:
                attrs = packed[name]["attributes"]
                require(attrs["X_ORIG_TYPE"] == kind, "packed output primitive")
                logical = attrs.get("X_ORIG_PORT_" + port)
                hierarchy = [name]
            if sampled_output(kind, logical):
                path = ".".join("\\" + part + " " for part in hierarchy)
                key = cell, port, f"functional_tb.dut.{path}.{logical}"
                lane = selected.setdefault(key, len(selected))
        require(lane < 32767, "selected output count")
        mapping.extend(struct.pack("<h", lane))
    require(0 < len(selected) < 32768, "selected output count")
    return names, list(selected), mapping


def monitor(pins: list) -> str:
    """Sample settled, mapped output bits before the falling edge ends each harness clock."""
    lines = [
        "`timescale 1ns/1ps",
        "module lane_masks;",
        'integer f; initial f=$fopen("pins.txt","w");',
    ]
    for j in range(0, len(pins), 64):
        group = pins[j : j + 64]
        expr = ",".join(pin[2] for pin in reversed(group))
        lines.append(f"wire [{len(group) - 1}:0] q{j}={{{expr}}};")
    lines += ["always @(posedge functional_tb.clock) begin", "#9;"]
    for j in range(0, len(pins), 64):
        lines.append(f'$fwrite(f,"%b ",q{j});')
    return "\n".join(lines + [r'$fwrite(f,"\n"); end endmodule', ""])


def comparisons(samples: Path, count: int, cycles: int) -> Iterator[tuple[int, int]]:
    """Yield masks for known changes and unknown comparisons at each settled clock."""
    old = known = seen = 0
    full = (1 << count) - 1
    widths = [min(64, count - i) for i in range(0, count, 64)]
    with samples.open() as stream:
        for line in stream:
            groups = line.split()
            require(
                seen < cycles and list(map(len, groups)) == widths,
                "output sample width",
            )
            bits = "".join(reversed(groups))
            require(re.fullmatch("[01xz]+", bits), "four-state output sample")
            value = int(bits.translate(str.maketrans("xz", "00")), 2)
            valid = int(bits.translate(str.maketrans("01xz", "1100")), 2)
            yield (old ^ value) & known & valid, full ^ (known & valid)
            old, known = value, valid
            seen += 1
    require(seen == cycles, "output sample count")


def transitions(samples: Path, count: int, cycles: int) -> bytes:
    """Encode only known-to-known changes on consecutive clocks, with a zero baseline."""
    width = (count + 7) // 8
    return b"".join(
        mask.to_bytes(width, "little")
        for mask, _ in comparisons(samples, count, cycles)
    )


def replay_pins(
    gallery: Path,
    replay: dict,
    backend: str,
    pins: list,
    trace: Path,
    sources: set,
) -> tuple[dict, bytes]:
    """Check pin comparisons against original cell masks and retain four-state buffer inputs."""
    b = replay["backends"][backend]
    cycles = replay["cycles"]
    count, size = len(pins), (b["cells"] + 7) // 8
    require(
        0 < count < 32768 and len({(a, p) for a, p, _ in pins}) == count,
        "pin inventory",
    )
    width = (count + 7) // 8
    retained = {(a, p): bytearray() for a, p, _ in pins if (a, p) in sources}
    masks = bytearray()
    locations = [
        (a // 8, 1 << (a % 8), i // 8, 1 << (i % 8), retained.get((a, p)))
        for i, (a, p, _) in enumerate(pins)
    ]
    for cycle, (changed, unknown) in enumerate(comparisons(trace, count, cycles)):
        offset = cycle % replay["chunk"]
        if not offset:
            chunk = read_asset(gallery, b["chunks"][cycle // replay["chunk"]])
        start = 2 * size * offset
        cell_change = memoryview(chunk)[start : start + size]
        cell_unknown = memoryview(chunk)[start + size : start + 2 * size]
        change, x = changed.to_bytes(width, "little"), unknown.to_bytes(width, "little")
        masks.extend(change)
        for c, cb, i, bit, keep in locations:
            on, invalid = bool(change[i] & bit), bool(x[i] & bit)
            if (on and not cell_change[c] & cb) or (
                invalid and not cell_unknown[c] & cb
            ):
                raise ValueError(
                    f"pin and cell disagree at clock {cycle}, cell byte {c}, pin byte {i}"
                )
            if keep is not None:
                keep.append(on | (invalid << 1))
    return retained, bytes(masks)


def attach_pins(
    gallery: Path,
    backend: dict,
    model: dict,
    cells: dict | None,
    checkpoint: str,
    pins: list,
    changes: bytes,
) -> None:
    """Bind timed rows to measured logical pins by cell, port and HDL expression."""
    _, selected, mapping = bindings(gallery, backend, model, cells)
    indices = {tuple(pin): i for i, pin in enumerate(pins)}
    remap = [indices[pin] for pin in selected]
    for i, (lane,) in enumerate(struct.iter_unpack("<h", mapping)):
        if lane >= 0:
            struct.pack_into("<h", mapping, i * 2, remap[lane])
    key = "vivado" if cells is None else "openxc7"
    model["outputActivity"] = dict(
        checkpoint=checkpoint,
        count=len(indices),
        rows=asset(gallery, key + "-output-rows", mapping),
        changes=asset(gallery, key + "-output-changes", changes),
    )


def native_pins(names: list[str], cells: dict) -> list[tuple]:
    """Monitor all connected RAM, carry, DSP and SRL data outputs, including buffer drivers."""
    pins = []
    for i, name in enumerate(names):
        cell = cells.get(name)
        if cell is None:
            continue
        attrs = cell["attributes"]
        kind = attrs.get("X_ORIG_TYPE", cell["type"])
        for port, bits in cell["connections"].items():
            if not bits or cell["port_directions"][port] != "output":
                continue
            logical = attrs.get("X_ORIG_PORT_" + port)
            if sampled_output(kind, logical):
                pins.append((i, port, f"functional_tb.dut.\\{name} .{logical}"))
    return pins


def observe(
    gallery: Path,
    replay: dict,
    key: str,
    work: Path,
    stage: Path,
    packed: dict | None,
    models: Path,
    guard: Path,
) -> None:
    """Replay a fresh named-pin monitor, reconciling every original cell mask and public sample."""
    backend = replay["backends"][key]
    model = replay["flow"][key] if packed is None else replay["flow"][key]["routed"]
    names, pins, mapping = bindings(gallery, backend, model, packed)
    stage.mkdir()
    (stage / "pins.sv").write_text(monitor(pins))
    (stage / "pins.json").write_text(json.dumps(pins) + "\n")
    shutil.copyfile(work / key / "primitive-types.txt", stage / "primitive-types.txt")
    netlist = work / ("vendor-net.v" if packed is None else "native.v")
    subprocess.run(
        [
            sys.executable,
            guard,
            stage / "compile",
            "300",
            "iverilog",
            "-g2012",
            "-s",
            "functional_tb",
            "-s",
            "glbl",
            "-s",
            "lane_masks",
            "-o",
            "pins.vvp",
            "-y",
            models / "unisims",
            HERE / "functional_tb.sv",
            netlist,
            stage / "pins.sv",
            models / "glbl.v",
        ],
        cwd=stage,
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            guard,
            stage / "sim",
            "900",
            "vvp",
            "-M" + str(work),
            "-mtransitions",
            "pins.vvp",
        ],
        cwd=stage,
        check=True,
    )
    cells = (stage / "cells.tsv").read_text().splitlines()
    require(
        names == [row.split("\t")[0] for row in cells], "output observer cell order"
    )
    for file in ("cells.tsv", "changes.bin", "initial-q.txt"):
        require(
            digest(stage / file) == digest(work / key / file), "output replay " + file
        )
    reference = work / ("vivado-sim-guard" if packed is None else "native-sim-guard")
    clocks = [
        re.findall(r"^\d+ [01]$", (p / "console.log").read_text(), re.M)
        for p in (stage / "sim", reference)
    ]
    require(
        len(clocks[0]) == replay["cycles"] and clocks[0] == clocks[1],
        "output replay clocks",
    )
    with (stage / "changes.bin").open("rb") as stream:
        for ref in backend["chunks"]:
            chunk = read_asset(gallery, ref)
            require(
                stream.read(len(chunk)) == chunk, "output replay differs from gallery"
            )
        require(not stream.read(1), "extra cell observations")
    masks = transitions(stage / "pins.txt", len(pins), replay["cycles"])
    model["outputActivity"] = dict(
        checkpoint=replay["checkpoints"][key],
        count=len(pins),
        rows=asset(gallery, key + "-output-rows", mapping),
        changes=asset(gallery, key + "-output-changes", masks),
    )


def publish(args: argparse.Namespace) -> None:
    """Publish both backends atomically after observing their original mapped netlists."""
    require(
        not args.output.exists() and not args.stage.exists(),
        "fresh gallery and evidence directory",
    )
    check_models(args.models)
    args.stage.mkdir()
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        gallery = Path(tmp) / "gallery"
        shutil.copytree(args.gallery, gallery)
        manifest = gallery / "workload.json"
        replay = json.loads(manifest.read_bytes())
        require(
            digest(args.routed) == replay["checkpoints"]["openxc7"], "native checkpoint"
        )
        vendor = json.loads((args.vendor_work / "measurement.json").read_bytes())
        require(
            vendor["capture"]["routed.dcp"] == replay["checkpoints"]["vivado"],
            "Vivado checkpoint",
        )
        packed = json.loads(args.routed.read_bytes())["modules"]["top"]["cells"]
        for key, cells, work in (
            ("vivado", None, args.vendor_work),
            ("openxc7", packed, args.native_work),
        ):
            observe(
                gallery,
                replay,
                key,
                work,
                args.stage / key,
                cells,
                args.models,
                args.guard,
            )
        manifest.write_text(json.dumps(replay, separators=(",", ":")) + "\n")
        gallery.rename(args.output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in (
        "gallery",
        "vendor-work",
        "native-work",
        "routed",
        "guard",
        "models",
        "stage",
        "output",
    ):
        parser.add_argument(
            "--" + option, type=lambda s: Path(s).resolve(), required=True
        )
    publish(parser.parse_args())
