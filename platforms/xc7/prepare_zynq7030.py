#!/usr/bin/env python3
"""Build a checked XC7Z030-SBG485 overlay without modifying the source database."""

import argparse
import csv
import hashlib
import io
import json
import re
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

PINOUT_URL = (
    "https://download.amd.com/adaptive-socs-and-fpgas/developer/"
    "adaptive-socs-and-fpgas/package-pinout-files/z7packages/z7all.zip"
)
PINOUT_SHA256 = "90388378c03e86713e0df9b12c6a4fb2dc437189ff15858682df034f831d7316"
PART = "xc7z030sbg485-1"
REFERENCE = "xc7z030fbg676-1"
# These are inputs from the experiment's pinned openXC7 package, not vendor exports.
DB_SHA256 = {
    "xc7z030fbg676-1/package_pins.csv": "073a761155005a8727cb5ff74a7e77d612d29b7292772325a286925979e2ba62",
    "xc7z030fbg676-1/part.json": "a6b5d444e85ef56b911f9c608d9f6564d17a85c7d19509f564c73bbb6cc3437d",
    "xc7z030fbg676-1/part.yaml": "40609e835cab9eeee78b3ac231466b7dfa3c5e8b3317f6129da6c8dc7da33641",
    "mapping/parts.yaml": "2bf079459554116519f4993647d990f5d63b8e0e4e9fae71dbf1c943281e592e",
    "mapping/devices.yaml": "fce2482b11ad8719dcb19d84a4fefbabbea668de6a08e7727d4ed4923b64950a",
    "xc7z030/tilegrid.json": "a3b2ec28c10ba7a40471e4aa808c9c0ee1fec5e2852c6ec45dcc04b139de3f7f",
}
FIELDS = ["pin", "bank", "site", "tile", "pin_function"]


def digest(data: bytes) -> str:
    """Return the SHA-256 identifier of an input or generated artifact."""
    return hashlib.sha256(data).hexdigest()


def checked(data: bytes, expected: str, label: str) -> bytes:
    """Reject inputs that differ from the reviewed source revision."""
    actual = digest(data)
    if actual != expected:
        raise ValueError(f"{label}: SHA-256 {actual}; expected {expected}")
    return data


def read_vendor(data: str, package: str) -> list[dict[str, str]]:
    """Read AMD package CSV rows, rejecting malformed pins and incomplete files."""
    lines = data.splitlines()
    if not lines or not lines[0].startswith(f"Device/Package {package} "):
        raise ValueError(f"wrong vendor package: expected {package}")
    rows = list(csv.DictReader(lines[2:]))
    pins = [r for r in rows if r["Pin"] and r["Pin"] != "Total Number of Pins"]
    totals = [r for r in rows if r["Pin"] == "Total Number of Pins"]
    if len(totals) != 1 or int(totals[0]["Pin Name"]) != len(pins):
        raise ValueError("vendor pin total does not match rows")
    if any(not re.fullmatch(r"[A-Z]+[0-9]+", r["Pin"]) for r in pins):
        raise ValueError("malformed vendor pin")
    if len({r["Pin"] for r in pins}) != len(pins):
        raise ValueError("duplicate vendor pin")
    return pins


def map_pins(reference: list[dict[str, str]], vendor_reference: list[dict[str, str]],
             vendor_target: list[dict[str, str]], grid: dict) -> list[dict[str, str]]:
    """Join bank/function identities after checking the reference package and sites.

    Target functions absent from the reference pinout are errors. Only dedicated
    functions already omitted by the reference database may remain unmapped.
    """
    by_pin = {r["Pin"]: r for r in vendor_reference}
    by_function = {}
    sites = set()
    for row in reference:
        pin, bank, site, tile, function = (row[k] for k in FIELDS)
        vendor = by_pin.get(pin)
        if vendor is None or (vendor["Bank"], vendor["Pin Name"]) != (bank, function):
            raise ValueError(f"reference pin {pin}: vendor/database disagreement")
        if site not in grid.get(tile, {}).get("sites", {}):
            raise ValueError(f"reference pin {pin}: missing site {tile}/{site}")
        key = (bank, function)
        if key in by_function or site in sites:
            raise ValueError(f"duplicate reference function or site: {key}/{site}")
        by_function[key] = row
        sites.add(site)
    # Power, JTAG and reference-voltage pins have no placeable fabric site.
    omitted = {(r["Bank"], r["Pin Name"]) for r in vendor_reference} - by_function.keys()
    result = []
    seen_sites = set()
    for row in vendor_target:
        key = (row["Bank"], row["Pin Name"])
        if key not in by_function:
            if key not in omitted or row["I/O Type"] in {"HR", "HP"}:
                raise ValueError(f"target pin {row['Pin']}: unmapped function {key}")
            continue
        mapped = dict(by_function[key], pin=row["Pin"])
        if mapped["site"] in seen_sites:
            raise ValueError(f"duplicate target site: {mapped['site']}")
        seen_sites.add(mapped["site"])
        result.append(mapped)
    return sorted(result, key=lambda row: row["pin"])


def prepare(database: Path, archive: Path, output: Path) -> Path:
    """Return an immutable, content-addressed overlay containing the checked part.

    Unchanged database entries are symlinks. The original database must remain
    available. Reusing an overlay verifies its generated files and link targets.
    """
    database = database.resolve(strict=True)
    family = database / "zynq7"
    inputs = {name: checked((family / name).read_bytes(), sha, name)
              for name, sha in DB_SHA256.items()}
    source = checked(archive.read_bytes(), PINOUT_SHA256, str(archive))
    with zipfile.ZipFile(io.BytesIO(source)) as bundle:
        vendor_reference, vendor_target = (
            read_vendor(bundle.read(f"7zSeriesALL/{package}pkg.csv").decode(), package)
            for package in ("xc7z030fbg676", "xc7z030sbg485")
        )
    reference = list(csv.DictReader(io.StringIO(inputs[f"{REFERENCE}/package_pins.csv"].decode())))
    rows = map_pins(reference, vendor_reference, vendor_target,
                    json.loads(inputs["xc7z030/tilegrid.json"]))
    if len(rows) != 302 or Counter(r["bank"] for r in rows if r["site"].startswith("IOB_")) != {
            "13": 50, "34": 50, "35": 50}:
        raise ValueError("unexpected SBG485 site or programmable I/O population")
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    # IDCODE, configuration frames and bank locations describe the same XC7Z030
    # silicon. Preserve them; only package-to-site bonding changes in this overlay.
    files = {"package_pins.csv": stream.getvalue().encode(),
             "part.json": inputs[f"{REFERENCE}/part.json"],
             "part.yaml": inputs[f"{REFERENCE}/part.yaml"]}
    manifest = {
        "part": PART, "reference": REFERENCE, "database": str(database),
        "pinout_url": PINOUT_URL, "pinout_sha256": PINOUT_SHA256,
        "database_sha256": DB_SHA256, "mapped_pins": len(rows),
        "outputs_sha256": {name: digest(data) for name, data in files.items()},
    }
    manifest_data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    destination = output.resolve() / digest(manifest_data)
    links = {p.name: p for p in family.iterdir() if p.name != PART}
    if destination.exists():
        checked((destination / "manifest.json").read_bytes(), digest(manifest_data), "manifest")
        for name, data in files.items():
            checked((destination / "zynq7" / PART / name).read_bytes(), digest(data), name)
        for name, path in links.items():
            link = destination / "zynq7" / name
            if not link.is_symlink() or link.resolve() != path.resolve():
                raise ValueError(f"changed overlay link: {link}")
        return destination
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output, prefix=".prepare-") as stage:
        staging = Path(stage)
        target = staging / "zynq7" / PART
        target.mkdir(parents=True)
        for name, data in files.items():
            (target / name).write_bytes(data)
        for name, path in links.items():
            (staging / "zynq7" / name).symlink_to(path)
        (staging / "manifest.json").write_bytes(manifest_data)
        staging.rename(destination)
    return destination


def main() -> None:
    """Prepare an overlay from the pinned installed database and AMD ZIP."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, help="installed prjxray-db root")
    parser.add_argument("archive", type=Path, help="AMD z7all.zip (SHA-256 checked)")
    parser.add_argument("output", type=Path, help="directory for generated overlays")
    args = parser.parse_args()
    print(prepare(args.database, args.archive, args.output))


if __name__ == "__main__":
    main()
