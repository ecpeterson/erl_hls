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


def collect(root: Path, patterns: list[str], output: Path) -> dict:
    """Write at most 4 MiB of payload plus an index; omit oversized non-log files.

    Patterns are relative to root. Symlinks, files outside root, Yosys netlists
    and excess files are omitted. The index records sizes, omissions and tails.
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
    # Prefer small reports to repetitive compiler output when the budget fills.
    ordered = sorted(files, key=lambda path: (path.stat().st_size, str(path)))
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
