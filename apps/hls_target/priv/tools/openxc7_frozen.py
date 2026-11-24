"""Derive selected routes from a complete, hash-bound openXC7 capture without rerouting."""

import argparse
import hashlib
import json
import mmap
from pathlib import Path

from openxc7_chipdb import ChipGrid
from openxc7_endpoints import qualify_selected


def verified(path: Path, descriptor: dict, limit: int) -> Path:
    """Check byte length and SHA-256 before using a bounded local input."""
    if path.stat().st_size != descriptor["bytes"] or descriptor["bytes"] > limit:
        raise ValueError(f"invalid input size: {path.name}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != descriptor["sha256"]:
        raise ValueError(f"input digest mismatch: {path.name}")
    return path


def capture_manifest(capture: Path, implementation: str, chipdb: Path) -> dict:
    """Bind the capture and architecture to the exact implementation named by the recording."""
    path = capture / "manifest.json"
    verified(path, {"sha256": implementation, "bytes": path.stat().st_size}, 1 << 20)
    manifest = json.loads(path.read_bytes())
    if not manifest["complete"] or manifest["format"] != "openxc7_placement":
        raise ValueError("incomplete openXC7 capture")
    verified(chipdb, manifest["chipdb"], 1 << 30)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("implementation")
    parser.add_argument("chipdb", type=Path)
    args = parser.parse_args()
    meta = capture_manifest(args.capture, args.implementation, args.chipdb)
    top, routes = (
        json.loads(verified(args.capture / n, meta["files"][n], 384 << 20).read_bytes())
        for n in ("routed.json", "routes.json")
    )
    with (
        args.chipdb.open("rb") as stream,
        mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        print(
            json.dumps(
                qualify_selected(ChipGrid(db), top["modules"]["top"], routes),
                separators=(",", ":"),
            )
        )
