#!/usr/bin/env python3
"""Independently verify the unsigned four-partition Zynq register-probe BOOT.bin."""

import argparse
import hashlib
import json
import struct
from pathlib import Path


def require(condition: bool, message: str) -> None:
    """Reject an image that violates the candidate's narrow boot contract."""
    if not condition:
        raise ValueError(message)


def elf_segments(data: bytes) -> tuple[int, list[tuple[int, int, bytes]]]:
    """Read little-endian ARM ELF32 load segments as (address, memory size, bytes)."""
    require(data[:7] == b"\x7fELF\x01\x01\x01" and len(data) >= 52, "not ELF32 little-endian")
    fields = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    kind, machine, _, entry, phoff, _, _, _, phsize, count, *_ = fields
    require(kind == 2 and machine == 40 and phsize == 32, "not an ARM executable")
    require(phoff + count * phsize <= len(data), "truncated ELF program headers")
    segments = []
    for i in range(count):
        typ, offset, _, address, filesz, memsz, _, _ = struct.unpack_from("<8I", data, phoff + i * phsize)
        if typ == 1:
            require(filesz <= memsz and offset + filesz <= len(data), "truncated ELF segment")
            require(address + memsz <= 1 << 32, "ELF segment wraps address space")
            segments.append((address, memsz, data[offset:offset + filesz]))
    require(bool(segments), "ELF has no load segments")
    return entry, segments


def bit_payload(data: bytes) -> bytes:
    """Remove a .bit container, requiring the exact XC7Z030-SBG485 target."""
    require(data[:13] == bytes.fromhex("00090ff00ff00ff00ff0000001"), "invalid .bit preamble")
    offset = 13
    fields = {}
    for tag in b"abcd":
        require(offset + 3 <= len(data) and data[offset] == tag, "invalid .bit metadata")
        length = int.from_bytes(data[offset + 1:offset + 3], "big")
        offset += 3
        require(offset + length <= len(data), "truncated .bit metadata")
        fields[tag] = data[offset:offset + length]
        offset += length
    require(fields[ord("b")] == b"xc7z030sbg485-1\0", "wrong .bit target")
    require(offset + 5 <= len(data) and data[offset] == ord("e"), "missing .bit payload")
    length = int.from_bytes(data[offset + 1:offset + 5], "big")
    payload = data[offset + 5:]
    require(length == len(payload) and length % 4 == 0 and length > 0, "invalid .bit length")
    return payload


def check_linux_elf(data: bytes) -> None:
    """Require a static ARM hard-float executable with mapped headers and a non-executable stack."""
    entry, _ = elf_segments(data)
    flags = struct.unpack_from("<I", data, 36)[0]
    require(flags & 0x600 == 0x400, "Linux diagnostic is not hard-float EABI")
    offset = struct.unpack_from("<I", data, 28)[0]
    count = struct.unpack_from("<H", data, 44)[0]
    headers = [struct.unpack_from("<8I", data, offset + i * 32) for i in range(count)]
    require(not any(h[0] == 3 for h in headers), "Linux diagnostic requires a dynamic interpreter")
    require(any(h[0] == 1 and h[1] == 0 and h[4] >= offset + count * 32 for h in headers),
            "Linux diagnostic does not map ELF program headers")
    require(any(h[0] == 1 and h[2] <= entry < h[2] + h[4] and h[6] & 1 for h in headers),
            "Linux diagnostic entry is not executable")
    require(any(h[0] == 0x6474e551 and h[6] == 6 for h in headers),
            "Linux diagnostic lacks a non-executable stack")


def check(image: bytes, fsbl: bytes, bitstream: bytes, uboot: bytes, dtb: bytes) -> list[dict]:
    """Check headers, ranges and each embedded source payload; return partition evidence."""
    require(len(image) >= 0xa0, "truncated boot header")
    header = struct.unpack_from("<11I", image, 0x20)
    require(header[:4] == (0xaa995566, 0x584c4e58, 0, 0x01010000), "unsupported boot header")
    require(sum(header) & 0xffffffff == 0xffffffff, "boot header checksum mismatch")
    iht, pht = struct.unpack_from("<2I", image, 0x98)
    require(iht >= 0xa0 and iht + 64 <= len(image), "invalid image header table")
    version, count, first, _, auth = struct.unpack_from("<5I", image, iht)
    require(version == 0x01020000 and count == 4 and first * 4 == pht and auth == 0,
            "expected four unsigned partitions")
    require(pht >= iht + 64 and pht + count * 64 <= len(image), "invalid partition table")
    evidence = []
    end = pht + count * 64
    for i, name in enumerate(("fsbl.elf", "probe.bit", "u-boot.elf", "system.dtb")):
        words = struct.unpack_from("<16I", image, pht + i * 64)
        encrypted, plain, total, load, entry, start, attrs, sections, checksum, ih, auth, *rest = words
        require(sum(words) & 0xffffffff == 0xffffffff, f"{name}: partition checksum mismatch")
        require(encrypted == plain == total and total > 0, f"{name}: unsupported payload encoding")
        expected_attrs = 0x20 if i == 1 else 0x10 | ((-len(dtb) % 4) if i == 3 else 0)
        require(attrs == expected_attrs and sections == 1 and checksum == auth == 0,
                f"{name}: unsupported partition attributes")
        require(iht + 64 <= ih * 4 < pht and rest[:4] == [0] * 4, f"{name}: invalid image metadata")
        start *= 4
        size = total * 4
        require(start >= end and start + size <= len(image), f"{name}: overlapping/truncated partition")
        payload = image[start:start + size]
        end = start + size
        if i in (0, 2):
            expected_entry, segments = elf_segments(fsbl if i == 0 else uboot)
            require(entry == expected_entry and load == min(a for a, _, d in segments if d),
                    f"{name}: ELF load/entry differs")
            require(load == (0 if i == 0 else 0x04000000), f"{name}: unexpected load address")
            for address, memory_size, data in segments:
                if i == 0:
                    require((0 <= address and address + memory_size <= 0x30000) or
                            (0xffff0000 <= address and address + memory_size <= 1 << 32),
                            "FSBL exceeds on-chip memory")
                if data:
                    relative = address - load
                    require(0 <= relative and relative + len(data) <= size and
                            payload[relative:relative + len(data)] == data, f"{name}: ELF payload differs")
            if i == 0:
                require(header[4:9] == (start, size, load, entry, size), "FSBL boot header differs")
        elif i == 1:
            raw = bit_payload(bitstream)
            swapped = b"".join(raw[n:n + 4][::-1] for n in range(0, len(raw), 4))
            padding = payload[len(swapped):]
            require(load == entry == 0 and payload[:len(swapped)] == swapped and len(padding) < 32 and
                    padding == b"\x00\x00\x00\x20" * (len(padding) // 4), "PL payload differs")
        else:
            require(load == 0x00100000 and entry == 0 and payload == dtb + b"\0" * (-len(dtb) % 4),
                    "device-tree load/payload differs")
        evidence.append({"name": name, "offset": start, "bytes": size,
                         "load": load, "entry": entry, "sha256": hashlib.sha256(payload).hexdigest()})
    return evidence


def check_directory(directory: Path) -> list[dict]:
    """Verify BOOT.bin against the four source files retained beside it."""
    return check(*(directory.joinpath(name).read_bytes() for name in
                   ("BOOT.bin", "fsbl.elf", "probe.bit", "u-boot.elf", "system.dtb")))


def main() -> None:
    """Print the checked partition map or fail without modifying the bundle."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(json.dumps(check_directory(parser.parse_args().directory), indent=2))


if __name__ == "__main__":
    main()
