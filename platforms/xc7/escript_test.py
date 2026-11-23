#!/usr/bin/env python3
"""Run board escript self-tests against the prepared local BEAM applications."""

import os
import shlex
import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


def run_self_test(script: Path, timeout: int = 30) -> None:
    """Compile local applications, expose their code paths and run one self-test."""
    subprocess.run(["rebar3", "compile"], cwd=PROJECT, check=True, timeout=timeout)
    paths = subprocess.check_output(
        ["rebar3", "path"], cwd=PROJECT, text=True, timeout=timeout).split()
    environment = os.environ.copy()
    path_flags = " ".join(f"-pa {shlex.quote(path)}" for path in paths)
    environment["ERL_FLAGS"] = " ".join(
        value for value in (environment.get("ERL_FLAGS", ""), path_flags) if value)
    subprocess.run(["escript", script, "--self-test"], cwd=PROJECT,
                   env=environment, check=True, timeout=timeout)
