#!/usr/bin/env python3
"""Generate the private credit link and simulate isolation, ordering and faults."""
import argparse
import hashlib
import json
from pathlib import Path
from backend_paths import PUBLIC
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, stage, name, output=None):
    with (stage / f"{name}.log").open("w") as log:
        if output:
            with (stage / output).open("w") as generated:
                subprocess.run(command, cwd=stage, stdout=generated, stderr=log,
                               check=True, timeout=600)
        else:
            subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/credit-link")
    args = parser.parse_args()
    stage, xls = args.stage.resolve(), args.xls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "priv/xls/hls_credit_link.x", ROOT / "test/xls/credit_link.x",
               args.erl_hls / "priv/xls/lib/axis.x"]
    tests = [ROOT / "test/rtl" / f"{name}.sv" for name in ("credit_link_tb", "credit_link_fault_tb")]
    tracked = sources + tests + [Path(__file__)] + list((xls / "xls/dslx/stdlib").rglob("*.x"))
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
        run(command, stage, name, output)
    for source in tests:
        name = source.stem
        run(["iverilog", "-g2012", "-s", name, "-o", name + ".vvp", str(source), "link.v"], stage, name + "-compile")
        run(["vvp", name + ".vvp"], stage, name)
        print((stage / f"{name}.log").read_text(), end="")
    if provenance != {str(path): digest(path) for path in tracked}:
        raise RuntimeError("credit-link build inputs changed during the run")
    (stage / "provenance.json").write_text(json.dumps({
        "commands": [command for command, _, _ in commands],
        "inputs": provenance,
        "rtl_sha256": digest(stage / "link.v")}, indent=2) + "\n")


if __name__ == "__main__":
    main()
