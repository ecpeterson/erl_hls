"""Replay an authenticated four-Phi capture under a serial process-group guard."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

from execution import digest, require
from capture import BRAM_MAP, VENDOR, audit_library

HERE = Path(__file__).resolve().parent
RAPIDWRIGHT = "f5108093ae59d6dfacf9128d0f35e2e0a4340af492f6af185af8dfc197258d41"
UNISIM = "de97e2b21318aa2dd4185a1f9d808a44c30be594efbaeabe5fbe23d1b89d1d10"
DEVICE_DATA = {
    "parts.db": "d3a8ff8d73d7f355c8307a2f25bbbfde260d47e5c464ed86d9de9efbec66d343",
    "unisim_data.dat": "adb8e1bbacca9de3908f3904698377e6834738f587bcb37c09932b6604f90a90",
    "devices/zynq/xc7z030_db.dat": "b4ea3cc9955e0e27c935cf8dac607517ef67d7bbbc588920f7a97d3c6336d80b",
}


def observations(work: Path) -> dict[str, str]:
    """Identify every measurement consumed when joining a replay to a placement."""
    names = ["rtl/units.json", "rtl/cycles.txt", "locations.tsv"]
    for backend, stage in [("vivado", "vivado"), ("openxc7", "native")]:
        names += [
            f"{backend}/{name}"
            for name in ("cells.tsv", "changes.bin", "initial-q.txt")
        ]
        names.append(f"{stage}-sim-guard/console.log")
    return {name: digest(work / name) for name in names}


def measure(
    run: Path, work: Path, models: Path, jar: Path, guard: Path, yosys: Path
) -> None:
    """Use the matching mapped netlists and physical checkpoints. Each stage requires fresh output."""
    capture_sha = digest(run / "capture.json")
    receipt = json.loads((run / "capture.json").read_text())
    for name, sha in receipt["files"].items():
        require(digest(run / name) == sha, "capture identity " + name)
    library = yosys.parent.parent / BRAM_MAP
    audit_library(library.read_text())
    require(
        digest(library) == receipt["tools"]["xc7-bram-map"], "synthesis mapping library"
    )
    require(digest(jar) == RAPIDWRIGHT, "RapidWright release")
    require(
        digest(yosys)
        in {receipt["tools"]["yosys"], receipt["tools"]["yosys-executable"]}
        and digest(yosys.parent.parent / "libexec/yosys")
        == receipt["tools"]["yosys-executable"],
        "Yosys executable",
    )
    model_set = hashlib.sha256()
    for model in [models / "glbl.v", *sorted((models / "unisims").glob("*.v"))]:
        model_set.update(
            str(model.relative_to(models)).encode()
            + b"\0"
            + bytes.fromhex(digest(model))
        )
    require(model_set.hexdigest() == UNISIM, "UNISIM release")
    work.mkdir()
    env = os.environ.copy()
    rw = Path(env.get("RAPIDWRIGHT_PATH", work / "rw")).resolve()
    env["RAPIDWRIGHT_PATH"] = str(rw)

    def stage(name: str, args: list, cwd: Path = work, seconds: int = 1200) -> None:
        """Run one bounded foreground command. Stop on failure before using its outputs."""
        subprocess.run(
            [sys.executable, guard, work / (name + "-guard"), str(seconds), *args],
            cwd=cwd,
            env=env,
            check=True,
        )

    stage("execution", [sys.executable, HERE / "execution.py", run, work / "rtl"])
    net = (run / VENDOR / "routed.v").read_text()
    logic, sep, _ = net.partition("`ifndef GLBL")
    require(
        bool(sep) and logic.count("`define XIL_TIMING") == 1,
        "archived functional source",
    )
    (work / "vendor-net.v").write_text(logic.replace("`define XIL_TIMING", ""))
    stage(
        "edif",
        [
            yosys,
            "-Q",
            "-q",
            "-p",
            "read_verilog -lib +/xilinx/cells_sim.v +/xilinx/cells_xtra.v; read_verilog vendor-net.v; hierarchy -top phi_timing_harness; write_edif -pvector bra -attrprop vendor.edf",
        ],
    )
    stage(
        "placement",
        [
            "java",
            "-Xmx3g",
            "-cp",
            jar,
            HERE / "Placement.java",
            run / VENDOR / "routed.dcp",
            work / "locations.tsv",
            work / "vendor.edf",
        ],
    )
    for name, sha in DEVICE_DATA.items():
        require(digest(rw / "data" / name) == sha, "RapidWright data " + name)
    stage("observer", ["iverilog-vpi", HERE / "transitions.cpp"])
    for backend, stage_name, net_name in [
        ("vivado", "vivado", "vendor-net.v"),
        ("openxc7", "native", "native-net.v"),
    ]:
        directory = work / backend
        directory.mkdir()
        if backend == "vivado":
            kinds = {
                l.split("\t")[1]
                for l in (work / "locations.tsv").read_text().splitlines()
            } - {"<PORT>", "<LOCKED>"}
        else:
            path = run / "native/synth.json"
            stage(
                "configured-init",
                [
                    sys.executable,
                    HERE / "init_bits.py",
                    path,
                    work / "synth.json",
                    work / "configuration.json",
                ],
            )
            stage(
                "emit-native",
                [
                    yosys,
                    "-Q",
                    "-q",
                    "-p",
                    "read_json synth.json; write_verilog -noattr -norename native-net.v",
                ],
            )
            kinds = {
                c["type"]
                for c in json.loads(path.read_bytes())["modules"]["phi_timing_harness"][
                    "cells"
                ].values()
            } - {"$scopeinfo"}
        (directory / "primitive-types.txt").write_text(
            "".join(k + "\n" for k in sorted(kinds))
        )
        program = work / (stage_name + ".vvp")
        stage(
            stage_name + "-compile",
            [
                "iverilog",
                "-g2012",
                "-s",
                "functional_tb",
                "-s",
                "glbl",
                "-o",
                program,
                "-y",
                models / "unisims",
                HERE / "functional_tb.sv",
                work / net_name,
                models / "glbl.v",
            ],
        )
        stage(
            stage_name + "-sim",
            ["vvp", "-M" + str(work), "-mtransitions", program],
            directory,
            seconds=3000 if backend == "openxc7" else 1200,
        )
    require(
        digest(run / "capture.json") == capture_sha, "capture changed during replay"
    )
    (work / "measurement.json").write_text(
        json.dumps(dict(capture=capture_sha, observations=observations(work)), indent=2)
        + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("run", "work", "models", "jar", "guard", "yosys"):
        parser.add_argument(key, type=lambda p: Path(p).resolve())
    measure(**vars(parser.parse_args()))
