"""Decode checked executor layouts and track message identity across mailbox row reuse."""
from collections import Counter
import re


def packed_layout(text: str, name: str) -> dict:
    """Read fixed generated DSLX layouts; unsupported type syntax fails instead of guessing offsets."""
    text = re.sub(r'//[^\n]*', '', text)
    if name == 'axis::Frame':
        return {'width': 128}
    if name == 'hls_failure::Code':
        return {'width': 16}
    primitive = re.fullmatch(r'[us](\d+)|(?:bits|[us]N)\[(?:u32:)?(\d+)\]', name)
    if primitive:
        return {'width': int(primitive[1] or primitive[2])}
    alias = re.search(r'\btype '+re.escape(name)+r'\s*=\s*([^;]+);', text)
    if alias:
        return packed_layout(text, alias[1].strip())
    enum = re.search(r'\benum '+re.escape(name)+r'\s*:\s*(u\d+)\s*\{', text)
    if enum:
        return packed_layout(text, enum[1])
    struct = re.search(r'\bstruct '+re.escape(name)+r'\s*\{([^}]+)\}', text)
    if not struct:
        raise ValueError(f'unsupported generated packed type: {name}')
    fields = [field.strip().split(':', 1) for field in struct[1].split(',') if field.strip()]
    result, offset = {}, 0
    for field, kind in reversed(fields):
        width = packed_layout(text, kind.strip())['width']
        result[field.strip()] = {'offset': offset, 'width': width}
        offset += width
    return {'width': offset, 'fields': result}


def decode(value: int, layout: dict) -> dict[str, int]:
    """Decode every declared field, rejecting bits outside the generated wire width."""
    if value < 0 or value >> layout['width']:
        raise ValueError('value exceeds generated executor layout')
    return {name: (value >> field['offset']) & ((1 << field['width'])-1)
            for name, field in layout['fields'].items()}


def frame_from_ram(raw: int) -> int:
    """Convert the axis whole-frame RAM ABI to the packed DSLX Frame channel layout."""
    if raw < 0 or raw >> 128:
        raise ValueError('mailbox RAM row exceeds the complete frame width')
    header=int.from_bytes((raw & 0xffffffff).to_bytes(4,'little'),'big')
    return (header << 96) | (raw >> 32)


class Mailbox:
    """Keep admission identities through postponement, phase release and physical row reuse."""

    def __init__(self, capacity: int) -> None:
        """Create one actor's empty bounded mailbox."""
        self.capacity = capacity
        self.order = []
        self.rows = {}
        self.postponed = set()
        self.released = {}
        self.counts = Counter()

    def admit(self, physical: int, message: dict) -> None:
        """Append a new identity only to unoccupied physical storage."""
        if not 0 <= physical < self.capacity or physical in self.rows or len(self.order) == self.capacity:
            raise ValueError('mailbox admission overwrote occupied storage')
        self.rows[physical] = message
        self.order.append(physical)
        self.released.pop(physical, None)
        self.counts['admitted'] += 1

    def select(self, physical: int, logical: int) -> dict:
        """Require the earliest non-postponed message, preserving its admission identity."""
        candidates = [index for index in self.order if index not in self.postponed]
        if not candidates or physical != candidates[0] or self.order.index(physical) != logical:
            raise ValueError('executor selection differs from mailbox order/postponement')
        self.counts['attempts'] += 1
        return self.rows[physical]

    def retire(self, physical: int, *, received: bool, dispatched: bool, directive: int,
               phase_boundary: bool, event: str) -> None:
        """Apply a checked outcome; a phase boundary releases every postponed identity."""
        if received and dispatched:
            if physical not in self.rows:
                raise ValueError('retirement lost its mailbox message')
            if directive == 0:
                del self.rows[physical]
                self.order.remove(physical)
                self.postponed.discard(physical)
                self.released.pop(physical, None)
                self.counts['consumed'] += 1
            elif directive == 1:
                self.postponed.add(physical)
                self.counts['postponed'] += 1
            else:
                raise ValueError('failure outcome in healthy mailbox recording')
        if phase_boundary:
            for index in self.postponed:
                self.released[index] = event
            self.counts['released'] += len(self.postponed)
            self.postponed.clear()
