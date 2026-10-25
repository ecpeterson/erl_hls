#!/usr/bin/env python3
"""Map validated full-device builds, with public debug and five clock crossings per device."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root, compiler_tool
import statistics
import subprocess

from backend_paths import ROOT, debug_rtl
from phi_build_artifacts import read_bridge_build
from backend_commands import digest


def wrapper(device: int) -> str:
    """Expose host/link streams; include their bounded crossings around the unchanged device."""
    ports = ["input wire clk, host_clk, peer_clk, reset",
             "output wire [31:0] fault", "output wire fault_valid", "input wire fault_ready"]
    wires, crossings, connections = [], [], [".clk(clk)", ".reset(local_reset)",
        "._fault_0_out(fault)", "._fault_0_out_vld(fault_valid)", "._fault_0_out_rdy(fault_ready)"]
    # The receive side owns the link crossing: the pair therefore includes exactly two.
    for name, width, inbound, clock in [("link_in", 33, True, "peer_clk"),
            ("link_out", 33, False, None), ("app_in", 33, True, "host_clk"),
            ("app_out", 33, False, "host_clk"), ("debug_in", 37, True, "host_clk"),
            ("debug_out", 37, False, "host_clk")]:
        direction, reverse = ("input", "output") if inbound else ("output", "input")
        ports += [f"{direction} wire [{width-1}:0] {name}_data",
                  f"{direction} wire {name}_valid", f"{reverse} wire {name}_ready"]
        inner = f"local_{name}" if clock else name
        if clock:
            wires += [f"wire [{width-1}:0] {inner}_data;", f"wire {inner}_valid, {inner}_ready;"]
            src, dst = (name, inner) if inbound else (inner, name)
            wr, rd = (clock, "clk") if inbound else ("clk", clock)
            crossings.append(f"hls_async_fifo #(.WIDTH({width})) {name}_crossing("
                f".reset(reset), .wr_clk({wr}), .rd_clk({rd}), " + ", ".join(
                f".{side}_{signal}({prefix}_{signal})" for side, prefix in [("in", src), ("out", dst)]
                for signal in ("data", "valid", "ready")) + ");")
        if name.startswith("debug"):
            side = "s" if inbound else "m"
            connections += [f".{side}_dbg_t{signal}({inner}_data{bits})"
                            for signal, bits in [("data", "[31:0]"), ("keep", "[35:32]"), ("last", "[36]")]]
            connections += [f".{side}_dbg_t{signal}({inner}_{signal})" for signal in ("valid", "ready")]
        else:
            port = name.replace("link_", "link_0_") if name.startswith("link_") else name
            connections += [f"._{port}({inner}_data)", f"._{port}_vld({inner}_valid)", f"._{port}_rdy({inner}_ready)"]
    return "\n".join(["module measured(" + ",\n".join(ports) + ");", "wire local_reset;",
        "hls_clock_reset device_reset(.clk(clk), .reset(reset), .local_reset(local_reset));",
        *wires, *crossings, f"hls_phi_debug_{device} dut(" + ",\n".join(connections) + ");", "endmodule", ""])


def measure(args: argparse.Namespace) -> None:
    """Retain cell distributions and hashes; reject edits to the simulated application artifacts."""
    provenance = read_bridge_build(args.build)
    args.stage.mkdir(parents=True, exist_ok=False)
    accounting = compiler_tool(args.erl_hls, "measure_topology_debug")
    sources = [ROOT / "rtl/hls_async_fifo.v", *debug_rtl(args.erl_hls)]
    report = {"scope": "Full devices: actors, RAM, application gateway, credited link, public topology/actor queries and five CDC FIFOs each; excludes optional counter/trace services, PS, DMA, Ethernet/GT and I/O pads. Synthesis only, no placement/timing claim.",
        "build_provenance_sha256": digest(args.build / "provenance.json"),
        "placement": provenance["inputs"]["config"].get("placement", "direct"),
        "yosys": subprocess.check_output([args.yosys, "-V"], text=True).strip(),
        "sources": {str(p): digest(p) for p in [Path(__file__), *sources]}, "devices": []}
    for device in (0, 1):
        stage = args.stage / f"device{device}"
        stage.mkdir()
        (stage / "measured.v").write_text(wrapper(device))
        rtl = [args.build / f"device{device}/debug" / n for n in ("instrumented.v", "debug_top.v")]
        samples = []
        for seed in args.seeds:
            script = stage / f"seed-{seed}.ys"
            script.write_text("read_verilog -sv " + " ".join(json.dumps(str(p)) for p in
                [*rtl, *sources, stage / "measured.v"]) + f"""
hierarchy -check -top measured
proc
flatten
opt
rename -scramble-name -seed {seed}
synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf -top measured
check -assert
scc -expect 0
tee -o seed-{seed}.json stat -json -tech xilinx
""")
            with (stage / f"seed-{seed}.log").open("w") as log:
                subprocess.run([args.yosys, "-Q", "-T", "-s", str(script)], cwd=stage,
                    stdout=log, stderr=subprocess.STDOUT, check=True, timeout=args.mapping_timeout)
            cells = json.loads((stage / f"seed-{seed}.json").read_text())["design"]["num_cells_by_type"]
            samples.append({"seed": seed, **accounting.cell_counts(cells), "DSP": cells.get("DSP48E1", 0), "primitives": cells})
            print(json.dumps({"device": device, "sample": samples[-1]}), flush=True)
        summary = {key: {"best": min(values), "mean": statistics.mean(values),
            "variance": statistics.pvariance(values), "worst": max(values)}
            for key in ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36", "DSP")
            for values in [[sample[key] for sample in samples]]}
        report["devices"].append({"device": device, "samples": samples, "summary": summary})
        (args.stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")


def main() -> None:
    """Select a completed build and matched, explicitly recorded mapping seeds."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--seeds", type=int, nargs="+", default=[1, 2])
    parser.add_argument("--mapping-timeout", type=int, default=3600,
                        help="per-device, per-seed native synthesis budget in seconds")
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    for name in ("build", "stage", "erl_hls"):
        setattr(args, name, getattr(args, name).resolve())
    measure(args)


if __name__ == "__main__":
    main()
