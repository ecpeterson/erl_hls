"""Bounded subprocess logs and file hashes shared by builds, reports and tests."""
import hashlib
import json
from pathlib import Path
import subprocess

from backend_paths import ROOT


def digest(path: Path) -> str:
    """Bind a source, emitted circuit or tool to its exact contents."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str | Path], stage: Path, name: str, output: Path | None = None,
        *, env: dict[str, str] | None = None, timeout: int | None = 240) -> None:
    """Run from the source root with fresh logs and an optional stdout product.

    Retain argv and failure tails; propagate failed exit status or timeout (240s
    by default). Use None only for drivers that bound their own stages. A supplied
    environment applies only to this child.
    """
    args = list(map(str, command))
    (stage / (name + '.command.json')).write_text(json.dumps(args) + '\n')
    path = stage / (name + '.log')
    try:
        with path.open('x') as log:
            if output is None:
                subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=timeout, env=env)
            else:
                with output.open('x') as out:
                    subprocess.run(args, cwd=ROOT, stdout=out, stderr=log, check=True, timeout=timeout, env=env)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        # Keep the full file and expose a bounded tail in the main CI log.
        print(path.read_text(errors='replace')[-6000:], flush=True)
        raise


def execute(command: list[str | Path], directory: Path, name: str,
            timeout: int = 180, output: Path | None = None,
            *, env: dict[str, str] | None = None) -> None:
    """Run in the artifact directory with replaceable logs; propagate failure and timeout."""
    with (directory / f"{name}.log").open("w") as log:
        if output is None:
            subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=timeout, env=env)
        else:
            with output.open("w") as result:
                subprocess.run(command, cwd=directory, stdout=result, stderr=log,
                               check=True, timeout=timeout, env=env)


