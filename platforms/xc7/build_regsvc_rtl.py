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
BACKEND = ROOT.parent.parent
UMBRELLA_TOOLS = BACKEND / "tools/hls_fabric"
BUILD = ROOT / "build/routed-dma/rtl"
GENERATED = ("regsvc", "hls_debug_observer", "hls_debug_server")
HANDWRITTEN = (("erl_hls", "test/rtl/regsvc_fabric_fixture.sv"),
               ("erl_hls", "src/examples/regsvc/regsvc_core_adapter.v"),
               ("erl_hls", "src/examples/regsvc/regsvc_debug_top.v"),
               ("hls_target", "priv/rtl/debug/hls_debug_tap.v"),
               ("hls_target", "priv/rtl/debug/hls_debug_monitor.v"),
               ("hls_target", "priv/rtl/debug/hls_trace_store.v"),
               ("hls_fabric", "priv/rtl/fabric/hls_fabric_ingress.v"),
               ("hls_fabric", "priv/rtl/fabric/hls_fabric_egress.v"))


def handwritten_sources(public: Path) -> list[Path]:
    """Resolve board support RTL through each selected umbrella application owner."""
    from compiler_paths import compiler_application
    return [compiler_application(public, application) / name for application, name in HANDWRITTEN]


def runtime_sources(public: Path) -> list[Path]:
    """List runtime sources beside the selected compiler application."""
    return sorted((public.parent / "hls_runtime/src").rglob("*.erl"))


def sources(directory: Path) -> list[Path]:
    """Reject stale compiler inputs or modified outputs before loading generated RTL."""
    manifest = json.loads((directory / "manifest.json").read_text())
    public = Path(manifest["compiler_root"])
    for name, expected in manifest["inputs"].items():
        if digest(public / name) != expected:
            raise ValueError(f"RTL source changed; rebuild: {name}")
    for name, expected in manifest["outputs"].items():
        if digest(directory / name) != expected:
            raise ValueError(f"RTL output changed: {name}")
    return [*handwritten_sources(public),
            *(directory / f"{name}.v" for name in GENERATED)]


def compiler_context(public: Path | None, profile: str) -> Path:
    """Refresh the selected fabric profile, or require an explicit prebuilt compiler root."""
    # Bootstrap helpers belong to this umbrella even when an explicit compiler root is selected.
    sys.path.insert(0, str(UMBRELLA_TOOLS))
    from backend_paths import compiler_ebin
    from compiler_paths import compiler_root
    if public is None:
        rebar = ["rebar3", "compile"] if profile == "default" else ["rebar3", "as", profile, "compile"]
        subprocess.run(rebar, cwd=BACKEND, check=True, env={**os.environ, "ERL_AFLAGS": ""})
    selected = compiler_root(profile, public, BACKEND)
    compiler_ebin(selected, profile, BACKEND)
    return selected


def build(xls: Path, public: Path | None = None, profile: str = "default") -> Path:
    """Generate DSLX, compile three procs and require the existing routed RTL regression."""
    public = compiler_context(public, profile)
    from backend_paths import compiler_ebin, erlang_environment
    from compiler_paths import compiler_application, compiler_source, compiler_tool
    compiler = compiler_tool(public, "compile_xls")
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "manifest.json").unlink(missing_ok=True)
    stage = BUILD / "dslx"
    stage.mkdir(exist_ok=True)
    subprocess.run(["erl", "-noshell", "-pa", str(compiler_ebin(public, profile)),
                    "-eval", 'ok = file:write_file(os:getenv("REGSVC_OUTPUT"), '
                    'xls_parse:to_xls("src/examples/regsvc/regsvc.erl")), halt().'],
                   cwd=public, env={**erlang_environment(profile, BACKEND, compiler=public),
                                    "REGSVC_OUTPUT": str(stage / "regsvc.x")}, check=True)
    libraries = sorted({path.resolve()
                        for application in ("hls_compile", "hls_fabric", "hls_target")
                        for path in (compiler_application(public, application) / "priv/xls").rglob("*.x")})
    if len({p.name for p in libraries}) != len(libraries):
        raise ValueError("DSLX import names collide")
    for path in libraries:
        shutil.copyfile(path, stage / path.name)
    for name, top, depth, interval in (("regsvc", "Top", 1, None),
                                      ("hls_debug_observer", "Observer", 2, None),
                                      ("hls_debug_server", "DebugServer", 3, 2)):
        output = BUILD / f"{name}-build"
        compiler.build(stage / f"{name}.x", xls, output, top=top,
                       pipeline_stages=depth, initiation_interval=interval)
        shutil.copyfile(output / f"{name}.v", BUILD / f"{name}.v")
    facade = compiler_application(public, "erl_hls")
    compile_app = compiler_application(public, "hls_compile")
    inputs = [Path(__file__), compiler_source(public, "compile_xls"),
              *handwritten_sources(public),
              *sorted((facade / "src").rglob("*.erl")), *sorted((compile_app / "src").rglob("*.erl")),
              *runtime_sources(public),
              *sorted((compile_app / "include").rglob("*.hrl")), *libraries]
    manifest = {"compiler_root": str(public), "rebar_profile": profile,
                "inputs": {os.path.relpath(p, public): digest(p) for p in inputs},
                "outputs": {f"{name}.v": digest(BUILD / f"{name}.v") for name in GENERATED},
                "build_manifests": {name: digest(BUILD / f"{name}-build/{name}.build.json") for name in GENERATED},
                "xls_tools": {name: digest(xls / name) for name in
                              ("ir_converter_main", "opt_main", "codegen_main")}}
    rtl = [*handwritten_sources(public), *(BUILD / f"{name}.v" for name in GENERATED)]
    with (BUILD / "test.log").open("w") as log:
        subprocess.run(["iverilog", "-g2012", "-s", "regsvc_pair_tb", "-o", str(BUILD / "test.vvp"),
                        str(facade / "test/rtl/regsvc_pair_tb.sv"), *map(str, rtl)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["vvp", str(BUILD / "test.vvp")], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=30)
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return BUILD


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--erl-hls", type=Path, help="Explicit compiler sources and matching beams.")
    parser.add_argument("--profile", default="default")
    args = parser.parse_args()
    print(build(args.xls_root.resolve(), args.erl_hls, args.profile))
