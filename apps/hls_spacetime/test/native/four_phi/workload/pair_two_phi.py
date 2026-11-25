"""Add a routed Vivado implementation to the replay of the same two-worker X-plane decoder."""

import argparse
import json
import mmap
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from flow import vivado, vendor_model
from measure import (
    DEVICE_DATA,
    HERE,
    RAPIDWRIGHT,
    UNISIM,
    check_models,
    simulate,
    vendor_netlist,
)
from pack import ChipGrid, digest, mapped, require
from capture import RTL
import two_phi
import vivado_lane

REPORTS = (
    "input-manifest.json",
    "routed.dcp",
    "routed.v",
    "routed.sdf",
    "effective.xdc",
    "hard-primitives.rpt",
    "route-status.rpt",
    "timing.rpt",
    "version.txt",
)
OBSERVATIONS = (
    "lane.sv",
    "vendor.edf",
    "locations.tsv",
    "vivado/cells.tsv",
    "vivado/changes.bin",
    "vivado/initial-q.txt",
    "vivado-sim-guard/console.log",
    "rtl/units.json",
)


def match(run: Path, vendor: Path) -> dict:
    """Require the two-pin, 20 ns routed Vivado result to identify the native run and all four RTL files."""
    cap = json.loads((run / "capture.json").read_text())
    manifest = json.loads((vendor / "input-manifest.json").read_text())
    require(
        manifest["part"] == cap["part"] == "xc7z030sbg485-1"
        and manifest["periodNs"] == cap["periodNs"] == 20
        and manifest["top"] == "phi_timing_harness"
        and manifest["nativeCapture"] == digest(run / "capture.json"),
        "Vivado and openXC7 capture identity",
    )
    require(
        {k: v for k, v in manifest["files"].items() if k.startswith("inputs/")}
        == {"inputs/phi/" + n: cap["files"][n] for n in RTL},
        "Vivado and openXC7 RTL inputs",
    )
    xdc = (vendor / "effective.xdc").read_text().splitlines()
    require(
        all(
            s in xdc
            for s in (
                "create_clock -period 20.000 -name workload [get_ports clock]",
                "set_property PACKAGE_PIN Y14 [get_ports clock]",
                "set_property PACKAGE_PIN V13 [get_ports activity]",
            )
        ),
        "effective Vivado clock and pins",
    )
    route = (vendor / "route-status.rpt").read_text()

    def count(label: str) -> int:
        """Read one named net total from report_route_status."""
        rows = re.findall(label + r"[^\n:]*:\s*(\d+)", route)
        require(len(rows) == 1, "Vivado route count " + label)
        return int(rows[0])

    require(
        count("routable nets") == count("fully routed nets") > 0
        and count("nets with routing errors") == 0,
        "incomplete Vivado route",
    )
    return {n: digest(vendor / n) for n in REPORTS}


def measure(
    run: Path,
    native_work: Path,
    vendor: Path,
    work: Path,
    java: Path,
    jar: Path,
    yosys: Path,
    models: Path,
    guard: Path,
) -> None:
    """Simulate the routed Vivado logic on the original functional bench and retain the DCP location inventory."""
    capture = match(run, vendor)
    check_models(models)
    require(digest(jar) == RAPIDWRIGHT, "RapidWright release")
    bound = json.loads((native_work / "bound-measurement.json").read_text())
    require(
        bound["capture"] == digest(run / "capture.json")
        and digest(native_work / "rtl/units.json")
        == bound["observations"]["rtl/units.json"],
        "native replay identity",
    )
    work.mkdir()
    (work / "rtl").mkdir()
    shutil.copyfile(native_work / "rtl/units.json", work / "rtl/units.json")

    def stage(name: str, args: list, cwd: Path = work, seconds: int = 1200) -> None:
        """Bound each stage separately and stop before recording an incomplete replay."""
        subprocess.run(
            [sys.executable, guard, work / (name + "-guard"), str(seconds), *args],
            cwd=cwd,
            check=True,
        )

    vendor_netlist(vendor, work, yosys, jar, str(java), stage)
    data = Path(os.environ["RAPIDWRIGHT_PATH"]) / "data"
    require(
        all(digest(data / n) == v for n, v in DEVICE_DATA.items()),
        "RapidWright device data",
    )
    stage("observer", ["iverilog-vpi", HERE / "transitions.cpp"])
    cells = [
        r.split("\t")[:2] for r in (work / "locations.tsv").read_text().splitlines()
    ]
    timing = vivado(vendor / "routed.sdf", [n for n, _ in cells])
    probes = vivado_lane.state_path(vendor, cells, *timing[:2])["probes"]
    (work / "lane.sv").write_text(vivado_lane.monitor(probes))
    del timing
    kinds = {k for _, k in cells} - {"<PORT>", "<LOCKED>"}
    simulate(
        work,
        models,
        "vivado",
        "vivado",
        "vendor-net.v",
        kinds,
        stage,
        extra_top=("state_lane", work / "lane.sv"),
    )
    vivado_lane.changes(work, native_work)
    require(capture == match(run, vendor), "Vivado capture changed during simulation")
    (work / "measurement.json").write_text(
        json.dumps(
            dict(
                capture=capture,
                models=UNISIM,
                bench=digest(HERE / "functional_tb.sv"),
                observer=digest(HERE / "transitions.cpp"),
                observations={n: digest(work / n) for n in OBSERVATIONS},
            ),
            indent=2,
        )
        + "\n"
    )


def publish(
    run: Path,
    native_work: Path,
    vendor: Path,
    work: Path,
    java: Path,
    jar: Path,
    chipdb: Path,
    constids: Path,
    output: Path,
) -> None:
    """Rebuild the native witness, join the separately observed Vivado route and publish both atomically."""
    require(not output.exists(), "fresh output required")
    cap = match(run, vendor)
    measured = json.loads((work / "measurement.json").read_text())
    native = json.loads((native_work / "measurement.json").read_text())
    bench = "apps/hls_spacetime/test/native/four_phi/workload/functional_tb.sv"
    require(
        measured["capture"] == cap
        and measured["models"] == native["unisim"] == UNISIM
        and measured["bench"]
        == native["files"][bench]
        == digest(HERE / "functional_tb.sv")
        and measured["observer"] == digest(HERE / "transitions.cpp")
        and measured["observations"] == {n: digest(work / n) for n in OBSERVATIONS}
        and digest(work / "rtl/units.json") == digest(native_work / "rtl/units.json"),
        "matched Vivado observation",
    )
    data = Path(os.environ["RAPIDWRIGHT_PATH"]) / "data"
    require(
        digest(jar) == RAPIDWRIGHT
        and all(digest(data / n) == v for n, v in DEVICE_DATA.items()),
        "RapidWright inputs",
    )
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        stage = Path(tmp)
        gallery = stage / "gallery"
        gallery.mkdir()
        expected = two_phi.build(run, native_work, chipdb, constids, gallery)
        replay = json.loads((gallery / "workload.json").read_text())
        with (
            chipdb.open("rb") as f,
            mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as db,
        ):
            grid = ChipGrid(db)
            backend = mapped(
                vendor, work, gallery, "vivado", grid, expected, planes="X"
            )
            replay["backends"]["vivado"] = backend
            replay["tiles"].update(
                {str(i): grid.tile_names[i] for i, _ in backend["occupancy"]}
            )
            cells = [
                r.split("\t")
                for r in (work / "vivado/cells.tsv").read_text().splitlines()
            ]
            names = [n for n, _ in cells]
            timing = vivado(vendor / "routed.sdf", names)
            lane = vivado_lane.state_path(vendor, cells, *timing[:2])
            require(
                vivado_lane.monitor(lane["probes"]) == (work / "lane.sv").read_text(),
                "observed state pins",
            )
            lane.update(vivado_lane.changes(work, native_work))
            model = vendor_model(
                vendor / "routed.sdf",
                vendor / "routed.dcp",
                work / "vendor.edf",
                java,
                jar,
                names,
                grid,
                stage,
                gallery,
                timing=timing,
            )
            model["stateLane"] = lane
        replay["checkpoints"]["vivado"] = cap["routed.dcp"]
        replay["flow"].update(vivado=model, sdf=cap["routed.sdf"])
        (gallery / "workload.json").write_text(
            json.dumps(replay, separators=(",", ":")) + "\n"
        )
        gallery.rename(output)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="command", required=True)
    for action, extra in (
        ("measure", ("models", "yosys", "guard")),
        ("publish", ("chipdb", "constids", "output")),
    ):
        sub = commands.add_parser(action)
        for key in ("run", "native-work", "vendor", "work", "java", "jar", *extra):
            sub.add_argument(
                "--" + key, type=lambda p: Path(p).resolve(), required=True
            )
    args = vars(cli.parse_args())
    action = args.pop("command")
    (measure if action == "measure" else publish)(**args)
