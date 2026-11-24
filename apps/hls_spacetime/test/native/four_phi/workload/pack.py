"""Publish synchronized RTL handshakes and per-cycle mapped switching on one XC7 tile grid."""

import argparse
import gzip
import json
import mmap
import re
import shutil
import tempfile
import struct
import sys
from collections import Counter
from pathlib import Path

from execution import CYCLES, digest, require
from measure import observations

sys.path.insert(0, str(Path(__file__).resolve().parents[5] / "hls_target/priv/tools"))
from openxc7_chipdb import ChipGrid
from capture import VENDOR
from vivado import properties
from scopes import links

CHUNK = 128


def asset(out: Path, name: str, data: bytes) -> dict:
    """Write a compressed, hash-addressed-by-manifest asset for browser verification."""
    path = out / (name + ".gz")
    path.write_bytes(gzip.compress(data, compresslevel=4, mtime=0))
    return dict(file=path.name, sha256=digest(path))


def logical(work: Path, out: Path) -> tuple[dict, list]:
    """Validate reset, backpressure, frames and digest. Encode four-state pre-edge probes."""
    units = json.loads((work / "rtl/units.json").read_text())
    probes = sum(len(u["signals"]) for u in units)
    require(units[-1]["kind"] == "Output", "public probe order")
    observations, frames, expected, ram_events = bytearray(), [], [], []
    lines = (work / "rtl/cycles.txt").read_text().splitlines()
    require(lines[CYCLES] == f"END {CYCLES}", "RTL footer")
    captures, held, valid_capture, checksum = [0, 0], [None, None], 0, 0
    flow = 0x13579BDF
    mask = (1 << 32) - 1
    kinds = {0x03000011: "Status", 0x0300000B: "Correction"}
    ram_bits = [
        i
        for i, (kind, _) in enumerate(
            (u["kind"], s) for u in units for s in u["signals"]
        )
        if kind == "RAM"
    ]
    for cycle, line in enumerate(lines[:CYCLES]):
        label, reset, valid, ready, x, z, *fields = line.split()
        require(
            int(label) == cycle and reset == str(int(cycle >= 4)), "reset alignment"
        )
        require(fields[-1] == str(checksum & 1), f"RTL digest at C{cycle}")
        require(
            len(valid) == len(ready) == probes and len(fields) == len(ram_bits) + 1,
            "RTL width",
        )
        for s in (valid, ready):
            known, high = (
                int("".join("1" if c in chars else "0" for c in s), 2)
                for chars in ("01", "1")
            )
            require(
                cycle < 4 or known.bit_count() == probes, f"unknown control at C{cycle}"
            )
            for value in (high, known):
                observations.extend(value.to_bytes((probes + 7) // 8, "little"))
        for i, bit in enumerate(ram_bits):
            if reset == "1" and valid[-1 - bit] == "1":
                ram_events.append([cycle, bit, int(fields[i], 16)])
        previous_valid = valid_capture
        previous_flow = flow
        require(
            ready[1] == str(int(bool(flow & 3)))
            and ready[0] == str(int(bool(flow & 12))),
            "sink readiness",
        )
        feedback = ((flow >> 31) ^ (flow >> 21) ^ (flow >> 1) ^ flow) & 1
        flow = ((flow << 1) | feedback) & mask
        old = captures.copy()
        checksum = ((checksum << 1) | (checksum >> 31)) & mask
        for value in old:
            for shift in range(0, 128, 32):
                checksum ^= (value >> shift) & mask
        checksum ^= valid_capture
        valid_capture = 0
        for plane, payload in enumerate((x, z)):
            v, r = valid[1 - plane], ready[1 - plane]
            if reset == "0":
                continue
            require(
                held[plane] is None or (v == "1" and held[plane] == payload),
                "frame changed under backpressure",
            )
            held[plane] = payload if v == "1" and r == "0" else None
            if v != "1":
                continue
            value = int(payload, 16)
            captures[plane] = value
            valid_capture |= 1 << (1 - plane)
            if r == "1":
                cx, cy = (value >> 32) & 65535, (value >> 48) & 65535
                require(
                    cx < 2 and cy == 0 and value >> 96 in kinds,
                    "unexpected public frame",
                )
                frames.append(
                    dict(
                        cycle=cycle,
                        plane="XZ"[plane],
                        x=cx,
                        y=cy,
                        step=value & mask,
                        kind=kinds[value >> 96],
                        value=(value >> 64) & mask,
                        hex=payload,
                    )
                )
        expected.append(
            (
                checksum & 1,
                [a ^ b for a, b in zip(captures, old)]
                + [previous_valid ^ valid_capture, previous_flow ^ flow],
            )
        )
    require(len({(f["plane"], f["x"]) for f in frames}) == 4, "planes and coordinates")
    return dict(
        units=units,
        probes=probes,
        streams=asset(out, "logical", observations),
        frames=frames,
        ram=ram_events,
    ), expected


def placement(run: Path, work: Path, backend: str) -> tuple[dict, dict, dict]:
    """Read physical cell identities and recover observable public capture register lanes."""
    if backend == "vivado":
        placed = {}
        lanes = {}
        for line in (work / "locations.tsv").read_text().splitlines():
            name, kind, site, _bel = line.split("\t")
            require(name not in placed, "duplicate Vivado placement")
            placed[name] = (kind, site)
            if m := re.fullmatch(r"([xz])_capture_reg\[(\d+)\]", name):
                require(kind == "FDRE", "capture register type")
                lanes[("xz".index(m[1]), int(m[2]))] = name
            if m := re.fullmatch(r"(valid_capture|flow)_reg\[([0-3])\]", name):
                require(kind == "FDRE", "handshake register type")
                lanes[(2 if m[1] == "valid_capture" else 3, int(m[2]))] = name
        for name, props in properties(
            (run / VENDOR / "hard-primitives.rpt").read_text()
        ).items():
            require(
                placed[name] == (props["REF_NAME"], props["LOC"]),
                "hard primitive property " + name,
            )
        return placed, lanes, {}
    syn = json.loads((run / "native/synth.json").read_bytes())["modules"][
        "phi_timing_harness"
    ]
    cells = {n: c["type"] for n, c in syn["cells"].items() if c["type"] != "$scopeinfo"}
    drivers = {
        c["connections"]["Q"][0]: n
        for n, c in syn["cells"].items()
        if c["type"] == "FDRE"
    }
    lanes = {
        (plane, i): drivers[bit]
        for plane, p in enumerate("xz")
        for i, bit in enumerate(syn["netnames"][p + "_capture"]["bits"])
        if bit in drivers
    }
    for group, name, width in ((2, "valid_capture", 2), (3, "flow", 4)):
        for i, bit in enumerate(syn["netnames"][name]["bits"][:width]):
            lanes[(group, i)] = drivers[bit]
    packed = json.loads((run / "native/placed.json").read_bytes())["modules"]["top"][
        "cells"
    ]
    placed = {
        n: (
            c["attributes"].get("X_ORIG_TYPE", c["type"]),
            c["attributes"]["NEXTPNR_BEL"].split("/")[0],
        )
        for n, c in packed.items()
    }
    # The packer converts one-input inverters to a LUT with truth table 01.
    # IO splitting retains the original cell name as the prefix of the buffer.
    for name, kind in cells.items():
        if kind == "INV" and name in packed:
            c = packed[name]
            require(
                placed[name][0] == "LUT1"
                and c["parameters"]["INIT"] == "01"
                and c["attributes"]["src"] == syn["cells"][name]["attributes"]["src"],
                "inverter " + name,
            )
            placed[name] = (kind, placed[name][1])
        elif kind in ("IBUF", "OBUF"):
            packed_name = name + "$intcell$" + kind
            require(
                name not in placed and placed[packed_name][0] == kind,
                "IO split " + name,
            )
            placed[name] = placed.pop(packed_name)
    return placed, lanes, cells


def mapped(
    run: Path, work: Path, out: Path, backend: str, grid: ChipGrid, expected: list
) -> dict:
    """Bind simulated outputs by exact name/type to placement and check each clock against the RTL."""
    placed, lanes, synthetic = placement(run, work, backend)
    cells = [
        line.split("\t")
        for line in (work / backend / "cells.tsv").read_text().splitlines()
    ]
    count = len(cells)
    require(0 < count <= 150000 and len(dict(cells)) == count, "cell inventory")
    if synthetic:
        require(dict(cells) == synthetic, "simulation omitted mapped synthesis cells")
    units = json.loads((work / "rtl/units.json").read_text())
    scopes = links(backend, run, units, cells)
    scopes.update({name: len(units) - 1 for name in lanes.values()})
    kinds = sorted(set(kind for _, kind in cells))
    indexes = {n: i for i, (n, _) in enumerate(cells)}
    checks = [(p, b, indexes[n]) for (p, b), n in lanes.items()]
    require(
        all(any(p == side for p, b, i in checks) for side in [0, 1]),
        "both plane registers",
    )
    require(
        sum(p >= 2 for p, b, i in checks) == 6, "qualified valid and ready registers"
    )
    occupied = Counter()
    for kind, site in placed.values():
        if kind not in ("<PORT>", "<LOCKED>"):
            occupied[grid.owners[site]] += 1
    catalogue = bytearray()
    missing, matched = Counter(), set()
    for name, kind in cells:
        tile = -1
        if name in placed and placed[name][0] == kind:
            matched.add(name)
            tile = grid.owners[placed[name][1]]
        else:
            missing[kind] += 1
        catalogue.extend(
            struct.pack("<iBh", tile, kinds.index(kind), scopes.get(name, -1))
        )
    require(
        not missing, f"{backend} simulation cells missing from placement: {missing}"
    )
    extras = Counter(kind for n, (kind, site) in placed.items() if n not in matched)
    if backend == "vivado":
        require(set(extras) <= {"<PORT>", "<LOCKED>"}, "unobserved Vivado primitive")
    initial = (work / backend / "initial-q.txt").read_text()
    require(len(initial) == count, "C0 register inventory")
    # Apply the first rising edge to the original harness registers' reset-time values.
    values = [a ^ b for a, b in zip((0, 0, 0, 0x13579BDF), expected[0][1])]
    for group, bit, cell in checks:
        require(
            initial[cell] == str((values[group] >> bit) & 1),
            f"{backend} C0 register value at {cells[cell][0]}",
        )
    stage = "vivado" if backend == "vivado" else "native"
    logs = (work / (stage + "-sim-guard") / "console.log").read_text().splitlines()
    require(f"OBSERVED {CYCLES} {count}" in logs, "mapped simulation footer")
    activity = [v.split() for v in logs if re.fullmatch(r"\d+ [01xz]", v)]
    require(len(activity) == CYCLES, "mapped cycle count")
    step = (count + 7) // 8
    chunks, changed, unknown = [], [], []
    ever_changed = ever_unknown = 0
    with (work / backend / "changes.bin").open("rb") as f:
        for begin in range(0, CYCLES, CHUNK):
            raw = f.read(step * 2 * CHUNK)
            require(len(raw) == step * 2 * CHUNK, "truncated transition masks")
            chunks.append(asset(out, f"{backend}-{begin}", raw))
            for offset in range(CHUNK):
                cycle = begin + offset
                start = offset * step * 2
                change = raw[start : start + step]
                x = raw[start + step : start + 2 * step]
                known_mask = int.from_bytes(change, "little")
                unknown_mask = int.from_bytes(x, "little")
                changed.append(known_mask.bit_count())
                unknown.append(unknown_mask.bit_count())
                if cycle:
                    ever_changed |= known_mask
                    ever_unknown |= unknown_mask
                bit, deltas = expected[cycle]
                require(
                    activity[cycle] == [str(cycle), str(bit)],
                    f"{backend} activity at C{cycle}",
                )
                if cycle:
                    for p, b, i in checks:
                        require(
                            not (x[i // 8] >> (i % 8) & 1)
                            and change[i // 8] >> (i % 8) & 1 == deltas[p] >> b & 1,
                            f"{backend} {('X', 'Z', 'valid', 'flow')[p]} bit {b} at C{cycle}",
                        )
            if not begin:
                require(changed[0] == 0 and unknown[0] == count, "baseline mask")
        require(not f.read(1), "extra transition masks")
    return dict(
        cells=count,
        mapped=len(matched),
        unplaced=dict(missing),
        placementOnly=dict(extras),
        captureLanes=[sum(p == side for p, b, i in checks) for side in [0, 1]],
        captureRegisters=[
            len({i for p, _, i in checks if p == side}) for side in [0, 1]
        ],
        controlLanes=6,
        kinds=kinds,
        occupancy=sorted(occupied.items()),
        catalogue=asset(out, backend + "-cells", catalogue),
        names=asset(out, backend + "-names", "\n".join(n for n, _ in cells).encode()),
        scoped=sum(n in scopes for n, _ in cells),
        entire=asset(
            out,
            backend + "-entire",
            ever_changed.to_bytes(step, "little")
            + ever_unknown.to_bytes(step, "little"),
        ),
        everChanged=ever_changed.bit_count(),
        chunks=chunks,
        changed=changed,
        unknown=unknown,
    )


def build_gallery(
    run: Path, work: Path, database: Path, detail: Path, out: Path
) -> None:
    """Authenticate the matched build, then publish a manifest only after both replays pass."""
    receipt = json.loads((run / "capture.json").read_text())
    measured = json.loads((work / "measurement.json").read_text())
    require(
        measured
        == dict(capture=digest(run / "capture.json"), observations=observations(work)),
        "measurements differ from their capture",
    )
    require(
        receipt["nativeStage"] == "placed"
        and digest(database) == receipt["tools"]["chipdb"],
        "physical database",
    )
    for name, sha in receipt["files"].items():
        require(digest(run / name) == sha, "build identity " + name)
    rtl, expected = logical(work, out)
    with (
        database.open("rb") as f,
        mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        require(grid.part == receipt["part"] == "xc7z030sbg485-1", "chipdb part")
        backends = {
            b: mapped(run, work, out, b, grid, expected) for b in ("vivado", "openxc7")
        }
        tiles = {
            i: grid.tile_names[i] for b in backends.values() for i, _ in b["occupancy"]
        }
        manifest = dict(
            schema=1,
            cycles=CYCLES,
            chunk=CHUNK,
            part=receipt["part"],
            period=receipt["periodNs"],
            checkpoints={
                b: receipt["files"][k]
                for b, k in (
                    ("vivado", str(VENDOR / "routed.dcp")),
                    ("openxc7", "native/placed.json"),
                )
            },
            width=grid.width,
            height=grid.count // grid.width,
            tiles=tiles,
            logical=rtl,
            backends=backends,
        )
    (out / "workload.json").write_text(
        json.dumps(manifest, separators=(",", ":")) + "\n"
    )

    index = json.loads((detail / "index.json").read_text())
    require(
        {e["file"] for e in index["examples"]} == {"vivado.json", "openxc7.json"},
        "transaction index",
    )
    for entry in index["examples"]:
        source = detail / entry["file"]
        require(digest(source) == entry["sha256"], "transaction recording")
        key = (
            str(VENDOR / "routed.dcp")
            if source.name == "vivado.json"
            else "native/placed.json"
        )
        require(
            json.loads(source.read_bytes())["hardwarePath"]["checkpoint"]
            == receipt["files"][key],
            "transaction checkpoint",
        )
        shutil.copyfile(source, out / source.name)
    index["workload"] = "four-phi"
    (out / "index.json").write_text(json.dumps(index) + "\n")


def publish(run: Path, work: Path, database: Path, detail: Path, out: Path) -> None:
    """Install a complete, validated gallery at a fresh path on the staging filesystem."""
    require(not out.exists(), "fresh publication directory required")
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as tmp:
        staged = Path(tmp) / "gallery"
        staged.mkdir()
        build_gallery(run, work, database, detail, staged)
        staged.rename(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("run", "work", "database", "detail", "out"):
        parser.add_argument(key, type=Path)
    publish(**vars(parser.parse_args()))
