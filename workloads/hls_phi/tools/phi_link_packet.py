"""Decode accepted D6 peer transfers, preserving word times and complete packet boundaries."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import defaultdict
from pathlib import Path


def transfer_words(raw: int, transport: str | dict) -> list[int]:
    """Validate one transfer and return its ordered 33-bit data/TLAST words."""
    if transport == 'serial':
        if raw < 0 or raw >> 33:
            raise ValueError('serial word exceeds its boundary width')
        return [raw]
    width = transport['words']
    if width not in (1, 2, 4) or raw < 0 or raw >> (34*width):
        raise ValueError('invalid packed boundary width')
    result, hole = [], False
    for i in range(width):
        word = (raw >> (34*i)) & ((1 << 34)-1)
        if word >> 33:
            if hole:
                raise ValueError('packed validity is not a prefix')
            result.append(word & ((1 << 33)-1))
        else:
            hole = True
    if not result:
        raise ValueError('empty packed transfer')
    return result


def packets(path: Path, transport: str | dict) -> dict[tuple[int, int], list[dict]]:
    """Decode full/compact packets and credits; retain an unfinished tail without inventing words."""
    partial, result = {}, defaultdict(list)
    compact_enabled = isinstance(transport, dict) and transport.get('compact', False)
    for line in path.read_text().splitlines():
        timestamp, device, port, raw = line.split()
        time, key = int(timestamp), (int(device), int(port))
        for word in transfer_words(int(raw, 16), transport):
            value, last = word & 0xffffffff, word >> 32
            if key not in partial:
                tag = value >> 16
                compact = compact_enabled and tag == 0x4851
                if tag != 0x4850 and not compact:
                    raise ValueError('invalid transport header')
                credit = not compact and bool(value & 0x8000)
                length = (value >> 5) & 7
                if compact and length > 3:
                    raise ValueError('invalid compact length')
                partial[key] = {'start_ns': time, 'lane': value & (31 if compact else 0x7fff),
                                'credit': credit, 'compact': compact, 'words': [], 'word_times_ns': [],
                                'expected_words': 1 if credit else 1+length if compact else 5}
            packet = partial[key]
            packet['words'].append(word)
            packet['word_times_ns'].append(time)
            if last != (len(packet['words']) == packet['expected_words']):
                raise ValueError('invalid packet termination')
            if last:
                result[key].append({**partial.pop(key), 'end_ns': time, 'complete': True})
    for key, packet in partial.items():
        result[key].append({**packet, 'complete': False})
    return dict(result)


def frame_header(packet: dict) -> int | None:
    """Return the exact actor header when available; credits and unstarted full headers have none."""
    if packet['credit']:
        return None
    if packet['compact']:
        word = packet['words'][0]
        return (((word >> 8) & 255) << 24) | ((word >> 5) & 7)
    return packet['words'][1] & 0xffffffff if len(packet['words']) > 1 else None


def word_kind(packet: dict, index: int) -> str:
    """Classify actual transmitted words without counting reconstructed zero padding."""
    if packet['credit']:
        return 'credit'
    if index == 0:
        return 'compact_header' if packet['compact'] else 'lane_header'
    if packet['compact']:
        return 'payload'
    if index == 1:
        return 'frame_header'
    return 'payload' if index-1 <= (frame_header(packet) & 255) else 'padding'
