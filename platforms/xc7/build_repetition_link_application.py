#!/usr/bin/env python3
"""Generate and compile the two scheduled halves of an N=6 repetition line."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from build_link_application import compiler_entry, copy_libraries
from packaging_commands import execute
from ethernet.prepare import digest

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
FIXTURE = ROOT / "application/repetition_link_fixture.erl"
BUILD = ROOT / "build/repetition-link/rtl"
DEVICES = {"a": 0, "b": 1}
CLOCK_PERIOD_PS = 40_000
SIZE = 6
SPLIT = [SIZE // 2, SIZE // 2]
RAM_CONFIGURATIONS = ",".join(
    f"scheduler_{index}_{kind}:1R1W:_scheduler_{index}_{stem}_read_req_out:"
    f"_scheduler_{index}_{stem}_read_resp_in:_scheduler_{index}_{stem}_write_req_out:"
    f"_scheduler_{index}_{stem}_write_resp_in"
    for index in range(3)
    for kind, stem in (("state", "ram"), ("mailbox", "mailbox"))
)


def codegen(xls: Path, optimized: Path, output: Path, log: Path) -> None:
    """Schedule the required two stages for the board's actual 25 MHz clock."""
    arguments = [
        xls / "codegen_main",
        "--pipeline_stages=2",
        f"--clock_period_ps={CLOCK_PERIOD_PS}",
        "--delay_model=unit",
        "--flop_inputs=false",
        "--flop_outputs=true",
        "--use_system_verilog=false",
        "--reset=reset",
        "--fifo_module=",
        f"--ram_configurations={RAM_CONFIGURATIONS}",
        f"--output_verilog_path={output}",
        optimized,
    ]
    with log.open("a") as diagnostics:
        result = subprocess.run([str(value) for value in arguments], cwd=optimized.parent,
                                stdout=diagnostics, stderr=subprocess.STDOUT,
                                timeout=1200)
    if result.returncode:
        raise RuntimeError(f"clock-aware code generation failed; see {log}")


def build(xls: Path, public: Path, output: Path = BUILD, *, profile: str = "default") -> Path:
    """Compile both role gateways and retain their external RAM shells."""
    sys.path.insert(0, str(PROJECT / "tools/hls_fabric"))
    from backend_paths import erlang_paths, erlang_environment
    from compiler_paths import compiler_root, compiler_source
    public = compiler_root(profile, public, PROJECT)
    paths = erlang_paths(profile, PROJECT, compiler=public)
    environment = erlang_environment(profile, PROJECT, compiler=public)
    output.mkdir(parents=True, exist_ok=True)
    (output / "manifest.json").unlink(missing_ok=True)
    stage = output / "dslx"
    stage.mkdir(exist_ok=True)
    ebin = output / "ebin"
    ebin.mkdir(exist_ok=True)
    log = output / "build.log"
    log.unlink(missing_ok=True)
    execute(["erlc", "+deterministic", *[item for path in paths for item in ("-pa", path)],
             "-o", ebin, FIXTURE], PROJECT, log, environment, timeout=1200)
    execute(["erl", "-noshell", "-pa", *paths, ebin, "-eval",
             "ok = repetition_link_fixture:write(hd(init:get_plain_arguments())), halt().",
             "-extra", stage], PROJECT, log, environment, timeout=1200)
    libraries = copy_libraries(stage, public)
    phi_field = PROJECT / "workloads/hls_phi/src/phi_field.x"
    artifact_source = PROJECT / "apps/hls_runtime/src/fabric/runtime/hls_deployment_artifact.erl"
    shutil.copyfile(phi_field, stage / phi_field.name)
    compiler = compiler_entry(public)
    products: dict[str, str] = {}
    for role, device in DEVICES.items():
        release = output / f"role-{role}-build"
        execute([os.environ.get("PYTHON", "python3"), compiler,
                 stage / f"phi_device_{device}.x", xls,
                 "--output", release, "--name", "repetition_application",
                 "--top", "Top", "--pipeline-stages", "2",
                 "--ram-configurations", RAM_CONFIGURATIONS], PROJECT, log, timeout=1200)
        rtl = output / f"repetition_application_{role}.v"
        ram = output / f"repetition_application_{role}_ram.v"
        codegen(xls, release.resolve() / "repetition_application.opt.ir", rtl, log)
        shutil.copyfile(stage / f"phi_device_{device}_ram.v", ram)
        products[rtl.name] = digest(rtl)
        products[ram.name] = digest(ram)
    inputs = [Path(__file__), ROOT / "packaging_commands.py",
              ROOT / "build_link_application.py", FIXTURE, artifact_source,
              compiler, compiler_source(public, "compile_xls"), phi_field,
              *libraries, *sorted((PROJECT / "apps/hls_fabric/src").glob("*.erl")),
              *sorted((PROJECT / "workloads/hls_phi/src").glob("*.erl"))]
    generated = ["deployment-a.etf", "deployment-b.etf", "fixture.json"]
    manifest = {
        "compiler_root": str(public), "rebar_profile": profile,
        "profile": "repetition-link-application",
        "size": SIZE,
        "split": SPLIT,
        "roles": list(DEVICES),
        "transport": "serial-credit-over-ethernet",
        "application_clock_period_ps": CLOCK_PERIOD_PS,
        "pipeline_stages": 2,
        "inputs": {os.path.relpath(path, PROJECT): digest(path) for path in inputs},
        "outputs": products | {name: digest(stage / name) for name in generated},
        "xls_tools": {name: digest(xls / name) for name in
                      ("ir_converter_main", "opt_main", "codegen_main")},
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return output


def main() -> None:
    """Select the pinned XLS installation and public compiler source checkout."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--public", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=BUILD)
    parser.add_argument("--profile", default="default")
    args = parser.parse_args()
    print(build(args.xls.resolve(), args.public.resolve(), args.output.resolve(), profile=args.profile))


if __name__ == "__main__":
    main()
