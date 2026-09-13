#!/usr/bin/env python3
"""Build matched production and fully instrumented D3 phi-memory applications.

Uses native XLS plus Yosys. Each directory retains DSLX, IR, RTL, source hashes,
commands and logs; debug/ contains the deployable shared-transport wrapper.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

import topology_debug as topology

ROOT = Path(__file__).resolve().parents[1]


def compile_dslx(xls, stage, module, top, stages, ii=1, rams=None):
    commands = [
        (".ir", [str(xls / "ir_converter_main"), "--warnings_as_errors=false", "--dslx_path=.",
                 f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}", f"--top={top}", f"{module}.x"]),
        (".opt.ir", [str(xls / "opt_main"), f"{module}.ir"]),
        (".v", [str(xls / "codegen_main"), f"--pipeline_stages={stages}", f"--worst_case_throughput={ii}",
                "--delay_model=unit", "--use_system_verilog=false", "--reset=reset", "--fifo_module=",
                *(["--flop_inputs=false", "--flop_outputs=true", f"--ram_configurations={rams}"] if rams else []),
                f"{module}.opt.ir"])]
    for suffix, command in commands:
        with (stage / f"{module}{suffix}").open("w") as output, (stage / f"{module}{suffix}.log").open("w") as log:
            subprocess.run(command, cwd=stage, stdout=output, stderr=log, check=True)
    (stage / f"{module}.build.json").write_text(json.dumps({
        "commands": commands, "tools": {name: hashlib.sha256((xls / name).read_bytes()).hexdigest()
            for name in ("ir_converter_main", "opt_main", "codegen_main")},
        "sources": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.glob("*.x")},
        "stdlib": {str(p.relative_to(xls)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in (xls / "xls/dslx/stdlib").rglob("*.x")},
        "outputs": {f"{module}{suffix}": hashlib.sha256((stage / f"{module}{suffix}").read_bytes()).hexdigest()
                    for suffix, _ in commands}
    }, indent=2) + "\n")


def build(args):
    stage, xls = args.stage.resolve(), args.xls.resolve()
    subprocess.run(["rebar3", "as", "test", "compile"], cwd=ROOT, check=True)
    for mode in ("production", "observed"):
        out = stage / mode
        out.mkdir(parents=True, exist_ok=True)
        subprocess.run(["erl", "-noshell", "-pa", str(ROOT / "_build/test/lib/erl_hls/ebin"),
                        str(ROOT / "_build/test/lib/erl_hls/test"), "-eval",
                        '[Dir, Flag, Shards] = init:get_plain_arguments(), ok = hls_phi_debug_dslx:write(Dir, Flag =:= "true", list_to_integer(Shards)), halt().',
                        "-extra", str(out), str(mode == "observed").lower(), str(args.shards)], cwd=ROOT, check=True)
        for source in [*ROOT.glob("priv/xls/lib/*.x"), *ROOT.glob("priv/xls/fabric/*.x"),
                       ROOT / "src/examples/phi_decoder/phi_field.x", ROOT / "priv/rtl/hls_1r1w_ram.v"]:
            shutil.copy(source, out)
        banks = len(json.loads((out / "actors.json").read_text())["banks"])
        rams = subprocess.check_output(["bash", "-c", 'source tools/phi_scheduler_rams.sh; phi_scheduler_ram_configurations "$1"',
                                        "phi-ram-config", str(banks)], cwd=ROOT, text=True).strip()
        print(f"Building {mode}: {banks} scheduler banks", flush=True)
        compile_dslx(xls, out, "phi_memory_gateway", "Top", 2, rams=rams)
    (stage / "fixture.json").write_text(json.dumps({"shards": args.shards}) + "\n")
    support = stage / "support"
    support.mkdir(exist_ok=True)
    for source in [*ROOT.glob("priv/xls/debug/*.x"), *ROOT.glob("priv/xls/fabric/*.x"), *ROOT.glob("priv/xls/lib/*.x")]:
        shutil.copy(source, support)
    for module, top, stages, ii in (("hls_fabric_router", "HostRoutedTx", 1, 1),
                                    ("hls_debug_observer", "Observer", 2, 1),
                                    ("hls_debug_server", "DebugServer", 3, 2)):
        compile_dslx(xls, support, module, top, stages, ii)
    out = stage / "observed"
    topology.instrument(argparse.Namespace(
        rtl=[out / "phi_memory_top.v", out / "phi_memory_gateway.v", out / "hls_1r1w_ram.v",
             support / "hls_fabric_router.v"], top="phi_memory_top", clock="aclk", reset="aresetn",
        reset_active_low=True, output_top="hls_instrumented_application", stage=stage / "debug",
        yosys=args.yosys, actor_projection=out / "actors.json", actor_root="",
        monitor_rx="s_axis", monitor_tx="m_axis", monitor_routed=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("_build/phi-debug"))
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--shards", type=int, choices=range(1, 10), default=1,
                        help="executors per phi plane; the standard D3 deployment uses one")
    build(parser.parse_args())
