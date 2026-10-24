#!/usr/bin/env python3
"""Check clock ratios, capacity, backpressure, wraparound and coordinated reset."""
import argparse
import json
from pathlib import Path
from backend_commands import digest, execute

ROOT = Path(__file__).resolve().parents[1]


def test(stage: Path, yosys: str, cells: Path | None) -> None:
    """Require bounded ordered operation and two-read-clock visibility before and after mapping."""
    stage.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "rtl/hls_async_fifo.v", ROOT / "test/rtl/async_fifo_tb.sv"]
    report = {"sources": {str(path.relative_to(ROOT)): digest(path) for path in sources},
              "cases": []}
    for bits, write, read in ((2, 3, 7), (3, 7, 3), (3, 5, 5), (4, 2, 11)):
        name = f"depth-{1 << bits}-clocks-{write * 2}-{read * 2}"
        output = stage / f"{name}.vvp"
        command = ["iverilog", "-g2012", "-s", "async_fifo_tb",
                   f"-Pasync_fifo_tb.ADDR_BITS={bits}", f"-Pasync_fifo_tb.WRITE_HALF={write}",
                   f"-Pasync_fifo_tb.READ_HALF={read}", "-o", str(output), *map(str, sources)]
        execute(command, stage, name + "-compile")
        execute(["vvp", str(output)], stage, name, timeout=30)
        log = (stage / f"{name}.log").read_text()
        if "PASS: async FIFO" not in log:
            raise RuntimeError(f"FIFO test did not complete: {name}")
        report["cases"].append({"name": name, "command": command, "result": log})
        print(log.strip())
    latency = ROOT / "test/rtl/async_fifo_latency_tb.sv"
    report["sources"][str(latency.relative_to(ROOT))] = digest(latency)
    execute(["iverilog", "-g2012", "-s", "async_fifo_latency_tb", "-o", str(stage / "latency.vvp"),
             str(sources[0]), str(latency)], stage, "latency-compile")
    execute(["vvp", str(stage / "latency.vvp")], stage, "latency", timeout=30)
    report["latency"] = (stage / "latency.log").read_text()
    print(report["latency"].strip())
    if cells is not None:
        script = stage / "mapped.ys"
        script.write_text(f'''read_verilog {json.dumps(str(sources[0]))}
chparam -set WIDTH 37 -set ADDR_BITS 3 hls_async_fifo
synth_xilinx -top hls_async_fifo -flatten -abc9 -arch xc7 -noiopad -noclkbuf
check -assert
scc -expect 0
rename hls_async_fifo hls_async_fifo_mapped
write_verilog -noattr mapped.v
''')
        execute([yosys, "-Q", "-T", "-s", str(script)], stage, "mapped-synthesis")
        command = ["iverilog", "-g2012", "-DMAPPED", "-s", "async_fifo_tb",
                   "-o", str(stage / "mapped.vvp"), str(stage / "mapped.v"), str(cells), str(sources[1])]
        execute(command, stage, "mapped-compile")
        execute(["vvp", str(stage / "mapped.vvp")], stage, "mapped", timeout=30)
        log = (stage / "mapped.log").read_text()
        if "PASS: async FIFO" not in log:
            raise RuntimeError("mapped FIFO did not finish its assertions")
        report["mapped"] = {"command": command, "result": log,
                            "cells_sha256": digest(cells), "rtl_sha256": digest(stage / "mapped.v")}
        print("Mapped XC7 primitives: " + log.strip())
        execute(["iverilog", "-g2012", "-DMAPPED", "-s", "async_fifo_latency_tb", "-o", str(stage / "mapped-latency.vvp"),
                 str(stage / "mapped.v"), str(cells), str(latency)], stage, "mapped-latency-compile")
        execute(["vvp", str(stage / "mapped-latency.vvp")], stage, "mapped-latency", timeout=30)
        report["mapped_latency"] = (stage / "mapped-latency.log").read_text()
        print(report["mapped_latency"].strip())
    (stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/async-fifo")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--xilinx-cells", type=Path,
                        help="also simulate mapped XC7 RTL using this cells_sim.v")
    args = parser.parse_args()
    test(args.stage.resolve(), args.yosys, args.xilinx_cells)
