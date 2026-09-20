"""Independent byte/FCS and table-driven 8b/10b oracle for the packet regression.

The tables express IEEE 802.3 clause 36 code groups, in transmission order.
No LiteEth/LiteX code is imported. This checks coding and frame contents, not
the complete clause-36 receiver synchronization or autonegotiation algorithm.
"""

import struct
import zlib
from pathlib import Path

# Negative-RD data sub-blocks; unbalanced sub-blocks complement at positive RD.
SIX = "100111 011101 101101 110001 110101 101001 011001 111000 111001 100101 010101 110100 001101 101100 011100 010111 011011 100011 010011 110010 001011 101010 011010 111010 110011 100110 010110 110110 001110 101110 011110 101011".split()
FOUR = "1011 1001 0101 1100 1101 1010 0110 1110".split()
CONTROL = {0xbc: "0011111010", 0xfb: "1101101000", 0xfd: "1011101000", 0xf7: "1110101000"}


def invert(bits: str) -> str:
    """Complement a textual code sub-block."""
    return bits.translate(str.maketrans("01", "10"))


def disparity(bits: str, previous: bool) -> bool:
    """Advance running disparity; balanced sub-blocks preserve its sign."""
    ones = bits.count("1")
    return previous if ones * 2 == len(bits) else ones * 2 > len(bits)


def encode(byte: int, control: bool, positive: bool) -> tuple[int, bool]:
    """Encode one data/control byte; result bit zero is transmitted first."""
    if control:
        bits = CONTROL[byte]
        bits = invert(bits) if positive else bits
    else:
        x, y = byte & 31, byte >> 5
        six = SIX[x]
        if positive and (six.count("1") != 3 or x == 7):
            six = invert(six)
        middle = disparity(six, positive)
        four = FOUR[y]
        if middle and (four.count("1") != 2 or y == 3):
            four = invert(four)
        if y == 7 and not middle and x in (17, 18, 20):
            four = "0111"
        if y == 7 and middle and x in (11, 13, 14):
            four = "1000"
        bits = six + four
    return int(bits[::-1], 2), disparity(bits, positive)


def payload(length: int, tag: int) -> bytes:
    """Create deterministic frames exercising all byte values across test cases."""
    return bytes((index * 17 + tag) & 255 for index in range(length))


def wire_bytes(data: bytes) -> bytes:
    """Return preamble/SFD, padded frame and little-endian Ethernet FCS."""
    data = data.ljust(60, b"\0")
    return b"\x55" * 7 + b"\xd5" + data + struct.pack("<I", zlib.crc32(data))


def vector(data: bytes) -> list[int]:
    """Encode idle, one frame, termination and idle for independent RX injection."""
    symbols = [(0xbc, True), (0x50, False)] * 16
    symbols += [(0xfb, True)] + [(byte, False) for byte in data[1:]]
    symbols += [(0xfd, True), (0xf7, True)] + [(0xbc, True), (0x50, False)] * 16
    positive = False
    result = []
    for byte, control in symbols:
        code, positive = encode(byte, control, positive)
        result.append(code)
    return result


def write_vectors(stage: Path) -> None:
    """Write good/FCS-bad/runt/oversize/preamble-bad vectors plus a decode table."""
    normal = wire_bytes(payload(97, 43))
    cases = {"good": normal, "crc_bad": normal[:-1] + bytes([normal[-1] ^ 1]),
             "oversize": wire_bytes(payload(1515, 19)),
             "runt": b"\x55" * 7 + b"\xd5" + bytes(20) + struct.pack("<I", zlib.crc32(bytes(20))),
             "preamble_bad": b"\x55" * len(normal)}
    for name, data in cases.items():
        values = vector(data)
        (stage / f"{name}.hex").write_text("\n".join(f"{value:03x}" for value in values) + "\n")
    table = [0x3ff] * 1024
    for control, values in ((False, range(256)), (True, CONTROL)):
        for byte in values:
            for positive in (False, True):
                code, _ = encode(byte, control, positive)
                value = byte | (int(control) << 8)
                assert table[code] in (0x3ff, value), (code, byte)
                table[code] = value
    (stage / "decode.hex").write_text("\n".join(f"{value:03x}" for value in table) + "\n")


def check_capture(path: Path, expected: list[tuple[int, int]]) -> None:
    """Require exact transmitted bytes, preamble, FCS and at least 12 IFG symbols."""
    table = {}
    for control, values in ((False, range(256)), (True, CONTROL)):
        for byte in values:
            for positive in (False, True):
                code, after = encode(byte, control, positive)
                table[(code, positive)] = (byte, control, after)
    positive = False
    synchronized = False
    packet: bytearray | None = None
    frames = []
    end_cycle = -100
    for cycle, line in enumerate(path.read_text().splitlines()):
        code = int(line, 16)
        if not synchronized:
            if code not in (encode(0xbc, True, False)[0], encode(0xbc, True, True)[0]):
                continue
            positive = code == encode(0xbc, True, True)[0]
            synchronized = True
        if (code, positive) not in table:
            raise AssertionError(f"invalid code/disparity at symbol {cycle}: {code:03x}, RD+={positive}")
        byte, control, positive = table[(code, positive)]
        if control and byte == 0xfb:
            assert packet is None and cycle - end_cycle >= 12, (cycle, end_cycle)
            packet = bytearray(b"\x55")
        elif control and byte == 0xfd:
            assert packet is not None
            frames.append(bytes(packet))
            packet = None
            end_cycle = cycle
        elif packet is not None:
            assert not control, (cycle, byte)
            packet.append(byte)
    assert packet is None
    assert frames == [wire_bytes(payload(length, tag)) for length, tag in expected], [len(frame) for frame in frames]
