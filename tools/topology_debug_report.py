#!/usr/bin/env python3
"""Render a manifest and the host's iterative topology-query report."""
import argparse
import hashlib
import json
from pathlib import Path


def validate(manifest, report):
    body = {key: value for key, value in manifest.items() if key != "fingerprint"}
    digest = hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False,
                                       separators=(",", ":")).encode()).hexdigest()
    if manifest.get("schema") != 3 or report.get("schema") != 1:
        raise ValueError("unsupported topology schema")
    if manifest.get("fingerprint") != digest or report.get("fingerprint") != digest:
        raise ValueError("manifest/report fingerprint mismatch")
    resources = manifest["resources"]
    if [r["id"] for r in resources] != list(range(len(resources))):
        raise ValueError("noncontiguous resource IDs")
    previous = -1
    for sample in report["observations"]:
        resource = resources[sample["id"]] if 0 <= sample["id"] < len(resources) else None
        if resource is None or not previous < sample["cycle"] < 1 << 64:
            raise ValueError("invalid resource or observation clock regression")
        if not 0 <= sample["value"] < 1 << resource["width"]:
            raise ValueError("value exceeds resource width")
        if resource["kind"] == "fifo" and sample["value"] > resource["capacity"]:
            raise ValueError("FIFO occupancy exceeds capacity")
        previous = sample["cycle"]
    return resources


def text_report(manifest, report):
    resources = validate(manifest, report)
    samples = report["observations"]
    lines = [f"{len(samples)} passive queries; {len(report['reobserved_blocked'])} channels blocked on both visits."]
    if samples:
        lines.append(f"Observation cycles {samples[0]['cycle']}–{samples[-1]['cycle']}.")
    latest = {s["id"]: s for s in samples}
    changed = set(report["changed_resources"])
    for resource_id, sample in latest.items():
        r = resources[resource_id]
        if r["kind"] == "fifo":
            suffix = " (changed on recheck)" if resource_id in changed else ""
            lines.append(f"  [{resource_id}] {r['name']}: {sample['value']}/{r['capacity']} stored, "
                         f"{r['capacity']-sample['value']} free slots at cycle {sample['cycle']}{suffix}")
    blocked = set(report["reobserved_blocked"])
    for edge in report["edges"]:
        resource_id = edge["channel"]
        state = "blocked on both visits" if resource_id in blocked else "changed on recheck"
        line = f"  [{resource_id}] {resources[resource_id]['name']}: {state}"
        if edge["kind"] == "external_sink":
            line += f"; external sink {edge['endpoint']}"
        elif edge["kind"] == "ambiguous":
            line += "; constant, missing, or ambiguous connection"
        else:
            targets = [str(i) for i in edge["next"] if i in blocked]
            line += "; candidate blocked outputs: " + (", ".join(targets) or "none observed")
        lines.append(line)
    for cycle in report["candidate_cycles"]:
        lines.append("Candidate cyclic group: " + ", ".join(map(str, cycle)))
    if report["truncated"]:
        lines.append("Exploration reached its query budget; unvisited dependencies remain.")
    if manifest["unsupported_queues"]:
        lines.append(f"{len(manifest['unsupported_queues'])} FIFO implementations have handshake probes only.")
    lines.append("These are successive observations, not a coherent snapshot or proof of deadlock. "
                 "Free slots exclude same-cycle pop credit. Actor-internal waits require further probes.")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("report", type=Path, nargs="?")
    parser.add_argument("--find", help="list resource IDs whose names contain this substring")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.find is not None:
        for r in manifest["resources"]:
            if args.find in r["name"]:
                print(f"[{r['id']}] {r['kind']}: {r['name']}")
    if args.report:
        print(text_report(manifest, json.loads(args.report.read_text())), end="")
    elif args.find is None:
        parser.error("supply a report or --find")


if __name__ == "__main__":
    main()
