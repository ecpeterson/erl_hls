#!/usr/bin/env python3
"""Bundle bounded CI diagnostics; large logs retain their tail, not their prefix."""
import glob
import json
import os
from pathlib import Path
import zipfile

FILE_BYTES = 256 * 1024
TOTAL_BYTES = 4 * 1024 * 1024
FILE_COUNT = 256
NETLISTS = {"flat.json", "hierarchy.json", "instrumented.json"}


def regression_priorities(root: Path, files: set[Path]) -> dict[Path, int]:
    """Prefer failed case evidence without adding paths or parsing unbounded metadata."""
    available = {path.resolve(): path for path in files}
    receipts = [path for path in files if path.name == "regression.json"]
    priorities = {path: 2 for path in receipts}
    remaining = TOTAL_BYTES

    def record(path: Path) -> dict:
        """Read at most one bounded JSON object, sharing the total metadata-read budget."""
        nonlocal remaining
        try:
            size = path.stat().st_size
            if size > min(FILE_BYTES, remaining):
                return {}
            with path.open("rb") as stream:
                data = stream.read(size)
            remaining -= len(data)
            value = json.loads(data)
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError, RecursionError):
            return {}

    def matched(value: object) -> Path | None:
        """Resolve a receipt reference only to a file already admitted by the workflow globs."""
        if not isinstance(value, str):
            return None
        try:
            return available.get((root / value).resolve())
        except (OSError, ValueError, RuntimeError):
            return None

    for receipt in sorted(receipts, key=lambda path: (path.stat().st_size, str(path))):
        metadata = record(receipt)
        if metadata.get("status") != "failed":
            continue
        priorities[receipt] = 0
        steps = metadata.get("steps")
        if not isinstance(steps, list):
            continue
        failed = next((step for step in reversed(steps) if isinstance(step, dict)
                       and step.get("status") in ("failed", "running")), {})
        log = failed.get("log")
        if not isinstance(log, str):
            continue
        for name in ("stderr.log", "command.json", "time.json", "stdout.log"):
            if path := matched(str(Path(log) / name)):
                priorities[path] = 1
        command = matched(str(Path(log) / "command.json"))
        # A failed command has not yet copied stdout into its result row. The
        # command record still names it, including products outside the log dir.
        stdout = record(command).get("stdout") if command is not None else failed.get("stdout")
        if path := matched(stdout):
            priorities[path] = 1
    return priorities


def collect(root: Path, patterns: list[str], output: Path) -> dict:
    """Write at most 4 MiB of payload plus an index; omit oversized non-log files.

    Patterns are relative to root. Symlinks, files outside root, Yosys netlists
    and excess files are omitted. Failed regression receipts and their step
    diagnostics take precedence. The index records sizes, omissions and tails.
    """
    root = root.resolve()
    files = set()
    for pattern in patterns:
        for match in glob.iglob(str(root / pattern), recursive=True):
            path = Path(match)
            if (path.is_file() and not path.is_symlink()
                    and path.resolve().is_relative_to(root)
                    and path.resolve() != output.resolve()):
                files.add(path)
    priorities = regression_priorities(root, files)
    ordered = sorted(files, key=lambda path: (priorities.get(path, 3), path.stat().st_size, str(path)))
    report = {"payload_bytes": 0, "matched_files": len(ordered),
              "unlisted_files": max(0, len(ordered) - FILE_COUNT), "files": []}
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in ordered[:FILE_COUNT]:
            name, size = str(path.relative_to(root)), path.stat().st_size
            item = {"path": name, "bytes": size}
            report["files"].append(item)
            if path.name in NETLISTS:
                item["omitted"] = "generated netlist"
                continue
            if size > FILE_BYTES and path.suffix != ".log":
                item["omitted"] = "file limit"
                continue
            count = min(size, FILE_BYTES)
            if report["payload_bytes"] + count > TOTAL_BYTES:
                item["omitted"] = "bundle limit"
                continue
            with path.open("rb") as source:
                source.seek(size - count)
                data = source.read(count)
            archive.writestr(name, data)
            item["retained_bytes"] = len(data)
            item["tail_only"] = count < size
            report["payload_bytes"] += len(data)
        archive.writestr("diagnostics-index.json", json.dumps(report, indent=2))
    return report


def main() -> None:
    """Collect the workflow's requested paths and report the actual upload size."""
    patterns = os.environ["DIAGNOSTIC_PATHS"].splitlines()
    output = Path(os.environ["DIAGNOSTIC_OUTPUT"])
    report = collect(Path.cwd(), [p.strip() for p in patterns if p.strip()], output)
    message = (f"CI diagnostics: {report['matched_files']} matched files; "
               f"{report['payload_bytes']} payload bytes; "
               f"{output.stat().st_size} compressed bytes. "
               "Limits: 256 files, 256 KiB/file, 4 MiB payload; expires in 2 days.\n")
    print(message, end="")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary).open("a") as stream:
            stream.write(message)


if __name__ == "__main__":
    main()
