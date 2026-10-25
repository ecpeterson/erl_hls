"""Decode and compare finite Phi profile event transcripts independently of their runner."""
from collections import defaultdict
from collections.abc import Iterable, Sequence
from pathlib import Path


def sequences(rows: Iterable[Sequence[int | str]]) -> dict[tuple, list[tuple]]:
    """Group [plane, x, y, step, kind, value] rows in per-cell arrival order."""
    result = defaultdict(list)
    for plane, x, y, step, kind, value in rows:
        result[plane, x, y].append((step, kind, value))
    return dict(result)


def rtl_events(path: Path) -> list[list[int | str]]:
    """Decode recorded correction/status frames; reject unknown tags or malformed rows."""
    result = []
    tags = {0x0300000b: "phi_correction", 0x03000011: "phi_status"}
    for line in path.read_text().splitlines():
        p, x, y, step, encoded = line.split()
        frame = int(encoded, 16)
        result.append([int(p), int(x), int(y), int(step), tags[frame >> 96], (frame >> 64) & 0xffffffff])
    return result
