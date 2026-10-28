#!/usr/bin/env python3
"""Prepare a checked logical GTX metadata overlay; never invent configuration bits."""

import argparse
import hashlib
import json
import tempfile
import urllib.request
from pathlib import Path

KINDS = ("GTXE2_CHANNEL", "GTXE2_COMMON", "IBUFDS_GTE2", "IPAD", "OPAD")


def digest(data: bytes) -> str:
    """Return the content identity used by source pins and overlay directories."""
    return hashlib.sha256(data).hexdigest()


def fetch(source: dict[str, str], cache: Path) -> bytes:
    """Read/download one pinned source, rejecting modified cached bytes."""
    target = cache / source["sha256"]
    if target.exists():
        data = target.read_bytes()
    else:
        with urllib.request.urlopen(source["url"], timeout=60) as response:
            data = response.read()
    if digest(data) != source["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {source['url']}")
    cache.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as stream:
            stream.write(data)
            temporary = Path(stream.name)
        temporary.replace(target)
    return data


def validate_site(kind: str, local: bytes, donor: bytes, metadata: bytes) -> None:
    """Require identical structural sites and metadata pins before reusing a site."""
    physical = json.loads(local)
    if physical != json.loads(donor):
        raise ValueError(f"structural site mismatch: {kind}")
    logical = json.loads(metadata)[kind]
    # The common-site metadata spells vector pins with brackets; X-Ray omits them.
    pins = {name.replace("[", "").replace("]", "") for name in logical["pins"]}
    if pins != set(physical["site_pins"]):
        raise ValueError(f"metadata pins mismatch: {kind}")
    for name, info in logical["pins"].items():
        physical_name = name.replace("[", "").replace("]", "")
        direction = {"INPUT": "IN", "OUTPUT": "OUT", "INOUT": "INOUT"}[info["dir"]]
        if physical["site_pins"][physical_name]["direction"] != direction:
            raise ValueError(f"metadata direction mismatch: {kind}.{name}")


def install_metadata(files: dict[str, bytes], output: Path) -> Path:
    """Publish an immutable overlay, checking existing contents before reuse."""
    identity = digest(json.dumps({name: digest(data) for name, data in sorted(files.items())},
                                 sort_keys=True).encode())
    target = output / f"metadata-{identity}"
    output.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        with tempfile.TemporaryDirectory(dir=output) as directory:
            stage = Path(directory) / "metadata"
            stage.mkdir()
            for name, data in files.items():
                (stage / name).write_bytes(data)
            stage.rename(target)
    actual = {path.name: path.read_bytes() for path in target.iterdir()}
    if actual != files:
        raise ValueError(f"modified metadata overlay: {target}")
    return target


def audit_database(database: Path, fasm: Path | None = None) -> dict:
    """Report absent GTX frame/feature data, optionally limited to routed tiles.

    Presence is only a prerequisite: this audit does not validate bit addresses,
    feature encodings, routing completeness or the resulting hardware behavior.
    """
    grid = json.loads((database / "xc7z030/tilegrid.json").read_text())
    used = ({line.split(".", 1)[0] for line in fasm.read_text().splitlines()
             if line and not line.startswith("#")} if fasm else set(grid))
    selected = {name: tile for name, tile in grid.items()
                if name in used and "GTX" in tile["type"]}
    if not selected:
        raise ValueError("no GTX tiles in the audited design/database")
    no_frames = sorted(name for name, tile in selected.items() if not tile.get("bits"))
    no_features = []
    for kind in sorted({tile["type"] for tile in selected.values()}):
        path = database / f"segbits_{kind.lower()}.db"
        if not path.is_file() or path.stat().st_size == 0:
            no_features.append(kind)
    return {"gtx_tiles": sorted(selected), "missing_frame_mapping": no_frames,
            "missing_segbits_types": no_features, "hardware_qualified": False,
            "assembly_data_present": not no_frames and not no_features}


def prepare(database: Path, metadata: Path, output: Path) -> Path:
    """Check pinned donor sites and publish metadata without changing the database."""
    lock = json.loads(Path(__file__).with_name("sources.lock.json").read_text())
    files = {path.name: path.read_bytes() for path in metadata.glob("*.json")}
    if not files:
        raise ValueError(f"empty installed metadata: {metadata}")
    for kind in KINDS:
        donor = fetch(lock["sites"][kind], output / "sources")
        logical = fetch(lock["metadata"][kind], output / "sources")
        validate_site(kind, (database / f"site_type_{kind}.json").read_bytes(), donor, logical)
        files[f"site_type_{kind}.json"] = logical
    overlay = install_metadata(files, output)
    report = {"metadata_identity": overlay.name, "sources": lock,
              "database_audit": audit_database(database)}
    (output / "preparation.json").write_text(json.dumps(report, indent=2) + "\n")
    return overlay


def main() -> None:
    """Accept installed database/metadata paths and an experiment-local cache."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(prepare(args.database.resolve(), args.metadata.resolve(), args.output.resolve()))


if __name__ == "__main__":
    main()
