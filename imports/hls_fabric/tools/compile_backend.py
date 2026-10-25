#!/usr/bin/env python3
"""Compile a prepared actor topology with explicit executor scheduling and completion storage."""
from __future__ import annotations

import argparse
from pathlib import Path

from compiler_paths import compiler_root, compiler_source, compiler_tool
from completion_fifo import transform
from optimizer_pipeline import prepare as prepare_optimizer_pipeline


def compile_topology(
    source: Path,
    xls: Path,
    output: Path,
    *,
    name: str,
    assets: list[Path],
    ram_configurations: str | None = None,
    stages: int = 2,
    executor_result_delay: int = 0,
    completion_storage: str = "registers",
    optimizer_pipeline: Path | None = None,
    timeout: int = 1800,
    public: Path | None = None,
    profile: str = "default",
) -> Path:
    """Publish an immutable, provenance-checked release after all requested lowering passes.

    Executor delay reserves unit-model budget at result sends, not physical
    picoseconds. It changes XLS scheduling, not pipeline depth. LUTRAM keeps
    completion queue capacity and latency fixed; unknown FIFO shapes fail. An
    explicit optimizer pipeline is frozen and hashed alongside the original tool.
    public selects compiler tools explicitly; otherwise profile selects the built dependency.
    """
    public = compiler_root(profile, public)
    compiler = compiler_tool(public, "compile_xls")
    if executor_result_delay < 0 or completion_storage not in ("registers", "lutram"):
        raise ValueError("invalid executor budget or completion storage policy")
    output = output.absolute()
    optimizer_policy = {}
    if optimizer_pipeline is not None:
        if any(path.name == "optimizer_pipeline.txtpb" for path in assets):
            raise ValueError("reserved optimizer pipeline asset name")
        xls, frozen_pipeline, optimizer_policy = prepare_optimizer_pipeline(
            xls, optimizer_pipeline, output.parent / ".xls-optimizer-pipelines", public=public)
        assets = [*assets, frozen_pipeline]
    policy = {
        **optimizer_policy,
        "executor_result_delay": executor_result_delay,
        "completion_storage": completion_storage,
        "driver_sha256": compiler.sha(Path(__file__)),
        "compiler_extension_sha256": compiler.sha(compiler_source(public, "compile_xls")),
    }

    def finalize(snapshot: Path, manifest: dict) -> dict:
        """Apply only the requested RTL legalization before the executor hashes and publishes it."""
        backend = dict(policy)
        if completion_storage == "lutram":
            rtl = snapshot / (name + ".v")
            text, audit = transform(rtl.read_text())
            rtl.write_text(text)
            backend.update({
                "completion_fifo": audit,
                "legalization_sha256": compiler.sha(Path(__file__).with_name("completion_fifo.py")),
            })
        return {**manifest, "backend": backend}

    return compiler.build(
        source, xls, output, name=name, top="Top", pipeline_stages=stages,
        ram_configurations=ram_configurations, assets=assets, timeout=timeout,
        channel_delays={"_result_out:send": executor_result_delay} if executor_result_delay else {},
        finalize=finalize,
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
    parser.add_argument("--pipeline-stages", type=int, default=2)
    parser.add_argument("--executor-result-delay", type=int, default=0)
    parser.add_argument("--completion-storage", choices=("registers", "lutram"), default="registers")
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
            stages=args.pipeline_stages,
            executor_result_delay=args.executor_result_delay,
            completion_storage=args.completion_storage,
            optimizer_pipeline=args.optimizer_pipeline,
            timeout=args.timeout,
            public=args.erl_hls, profile=args.profile,
        )
    )


if __name__ == "__main__":
    main()
