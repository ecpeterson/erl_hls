#!/usr/bin/env python3
"""Locate retained HLS measurements outside source repositories."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = "repositories/hls_fabric/pre-packaging-2026-10-01"


def artifact_root(root: Path = ROOT) -> Path:
    """Honor HLS_ARTIFACT_ROOT, otherwise use hls_artifacts beside the primary checkout."""
    root = root.resolve()
    configured = os.environ.get("HLS_ARTIFACT_ROOT")
    if configured:
        target = Path(configured).expanduser().resolve()
    else:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True,
            text=True,
            check=False,
        )
        sibling = Path(result.stdout.strip()).parent.parent if result.returncode == 0 else root.parent
        target = sibling / "hls_artifacts"
    if target == root or root in target.parents:
        raise ValueError("HLS_ARTIFACT_ROOT must be outside the source repository")
    return target


def archive_path(relative: str) -> Path:
    """Locate a historical report without requiring a local archive installation."""
    name = Path(relative)
    if name.is_absolute() or ".." in name.parts:
        raise ValueError("archive name must be repository-relative")
    return artifact_root() / ARCHIVE / name


def archived(relative: str) -> Path:
    """Require a historical report to be installed in the external archive."""
    target = archive_path(relative)
    if not target.is_file():
        raise FileNotFoundError(f"measurement is not installed locally: {target}")
    return target


def output_path(relative: str) -> Path:
    """Create the parent for a retained report under the external runs directory."""
    name = Path(relative)
    if name.is_absolute() or ".." in name.parts:
        raise ValueError("output name must be relative")
    target = artifact_root() / "runs" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    return target


def main() -> None:
    """Print the archive location, optionally resolving a historical repository path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?")
    args = parser.parse_args()
    print(archived(args.path) if args.path else artifact_root())


if __name__ == "__main__":
    main()
