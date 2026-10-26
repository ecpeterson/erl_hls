#!/usr/bin/env python3
"""Exercise generated multi-peer connectivity with independent blocked recipients and repeated lane IDs."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root
import shutil

from backend_commands import digest, execute
from backend_paths import erl_command
from backend_paths import ROOT


def connections() -> str:
    """Bind one generated four-peer endpoint to four identical single-link endpoints."""
    ports = [".clk(clk)", ".reset(reset)"]
    peers = []
    for p in range(4):
        ports += [f"._link_{p}_in(back[{p}])", f"._link_{p}_in_vld(back_valid[{p}])", f"._link_{p}_in_rdy(back_ready[{p}])",
                  f"._link_{p}_out(tx[{p}])", f"._link_{p}_out_vld(tx_valid[{p}])", f"._link_{p}_out_rdy(tx_ready[{p}])",
                  f"._fault_{p}_out(fault[{p}])", f"._fault_{p}_out_vld(fault_valid[{p}])", f"._fault_{p}_out_rdy(1'b1)"]
        other = [".clk(clk)", ".reset(reset)", f"._link_in(tx[{p}])", f"._link_in_vld(tx_valid[{p}])", f"._link_in_rdy(tx_ready[{p}])",
                 f"._link_out(back[{p}])", f"._link_out_vld(back_valid[{p}])", f"._link_out_rdy(back_ready[{p}])",
                 f"._fault_out(fault[{p+4}])", f"._fault_out_vld(fault_valid[{p+4}])", "._fault_out_rdy(1'b1)"]
        for lane in range(2):
            for node_ports, prefix_in, prefix_out, flat in (
                (ports, f"_outgoing_{p}_c__{lane}", f"_received_{p}_p__{lane}", 2*p+lane),
                (other, f"_frames_in__{lane}", f"_frames_out__{lane}", 8+2*p+lane)):
                node_ports += [f".{prefix_in}(frame_in[{flat}])", f".{prefix_in}_vld(sent[{flat}] < COUNT)",
                               f".{prefix_in}_rdy(in_ready[{flat}])", f".{prefix_out}(frame_out[{flat}])",
                               f".{prefix_out}_vld(out_valid[{flat}])", f".{prefix_out}_rdy(out_ready[{flat}])"]
        peers.append(f"link peer_{p} (" + ",\n    ".join(other) + ");")
    return "partition_peers center (" + ",\n    ".join(ports) + ");\n" + "\n".join(peers) + "\n"


def main() -> None:
    """Compile only small link endpoints; complete D3 application coverage remains a separate CI job."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/partition-peers")
    parser.add_argument("--erl-hls", type=Path, default=None)
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    stage, xls, public = args.stage.resolve(), args.xls.resolve(), args.erl_hls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    execute(erl_command(public, "ok = hls_partition_link_fixture:write(hd(init:get_plain_arguments())), halt().",
                        stage / "partition_peers.x", profile="test"), stage, "generation", timeout=60)
    sources = [ROOT / "priv/xls/hls_credit_link.x", ROOT / "test/xls/credit_link.x", public / "priv/xls/lib/axis.x",
               public / "priv/xls/lib/frame_config.x"]
    for path in sources:
        shutil.copy(path, stage)
    tracked = sources + [ROOT / "test/rtl/partition_peers_tb.sv", Path(__file__),
        ROOT / "src/hls_partition_links.erl", ROOT / "test/hls_partition_link_fixture.erl"]
    tracked += list((xls / "xls/dslx/stdlib").rglob("*.x"))
    tracked += [Path(shutil.which(args.yosys) or args.yosys).resolve()]
    tracked += [xls / name for name in ("ir_converter_main", "opt_main", "codegen_main")]
    before = {str(p): digest(p) for p in tracked}
    for source, top in (("partition_peers", "partition_peers"), ("credit_link", "link")):
        execute([str(xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false", "--dslx_path=.",
                 f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}", f"{source}.x"], stage, top+"-convert", output=stage/f"{top}.ir", timeout=120)
        execute([str(xls / "opt_main"), f"{top}.ir"], stage, top+"-optimize", output=stage/f"{top}.opt.ir", timeout=120)
        execute([str(xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit", "--flop_inputs=false",
                 "--flop_outputs=true", "--use_system_verilog=false", "--reset=reset", "--fifo_module=", f"--module_name={top}",
                 f"{top}.opt.ir"], stage, top+"-codegen", output=stage/f"{top}.v", timeout=120)
    # Independent codegen invocations reuse internal module names. Flatten only the small peer.
    execute([args.yosys, "-Q", "-T", "-p",
        "read_verilog -sv link.v; hierarchy -top link; proc; flatten; write_verilog -noattr link.flat.v"], stage, "flatten-peer")
    (stage / "partition_peers_devices.vh").write_text(connections())
    execute(["iverilog", "-g2012", "-s", "partition_peers_tb", "-I", str(stage), "-o", "peers.vvp",
             str(ROOT / "test/rtl/partition_peers_tb.sv"), "partition_peers.v", "link.flat.v"], stage, "iverilog")
    execute(["vvp", "peers.vvp"], stage, "simulation")
    result = (stage / "simulation.log").read_text()
    if "PASS:" not in result:
        raise RuntimeError("peer test did not complete")
    if before != {str(p): digest(p) for p in tracked}:
        raise RuntimeError("peer test inputs changed during compilation")
    (stage / "provenance.json").write_text(json.dumps({"inputs": before,
        "generated": {str(p.relative_to(stage)): digest(p) for p in sorted(stage.glob("*.x"))},
        "rtl": {p.name: digest(p) for p in sorted(stage.glob("*.v"))}}, indent=2)+"\n")
    print(result, end="")


if __name__ == "__main__":
    main()
