#!/usr/bin/env python3
"""Compile a prepared actor topology with explicit executor scheduling and completion storage."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from backend_paths import PUBLIC
from compile_xls import build, identity, locked, sha
from completion_fifo import transform


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
    timeout: int = 1800,
) -> Path:
    """Publish an immutable, provenance-checked release after all requested lowering passes.

    Executor delay reserves unit-model budget at result sends, not physical
    picoseconds. It changes XLS scheduling, not pipeline depth. LUTRAM keeps
    completion queue capacity and latency fixed; unknown FIFO shapes fail.
    """
    if executor_result_delay < 0 or completion_storage not in ("registers", "lutram"):
        raise ValueError("invalid executor budget or completion storage policy")
    output = output.resolve() if not output.is_symlink() else output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    with locked(output.parent / f".{output.name}.lock"):
        raw = output.parent / ("." + output.name + "-xls")
        release = build(
            source,
            xls,
            raw,
            name=name,
            top="Top",
            pipeline_stages=stages,
            ram_configurations=ram_configurations,
            assets=assets,
            timeout=timeout,
            channel_delays={"_result_out:send": executor_result_delay} if executor_result_delay else {},
        )
        release = release.resolve()
        manifest = json.loads((release / (name + ".build.json")).read_text())
        rtl_name = name + ".v"
        text = (release / rtl_name).read_text()
        policy = {
            "executor_result_delay": executor_result_delay,
            "completion_storage": completion_storage,
            "driver_sha256": sha(Path(__file__)),
            "compiler_extension_sha256": sha(PUBLIC / "tools/compile_xls.py"),
        }
        if completion_storage == "lutram":
            text, audit = transform(text)
            policy.update(
                {
                    "completion_fifo": audit,
                    "legalization_sha256": sha(Path(__file__).with_name("completion_fifo.py")),
                }
            )
        digest = hashlib.sha256(text.encode()).hexdigest()
        manifest = {
            **manifest,
            "backend": policy,
            "rtl": {**manifest["rtl"], rtl_name: digest},
            "artifacts": {**manifest["artifacts"], rtl_name: digest},
        }
        destination = output.parent / ("." + output.name + "-backend") / identity(manifest)
        destination.parent.mkdir(exist_ok=True)
        if not destination.exists():
            with tempfile.TemporaryDirectory(prefix="release-", dir=destination.parent) as tmp:
                staged = Path(tmp) / "content"
                staged.mkdir()
                for filename in manifest["artifacts"].keys() | manifest["assets"].keys():
                    shutil.copyfile(release / filename, staged / filename)
                (staged / rtl_name).write_text(text)
                (staged / (name + ".build.json")).write_text(json.dumps(manifest, indent=2) + "\n")
                staged.rename(destination)
        actual = json.loads((destination / (name + ".build.json")).read_text())
        if actual != manifest or any(
            sha(destination / n) != h for table in ("artifacts", "assets") for n, h in manifest[table].items()
        ):
            raise ValueError("backend release changed; preserve it and rebuild in a fresh output directory")
        pending = output.with_name(output.name + ".pending")
        pending.unlink(missing_ok=True)
        pending.symlink_to(destination)
        os.replace(pending, output)
        return destination


def main() -> None:
    """Compile once; simulations and physical measurements consume the same release."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name", default="snowflake_actor_topology")
    parser.add_argument("--asset", type=Path, action="append", default=[])
    parser.add_argument("--ram-configurations")
    parser.add_argument("--pipeline-stages", type=int, default=2)
    parser.add_argument("--executor-result-delay", type=int, default=0)
    parser.add_argument("--completion-storage", choices=("registers", "lutram"), default="registers")
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
            timeout=args.timeout,
        )
    )


if __name__ == "__main__":
    main()
