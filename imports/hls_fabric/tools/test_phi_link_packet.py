#!/usr/bin/env python3
"""Validate mixed compact/full frame boundaries independently of RTL and bus grouping."""
from pathlib import Path
import tempfile
import unittest

from phi_link_packet import packets, frame_header, word_kind


def decode(words: list[int], width: int = 4, compact: bool = True) -> list[dict]:
    """Group protocol words into public accepted transfers, retaining every packet boundary."""
    rows = []
    for offset in range(0, len(words), width):
        transfer = sum(((1 << 33) | word) << (34*i) for i, word in enumerate(words[offset:offset+width]))
        rows.append(f'{offset*8} 0 1 {transfer:x}')
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)/'wire.log'
        path.write_text('\n'.join(rows))
        return packets(path, {'words': width, 'credits': 4, 'compact': compact})[0, 1]


class PacketDecodeTest(unittest.TestCase):
    """Opcode, length and lane fields remain independent, including opcode bit seven."""

    def test_all_compact_lengths(self) -> None:
        """Every length and opcode edge reconstructs the precise canonical actor header."""
        for width in (1, 2, 4):
            for length in range(4):
                for opcode in (0, 1, 128, 255):
                    header = 0x48510000 | opcode << 8 | length << 5 | 31
                    words = [header, *range(length)]
                    words[-1] |= 1 << 32
                    packet, = decode(words, width)
                    self.assertEqual(frame_header(packet), opcode << 24 | length)
                    self.assertEqual(packet['lane'], 31)
                    self.assertFalse(packet['credit'])
                    self.assertTrue(packet['complete'])
                    self.assertEqual([word_kind(packet, i) for i in range(length+1)],
                                     ['compact_header']+['payload']*length)

    def test_regrouped_repeated_lane(self) -> None:
        """Repeated header-only frames for a lane remain legal under every transfer grouping."""
        words = [(1 << 32) | 0x48510000 | opcode << 8 | 2 for opcode in (165, 90, 60, 195)]
        for width in (1, 2, 4):
            result = decode(words, width)
            self.assertEqual([frame_header(p) for p in result], [op << 24 for op in (165, 90, 60, 195)])
            self.assertEqual([p['lane'] for p in result], [2]*4)

    def test_extended_metadata_and_credit(self) -> None:
        """Large lane IDs, arbitrary metadata, padding and returned credits retain their full form."""
        full = [0x48500020, 0xff821001, 17, 0x48518000, (1 << 32) | 29]
        credit = (1 << 32) | 0x48508020
        for width in (1, 2, 4):
            result = decode([*full, credit], width)
            self.assertEqual(result[0]['words'], full)
            self.assertEqual(frame_header(result[0]), 0xff821001)
            self.assertEqual([word_kind(result[0], i) for i in range(5)],
                             ['lane_header', 'frame_header', 'payload', 'padding', 'padding'])
            self.assertEqual(result[1]['lane'], 32)
            self.assertTrue(result[1]['credit'])
            self.assertIsNone(frame_header(result[1]))

    def test_invalid_and_partial(self) -> None:
        """Invalid tags/lengths/termination fail; incomplete tails stay visibly incomplete."""
        for words, compact in [([0x14851a500], False), ([0x14851a580], True),
                               ([0x04851a500], True), ([0x14851a520], True),
                               ([0x12340000], True)]:
            with self.subTest(words=words), self.assertRaises(ValueError):
                decode(words, compact=compact)
        partial, = decode([0x48500020])
        self.assertFalse(partial['complete'])
        self.assertIsNone(frame_header(partial))


if __name__ == '__main__':
    unittest.main()
