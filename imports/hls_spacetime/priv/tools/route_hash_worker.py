"""Hash explicit frozen inputs and fresh route outputs over one bounded pipe.

One UTF-8 request line is DECIMAL_ID<TAB>HEX_UTF8_ABSOLUTE_PATH. IDs start at
one and increase by one. Replies are ID<TAB>SHA256. There is no digest cache.
EOF is clean shutdown; malformed requests/files emit no successful reply and
terminate nonzero. The caller's process-group guard covers blocked I/O.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

MAX_LINE = 16384
MAX_PATH = 4096
MAX_PLAN = 16 * 1024**2
MAX_FILE = 16 * 1024**2
MAX_DCP = 512 * 1024**2


def require(value: bool, reason: str) -> None:
    if not value:
        raise ValueError(reason)


def absolute(value: str) -> Path:
    """Require a canonical absolute path without symlink or control aliases."""
    require(isinstance(value, str) and not re.search(r"[\x00-\x1f\x7f]", value), "invalid path")
    path = Path(value)
    require(path.is_absolute() and str(path) == value and path.resolve() == path, "noncanonical path")
    return path


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate plan key")
        result[key] = value
    return result


class Worker:
    def __init__(self, plan_path: str, output_root: str):
        path = absolute(plan_path)
        require(path.is_file() and path.stat().st_size <= MAX_PLAN, "invalid plan")
        raw = path.read_bytes()
        require(len(raw) <= MAX_PLAN, "oversized plan")
        plan = json.loads(raw, object_pairs_hook=unique)
        require(isinstance(plan, dict) and isinstance(plan.get("inputs"), dict), "missing plan inputs")
        self.inputs = set()
        for name, expected in plan["inputs"].items():
            require(isinstance(name, str) and isinstance(expected, str) and
                    re.fullmatch(r"[0-9a-f]{64}", expected) is not None, "invalid plan input")
            source = Path(name)
            if not source.is_absolute():
                require(".." not in source.parts and str(source) == name, "invalid relative input")
                source = path.parent / source
            source = absolute(str(source))
            require(source not in self.inputs, "duplicate input path alias")
            self.inputs.add(source)
        self.output_root = absolute(output_root)
        require(self.output_root == path.parent / "result" / "routes", "invalid output root")

    def hash(self, value: str) -> str:
        """Read actual bytes each time; a plan digest authorizes a path, not a cache."""
        path = absolute(value)
        require(path in self.inputs or self.output_root in path.parents, "forbidden path")
        limit = MAX_DCP if path in self.inputs and path.suffix.lower() == ".dcp" else MAX_FILE
        before = path.stat(follow_symlinks=False)
        require(stat.S_ISREG(before.st_mode) and before.st_size <= limit, "invalid file size/type")
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            opened = os.fstat(stream.fileno())
            require((opened.st_dev, opened.st_ino) == (before.st_dev, before.st_ino) and
                    stat.S_ISREG(opened.st_mode) and opened.st_size <= limit, "file changed before read")
            checksum = hashlib.sha256()
            total = 0
            while chunk := stream.read(1024**2):
                total += len(chunk)
                require(total <= limit, "file grew beyond limit")
                checksum.update(chunk)
            after = os.fstat(stream.fileno())
            require(total == opened.st_size and
                    (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) ==
                    (after.st_size, after.st_mtime_ns, after.st_ctime_ns), "file changed during read")
        require(path.stat(follow_symlinks=False).st_ino == opened.st_ino, "file replaced during read")
        return checksum.hexdigest()

    def serve(self, source, destination) -> None:
        expected = 1
        while True:
            line = source.readline(MAX_LINE + 1)
            if line == b"":
                return
            require(len(line) <= MAX_LINE and line.endswith(b"\n"), "oversized or unterminated request")
            fields = line[:-1].split(b"\t")
            require(len(fields) == 2 and re.fullmatch(rb"[1-9][0-9]{0,19}", fields[0]) is not None,
                    "malformed request")
            number = int(fields[0])
            require(number == expected, "out-of-order request")
            require(len(fields[1]) <= MAX_PATH * 2 and
                    re.fullmatch(rb"(?:[0-9a-f]{2})+", fields[1]) is not None, "malformed encoded path")
            path = bytes.fromhex(fields[1].decode("ascii")).decode("utf-8", errors="strict")
            result = self.hash(path)
            destination.write(f"{number}\t{result}\n".encode("ascii"))
            destination.flush()
            expected += 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    try:
        Worker(args.plan, args.output_root).serve(sys.stdin.buffer, sys.stdout.buffer)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"route hash worker failed: {str(error)[:240]}", file=sys.stderr, flush=True)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
