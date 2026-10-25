#!/usr/bin/env python3
"""Generate the private credit link and simulate isolation, ordering and faults."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root
import shutil
from backend_commands import digest, execute

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """Compile a fresh link and run the ordered-delivery and malformed-frame witnesses."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/credit-link")
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    stage, xls = args.stage.resolve(), args.xls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "priv/xls/hls_credit_link.x", ROOT / "test/xls/credit_link.x",
               args.erl_hls / "priv/xls/lib/axis.x"]
    tests = [ROOT / "test/rtl" / f"{name}.sv" for name in ("credit_link_tb", "credit_link_fault_tb")]
    tracked = sources + tests + [Path(__file__), ROOT/'tools/backend_commands.py'] + list((xls / "xls/dslx/stdlib").rglob("*.x"))
    tracked += [xls / name for name in ("ir_converter_main", "opt_main", "codegen_main")]
    provenance = {str(path): digest(path) for path in tracked}
    for path in sources:
        shutil.copyfile(path, stage / path.name)
    commands = [
        ([str(xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
          "--dslx_path=.", f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}", "credit_link.x"], "convert", "link.ir"),
        ([str(xls / "opt_main"), "link.ir"], "optimize", "link.opt.ir"),
        ([str(xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit", "--flop_inputs=false",
          "--flop_outputs=true", "--use_system_verilog=false", "--reset=reset", "--fifo_module=",
          "--module_name=link", "link.opt.ir"], "codegen", "link.v")]
    for command, name, output in commands:
        execute(command, stage, name, timeout=600, output=stage / output)
    for source in tests:
        name = source.stem
        execute(["iverilog", "-g2012", "-s", name, "-o", name + ".vvp", str(source), "link.v"], stage, name + "-compile", timeout=600)
        execute(["vvp", name + ".vvp"], stage, name, timeout=600)
        print((stage / f"{name}.log").read_text(), end="")
    if provenance != {str(path): digest(path) for path in tracked}:
        raise RuntimeError("credit-link build inputs changed during the run")
    (stage / "provenance.json").write_text(json.dumps({
        "commands": [command for command, _, _ in commands],
        "inputs": provenance,
        "rtl_sha256": digest(stage / "link.v")}, indent=2) + "\n")


if __name__ == "__main__":
    main()
