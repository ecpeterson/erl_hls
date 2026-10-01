#!/usr/bin/env python3
"""Report or losslessly compress old build artifacts on macOS; never prune caches."""

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Textual generated artifacts; exclude chip databases, PLTs, objects and tools.
SUFFIXES = {".json", ".log", ".console", ".ir", ".v", ".sv", ".vvp"}
PROFILES = {"default", "test", "prod"}
COMPRESSED = 0x20  # Darwin UF_COMPRESSED; absent from Python's stat on some hosts.


def signature(info: os.stat_result) -> tuple[int, ...]:
    """Identify a file revision, including metadata that a copy must not race."""
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns,
            info.st_ctime_ns, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, getattr(info, "st_flags", 0))


def allocated(info: os.stat_result) -> int:
    """Return allocated bytes rather than the file's uncompressed logical size."""
    return info.st_blocks * 512


def candidates(root: Path, cutoff: float, minimum: int) -> list[tuple[Path, os.stat_result]]:
    """Find old, owned, uncompressed artifact files without following symlinks.

    Rebar profiles, hidden directories, hard links and other file types are
    excluded. The caller must keep builds idle while applying the resulting plan.
    """
    if root.is_symlink() or root.name != "_build" or not root.is_dir():
        raise ValueError("root must be a real directory named _build")
    found = []
    for directory, directories, files in os.walk(root, followlinks=False):
        parent = Path(directory)
        directories[:] = [name for name in directories
                          if not name.startswith(".") and not (parent / name).is_symlink()
                          and not (parent == root and name in PROFILES)]
        for name in files:
            path = parent / name
            if path.suffix not in SUFFIXES or name.startswith("."):
                continue
            info = path.lstat()
            if (stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                    and info.st_uid == os.getuid() and info.st_mtime <= cutoff
                    and info.st_size >= minimum and allocated(info) >= minimum
                    and not getattr(info, "st_flags", 0) & COMPRESSED):
                found.append((path, info))
    return sorted(found, key=lambda item: allocated(item[1]), reverse=True)


def sha256(path: Path) -> str:
    """Hash readable file contents, including transparently decompressed data."""
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def verify_copy(source: Path, copy: Path, before: os.stat_result) -> str:
    """Require an unchanged source and a readable copy with matching bytes/metadata."""
    if signature(source.lstat()) != signature(before):
        raise ValueError(f"source changed: {source}")
    after = copy.lstat()
    if (not stat.S_ISREG(after.st_mode) or after.st_size != before.st_size
            or (after.st_mode, after.st_uid, after.st_gid, after.st_mtime_ns) !=
               (before.st_mode, before.st_uid, before.st_gid, before.st_mtime_ns)):
        raise ValueError(f"copy size or metadata mismatch: {source}")
    digest = sha256(source)
    if sha256(copy) != digest:
        raise ValueError(f"copy content mismatch: {source}")
    if signature(source.lstat()) != signature(before):
        raise ValueError(f"source changed during verification: {source}")
    return digest


def compact_one(path: Path, before: os.stat_result) -> tuple[int, str]:
    """Atomically replace a verified file only when native compression saves space.

    A failed copy or verification leaves the original untouched. macOS compression
    flags must be permitted; a sandbox that strips them is rejected explicitly.
    """
    if signature(path.lstat()) != signature(before):
        raise ValueError(f"source changed since scan: {path}")
    with tempfile.TemporaryDirectory(prefix=".compact-", dir=path.parent) as directory:
        copy = Path(directory) / path.name
        subprocess.run(["/usr/bin/ditto", "--hfsCompression", "--nocache", str(path), str(copy)],
                       check=True, capture_output=True)
        copied = copy.lstat()
        if not getattr(copied, "st_flags", 0) & COMPRESSED:
            raise ValueError(f"filesystem compression was not enabled for {path}; "
                             "check filesystem support and sandbox permissions")
        digest = verify_copy(path, copy, before)
        saved = allocated(before) - allocated(copied)
        if saved <= 0:
            return 0, digest
        # Applying requires an idle build tree; the revision check detects changes
        # during copying, but is not a lock honored by arbitrary build processes.
        os.replace(copy, path)
        return saved, digest


def main() -> None:
    """Default to a size report; --apply performs verified macOS compression."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, nargs="?", default=Path("_build"))
    parser.add_argument("--apply", action="store_true", help="compress files; requires idle builds")
    parser.add_argument("--older-than-hours", type=float, default=24)
    parser.add_argument("--min-mib", type=float, default=1)
    parser.add_argument("--report", type=Path, help="write a JSON receipt after applying")
    args = parser.parse_args()
    if args.older_than_hours < 0 or args.min_mib <= 0:
        parser.error("age must be nonnegative and minimum size must be positive")
    if args.apply and sys.platform != "darwin":
        parser.error("--apply requires macOS native filesystem compression")
    root = args.root.absolute()
    plan = candidates(root, time.time() - args.older_than_hours * 3600,
                      int(args.min_mib * 2**20))
    total = sum(allocated(info) for _, info in plan)
    print(f"{len(plan)} eligible files occupy {total / 2**30:.2f} GiB; "
          "rebar profiles, tools and binary caches excluded.", flush=True)
    if not args.apply:
        groups = {}
        for path, info in plan:
            name = path.relative_to(root).parts[0]
            groups[name] = groups.get(name, 0) + allocated(info)
        for name, size in sorted(groups.items(), key=lambda item: item[1], reverse=True):
            print(f"{size / 2**30:6.2f} GiB  {name}")
        print("No files changed. Stop builds before using --apply.")
        return
    receipt = {"root": str(root), "eligible_allocated_bytes": total, "saved_allocated_bytes": 0,
               "files": [], "complete": False}
    try:
        for index, (path, info) in enumerate(plan, 1):
            saved, digest = compact_one(path, info)
            receipt["saved_allocated_bytes"] += saved
            receipt["files"].append({"path": str(path.relative_to(root)), "sha256": digest,
                                     "saved_allocated_bytes": saved})
            if index % 25 == 0 or index == len(plan):
                print(f"{index}/{len(plan)} checked; "
                      f"{receipt['saved_allocated_bytes'] / 2**30:.2f} GiB saved", flush=True)
        receipt["complete"] = True
    finally:
        if args.report:
            args.report.write_text(json.dumps(receipt, indent=2) + "\n")
    print("Paths, contents and mtimes preserved; no cache or artifact was discarded.")


if __name__ == "__main__":
    main()
