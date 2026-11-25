"""Replay the retained N2 trace at the pin-fitting top, sampling before each rising edge."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess


def replay(trace: Path, source: Path, work: Path, suite: Path) -> dict:
    """Compare every public field and declared tap for the complete pre-edge RLE horizon."""
    work.mkdir()
    rows = gzip.decompress(trace.read_bytes()).decode().splitlines()
    header, public, *body = [line.split("\t") for line in rows]
    names = "reset input_valid input_data input_last output_ready input_ready output_valid output_data output_last fault running"
    if header != ["H", "spacetime_cycle_trace", "1"] or public != ["P", *names.split()]:
        raise ValueError("trace schema")
    fields = [
        ("reset", 1),
        ("s_app_tvalid", 1),
        ("s_app_tdata", 32),
        ("s_app_tlast", 1),
        ("m_app_tready", 1),
        ("s_app_tready", 1),
        ("m_app_tvalid", 1),
        ("m_app_tdata", 32),
        ("m_app_tlast", 1),
        ("aggregate_fault", 1),
        ("running", 1),
    ]
    taps = [row for row in body if row[0] == "T"]
    for _, _, width, path in taps:
        suffix = path.removeprefix("TOP.protocol_application_top.")
        if suffix == path or not re.fullmatch(
            r"[a-zA-Z_][\w]*(\.[a-zA-Z_][\w]*)*", suffix
        ):
            raise ValueError("unexpected tap path")
        fields.append(("dut.application.dut." + suffix, int(width)))
    footer = body[-1]
    cycles = int(footer[1])
    samples = [row for row in body if row[0] == "S"]
    if not (
        footer[:5] == ["F", str(cycles), "complete", str(cycles), str(len(samples))]
        and footer[-1] == "ok"
        and cycles == 2369
        and body == taps + samples + [footer]
    ):
        raise ValueError("incomplete N2 recording")
    groups = [fields[:5], fields[5:11]]
    for field in fields[11:]:
        if len(groups) == 2 or sum(w for _, w in groups[-1]) + field[1] > 1024:
            groups.append([])
        groups[-1].append(field)
    bench = [
        "module bench;",
        "bit clk, reset, s_app_tvalid, s_app_tlast, m_app_tready;",
        "bit [31:0] s_app_tdata; wire [31:0] m_app_tdata;",
        "wire s_app_tready, m_app_tvalid, m_app_tlast, startup_done, running, ingress_fault;",
        "wire [5:0] fault; bit [2:0] failure_actor; wire [15:0] failure; bit aggregate_fault;",
        "top dut(.*);",
        "int cycle;",
    ]
    offset = 0
    checks = []
    for i, group in enumerate(groups):
        width = sum(w for _, w in group)
        name = f"sample_{i}"
        bench += [
            f"reg [{width - 1}:0] {name}[0:{cycles - 1}];",
            f'initial $readmemh("{name}.hex", {name});',
        ]
        with (work / f"{name}.hex").open("x") as stream:
            end = 0
            for _, first, repeat, *values in samples:
                if int(first) != end or len(values) != len(fields) or int(repeat) <= 0:
                    raise ValueError("noncontiguous samples")
                end += int(repeat)
                value = 0
                for (_, w), raw in zip(group, values[offset:]):
                    word = int(raw, 16)
                    if word.bit_length() > w:
                        raise ValueError("tap exceeds width")
                    value = (value << w) | word
                stream.write((f"{value:x}\n") * int(repeat))
            if end != cycles:
                raise ValueError("sample horizon")
        packed = "{" + ",".join(field for field, _ in group) + "}"
        if i == 0:
            drive = f"{packed} = {name}[cycle];"
        else:
            checks.append(
                f'if ({packed} !== {name}[cycle]) $fatal(1, "cycle %d slice {i}", cycle);'
            )
        offset += len(group)
    bench += [
        "initial begin #1;",
        f"for (cycle=0; cycle<{cycles}; cycle++) begin",
        drive,
        "#1; aggregate_fault = ingress_fault | (|fault);",
        "for (int actor=0; actor<8; actor++) begin failure_actor=3'(actor); #1;",
        "if (actor < 6) begin",
        "if (failure !== dut.words[actor]) $fatal;",
        "aggregate_fault |= (|failure); end else if (failure !== 0) $fatal; end",
        *checks,
        "clk=1; #1; clk=0; #1; end $finish; end endmodule",
    ]
    (work / "bench.sv").write_text("\n".join(bench) + "\n")
    rtl = [source / f for f in (source / "files.f").read_text().splitlines()] + [
        source / "top.sv"
    ]
    compiler = suite / "bin/verilator"
    with (work / "compile.log").open("xb") as log:
        subprocess.run(
            [
                compiler,
                "--binary",
                "--timing",
                "--top-module",
                "bench",
                "-Wno-fatal",
                "-j",
                "2",
                suite / "share/yosys/xilinx/cells_sim.v",
                *rtl,
                "bench.sv",
            ],
            cwd=work,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
            timeout=300,
        )
    with (work / "simulation.log").open("xb") as log:
        subprocess.run(
            ["obj_dir/Vbench"],
            cwd=work,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
            timeout=120,
        )
    return {
        "cycles": cycles,
        "taps": len(taps),
        "tap_bits_per_cycle": sum(w for _, w in fields[11:]),
        "trace_sha256": hashlib.sha256(trace.read_bytes()).hexdigest(),
        "rtl_sha256": [hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl],
        "verilator": subprocess.check_output(
            [compiler, "--version"], text=True
        ).strip(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["trace", "source", "work", "suite"]:
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    result = replay(
        *(p.resolve() for p in (args.trace, args.source, args.work, args.suite))
    )
    (args.work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
