#!/usr/bin/env python3
"""Build and verify a periodic repetition-code workload; optionally map XC7 resources."""
import phi_tool_paths  # Resolve shared tooling for this application.
from compiler_paths import compiler_resource, compiler_root, compiler_tool
from backend_paths import erl_command, erlang_environment
from backend_build_profile import emit as emit_build_profile, read as read_build_profile
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]


def run(command: list[str], cwd: Path, log: Path, timeout: int = 120) -> None:
    """Keep diagnostics for each bounded build or simulation stage."""
    with log.open("w") as stream:
        subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout)


def sequences(rows: list[list]) -> dict[int, list]:
    """Preserve causal event order within each actor, allowing inter-actor reordering."""
    result: dict[int, list] = {}
    for x, step, kind, value in rows:
        result.setdefault(x, []).append([step, kind, value])
    return result


def map_xc7(stage: Path, compiled: Path, yosys: Path, public: Path) -> dict:
    """Measure application resources, excluding board I/O, transport and clocking."""
    source = ROOT / "platforms/xc7/phi_timing.py"
    spec = importlib.util.spec_from_file_location("_repetition_phi_timing", source)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load mapping support: {source}")
    timing = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(timing)
    accounting = compiler_tool(public, "measure_topology_debug")

    stage.mkdir(exist_ok=True)
    sources = [compiled / name for name in
               ("repetition.v", "phi_repetition_top.v", "hls_1r1w_ram.v")]
    script = "read_verilog -sv " + " ".join(map(timing.quote, sources)) + "\n"
    script += "hierarchy -check -top phi_repetition_top\nproc\nflatten\nopt\nmemory_collect\n"
    script += "synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top phi_repetition_top\n"
    script += "check -assert\nscc -expect 0\ntee -o stat.json stat -json -tech xilinx\n"
    receipt = timing.mapped_stage(stage, "map", script, sources, ["stat.json", "map.log"], yosys)
    cells = json.loads((stage / "stat.json").read_text())["design"]["num_cells_by_type"]
    return {**accounting.cell_counts(cells), "DSP": cells.get("DSP48E1", 0),
            "CARRY4": cells.get("CARRY4", 0), "completion": receipt}


def profile(stage: Path, xls: Path, count: int, table: Path | None,
            yosys: Path | None, *, public: Path | None = None) -> None:
    """Reject per-actor BEAM/RTL event mismatches before reporting performance."""
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "results.json").unlink(missing_ok=True)
    run(["rebar3", "as", "test", "compile"], ROOT, stage / "beam.log")
    public = compiler_root("test", public)
    compiler = compiler_tool(public, "compile_xls")
    expression = ('S=os:getenv("REPETITION_STAGE"), '
                  'N=list_to_integer(os:getenv("REPETITION_COUNT")), '
                  'phi_repetition_fixture:write(S,N), '
                  'phi_repetition_fixture:oracle(S,N), halt().')
    with (stage / "prepare.log").open("w") as out:
        subprocess.run(erl_command(public, expression, profile="test"),
                       cwd=ROOT, env=dict(erlang_environment("test", compiler=public),
                                        REPETITION_STAGE=str(stage), REPETITION_COUNT=str(count)),
                       stdout=out, stderr=subprocess.STDOUT, check=True, timeout=120)
    for directory in (ROOT / "apps/hls_target/priv/xls/lib",
                      compiler_resource(public, "hls_compile", "priv/xls/lib"),
                      compiler_resource(public, "hls_fabric", "priv/xls/fabric")):
        for source in directory.glob("*.x"):
            shutil.copy2(source, stage / source.name)
    for source in (ROOT / "workloads/hls_phi/src/phi_field.x",
                   compiler_resource(public, "hls_target", "priv/rtl/hls_1r1w_ram.v")):
        shutil.copy2(source, stage / source.name)
    configurations = ",".join(
        f"scheduler_{i}_{kind}:1R1W:_scheduler_{i}_{stem}_read_req_out:"
        f"_scheduler_{i}_{stem}_read_resp_in:_scheduler_{i}_{stem}_write_req_out:"
        f"_scheduler_{i}_{stem}_write_resp_in"
        for i in range(3) for kind, stem in [("state", "ram"), ("mailbox", "mailbox")])
    policy_file = Path(tempfile.mkdtemp(prefix="build-policy-", dir=stage)) / "repetition-build-profile.json"
    emit_build_profile(policy_file, profile="test", public=public,
                       delay_model="xc7_7030" if table else "unit")
    expected_policy = compiler.sha(policy_file)

    def policy(snapshot: Path) -> dict:
        """Consume selected policy bytes from the compiler's immutable candidate."""
        selected = snapshot / "assets" / policy_file.name
        if compiler.sha(selected) != expected_policy:
            raise ValueError("repetition build policy changed during snapshot")
        return read_build_profile(selected)

    compiled = compiler.build(stage / "phi_repetition_topology.x", xls, stage / "compiled",
                     name="repetition", codegen_flags=lambda snapshot: policy(snapshot)["codegen_flags"],
                     ram_configurations=configurations, timeout=1200,
                     assets=[stage / "phi_repetition_top.v", stage / "hls_1r1w_ram.v", policy_file],
                     metadata=lambda snapshot: {"line_cells": count, "build_profile": policy(snapshot)},
                     delay_table=table)
    oracle = json.loads((stage / "oracle.json").read_text())
    expected = sequences([[x, step, kind, value] for _, x, _, step, kind, value in oracle])
    measurements = []
    for stalled in (0, 1):
        output = stage / f"stalled-{stalled}"
        output.mkdir(exist_ok=True)
        run(["iverilog", "-g2012", "-s", "phi_repetition_tb",
             f"-Pphi_repetition_tb.N={count}", f"-Pphi_repetition_tb.STALLED={stalled}",
             "-o", str(output / "simulation.vvp"),
             *[str(compiled / name) for name in
               ("repetition.v", "phi_repetition_top.v", "hls_1r1w_ram.v")],
             str(ROOT / "workloads/hls_phi/test/rtl/phi_repetition_tb.sv")], output, output / "compile.log")
        (output / "events.txt").unlink(missing_ok=True)
        run(["vvp", "simulation.vvp"], output, output / "simulation.log", 300)
        rows = []
        for line in (output / "events.txt").read_text().splitlines():
            x, step, kind, value = map(int, line.split())
            rows.append([x, step, {17: "phi_status", 11: "phi_correction"}[kind], value])
        if sequences(rows) != expected:
            raise ValueError(f"BEAM/RTL event mismatch; see {output}")
        (output / "simulation.vvp").unlink()
        log = (output / "simulation.log").read_text()
        match = re.search(rf"PASS N={count} cycles_per_step=([0-9.]+) stalled={stalled}", log)
        if not match:
            raise ValueError(f"missing completed measurement; see {output}")
        measurements.append({"stalled": bool(stalled), "events": len(rows),
                             "cycles_per_step": float(match[1]), "result": log})
    result = {"cells": count, "actors": 3 * count, "simulations": measurements}
    if yosys:
        result["mapping"] = map_xc7(stage / "mapping", compiled, yosys, public)
    (stage / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


def main() -> None:
    """Require explicit tool paths and a line bounded by u16 coordinates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--erl-hls", type=Path, help="Compiler source with matching test-profile beams.")
    parser.add_argument("stage", type=lambda s: Path(s).resolve())
    parser.add_argument("--xls", type=lambda s: Path(s).resolve(), required=True)
    parser.add_argument("--cells", type=int, default=3)
    parser.add_argument("--table", type=lambda s: Path(s).resolve())
    parser.add_argument("--yosys", type=lambda s: Path(s).resolve())
    args = parser.parse_args()
    if not 2 <= args.cells <= 65535:
        parser.error("cells must be in 2..65535")
    profile(args.stage, args.xls, args.cells, args.table, args.yosys, public=args.erl_hls)


if __name__ == "__main__":
    main()
