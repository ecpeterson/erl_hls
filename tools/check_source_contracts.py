#!/usr/bin/env python3
"""Check Erlang source contracts, rejecting new or changed undocumented declarations."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile


def run(*args: str) -> str:
    """Return checked UTF-8 command output; failures stop the audit."""
    return subprocess.check_output(args, text=True)


def selected(paths: list[str], config: dict[str, object]) -> list[str]:
    """Select owned Erlang declarations using the reviewed repository scope."""
    return sorted(set(p for p in paths if p.endswith((".erl", ".hrl"))
                      and any(Path(p).match(pattern) for pattern in config["include"])
                      and not any(Path(p).match(pattern) for pattern in config.get("exclude", []))))


def findings(stage: str, paths: list[str], cwd: str) -> list[dict[str, object]]:
    """Read source with a macro-preserving parser, without compiling or executing it."""
    result = subprocess.run(["erl", "+S", "2", "-noshell", "-pa", stage,
                             "-s", "source_contracts", "main", "--", *paths],
                            cwd=cwd, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def key(item: dict[str, object]) -> tuple[object, object, object]:
    """Identify a requirement on one declaration independently of source line numbers."""
    return item["path"], item["id"], item["rule"]


def baseline(stage: str, revision: str, config: dict[str, object]) -> list[dict[str, object]]:
    """Audit the comparison revision as inert source using the current checker."""
    paths = selected(run("git", "ls-tree", "-r", "--name-only", revision).splitlines(), config)
    if not paths:
        return []
    archive = subprocess.check_output(["git", "archive", revision, "--", *paths])
    with tempfile.TemporaryDirectory(prefix="source-contracts-base-") as directory:
        with tarfile.open(fileobj=io.BytesIO(archive)) as files:
            files.extractall(directory, filter="data")
        return findings(stage, paths, directory)


def regressions(gaps: list[dict[str, object]], prior: list[dict[str, object]]) -> list[dict[str, object]]:
    """Reject new debt, retaining each conditional definition's distinct fingerprint."""
    prior_by_key = defaultdict(set)
    for item in prior:
        prior_by_key[key(item)].add(item["fingerprint"])
    return [item for item in gaps if item["rule"] == "parse"
           or item["fingerprint"] not in prior_by_key[key(item)]]


def main() -> int:
    """Check changed declarations, optionally reporting the full backlog or requiring zero debt."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="comparison revision; default: merge base with the configured target")
    parser.add_argument("--strict", action="store_true", help="require zero gaps, including unchanged declarations")
    parser.add_argument("--report", default="_build/source-contracts.json", help="complete machine-readable audit")
    parser.add_argument("paths", nargs="*", help="check only these paths (use --strict for migrated modules)")
    args = parser.parse_args()
    config = json.loads(Path("source-contracts.json").read_text())
    paths = args.paths or selected(run("git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines(), config)
    revision = args.base or run("git", "merge-base", "HEAD", config["base_ref"]).strip()
    with tempfile.TemporaryDirectory(prefix="source-contracts-") as stage:
        subprocess.run(["erlc", "-Werror", "-o", stage, "tools/source_contracts.erl"], check=True)
        gaps = findings(stage, paths, str(Path.cwd()))
        prior = [] if args.strict else baseline(stage, revision, config)
    new = regressions(gaps, prior)
    report = {"base": revision, "files": len(paths), "gaps": gaps, "new": new,
              "counts": dict(Counter(i["rule"] for i in gaps))}
    destination = Path(args.report)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for item in new:
        print(f"{item['path']}:{item['line']}: {item['id']}: missing {item['rule']}")
    print(f"Checked {len(paths)} Erlang files; {len(gaps)} existing/current gaps: {report['counts']}; {len(new)} new/changed gaps")
    return int(bool(new))


if __name__ == "__main__":
    raise SystemExit(main())
