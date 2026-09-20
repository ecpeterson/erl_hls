#!/usr/bin/env python3
"""Compile the current routed register service and debug procs for board integration."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from prepare_te0715_boot import digest

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
BUILD = ROOT / "build/routed-dma/rtl"
GENERATED = ("regsvc", "hls_debug_observer", "hls_debug_server")
HANDWRITTEN = ("test/rtl/regsvc_fabric_fixture.sv", "src/examples/regsvc/regsvc_core_adapter.v",
               "src/examples/regsvc/regsvc_debug_top.v", "priv/rtl/debug/hls_debug_tap.v",
               "priv/rtl/debug/hls_debug_monitor.v", "priv/rtl/debug/hls_trace_store.v",
               "priv/rtl/fabric/hls_fabric_ingress.v", "priv/rtl/fabric/hls_fabric_egress.v")


def sources(directory: Path) -> list[Path]:
    """Reject stale compiler inputs or modified outputs before loading generated RTL."""
    manifest = json.loads((directory / "manifest.json").read_text())
    for name, expected in manifest["inputs"].items():
        if digest(PROJECT / name) != expected:
            raise ValueError(f"RTL source changed; rebuild: {name}")
    for name, expected in manifest["outputs"].items():
        if digest(directory / name) != expected:
            raise ValueError(f"RTL output changed: {name}")
    return [*(PROJECT / name for name in HANDWRITTEN),
            *(directory / f"{name}.v" for name in GENERATED)]


def build(xls: Path) -> Path:
    """Generate DSLX, compile three procs and require the existing routed RTL regression."""
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "manifest.json").unlink(missing_ok=True)
    stage = BUILD / "dslx"
    stage.mkdir(exist_ok=True)
    subprocess.run(["rebar3", "compile"], cwd=PROJECT, check=True)
    subprocess.run(["erl", "-noshell", "-pa", str(PROJECT / "_build/default/lib/erl_hls/ebin"),
                    "-eval", 'ok = file:write_file(os:getenv("REGSVC_OUTPUT"), '
                    'xls_parse:to_xls("src/examples/regsvc/regsvc.erl")), halt().'],
                   cwd=PROJECT, env=dict(os.environ, REGSVC_OUTPUT=str(stage / "regsvc.x")), check=True)
    libraries = list((PROJECT / "priv/xls").rglob("*.x"))
    if len({p.name for p in libraries}) != len(libraries):
        raise ValueError("DSLX import names collide")
    for path in libraries:
        shutil.copyfile(path, stage / path.name)
    for name, top, depth, extra in (("regsvc", "Top", 1, []),
                                   ("hls_debug_observer", "Observer", 2, []),
                                   ("hls_debug_server", "DebugServer", 3, ["--initiation-interval", "2"])):
        output = BUILD / f"{name}-build"
        subprocess.run([sys.executable, str(PROJECT / "tools/compile_xls.py"),
                        str(stage / f"{name}.x"), str(xls), "--output", str(output),
                        "--top", top, "--pipeline-stages", str(depth), *extra], check=True)
        shutil.copyfile(output / f"{name}.v", BUILD / f"{name}.v")
    inputs = [Path(__file__), PROJECT / "tools/compile_xls.py",
              *(PROJECT / name for name in HANDWRITTEN),
              *sorted((PROJECT / "src").rglob("*.erl")), *sorted((PROJECT / "src").rglob("*.hrl")),
              *sorted((PROJECT / "include").rglob("*.hrl")), *sorted((PROJECT / "priv/xls").rglob("*.x"))]
    manifest = {"inputs": {str(p.relative_to(PROJECT)): digest(p) for p in inputs},
                "outputs": {f"{name}.v": digest(BUILD / f"{name}.v") for name in GENERATED},
                "build_manifests": {name: digest(BUILD / f"{name}-build/{name}.build.json") for name in GENERATED},
                "xls_tools": {name: digest(xls / name) for name in
                              ("ir_converter_main", "opt_main", "codegen_main")}}
    rtl = [*(PROJECT / name for name in HANDWRITTEN), *(BUILD / f"{name}.v" for name in GENERATED)]
    with (BUILD / "test.log").open("w") as log:
        subprocess.run(["iverilog", "-g2012", "-s", "regsvc_pair_tb", "-o", str(BUILD / "test.vvp"),
                        str(PROJECT / "test/rtl/regsvc_pair_tb.sv"), *map(str, rtl)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["vvp", str(BUILD / "test.vvp")], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=30)
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return BUILD


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls_root", type=Path)
    print(build(parser.parse_args().xls_root.resolve()))
