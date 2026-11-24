#!/usr/bin/env python3
"""Check source contracts, rejecting new or changed undocumented declarations."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from fnmatch import fnmatchcase
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

import dslx_source_contracts


def run(*args: str) -> str:
    """Return checked UTF-8 command output; failures stop the audit."""
    return subprocess.check_output(args, text=True)


def selected(paths: list[str], config: dict[str, object]) -> list[str]:
    """Select owned Erlang and handwritten DSLX using the reviewed repository scope."""
    return sorted(set(p for p in paths if p.endswith((".erl", ".hrl", ".x"))
                      and any(fnmatchcase(p, pattern) for pattern in config["include"])
                      and not any(fnmatchcase(p, pattern) for pattern in config.get("exclude", []))))


def moved_path(path: str, moves: dict[str, str]) -> str:
    """Translate one historical path through an explicit mechanical landing map."""
    for source in sorted(moves, key=len, reverse=True):
        if path.startswith(source):
            return moves[source] + path[len(source):]
    return path


def test_module_scope(path: str) -> str | None:
    """Return the application whose tests own a module isolated in a separate VM."""
    parts = Path(path).parts
    if (len(parts) >= 4 and parts[0] in {"apps", "workloads"}
            and parts[2] in {"test", "test_data"}):
        return parts[1]
    return None


def erlang_findings(files: list[dict[str, object]]) -> list[dict[str, object]]:
    """Attach module identities and reject copies that can share one code server."""
    owners = defaultdict(list)
    for item in files:
        if item["module"] is not None:
            owners[item["module"]].append(item)
    ambiguous = set()
    for module, items in owners.items():
        scopes = [test_module_scope(item["path"]) for item in items]
        isolated = all(scope is not None for scope in scopes) and len(scopes) == len(set(scopes))
        if len(items) > 1 and not isolated:
            ambiguous.add(module)
    gaps = []
    for item in files:
        module = item["module"]
        scope = test_module_scope(item["path"])
        identity = ({"module": module} | ({"module_scope": scope} if scope else {})) \
            if module is not None and module not in ambiguous else {}
        gaps.extend(gap | identity for gap in item["findings"])
        if module in ambiguous:
            gaps.append({"path": item["path"], "line": item["module_line"],
                         "id": f"module:{module}", "rule": "module_identity",
                         "fingerprint": hashlib.sha256(module.encode()).hexdigest(),
                         "reason": f"duplicate Erlang module {module}; source identity is ambiguous"})
    return gaps


def findings(stage: str, paths: list[str], cwd: str) -> list[dict[str, object]]:
    """Inspect inert source; paths must include the complete owned module inventory."""
    erlang = [p for p in paths if p.endswith((".erl", ".hrl"))]
    gaps = []
    if erlang:
        result = subprocess.run(["erl", "+S", "2", "-noshell", "-pa", stage,
                                 "-s", "source_contracts", "main", "--", *erlang],
                                cwd=cwd, check=True, text=True, capture_output=True)
        gaps = erlang_findings(json.loads(result.stdout))
    return gaps + dslx_source_contracts.findings([p for p in paths if p.endswith(".x")], cwd)


def key(item: dict[str, object]) -> tuple[object, object, object]:
    """Match unique Erlang modules across moves; other source remains path-bound."""
    owner = (("module", item["module"], item.get("module_scope"))
             if "module" in item else ("path", item["path"]))
    return owner, item["id"], item["rule"]


def baseline(stage: str, revision: str, config: dict[str, object],
             moves: dict[str, str] | None = None) -> list[dict[str, object]]:
    """Audit one historical inventory after its declared mechanical path landing."""
    moves = moves or {}
    tree = run("git", "ls-tree", "-r", "--name-only", revision).splitlines()
    landed = {path: moved_path(path, moves) for path in tree}
    selected_landed = set(selected(list(landed.values()), config))
    paths = [path for path in tree if landed[path] in selected_landed]
    if not paths:
        return []
    archive = subprocess.check_output(["git", "archive", revision, "--", *paths])
    with tempfile.TemporaryDirectory(prefix="source-contracts-base-") as directory:
        with tarfile.open(fileobj=io.BytesIO(archive)) as files:
            files.extractall(directory, filter="data")
        result = []
        for item in findings(stage, paths, directory):
            path = moved_path(item["path"], moves)
            landed = item | {"path": path}
            if "module" in landed:
                scope = test_module_scope(path)
                landed = (landed | {"module_scope": scope}) if scope else {
                    key: value for key, value in landed.items() if key != "module_scope"}
            result.append(landed)
        return result


def inherited_baselines(stage: str, primary: str,
                        config: dict[str, object]) -> tuple[list[dict[str, object]], list[str]]:
    """Combine the primary base with migration parents absent from that base."""
    revisions = [primary]
    prior = baseline(stage, primary, config, config.get("baseline_moves", {}))
    for migration in config.get("migration_baselines", []):
        revision = migration["revision"]
        contained = subprocess.run(["git", "merge-base", "--is-ancestor", revision, primary],
                                   check=False, capture_output=True).returncode == 0
        if not contained:
            revisions.append(revision)
            prior.extend(baseline(stage, revision, config, migration.get("moves", {})))
    return prior, revisions


def regressions(gaps: list[dict[str, object]], prior: list[dict[str, object]]) -> list[dict[str, object]]:
    """Retain unchanged declaration debt; parse and identity failures always reject."""
    prior_by_key = defaultdict(set)
    for item in prior:
        prior_by_key[key(item)].add(item["fingerprint"])
    return [item for item in gaps if item["rule"] in {"parse", "module_identity"}
           or item["fingerprint"] not in prior_by_key[key(item)]]


def main() -> int:
    """Check selected declarations while determining module uniqueness repository-wide."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="comparison revision; default: merge base with the configured target")
    parser.add_argument("--strict", action="store_true", help="require zero gaps, including unchanged declarations")
    parser.add_argument("--report", default="_build/source-contracts.json", help="complete machine-readable audit")
    parser.add_argument("paths", nargs="*", help="check only these paths (use --strict for migrated modules)")
    args = parser.parse_args()
    config = json.loads(Path("source-contracts.json").read_text())
    tracked = run("git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    # Deleted old paths are absent from the current tree, including unstaged moves.
    inventory = [p for p in selected(tracked, config) if Path(p).is_file()]
    # Resolve both sides so filesystem aliases cannot duplicate one Git path.
    source_root = Path.cwd().resolve()
    paths = list(dict.fromkeys(os.path.relpath(Path(p).resolve(), source_root)
                               for p in args.paths)) or inventory
    revision = args.base or run("git", "merge-base", "HEAD", config["base_ref"]).strip()
    with tempfile.TemporaryDirectory(prefix="source-contracts-") as stage:
        subprocess.run(["erlc", "-Werror", "-o", stage, "tools/source_contracts.erl"], check=True)
        current = findings(stage, sorted(set(inventory) | set(paths)), str(source_root))
        gaps = [item for item in current if item["path"] in paths or item["rule"] == "module_identity"]
        prior, revisions = ([], []) if args.strict else inherited_baselines(stage, revision, config)
    new = regressions(gaps, prior)
    report = {"base": revision, "bases": revisions, "files": len(paths),
              "gaps": gaps, "new": new,
              "counts": dict(Counter(i["rule"] for i in gaps))}
    destination = Path(args.report)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for item in new:
        reason = item.get("reason", f"missing {item['rule']}")
        print(f"{item['path']}:{item['line']}: {item['id']}: {reason}")
    print(f"Checked {len(paths)} source files; {len(gaps)} existing/current gaps: {report['counts']}; {len(new)} new/changed gaps")
    return int(bool(new))


if __name__ == "__main__":
    raise SystemExit(main())
