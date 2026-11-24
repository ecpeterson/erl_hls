"""Replay the retained repetition N2 RTL and publish a scoped step-4 implementation on XC7."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile


HERE = Path(__file__).resolve().parent
EXPORT = HERE.parents[4] / "hls_target/priv/tools/export_openxc7.py"
MEMBERS = [
    "inputs/boundary/core.v",
    "inputs/boundary/protocol_boundary.sv",
    "inputs/application/gateway.v",
    "inputs/application/protocol_application_top.sv",
    "inputs/support/fabric/rtl/hls_partition_activation.sv",
    "native_top.sv",
]


def stage(archive: Path, directory: Path) -> dict:
    """Copy only the named RTL and the source plan, checking each retained input digest."""
    directory.mkdir()
    with tarfile.open(archive) as tar:
        plan = json.load(tar.extractfile("native-1/plan.json"))
        for name in MEMBERS:
            data = tar.extractfile("native-1/" + name).read()
            if hashlib.sha256(data).hexdigest() != plan["inputs"][name]:
                raise ValueError("native source mismatch: " + name)
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    (directory / "files.f").write_text("\n".join(MEMBERS) + "\n")
    (directory / "top.sv").write_bytes((HERE / "top.sv").read_bytes())
    ports = {
        "clk": 1,
        "reset": 1,
        "s_app_tdata": 32,
        "m_app_tdata": 32,
        "fault": 6,
        "failure_actor": 3,
        "failure": 16,
    }
    ports.update(
        dict.fromkeys(
            "s_app_tlast s_app_tvalid s_app_tready m_app_tlast m_app_tvalid m_app_tready startup_done running ingress_fault".split(),
            1,
        )
    )
    with (directory / "pins.xdc").open("x") as stream:
        for name, width in ports.items():
            for i in range(width):
                port = name if width == 1 else f"{name}[{i}]"
                pin = "PACKAGE_PIN Y14 " if name == "clk" else ""
                stream.write(
                    f"set_property -dict {{{pin}IOSTANDARD LVCMOS33}} [get_ports {{{port}}}]\n"
                )
    return plan


def publish(args: argparse.Namespace) -> None:
    """Join only the checked replay and build, then prepare the viewer's ordinary portable publication."""
    public = json.loads((args.archive / "capture-1/live-1/public.json").read_bytes())[
        "events"
    ]
    previous, correction, completion = [
        next(e["cycle"] for e in public if e["event"] == event)
        for event in (
            ["phi_status", 3, 0, 0, 0],
            ["phi_correction", 4, 0, 0, 2],
            ["phi_status", 4, 0, 0, 0],
        )
    ]
    if (previous, correction, completion) != (1774, 1852, 1873):
        raise ValueError("step-4 completion oracle")
    metadata = {
        "title": "Repetition N2 · openXC7 · step 4",
        "selection": {
            "step": 4,
            "previousCompletionCycle": previous,
            "completionCycle": completion,
            "spacingCycles": completion - previous,
            "firstCycle": previous + 1,
            "endCycle": completion + 1,
        },
        "annotations": {
            "public": [
                dict(e, id=f"public/{i}", label=str(e["event"]))
                for i, e in enumerate(public)
            ],
            "boundaries": [],
        },
        "examples": [
            {
                "id": "register-residence",
                "label": "Register residence C1852–C1866",
                "event": "e/25527",
                "version": "v/25067",
                "events": ["e/25066", "e/25521", "e/25522", "e/25527"],
                "firstCycle": 1852,
                "endCycle": 1867,
                "scope": "Observed write, read and actor action",
            }
        ],
    }
    (args.output / "metadata.json").write_text(json.dumps(metadata) + "\n")
    root = HERE.parents[5]
    subprocess.run(
        [
            "escript",
            HERE / "bind_replay.escript",
            args.archive / "capture-1/live-1/bundle.json.gz",
            args.output,
            args.output / "joined",
        ],
        check=True,
        env=dict(os.environ, ERL_LIBS=str(root / "_build/spacetime/lib")),
    )
    scripts = root / "apps/hls_spacetime/scripts"
    subprocess.run(
        [
            "node",
            scripts / "prepare-view.mjs",
            "--bundle",
            args.output / "joined/bundle.json",
            "--openxc7",
            args.output / "native",
            "--metadata",
            args.output / "metadata.json",
            "--output",
            args.output / "view",
        ],
        check=True,
    )
    subprocess.run(
        [
            "node",
            scripts / "prepare-render.mjs",
            "--input",
            args.output / "view",
            "--output",
            args.output / "prepared",
        ],
        check=True,
    )


def capture(args: argparse.Namespace) -> None:
    """Use an explicit 200 MHz target, explicitly bounded pilot or complete register population."""
    args.output.mkdir()
    inputs = args.output / "inputs"
    plan = stage(args.archive / "physical-1/reproduction.tar.gz", inputs)
    trace = args.archive / "capture-1/live-1/capture.tsv.gz"
    subprocess.run(
        [
            sys.executable,
            HERE / "replay.py",
            trace,
            inputs,
            args.output / "replay",
            args.apio / "packages/oss-cad-suite",
        ],
        check=True,
    )
    replay = (args.output / "replay/result.json").read_bytes()
    focus = {"____state_137": [123, 137], "____state_154": [0, 1]}
    cmd = [
        sys.executable,
        EXPORT,
        "--apio-home",
        args.apio,
        "--chipdb",
        args.chipdb,
        "--timing-tools",
        args.tools,
        "--allow-timing-fail",
        "--flatten",
        "--freq",
        "200",
        "--xdc",
        inputs / "pins.xdc",
        "--max-bytes",
        str((384 if args.all_words else 256) << 20),
        "--max-timing-objects",
        "650000" if args.all_words else "250000",
        "--sta",
        "--route-sta",
        "--source-id",
        plan["build"]["source"],
        "--observation-id",
        hashlib.sha256(replay).hexdigest(),
    ]
    for name in MEMBERS + ["top.sv"]:
        cmd += ["--rtl", inputs / name]
    if args.all_words:
        observation = json.loads(
            (args.archive / "capture-1/observation.json").read_bytes()
        )
        with gzip.open(args.archive / "capture-1/live-1/bundle.json.gz") as stream:
            events = json.load(stream)["events"]
        written = {
            e["access"]["resource"]
            for e in events
            if 1774 < e["cycle"] <= 1873
            and (e.get("access") or {}).get("kind") == "write"
        }
        for register in observation["registers"]:
            if "register/" + register["name"] in written:
                focus.setdefault(register["name"], [])
        if {"register/" + word for word in focus} != written:
            raise ValueError("written resource absent from observation plan")
    for word, bits in focus.items():
        net = "application.dut.network.core." + word
        cmd += ["--storage-word", "register/" + word + "=" + net]
        if args.all_words:
            cmd += ["--focus-word", net]
        for bit in bits:
            cmd += ["--focus-bit", f"{net}[{bit}]", "--route-bit", f"{net}[{bit}]"]
    if args.demand:
        demand = json.loads(args.demand.read_bytes())
        cmd += ["--route-checkpoint", demand["checkpoint"]]
        for name in demand["nets"]:
            cmd += ["--route-net", name]
    subprocess.run(cmd + [args.output / "native"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("archive", "apio", "chipdb", "tools", "output"):
        parser.add_argument(key, type=Path)
    parser.add_argument(
        "--all-words", action="store_true", help="qualify all 51 observed storage words"
    )
    parser.add_argument(
        "--demand", type=Path, help="selected sink path nets from the frozen first run"
    )
    parser.add_argument(
        "--publish-only",
        action="store_true",
        help="publish an existing complete, unjoined capture",
    )
    args = parser.parse_args()
    if not args.publish_only:
        capture(args)
    publish(args)
