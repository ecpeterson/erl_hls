#!/usr/bin/env python3
"""Derive external PRBS from retained Vivado images using their measured GTX delta."""

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "boot/reference-images.json"
PART = "xc7z030sbg485-1"
REMOVED = {
    "bit_00442494_036_28",
    "bit_00442495_029_20",
    "bit_00442496_036_28",
    "bit_00442498_036_28",
    "bit_00442499_029_20",
    "bit_00442499_036_28",
}
ADDED = {
    "bit_00442495_041_22",
    "bit_00442499_041_22",
}


def digest(path: Path) -> str:
    """Return one file's SHA-256 identity."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode_bits(text: str) -> set[str]:
    """Decode bitread's nonzero-bit listing, rejecting duplicates and malformed rows."""
    rows = text.splitlines()
    bits = set(rows)
    if len(bits) != len(rows) or not bits or any(
            len(row.split("_")) != 4 or not row.startswith("bit_") for row in rows):
        raise ValueError("malformed bitread set-bit listing")
    return bits


def derive_bits(loopback: set[str], external: set[str], prbs: set[str]) -> set[str]:
    """Apply the exact retained Ethernet external-mode delta to retained PRBS bits."""
    removed = loopback - external
    added = external - loopback
    if removed != REMOVED or added != ADDED:
        raise ValueError(f"retained Ethernet external delta changed: -{removed} +{added}")
    if not REMOVED <= prbs or ADDED & prbs:
        raise ValueError("retained PRBS image does not have the loopback-side GTX values")
    return (prbs - REMOVED) | ADDED


def parse_frame_dump(text: str) -> dict[int, list[int]]:
    """Parse bitread's complete frame dump into ordered 101-word frames."""
    frames: dict[int, list[int]] = {}
    address = None
    words: list[int] = []
    for line in text.splitlines():
        if line.startswith(".frame "):
            if address is not None:
                if len(words) != 101:
                    raise ValueError(f"malformed frame {address:#010x}: {len(words)} words")
                frames[address] = words
            address = int(line.split()[1], 16)
            if address in frames:
                raise ValueError(f"duplicate frame: {address:#010x}")
            words = []
        elif line.strip():
            if address is None:
                raise ValueError("frame data precedes its address")
            words.extend(int(word, 16) for word in line.split())
    if address is None or len(words) != 101:
        raise ValueError("empty or malformed final frame")
    frames[address] = words
    return frames


def patch_frames(frames: dict[int, list[int]]) -> None:
    """Replace the loopback/polarity delta in one complete PRBS frame map."""
    for name, value in [(name, 0) for name in REMOVED] + [(name, 1) for name in ADDED]:
        _, frame_text, word_text, bit_text = name.split("_")
        frame, word, bit = int(frame_text, 16), int(word_text), int(bit_text)
        present = (frames[frame][word] >> bit) & 1
        if present != 1 - value:
            raise ValueError(f"unexpected source value for {name}: {present}")
        if value:
            frames[frame][word] |= 1 << bit
        else:
            frames[frame][word] &= ~(1 << bit)


def write_frames(path: Path, frames: dict[int, list[int]]) -> None:
    """Write Project X-Ray's one-line frame format for checked bitstream assembly."""
    with path.open("w") as stream:
        for address, words in frames.items():
            stream.write(f"0x{address:08x} " + ",".join(f"0x{word:08x}" for word in words) + "\n")


def normalize_bit_header(path: Path) -> dict[str, str]:
    """Replace xc7frames2bit's clock fields after validating its structured header."""
    data = bytearray(path.read_bytes())
    if len(data) < 16:
        raise ValueError("truncated .bit header")
    offset = 2 + struct.unpack_from(">H", data)[0]
    if data[offset:offset + 2] != b"\x00\x01":
        raise ValueError("unexpected .bit header preamble")
    offset += 2
    fields: dict[str, tuple[int, int]] = {}
    for expected in b"abcd":
        if data[offset] != expected:
            raise ValueError(f"missing .bit header field {chr(expected)}")
        length = struct.unpack_from(">H", data, offset + 1)[0]
        start = offset + 3
        if start + length > len(data):
            raise ValueError("truncated .bit header field")
        fields[chr(expected)] = (start, length)
        offset = start + length
    replacements = {"c": b"2000/01/01\0", "d": b"00:00:00\0"}
    for field, replacement in replacements.items():
        start, length = fields[field]
        if length != len(replacement):
            raise ValueError(f"unexpected .bit {field} field length: {length}")
        data[start:start + length] = replacement
    design_start, design_length = fields["a"]
    design = bytes(data[design_start:design_start + design_length]).rstrip(b"\0").decode()
    path.write_bytes(data)
    return {"design": design, "date": "2000/01/01", "time": "00:00:00"}


def run(command: list[Path | str], log: Path, cwd: Path | None = None) -> None:
    """Run one bounded conversion step and retain its output."""
    with log.open("w") as stream:
        subprocess.run(list(map(str, command)), stdout=stream, stderr=subprocess.STDOUT,
                       check=True, timeout=180, cwd=cwd)


def compose(prbs: Path, loopback: Path, external: Path, bitread: Path,
            frames2bit: Path, part_file: Path, output: Path) -> dict:
    """Create and round-trip-check an external-PRBS bitstream in a new directory."""
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    reference = json.loads(REFERENCE.read_text())
    inputs = {"prbs": prbs, "ethernet-loopback": loopback, "ethernet-external": external}
    for profile, path in inputs.items():
        expected = reference["profiles"][profile]["artifacts_sha256"]["candidate.bit"]
        if digest(path) != expected:
            raise ValueError(f"bitstream differs from retained {profile} reference")
    output.mkdir(parents=True)
    listings = {}
    for profile, path in inputs.items():
        listing = output / f"{profile}.bits"
        run([bitread, "--part_file", part_file, "-y", "-z", "-o", listing, path],
            output / f"{profile}-bitread.log")
        listings[profile] = decode_bits(listing.read_text())
    expected_bits = derive_bits(listings["ethernet-loopback"],
                                listings["ethernet-external"], listings["prbs"])
    dump = output / "prbs.dump"
    run([bitread, "--part_file", part_file, "-o", dump, prbs], output / "prbs-frame-read.log")
    frames = parse_frame_dump(dump.read_text())
    patch_frames(frames)
    frame_file = output / "candidate.frames"
    write_frames(frame_file, frames)
    candidate = output / "candidate.bit"
    run([frames2bit, "--part_file", part_file, "--part_name", PART,
         "--frm_file", "candidate.frames", "--output_file", "candidate.bit"],
        output / "frames2bit.log", cwd=output)
    header = normalize_bit_header(candidate)
    decoded = output / "candidate.bits"
    run([bitread, "--part_file", part_file, "-y", "-z", "-o", decoded, candidate],
        output / "candidate-bitread.log")
    actual_bits = decode_bits(decoded.read_text())
    if actual_bits != expected_bits:
        raise ValueError(f"derived bitstream mismatch: {len(expected_bits-actual_bits)} missing, "
                         f"{len(actual_bits-expected_bits)} extra")
    result = {
        "part": PART,
        "profile": "prbs-external",
        "composition": "Retained timing-closed PRBS frames with the exact eight-bit GTX external-mode delta from retained timing-closed Ethernet images",
        "inputs_sha256": {profile: digest(path) for profile, path in inputs.items()},
        "removed_bits": sorted(REMOVED),
        "added_bits": sorted(ADDED),
        "non_ecc_set_bits": len(actual_bits),
        "candidate_frames_sha256": digest(frame_file),
        "candidate_bitstream_sha256": digest(candidate),
        "bitstream_header": header,
        "tools_sha256": {"bitread": digest(bitread), "xc7frames2bit": digest(frames2bit)},
        "timing_basis": reference["profiles"]["prbs"]["timing"],
        "hardware_validated": False,
        "limits": "No new route or fabric timing change; the composite hard-GTX mode and external analog path require this hardware test.",
    }
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Select three retained references, conversion tools and a fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("prbs", "ethernet-loopback", "ethernet-external", "bitread",
                 "frames2bit", "part-file", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    result = compose(args.prbs.resolve(), args.ethernet_loopback.resolve(),
                     args.ethernet_external.resolve(), args.bitread.resolve(),
                     args.frames2bit.resolve(), args.part_file.resolve(), args.output.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
