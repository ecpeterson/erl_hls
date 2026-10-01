#!/usr/bin/env python3
"""Compile the application gateway and check its public protocol under stalls and malformed traffic."""
import argparse
import json
from pathlib import Path
from backend_paths import PUBLIC
import shutil

from test_actor_rtl import digest, execute

ROOT = Path(__file__).resolve().parents[1]


def run(args: argparse.Namespace) -> None:
    """Retain source/tool hashes beside generated RTL and the protocol witness."""
    stage, public, xls = args.stage, args.erl_hls, args.xls
    stage.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "priv/xls/hls_partition_io.x", ROOT / ("test/xls/partition_tile_io.x" if args.tile else "test/xls/partition_io.x"),
               ROOT / "priv/xls/hls_partition_tile_io.x",
               public / "priv/xls/lib/axis.x", public / "priv/xls/fabric/hls_spatial_router.x"]
    bench = ROOT / "test/rtl/partition_io_tb.sv"
    tracked = sources + [bench, Path(__file__), ROOT / "tools/test_actor_rtl.py"]
    tracked += [xls / name for name in ("ir_converter_main", "opt_main", "codegen_main")]
    tracked += list((xls / "xls/dslx/stdlib").rglob("*.x"))
    tracked += [Path(shutil.which(name)).resolve() for name in ("iverilog", "vvp")]
    inputs = {str(path): digest(path) for path in tracked}
    for path in sources:
        shutil.copy(path, stage / ("partition_io.x" if path.name == "partition_tile_io.x" else path.name))
    commands = [
        ("convert", [str(xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
                     "--dslx_path=.", f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}", "partition_io.x"], stage / "io.ir"),
        ("optimize", [str(xls / "opt_main"), "io.ir"], stage / "io.opt.ir"),
        ("codegen", [str(xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit",
                     "--flop_inputs=false", "--flop_outputs=true", "--use_system_verilog=false",
                     "--reset=reset", "--fifo_module=", "--module_name=partition_io", "io.opt.ir"], stage / "io.v")]
    for name, command, output in commands:
        execute(command, stage, name, timeout=300, output=output)
    execute(["iverilog", *(["-DPARTITION_TILE"] if args.tile else []), "-g2012", "-s", "partition_io_tb", "-o", "io.vvp", str(bench), "io.v"], stage, "iverilog")
    execute(["vvp", "io.vvp"], stage, "simulation", timeout=30)
    result = (stage / "simulation.log").read_text()
    if "PASS: routed gateway" not in result:
        raise RuntimeError("gateway simulation did not reach its assertions")
    if inputs != {str(path): digest(path) for path in tracked}:
        raise RuntimeError("gateway inputs changed during compilation")
    (stage / "provenance.json").write_text(json.dumps({
        "inputs": inputs, "commands": [command for _, command, _ in commands],
        "rtl_sha256": digest(stage / "io.v")}, indent=2) + "\n")
    print(result, end="")


def main() -> None:
    """Resolve tool and output paths before starting a fresh regression."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--tile", action="store_true", help="exercise wrapper-bound configuration using the same protocol checks")
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/partition-io")
    args = parser.parse_args()
    for name in ("xls", "erl_hls", "stage"):
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == "__main__":
    main()
