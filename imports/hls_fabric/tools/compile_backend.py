#!/usr/bin/env python3
"""Compile a prepared actor topology with an emitted build profile."""
from __future__ import annotations

import argparse
from pathlib import Path

from compiler_paths import compiler_root, compiler_source, compiler_tool
from completion_fifo import transform
from backend_build_profile import read as read_build_profile


def compile_topology(
    source: Path,
    xls: Path,
    output: Path,
    *,
    name: str,
    assets: list[Path],
    ram_configurations: str | None = None,
    build_profile: Path,
    optimizer_pipeline: Path | None = None,
    timeout: int = 1800,
    public: Path | None = None,
    profile: str = "default",
) -> Path:
    """Publish prepared DSLX with the frozen Erlang profile's schedule and storage policy.

    Unknown completion FIFO shapes fail before publication. The optimizer pipeline
    is a compiler-managed asset; the actual tool executable keeps its own identity.
    public selects compiler tools explicitly; otherwise profile selects the dependency.
    """
    public = compiler_root(profile, public)
    compiler = compiler_tool(public, "compile_xls")
    assets = [*assets, build_profile]

    def selected(snapshot: Path) -> dict:
        """Read only the private snapshot so source edits cannot change an active build."""
        return read_build_profile(snapshot / "assets" / build_profile.name)

    def metadata(snapshot: Path) -> dict:
        """Bind driver identities and the exact emitted profile before invoking XLS."""
        return {"backend": {
            "build_profile": selected(snapshot),
            "driver_sha256": compiler.sha(Path(__file__)),
            "compiler_extension_sha256": compiler.sha(compiler_source(public, "compile_xls")),
        }}

    def finalize(snapshot: Path, manifest: dict) -> dict:
        """Apply only the requested RTL legalization before the executor hashes and publishes it."""
        backend = dict(manifest["backend"])
        if optimizer_pipeline is not None:
            backend.update({
                "optimizer_pipeline_sha256": manifest["assets"]["optimizer_pipeline.txtpb"],
                "optimizer_executable_sha256": manifest["tools"]["opt_main"],
            })
        if backend["build_profile"]["profile"]["postprocess"]["completion_storage"] == "lutram":
            rtl = snapshot / (name + ".v")
            text, audit = transform(rtl.read_text())
            rtl.write_text(text)
            backend.update({
                "completion_fifo": audit,
                "legalization_sha256": compiler.sha(Path(__file__).with_name("completion_fifo.py")),
            })
        return {**manifest, "backend": backend}

    return compiler.build(
        source, xls, output, name=name, top="Top",
        ram_configurations=ram_configurations, assets=assets, timeout=timeout,
        codegen_flags=lambda snapshot: selected(snapshot)["codegen_flags"],
        optimizer_pipeline=optimizer_pipeline, metadata=metadata, finalize=finalize,
    )


def main() -> None:
    """Compile once; simulations and physical measurements consume the same release."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--erl-hls", type=Path, help="Explicit compiler source and Python tool root.")
    parser.add_argument("--profile", default="default", help="Compiled rebar profile when no compiler override is supplied.")
    parser.add_argument("source", type=Path)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name", default="snowflake_actor_topology")
    parser.add_argument("--asset", type=Path, action="append", default=[])
    parser.add_argument("--ram-configurations")
    parser.add_argument("--build-profile", type=Path, required=True, help="JSON emitted by hls-fabric profile.")
    parser.add_argument("--optimizer-pipeline", type=Path, help="Explicit XLS pipeline textproto; frozen into the release.")
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    print(
        compile_topology(
            args.source,
            args.xls,
            args.output,
            name=args.name,
            assets=args.asset,
            ram_configurations=args.ram_configurations,
            build_profile=args.build_profile,
            optimizer_pipeline=args.optimizer_pipeline,
            timeout=args.timeout,
            public=args.erl_hls, profile=args.profile,
        )
    )


if __name__ == "__main__":
    main()
