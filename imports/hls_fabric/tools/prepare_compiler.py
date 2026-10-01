#!/usr/bin/env python3
"""Prepare the pinned compiler revision in disposable storage; never edit a developer checkout."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    """Identify file content independently of its location."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _prepare(root: Path, source: Path | None) -> Path:
    """Fetch the pinned revision once, validating cached sources before reuse.

    An explicit source supplies Git objects, not its working tree. Existing
    developer checkouts are never replaced. Remove a changed managed cache
    deliberately before rebuilding it.
    """
    lock_path = root / "tools/compiler/manifest.json"
    lock = json.loads(lock_path.read_text())
    identity = sha(lock_path)[:20]
    base = root / "_build/compiler"
    target = base / identity
    checkout = root / "_checkouts/erl_hls"
    managed = checkout.is_symlink() and checkout.resolve().parent == base.resolve()
    if (
        (checkout.exists() or checkout.is_symlink())
        and checkout.resolve() != target.resolve()
        and not managed
    ):
        raise ValueError(
            "an erl_hls checkout is already selected; preserve it and remove the _checkouts/erl_hls link before preparing the pinned compiler"
        )
    base.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        repository = source
        if repository is None:
            repository = base / "objects"
            if not repository.exists():
                subprocess.run(
                    ["git", "init", "--bare", str(repository)], check=True, stdout=subprocess.DEVNULL
                )
            if subprocess.run(
                ["git", "-C", str(repository), "cat-file", "-e", lock["revision"] + "^{commit}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ).returncode:
                subprocess.run(
                    ["git", "-C", str(repository), "fetch", "--depth=1", lock["url"], lock["revision"]],
                    check=True,
                )
        archive = subprocess.check_output(["git", "-C", str(repository), "archive", lock["revision"]])
        with tempfile.TemporaryDirectory(prefix="prepare-", dir=base) as temporary:
            stage = Path(temporary) / "source"
            stage.mkdir()
            with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
                bundle.extractall(stage, filter="data")
            files = {str(p.relative_to(stage)): sha(p) for p in stage.rglob("*") if p.is_file()}
            (stage / ".compiler-snapshot.json").write_text(json.dumps(files, sort_keys=True) + "\n")
            stage.rename(target)
    files = json.loads((target / ".compiler-snapshot.json").read_text())
    changed = [
        name
        for name, digest in files.items()
        if not (target / name).is_file() or sha(target / name) != digest
    ]
    if changed:
        raise ValueError(f"compiler cache changed ({changed[0]}); preserve edits before deleting {target}")
    checkout.parent.mkdir(exist_ok=True)
    if not checkout.is_symlink():
        checkout.symlink_to(Path("../_build/compiler") / identity)
    elif checkout.resolve() != target.resolve():
        # Switch only a managed or dangling link after the new snapshot validates.
        checkout.unlink()
        checkout.symlink_to(Path("../_build/compiler") / identity)
    return target


def prepare(root: Path = ROOT, source: Path | None = None) -> Path:
    """Serialize preparation and publish only a completely verified compiler snapshot."""
    lock = root / "_build/compiler/prepare.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        return _prepare(root, source)


def main() -> None:
    """Prepare the compiler without launching a build or accepting credentials."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=lambda p: Path(p).resolve(),
        help="optional local Git repository supplying the pinned revision",
    )
    args = parser.parse_args()
    print(prepare(source=args.source))


if __name__ == "__main__":
    main()
