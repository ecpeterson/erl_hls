#!/usr/bin/env python3
"""Generate and compile the two role-specific partition-link applications."""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

from ethernet.prepare import digest
from packaging_commands import execute

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
ACTOR = ROOT / "application/hls_link_probe_actor.erl"
FIXTURE = ROOT / "application/link_probe_fixture.erl"
BUILD = ROOT / "build/partition-link/rtl"


def compiler_entry(public: Path) -> Path:
    """Return the target application's standalone build entrypoint."""
    from compiler_paths import compiler_resource
    return compiler_resource(public, "hls_target", "priv/tools/compile_xls.py")


def copy_libraries(stage: Path, public: Path) -> list[Path]:
    """Flatten the complete private DSLX libraries after rejecting name collisions."""
    from compiler_paths import compiler_resource
    roots = [compiler_resource(public, "hls_compile", "priv/xls"),
             compiler_resource(public, "hls_fabric", "priv/xls"),
             compiler_resource(public, "hls_target", "priv/xls")]
    libraries = sorted({path.resolve() for root in roots for path in root.rglob("*.x")})
    names = [path.name for path in libraries]
    if len(set(names)) != len(names):
        duplicates = sorted({name for name in names if names.count(name) > 1})
        raise ValueError(f"DSLX import names collide: {duplicates}")
    for path in libraries:
        shutil.copyfile(path, stage / path.name)
    return libraries


def build(xls: Path, public: Path, output: Path = BUILD, *, profile: str = "default") -> Path:
    """Compile the actor, generated graphs and two complete gateway wrappers."""
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
             "-o", ebin, ACTOR, FIXTURE], PROJECT, log, environment, timeout=1200)
    expression = ("ok = link_probe_fixture:write(hd(init:get_plain_arguments()), "
                  "lists:nth(2, init:get_plain_arguments())), halt().")
    execute(["erl", "-noshell", "-pa", *paths, ebin, "-eval", expression, "-extra", stage, ACTOR], PROJECT, log, environment, timeout=1200)
    libraries = copy_libraries(stage, public)
    compiler = compiler_entry(public)
    artifact_source = PROJECT / "apps/hls_runtime/src/fabric/runtime/hls_deployment_artifact.erl"
    products = {}
    for role in ("a", "b"):
        release = output / f"role-{role}-build"
        execute([os.environ.get("PYTHON", "python3"), compiler,
                 stage / f"link_application_{role}.x", xls,
                 "--output", release, "--name", "link_application",
                 "--top", "Top", "--pipeline-stages", "2"], PROJECT, log, timeout=1200)
        rtl = output / f"link_application_{role}.v"
        shutil.copyfile(release / "link_application.v", rtl)
        products[rtl.name] = digest(rtl)
    inputs = [Path(__file__), ROOT / "packaging_commands.py", ACTOR, FIXTURE,
              artifact_source, compiler, compiler_source(public, "compile_xls"),
              *libraries, *sorted((PROJECT / "apps/hls_fabric/src").glob("*.erl"))]
    manifest = {
        "compiler_root": str(public), "rebar_profile": profile,
        "profile": "partition-link-application",
        "roles": ["a", "b"],
        "transport": "serial-credit-over-ethernet",
        "inputs": {os.path.relpath(path, PROJECT): digest(path) for path in inputs},
        "outputs": products | {
            "hls_link_probe_actor.beam": digest(ebin / "hls_link_probe_actor.beam")
        } | {
            name: digest(stage / name) for name in
            ("deployment-a.etf", "deployment-b.etf", "fixture.json")
        },
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
