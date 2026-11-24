"""Observe every generated process, FIFO and RAM in the archived closed four-Phi decoder."""

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from capture import INPUT, RTL, digest
from replay import CYCLES, require

GRID = "__phi_decoder_profile_topology__SchedulerGrid_0_next_inst"
BASE = "decoder.application." + GRID


def unit_label(path: str) -> str:
    """Describe one instance in the frozen topology, preserving repeated service/FIFO identities."""
    leaf = path.rsplit(".", 1)[-1]
    scheduler = re.search(r"SharedService_0__2_([0-3])_", path)
    suffix = f" {scheduler[1]}" if scheduler else ""
    if leaf.startswith("materialized_fifo_fifo__"):
        return leaf.removeprefix("materialized_fifo_fifo__").strip("_") + suffix
    if "SharedExecutor" in leaf or "SharedService" in leaf:
        family = "Syndrome replay" if "syndrome" in leaf else "Phi halo"
        return family + (" executor" if "Executor" in leaf else " scheduler") + suffix
    if m := re.search(r"Scheduler(Startup|Router)(\d)", leaf):
        return f"{m[1]} {m[2]}"
    if "ReductionPlane" in leaf:
        return ("X" if "Phi_x" in leaf else "Z") + " reduction"
    if "FrameRelay" in leaf:
        return "Frame relay " + ("1" if leaf.endswith("_1") else "0")
    if "Arbiter" in leaf:
        return "Effect arbiter"
    return leaf


def inventory(source: Path) -> list[dict]:
    """Walk generated module instances from the grid; fail on missing or unobserved process ports."""
    rtl = source.read_text()
    modules = dict(re.findall(r"^module (\w+)\((.*?)^endmodule", rtl, re.M | re.S))
    rows = []

    def walk(name: str, path: str) -> None:
        """Enumerate declared interfaces and descend through generated child instances."""
        body = modules[name]
        signals = []
        for valid in re.findall(r"^  (?:input|output) wire (\w+_vld)[,\n]", body, re.M):
            ready = valid[:-4] + "_rdy"
            require(
                re.search(rf"^  (?:input|output) wire {ready}[,\n]", body, re.M), ready
            )
            signals.append((valid[:-4].strip("_"), valid, ready))
        fifo = name.startswith("fifo_for_")
        if fifo:
            signals.extend((n, n + "_valid", n + "_ready") for n in ("push", "pop"))
        for stage in re.findall(r"^  wire (p\d+_stage_done);", body, re.M):
            signals.append((stage, stage, None))
        if path != BASE:
            require(bool(signals), "unobserved instance " + path)
            rows.append(
                dict(
                    path=path,
                    label=unit_label(path),
                    kind="FIFO" if fifo else "Process",
                    signals=signals,
                )
            )
        for child, inst in re.findall(r"^  (\w+) (\w+) \(", body, re.M):
            if child in modules:
                walk(child, path + "." + inst)

    walk(GRID.removesuffix("_inst"), BASE)
    for i in range(4):
        for kind in ("state", "mailbox"):
            name = f"scheduler_{i}_{kind}"
            rows.append(
                dict(
                    path="decoder." + name,
                    label=f"Scheduler {i} {kind} RAM",
                    kind="RAM",
                    signals=[("read", "rd_en", None), ("write", "wr_en", None)],
                )
            )
    rows.append(
        dict(
            path="",
            label="Decoder outputs",
            kind="Output",
            signals=[
                ("X frame", "x_valid", "x_ready"),
                ("Z frame", "z_valid", "z_ready"),
            ],
        )
    )
    require(len({r["path"] for r in rows}) == len(rows) <= 256, "instance inventory")
    return rows


def generate(rows: list[dict]) -> str:
    """Sample each handshake, pipeline enable, public payload and physical RAM address before the edge."""
    signals = []
    addresses = []
    for row in rows:
        scope = "dut." + row["path"] + "." if row["path"] else "dut."
        for _, valid, ready in row["signals"]:
            signals.append((scope + valid, scope + ready if ready else "1'b1"))
        if row["kind"] == "RAM":
            addresses.extend([scope + "rd_addr", scope + "wr_addr"])
    require(len(signals) <= 2048, "probe limit")
    fields = [
        "cycle",
        "dut.resetn",
        "{" + ",".join(v for v, r in reversed(signals)) + "}",
        "{" + ",".join(r for v, r in reversed(signals)) + "}",
        "dut.x_event",
        "dut.z_event",
        *addresses,
        "dut.activity",
    ]
    fmt = "%0d %b %b %b %h %h " + " ".join(["%h"] * len(addresses)) + " %b"
    return f"""`timescale 1ns/1ps
module whole_rtl_tb;
 reg clock=0; wire activity;
 phi_timing_harness dut(.clock(clock),.activity(activity));
 integer cycle;
 initial begin
  #200;
  for(cycle=0;cycle<{CYCLES};cycle=cycle+1) begin
   #10; $display("{fmt}",{",".join(fields)}); clock=1; #10; clock=0;
  end
  $display("END {CYCLES}"); $finish;
 end
endmodule
"""


def observe(run: Path, out: Path) -> None:
    """Replay exactly the source files authenticated by the existing matched capture receipt."""
    files = json.loads((run / "capture.json").read_text())["files"]
    for name in RTL:
        require(
            digest(run / INPUT / name) == files[str(INPUT / name)], "RTL hash " + name
        )
    rows = inventory(run / INPUT / "phi_decoder_profile.v")
    out.mkdir()
    (out / "units.json").write_text(json.dumps(rows, indent=2) + "\n")
    (out / "monitor.sv").write_text(generate(rows))
    subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-s",
            "whole_rtl_tb",
            "-o",
            out / "observer",
            out / "monitor.sv",
            *(run / INPUT / name for name in RTL),
        ],
        check=True,
    )
    with (out / "cycles.txt").open("x") as f:
        subprocess.run(["vvp", out / "observer"], stdout=f, check=True, timeout=600)


if __name__ == "__main__":
    observe(Path(sys.argv[1]), Path(sys.argv[2]))
