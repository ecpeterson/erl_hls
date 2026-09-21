#!/usr/bin/env python3
"""Assemble the measured TE0715 lane only after matching a retained vendor reference."""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from check_zynq7030_bitstream import check as check_serialization
from gtx.coverage import audit, compare, definitions, enabled_features
from gtx.clock_cascades import prepare as prepare_clock_cascades
from gtx.prepare import digest
from prepare_zynq7030 import DB_SHA256, PART, checked
from vivado.evidence import compare_configuration

# Only these physical sites have independent configuration evidence. Frame count
# comes from the Zynq part; word spans enclose the donor's known bit coordinates.
TILES = {"GTX_CHANNEL_1_X186Y17": ("channel", 22), "GTX_COMMON_X186Y23": ("common", 101)}
REFERENCE = ROOT / "results/vivado-reference-2026-09-21.json"


def selected_grid(grid: dict, locations: dict) -> dict:
    """Add the measured frames to two tiles, rejecting pre-existing/conflicting mappings."""
    result = json.loads(json.dumps(grid))
    for tile, (kind, words) in TILES.items():
        mapping = locations[kind]
        if result[tile]["bits"]:
            raise ValueError(f"GTX mapping already present: {tile}")
        if (mapping["baseaddr"], mapping["word_offset"]) != ("0x00442480", 22 if kind == "channel" else 0):
            raise ValueError(f"unexpected measured mapping: {kind}")
        result[tile]["bits"] = {"CLB_IO_CLK": {
            "baseaddr": mapping["baseaddr"], "frames": 32, "offset": mapping["word_offset"], "words": words}}
    return result


def require_scope(grid: dict, text: str, donor: dict[str, bytes]) -> None:
    """Reject other GTX sites/features; unconditional interface wires need no frames."""
    features = enabled_features(text)
    for required in ("GTX_CHANNEL_1_X186Y17.GTXE2_CHANNEL.IN_USE",
                     "GTX_COMMON_X186Y23.IBUFDS_GTE2_Y1.IN_USE"):
        if required not in features:
            raise ValueError(f"missing measured site: {required}")
    for feature in features:
        tile, suffix = feature.split(".", 1)
        kind = grid[tile]["type"]
        if "GTX" not in kind:
            continue
        fixed = definitions(donor.get(f"ppips_{kind.lower()}.db", b"").decode(), pseudo=True)
        if tile not in TILES and kind + "." + suffix not in fixed:
            raise ValueError(f"unmeasured GTX tile: {tile}")
        if "IBUFDS_GTE2_Y0." in suffix or suffix == "GTXE2_COMMON.IN_USE":
            raise ValueError(f"unqualified reference-buffer/QPLL profile: {feature}")
    coverage = compare(grid, text, donor)
    if not coverage["donor_covers_enabled_features"] or coverage["missing_frame_mapping"]:
        raise ValueError(f"incomplete GTX assembly data: {coverage}")


def install(database: Path, donor: dict[str, bytes], locations: dict, output: Path) -> Path:
    """Publish a checked overlay without modifying the installed database or other tiles.

    Unchanged files remain links to the source database. Reuse checks generated
    bytes and link targets; the source installation must remain available.
    """
    database = database.resolve(strict=True)
    grid_bytes = checked((database / "xc7z030/tilegrid.json").read_bytes(),
                         DB_SHA256["xc7z030/tilegrid.json"], "source Z7030 tilegrid")
    checked((database / PART / "part.yaml").read_bytes(),
            DB_SHA256["xc7z030fbg676-1/part.yaml"], "source Z7030 frames")
    grid = selected_grid(json.loads(grid_bytes), locations)
    files = {name: data for name, data in donor.items() if name.startswith(("segbits_", "ppips_"))}
    files["xc7z030/tilegrid.json"] = (json.dumps(grid, indent=2, sort_keys=True) + "\n").encode()
    files["LICENSE.gtx-donor"] = (ROOT / "gtx/LICENSE.prjxray").read_bytes()
    links = {p.name: p for p in database.iterdir() if p.name not in files and p.name != "xc7z030"}
    links.update({"xc7z030/" + p.name: p for p in (database / "xc7z030").iterdir() if p.name != "tilegrid.json"})
    manifest = {"database": str(database), "reference_sha256": digest(REFERENCE.read_bytes()),
                "files": {name: digest(data) for name, data in files.items()},
                "links": {name: str(path.resolve()) for name, path in links.items()}}
    files["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    target = output / digest(files["manifest.json"])
    output.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        with tempfile.TemporaryDirectory(dir=output) as directory:
            stage = Path(directory) / "database"
            (stage / "xc7z030").mkdir(parents=True)
            for name, data in files.items():
                (stage / name).write_bytes(data)
            for name, path in links.items():
                (stage / name).symlink_to(path)
            stage.rename(target)
    for name, data in files.items():
        checked((target / name).read_bytes(), digest(data), name)
    for name, path in links.items():
        if not (target / name).is_symlink() or (target / name).resolve() != path.resolve():
            raise ValueError(f"modified overlay link: {name}")
    return target


def require_match(report: dict) -> None:
    """Require equality within the known GTX mask, including unset and negated bits."""
    if not report["enabled_features"] or report["missing_enabled_features"] or report["extra_known_bits"]:
        raise ValueError(f"GTX configuration differs from reference: {report}")


def run(argv: list[str], log: Path) -> None:
    """Run a bounded assembly tool and retain its diagnostics."""
    with log.open("w") as stream:
        subprocess.run(argv, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=180)


def assemble(database: Path, fasm: Path, reference: Path, profile: str, tools: Path, output: Path) -> dict:
    """Create one fresh candidate and report only after independent GTX and round-trip checks.

    The reference must be the retained Vivado image for the named profile. This
    proves neither complete configuration semantics nor timing/hardware operation.
    Failed attempts retain logs but never a successfully published candidate.bit.
    """
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    reference_record = json.loads(REFERENCE.read_text())
    expected = reference_record["profiles"][profile]["artifacts_sha256"]["candidate.bit"]
    reference_data = checked(reference.read_bytes(), expected, "vendor reference bitstream")
    locations = reference_record["gtx_locations"]
    output.mkdir(parents=True)
    # Freeze both inputs so checks and assembly consume precisely the same bytes.
    (output / "input.fasm").write_bytes(fasm.read_bytes())
    fasm = output / "input.fasm"
    vendor = output / "reference.bit"
    vendor.write_bytes(reference_data)
    coverage = audit(database, fasm, output / "coverage")
    donor = {name: (output / "coverage/sources" / pin["sha256"]).read_bytes()
             for name, pin in coverage["sources"].items()}
    clock_data, clock_evidence = prepare_clock_cascades(database)
    donor["segbits_clk_hrow_bot_r.db"] = clock_data
    overlay = install(database, donor, locations, output / "databases")
    grid = json.loads((overlay / "xc7z030/tilegrid.json").read_text())
    require_scope(grid, fasm.read_text(), donor)
    part = overlay / PART / "part.yaml"
    vendor_bits = output / "reference.bits"
    run([str(tools / "bitread"), "--part_file", str(part), "-y", "-z", "-o", str(vendor_bits), str(vendor)],
        output / "reference-bitread.log")
    comparison = compare_configuration(fasm, vendor_bits, output / "coverage/sources", locations)
    require_match(comparison)
    frames, bitstream, bits = (output / name for name in ("candidate.frames", "unchecked.bit", "candidate.bits"))
    run([str(tools / "fasm2frames"), "--part", PART, "--db-root", str(overlay), str(fasm), str(frames)],
        output / "fasm2frames.log")
    run([str(tools / "xc7frames2bit"), "--part_file", str(part), "--part_name", PART,
         "--frm_file", str(frames), "--output_file", str(bitstream)], output / "frames2bit.log")
    run([str(tools / "bitread"), "--part_file", str(part), "-y", "-z", "-o", str(bits), str(bitstream)],
        output / "bitread.log")
    recovered = check_serialization(frames.read_text(), bits.read_text())
    native = compare_configuration(fasm, bits, output / "coverage/sources", locations)
    require_match(native)
    result = {"part": PART, "profile": profile, "reference_bitstream_sha256": expected,
              "vendor_comparison": comparison, "native_comparison": native,
              "clock_cascades": clock_evidence,
              "recovered_non_ecc_bits": recovered, "bitstream_bytes": bitstream.stat().st_size,
              "artifacts_sha256": {p.name: digest(p.read_bytes()) for p in (fasm, frames, bits)},
              "bitstream_sha256": digest(bitstream.read_bytes()), "overlay": str(overlay),
              "tools_sha256": {name: digest((tools / name).read_bytes())
                               for name in ("bitread", "fasm2frames", "xc7frames2bit")},
              "hardware_qualified": False, "timing_qualified": False,
              "limits": "GTX known-mask equality and complete frame serialization only; other configuration semantics are not independently validated."}
    bitstream.rename(output / "candidate.bit")
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Choose a routed design, retained reference, native tools and fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("database", "fasm", "reference", "tools", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--profile", choices=("prbs", "ethernet-loopback", "ethernet-external"), required=True)
    args = parser.parse_args()
    result = assemble(args.database.resolve(), args.fasm.resolve(), args.reference.resolve(), args.profile,
                      args.tools.resolve(), args.output.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
