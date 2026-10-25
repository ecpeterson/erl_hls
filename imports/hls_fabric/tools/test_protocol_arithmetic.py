"""Check source-bound arithmetic sharing, registered ownership and connected XC7 cost."""
from pathlib import Path
from types import SimpleNamespace
import argparse
import json
from backend_paths import ROOT, erlang_environment
from compiler_paths import compiler_root
from protocol_test_build import compile_build, emit_command
from backend_commands import run
from test_local_protocol import prove


# Public ordinary functions remain reference APIs even on a shared receiver.
ORDINARY_CONTRACT = """
// Preserve all ordinary callback inputs, independently of the sharing owner.
pub fn ordinary(raw: reference::MachineBits, frame: bits[128], received: bool, slot: u32) -> bool {
  let a = reference::local_action_at(raw, frame, received, slot);
  let b = shared::local_action_at(raw, frame, received, slot);
  a.private_machine == b.private_machine && a.dispatched == b.dispatched &&
    a.directive == b.directive && a.phase_boundary == b.phase_boundary
}
"""


def emit(stage: Path, members: int, shared: bool) -> Path:
    """Invoke the public network writer with fresh source and logical actor IDs."""
    stage.mkdir()
    config = stage / "config.erl"
    group = ",arithmetic_groups=>[[" + ",".join(map(str, range(members))) + "]]" if shared else ""
    config.write_text('#{sources=>[{"test/hls_protocol_arithmetic_fixture.erl",[]}],'
        'topology=>{hls_protocol_arithmetic_fixture,topology,[' + str(members) + ']},actor_limit=>3' + group + '}.\n')
    build = stage / "build"
    run(emit_command("network", config, build), stage, "emit", env=erlang_environment("test"))
    return build


def simulate(build: Path, stage: Path, members: int) -> None:
    """Observe only public pins across 32 reset positions, independent stalls and complete drains."""
    manifest = json.loads((build / "network/manifest.json").read_text())
    connections = [".clk(clk)", ".reset(reset)"]
    wires = []
    faults = []
    for p in manifest["outputs"]:
        name, width = p["name"], p["width"]
        wires.append(f"wire [{width-1}:0] {name};")
        connections.append(f".{name}({name})")
        if name.endswith(("_fault", "_failure")): faults.append(name)
    for boundary in manifest["boundaries"]:
        name, i = boundary["name"], boundary["source_index"]
        connections.append(f".{name}_ready(ready[{i}])")
        wires += [f"assign valid[{i}]={name}_valid;", f"assign data[{i}]={name}_data;"]
    wires += ["wire faults=" + "|".join(faults) + ";", "protocol_network dut(" + ",".join(connections) + ");"]
    bench = stage / "bench.sv"
    bench.write_text((ROOT / "test/rtl/protocol_arithmetic_tb.sv").read_text().replace("@@MEMBERS@@", str(members)).replace("@@WIRING@@", "\n".join(wires)))
    run(["iverilog", "-g2012", "-s", "tb", "-o", stage / "sim", bench,
         build / "network/core.v", build / "network/protocol_network.sv"], stage, "rtl-compile")
    run(["vvp", stage / "sim"], stage, "rtl-witness")
    assert "ARITHMETIC_PASS" in (stage / "rtl-witness.log").read_text()


def mapped_cost(build: Path, stage: Path) -> dict:
    """Count the complete connected fixture; local mapping is not routed area or timing."""
    netlist = stage / "mapped.json"
    script = stage / "map.ys"
    script.write_text(f'read_verilog "{build}/network/core.v" "{build}/network/protocol_network.sv"\n'
        f'synth_xilinx -family xc7 -top protocol_network -flatten -nowidelut\nwrite_json "{netlist}"\n')
    run(["yosys", "-Q", "-T", "-s", script], stage, "map")
    types = [c["type"] for c in json.loads(netlist.read_text())["modules"]["protocol_network"]["cells"].values()]
    counts = {key: sum(t.startswith(prefix) for t in types) for key, prefix in
              [("lut", "LUT"), ("ff", "FD"), ("dsp", "DSP"), ("bram", "RAMB")]}
    (stage / "cost.json").write_text(json.dumps(counts, indent=2) + "\n")
    return counts


def action_contract(xls: Path, build: Path, stage: Path) -> None:
    """Check source completion, ordinary public actions and busy exclusion over finite input domains."""
    source = stage / "arithmetic_contract.x"
    source.write_text("import actor_0 as reference;\nimport receiver_0 as shared;\n" +
        "// Under source completion eligibility, shared computation equals ordinary dispatch.\n"
        "pub fn completion(raw: reference::MachineBits) -> bool {\n"
        "let a = reference::local_action_at(raw, bits[128]:0, false, u32:0);\n"
        "let b = shared::local_reduce_action_at(raw, u32:0);\n"
        "!shared::local_reduce_pending(raw,u32:0) || (a.private_machine == b.private_machine &&\n"
        "a.dispatched == b.dispatched && a.directive == b.directive && a.phase_boundary == b.phase_boundary) }\n"
        "// A busy action cannot acquire another completion.\n"
        "pub fn busy(s: shared::LocalOwnerState) -> bool {\n"
        "!shared::local_reduce_request(shared::LocalOwnerState{action_valid:true,..s},u32:0) }\n"
        "// A deliberately wrong destination bit must yield a counterexample.\n"
        "pub fn wrong(raw: reference::MachineBits) -> bool {\n"
        "let a=reference::local_action_at(raw,bits[128]:0,false,u32:0);\n"
        "let b=shared::local_reduce_action_at(raw,u32:0);\n"
        "!shared::local_reduce_pending(raw,u32:0) || a.private_machine == (b.private_machine ^ reference::MachineBits:1) }\n" + ORDINARY_CONTRACT)
    raw = stage / "contract.ir"
    paths = [build / "actors", ROOT / "priv/xls/lib", ROOT / "priv/xls/fabric", compiler_root('test') / "priv/xls/lib", compiler_root('test') / "priv/xls/fabric"]
    run([xls / "ir_converter_main", "--warnings_as_errors=false", "--dslx_path=" + ":".join(map(str, paths)),
         "--dslx_stdlib_path=" + str(xls / "xls/dslx/stdlib"), source], stage, "contract-convert", raw)
    args = SimpleNamespace(xls=xls, yosys="yosys")
    results = [prove(args, stage, raw, "arithmetic_contract", prop, positive)
               for prop, positive in [("completion", True), ("busy", True), ("ordinary", True), ("wrong", False)]]
    (stage / "contracts.json").write_text(json.dumps({"results": results,
        "domain": "All finite fixture inputs: machine/owner bits and slot zero for completion/busy; arbitrary frame, received and slot for ordinary API preservation. Completion eligibility is explicit.",
        "trust": ["source extraction", "DSLX/XLS", "Yosys/ABC/SAT"],
        "limits": "Combinational source equality and busy exclusion, not temporal progress or arbitrary-program refinement."}, indent=2) + "\n")


def main() -> None:
    """Compile each fresh case once; preserve per-case cost and functional evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=lambda p: Path(p).resolve())
    parser.add_argument("stage", type=lambda p: Path(p).resolve())
    parser.add_argument("--cases", nargs="+", choices=["local3", "shared2", "shared3"], default=["local3", "shared2", "shared3"])
    args = parser.parse_args(); args.stage.mkdir()
    run(["rebar3", "as", "test", "compile"], args.stage, "build-backend")
    results = {}
    for case in args.cases:
        members = int(case[-1]); part = args.stage / case
        build = emit(part, members, case.startswith("shared"))
        build = compile_build(args.xls, build, profile="test")
        simulate(build, part, members)
        results[case] = mapped_cost(build, part)
        if case == "shared3": action_contract(args.xls, build, part)
        (args.stage / "costs.json").write_text(json.dumps(results, indent=2) + "\n")
    if "local3" in results and "shared3" in results:
        baseline, shared = results["local3"], results["shared3"]
        assert shared["dsp"] <= 1 and shared["dsp"] < baseline["dsp"], results
        assert shared["lut"] <= baseline["lut"] + 1000 and shared["ff"] <= baseline["ff"] + 2, results
    (args.stage / "result.json").write_text(json.dumps({"passed": True, "costs": results,
        "evidence": "32 reset positions with finite independent-stall RTL witnesses; XC7 screen only, no native forecast."}, indent=2) + "\n")


if __name__ == "__main__": main()
