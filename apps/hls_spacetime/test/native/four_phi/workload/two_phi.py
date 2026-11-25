"""Publish the routed two-worker X-plane decoder and its matched functional replay."""

import argparse
import json
import mmap
import tempfile
from pathlib import Path

from flow import inventory
from openxc7 import connected_path, pins
from pack import CHUNK, CYCLES, ChipGrid, digest, logical, mapped, require
from routed_flow import flow_model

NATIVE = ("synth.json", "routed.json", "routing.log", "fixed-routes.txt", "routed.sdf")
OBSERVATIONS = (
    "rtl/units.json",
    "rtl/cycles.txt",
    "rtl-sim-guard/console.log",
    "native-sim-guard/console.log",
    "openxc7/cells.tsv",
    "openxc7/changes.bin",
    "openxc7/initial-q.txt",
    "selected-observations.json",
    "native-pins.sv",
    "rtl-pins.sv",
)


def selected_path(synth: dict, top: dict) -> dict:
    """Trace scheduler state bit 84 through the packed capture FF to a mapped arithmetic DSP."""
    memory = "decoder.scheduler_1_state"
    read = synth["netnames"][memory + ".rd_data"]["bits"]
    require(
        read == synth["netnames"][memory + "_rd_data"]["bits"], "scheduler read alias"
    )
    drivers = [
        (n, f"{port}[{lane}]")
        for n, c in synth["cells"].items()
        if c["type"].startswith("RAMB")
        for port, lane, bit in pins(c, "output")
        if bit == read[84]
    ]
    require(len(drivers) == 1, "state bit 84 BRAM driver")
    targets = {
        n
        for n, c in synth["cells"].items()
        if c["type"] == "DSP48E1"
        and c["connections"]["CLK"] == ["0"]
        and "mul2dsp.v:" in c["attributes"].get("src", "")
    }
    steps = connected_path(top, *drivers[0], targets, allow_capture=True)
    require(
        sum(s["kind"] == "SLICE_FFX" for s in steps) == 1,
        "expected one capture boundary",
    )
    return dict(memory=memory, bit=84, steps=steps)


def pin_changes(work: Path, top: dict, path: dict) -> dict:
    """Match each sampled output to its original Verilog pin and count known adjacent transitions."""
    steps = path["steps"]
    capture = next(s for s in steps if s["kind"] == "SLICE_FFX")
    probes = (
        (steps[0], steps[0]["output"]),
        (capture, "Q"),
        (steps[-1], steps[-1]["input"]),
    )
    monitor = (work / "native-pins.sv").read_text()
    for step, port in probes:
        original = top["cells"][step["cell"]]["attributes"].get(
            "X_ORIG_PORT_" + port, port
        )
        require(f"\\{step['cell']} .{original}" in monitor, "selected physical pin")
    require(
        f".{path['memory']}.rd_data[{path['bit']}]"
        in (work / "rtl-pins.sv").read_text(),
        "selected logical lane",
    )
    rows = [
        line.split()
        for line in (work / "native-sim-guard/console.log").read_text().splitlines()
        if line.startswith("PINS ")
    ]
    require(
        [int(row[1]) for row in rows] == list(range(CYCLES)),
        "selected pin observation clocks",
    )
    changes = {
        key: [
            c
            for c in range(1, CYCLES)
            if {rows[c - 1][col], rows[c][col]} == {"0", "1"}
        ]
        for key, col in (("ram", 2), ("q", 6), ("dsp", 7))
    }
    activity = json.loads((work / "selected-observations.json").read_bytes())
    require(
        activity["bit"] == path["bit"]
        and activity["afterWriteReads"] > 0
        and changes == activity["transitions"],
        "state lane replay",
    )
    return changes


def build(run: Path, work: Path, chipdb: Path, constids: Path, out: Path) -> list:
    """Export the native witness and return its cycle-by-cycle reference for a matched replay."""
    receipt = json.loads((run / "capture.json").read_bytes())
    measured = json.loads((work / "bound-measurement.json").read_bytes())
    require(
        measured
        == dict(
            capture=digest(run / "capture.json"),
            observations={n: digest(work / n) for n in OBSERVATIONS},
        ),
        "measurement identity",
    )
    require(
        receipt["nativeStage"] == "routed"
        and digest(chipdb) == receipt["tools"]["chipdb"],
        "routed chip database",
    )
    for name, sha in receipt["files"].items():
        require(
            (run / name).stat().st_size <= 512 << 20 and digest(run / name) == sha,
            "capture file " + name,
        )
    paths = {n: run / "native" / n for n in NATIVE}
    require(
        all("native/" + n in receipt["files"] for n in paths),
        "missing implementation input",
    )
    profile = json.loads((run / "profile.json").read_bytes())
    require(
        (
            profile["planes"],
            profile["width"],
            profile["height"],
            profile["phi_actor_count"],
            profile["scheduler_count"],
        )
        == (["x"], 2, 1, 2, 2),
        "decoder geometry",
    )
    top = json.loads(paths["routed.json"].read_bytes())["modules"]["top"]
    require(
        float(top["settings"]["target_freq"]) == 50e6
        and int(top["settings"]["seed.arg"], 2) == 1,
        "native clock and seed",
    )
    for cell, pad in (("clock", "Y14"), ("activity", "V13")):
        require(
            top["cells"][cell]["attributes"]["PACKAGE_PIN"] == pad, "native package pin"
        )
    synth = json.loads(paths["synth.json"].read_bytes())["modules"][
        "phi_timing_harness"
    ]
    path = selected_path(synth, top)
    del synth
    path["transitions"] = pin_changes(work, top, path)
    source, expected = logical(work, out, planes="X")
    with (
        chipdb.open("rb") as f,
        mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        require(grid.part == receipt["part"] == "xc7z030sbg485-1", "chip identity")
        backend = mapped(run, work, out, "openxc7", grid, expected, planes="X")
        model = flow_model(
            paths, top, inventory(out, backend["names"]), path, grid, constids, out
        )
        for step in path["steps"]:
            step["tile"] = grid.owners[step["site"]]
        tiles = {i: grid.tile_names[i] for i, _ in backend["occupancy"]}
        width, height = grid.width, grid.count // grid.width
    peak = max(range(1, CYCLES), key=lambda c: backend["changed"][c])
    replay = dict(
        schema=1,
        title="Two-Phi decoder",
        topologyLabel="X plane · 2 × 1 cells",
        transaction=False,
        part=receipt["part"],
        period=20,
        cycles=CYCLES,
        chunk=CHUNK,
        width=width,
        height=height,
        tiles=tiles,
        checkpoints={"openxc7": model["routed"]["checkpoint"]},
        logical=source,
        backends={"openxc7": backend},
        flow=dict(schema=1, defaultCycle=peak, openxc7=model),
        selectedPath=path,
    )
    (out / "workload.json").write_text(json.dumps(replay, separators=(",", ":")) + "\n")
    (out / "index.json").write_text(json.dumps(dict(workload="two-phi", flow=1)) + "\n")
    return expected


def publish(run: Path, work: Path, chipdb: Path, constids: Path, output: Path) -> None:
    """Install the viewer and index as a unit after validating the entire replay."""
    require(not output.exists(), "fresh publication directory required")
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        dest = Path(tmp) / "gallery"
        dest.mkdir()
        build(run, work, chipdb, constids, dest)
        dest.rename(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("run", "work", "chipdb", "constids", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    publish(**vars(parser.parse_args()))
