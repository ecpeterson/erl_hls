#!/usr/bin/env python3
"""Count optimized XLS state and access structure; these counts do not estimate LUTs."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

NODE = re.compile(r"^  ([\w.]+): (.*?) = (\w+)\((.*)\)$")


def bit_width(kind: str) -> int:
    """Count bits in scalar, tuple and nested-array IR types; reject unknown syntax."""
    text = re.sub(r"\s+", "", kind)
    cursor = 0

    def take(token: str) -> None:
        """Consume a required token at the current type position."""
        nonlocal cursor
        if not text.startswith(token, cursor):
            raise ValueError(f"invalid IR type: {kind}")
        cursor += len(token)

    def number() -> int:
        """Read an unsigned width or array length."""
        nonlocal cursor
        match = re.match(r"[0-9]+", text[cursor:])
        if match is None:
            raise ValueError(f"missing width in IR type: {kind}")
        cursor += len(match[0])
        return int(match[0])

    def value() -> int:
        """Read one type, including all of its array dimensions."""
        nonlocal cursor
        if text.startswith("bits[", cursor):
            take("bits[")
            width = number()
            take("]")
        elif text.startswith("token", cursor):
            take("token")
            width = 0
        else:
            take("(")
            width = 0
            if not text.startswith(")", cursor):
                width = value()
                while text.startswith(",", cursor):
                    take(",")
                    width += value()
            take(")")
        while text.startswith("[", cursor):
            take("[")
            width *= number()
            take("]")
        return width

    width = value()
    if cursor != len(text):
        raise ValueError(f"trailing text in IR type: {kind}")
    return width


def census(path: Path, include: str = ".*") -> dict:
    """Stream selected procs and deduplicate multiple reads of each state element."""
    pattern = re.compile(include)
    reports = []
    current = None
    counts: Counter[str] = Counter()
    states: dict[str, int] = {}
    access: Counter[str] = Counter()

    def finish() -> None:
        """Retain one proc's structural counts without its expression graph."""
        if current is not None:
            reports.append({"proc": current, "state_bits": sum(states.values()),
                            "state": dict(sorted(states.items())),
                            "nodes": sum(counts.values()), "operations": dict(sorted(counts.items())),
                            "access_result_bits": dict(sorted(access.items()))})

    with path.open() as stream:
        for line in stream:
            if len(line) > 4_000_000:
                raise ValueError("IR line exceeds diagnostic bound")
            if re.match(r"^(?:top )?(?:proc|fn) ", line):
                finish()
                match = re.match(r"^(?:top )?proc ([\w.]+)[<(]", line)
                current = match[1] if match and pattern.search(match[1]) else None
                counts, states, access = Counter(), {}, Counter()
            if current is None or not (match := NODE.fullmatch(line.rstrip())):
                continue
            name, kind, operation, arguments = match.groups()
            counts[operation] += 1
            if operation == "state_read":
                state = re.search(r"(?:^|,\s*)state_element=([\w.]+)(?:,|$)", arguments)
                if state is None:
                    raise ValueError(f"state read has no identity: {name}")
                width = bit_width(kind)
                if state[1] in states and states[state[1]] != width:
                    raise ValueError("inconsistent state read types")
                states[state[1]] = width
            if operation in {"sel", "priority_sel", "one_hot_sel", "array_index", "array_update"}:
                access[operation] += bit_width(kind)
    finish()
    if not reports:
        raise ValueError("no matching procs")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"ir_sha256": digest, "include": include,
            "scope": "IR storage/access counts only; not mapped area or timing",
            "state_bits": sum(report["state_bits"] for report in reports),
            "nodes": sum(report["nodes"] for report in reports), "procs": reports}


def main() -> None:
    """Write structural census JSON for the selected IR proc names."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ir", type=Path)
    parser.add_argument("--include", default=".*", help="Proc-name regular expression.")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(census(args.ir, args.include), indent=2) + "\n")


if __name__ == "__main__":
    main()
