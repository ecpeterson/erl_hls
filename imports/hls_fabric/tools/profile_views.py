"""Stack observed actor ownership and boundary clocks without changing timing dependencies."""

from __future__ import annotations
from collections import defaultdict
import html
import json


def actor_views(profile: dict) -> list[dict]:
    """Nest boundary clock bins under each vertex's owned transactions.

    Equal-time boundaries share one display bin. Original event IDs remain in
    its arguments; these presentation slices add no work or causal relation.
    Ownership includes waits and is never labeled as compute occupancy.
    """
    owners = {
        event["args"]["source"]: event["args"]["group"]
        for event in profile["events"]
        if event["category"] == "ownership" and event["track"].startswith("activation/owner/")
    }
    grouped = defaultdict(list)
    for event in profile["events"]:
        if not event["track"].startswith(("activation/", "collection/", "mailbox/")):
            continue
        source = event.get("args", {}).get("source")
        if source in owners:
            grouped[source].append(event)
    views = []
    for source, events in sorted(grouped.items(), key=lambda item: (owners[item[0]], item[0])):
        bins = defaultdict(list)
        slices = []
        for event in events:
            if event["category"] == "ownership":
                slices.append(
                    {
                        "ts": event["ts"],
                        "dur": event["dur"],
                        "name": event["name"],
                        "category": "ownership",
                        "source_event_ids": [event["id"]],
                    }
                )
            else:
                width = event.get("display_duration_ns", event["dur"])
                bins[event["ts"], width].append(event)
        for (ts, width), items in bins.items():
            names = [event["name"].split(": v", 1)[0] for event in items]
            slices.append(
                {
                    "ts": ts,
                    "dur": width,
                    "name": " + ".join(dict.fromkeys(names)),
                    "category": "boundary clock",
                    "source_event_ids": [event["id"] for event in items],
                }
            )
        slices.sort(key=lambda event: (event["ts"], -event["dur"], event["category"] != "ownership"))
        stack = []
        for event in slices:
            while stack and event["ts"] >= stack[-1]:
                stack.pop()
            if stack and event["ts"] + event["dur"] > stack[-1]:
                raise ValueError("combined view would contain crossing, non-nested slices")
            event["depth"] = len(stack)
            if event["dur"]:
                stack.append(event["ts"] + event["dur"])
        views.append(
            {
                "name": f"Executor {owners[source]} / vertex {source:02d}",
                "source": source,
                "executor": owners[source],
                "slices": slices,
            }
        )
    return views


def perfetto(profile: dict, exported: dict) -> dict:
    """Add combined presentation tracks while preserving all original slices and causal flows."""
    events = list(exported["traceEvents"])
    pid = 1 + max((event.get("pid", 0) for event in events), default=0)
    additions = [
        {
            "ph": "M",
            "name": "process_name",
            "pid": pid,
            "args": {"name": "Combined vertex activity — ownership includes waits"},
        }
    ]
    for tid, view in enumerate(actor_views(profile), 1):
        additions.append(
            {"ph": "M", "name": "thread_name", "pid": pid, "tid": tid, "args": {"name": view["name"]}}
        )
        for event in view["slices"]:
            additions.append(
                {
                    "ph": "X",
                    "pid": pid,
                    "tid": tid,
                    "ts": event["ts"] / 1000,
                    "dur": event["dur"] / 1000,
                    "name": event["name"],
                    "cat": event["category"],
                    "args": {
                        "display_only": True,
                        "source_event_ids": json.dumps(event["source_event_ids"]),
                        "executor": view["executor"],
                        "vertex": view["source"],
                        "scope": "Combined view of existing observations; no additional work or dependencies inferred.",
                    },
                }
            )
    return {**exported, "traceEvents": additions + events}


def svg(profile: dict, start: int, end: int) -> str:
    """Render the same nested presentation for readers without an interactive trace viewer."""
    if end <= start:
        raise ValueError("empty view window")
    views = actor_views(profile)
    width = 1450
    height = 110 + 58 * len(views)
    left = 205
    span = width - left - 20

    def x(time: int) -> float:
        """Position a trace timestamp on the visible interval."""
        return left + span * (time - start) / (end - start)

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        "<style>text{font:12px sans-serif;fill:#17212b}</style>",
        '<text x="15" y="23">Executor + vertex activity — blue: owned transaction (includes waits); purple: observed boundary clock</text>',
        '<text x="15" y="43">Nested blocks repeat existing observations. Blank space is unowned time, not a claim of idle hardware.</text>',
    ]
    for tick in range(9):
        ts = start + (end - start) * tick // 8
        xp = x(ts)
        out.append(
            f'<path d="M{xp:.2f} 70 V{height-20}" stroke="#eee"/><text x="{xp:.2f}" y="65" text-anchor="middle">{ts} ns</text>'
        )
    for index, view in enumerate(views):
        y = 90 + index * 58
        out.append(f'<text x="12" y="{y+5}">{html.escape(view["name"])}</text>')
        for event in view["slices"]:
            if event["ts"] >= end or event["ts"] + event["dur"] <= start:
                continue
            xp = x(max(start, event["ts"]))
            w = max(1, x(min(end, event["ts"] + event["dur"])) - xp)
            yp = y + event["depth"] * 15
            color = "#5c95bb" if event["category"] == "ownership" else "#8862aa"
            tip = html.escape(json.dumps(event))
            out.append(
                f'<rect x="{xp:.2f}" y="{yp}" width="{w:.2f}" height="13" fill="{color}"><title>{tip}</title></rect>'
            )
    return "\n".join([*out, "</svg>"]) + "\n"
