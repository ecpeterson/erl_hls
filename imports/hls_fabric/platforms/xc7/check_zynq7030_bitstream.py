#!/usr/bin/env python3
"""Check that bitread recovers every configuration bit supplied to bitstream assembly."""

import argparse
from pathlib import Path


def frame_bits(frames: str) -> set[str]:
    """Expand sparse Project X-Ray frames into bitread's set-bit notation.

    Frame ECC occupies the low 13 bits of word 50. The assembler generates it;
    bitread omits it by default, so it is outside this round-trip comparison.
    """
    bits = set()
    addresses = set()
    for line in frames.splitlines():
        address, data = line.split()
        frame = int(address, 16)
        words = [int(word, 16) for word in data.split(",")]
        if frame in addresses or len(words) != 101:
            raise ValueError(f"duplicate or malformed frame: {address}")
        addresses.add(frame)
        for index, value in enumerate(words):
            if not 0 <= value < 1 << 32:
                raise ValueError(f"invalid word: {address}/{index}")
            if index == 50:
                value &= ~0x1fff
            while value:
                bit = (value & -value).bit_length() - 1
                bits.add(f"bit_{frame:08x}_{index:03d}_{bit:02d}")
                value &= value - 1
    if not addresses or not bits:
        raise ValueError("empty frame witness")
    return bits


def check(frames: str, decoded: str) -> int:
    """Return the matched set-bit count, or reject missing and extra decoded bits."""
    expected = frame_bits(frames)
    actual = set(decoded.splitlines())
    if expected != actual:
        raise ValueError(f"bitstream mismatch: {len(expected - actual)} missing, "
                         f"{len(actual - expected)} extra bits")
    return len(expected)


def main() -> None:
    """Compare an assembler input .frames file with bitread -y -z output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("decoded", type=Path)
    args = parser.parse_args()
    count = check(args.frames.read_text(), args.decoded.read_text())
    print(f"PASS: {count} non-ECC configuration bits recovered from bitstream")


if __name__ == "__main__":
    main()
