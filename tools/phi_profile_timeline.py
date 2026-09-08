#!/usr/bin/env python3
"""Render a clock-aligned SVG timeline from the phi VPI trace CSV."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
import csv
import html
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Event:
    cycle: int
    component: str
    event: str
    slot: int | None
    detail: str


@dataclass(frozen=True)
class Dependency:
    source: Event
    target: Event
    kind: str
    detail: str


BACKGROUND = "var(--background, var(--phi-background))"
FOREGROUND = "var(--foreground, var(--phi-foreground))"
MUTED = "var(--muted, var(--phi-muted))"
MUTED_FOREGROUND = (
    "var(--muted-foreground, var(--phi-muted-foreground))"
)
BORDER = "var(--border, var(--phi-border))"
DESTRUCTIVE = "var(--destructive, var(--phi-destructive))"
SERIES = {
    index: f"var(--viz-series-{index}, var(--phi-series-{index}))"
    for index in range(1, 7)
}

# Codex supplies the unprefixed theme variables when a figure is embedded in
# conversation.  The private phi variables make the exact same SVG portable:
# browsers, Quick Look, and editor previews do not need an external stylesheet.
SVG_THEME_CSS = [
    "svg{color-scheme:light dark;"
    "--phi-background:#ffffff;--phi-foreground:#1f2328;"
    "--phi-muted:#afb8c1;--phi-muted-foreground:#59636e;"
    "--phi-border:#d0d7de;--phi-destructive:#cf222e;"
    "--phi-series-1:#0969da;--phi-series-2:#1a7f37;"
    "--phi-series-3:#8250df;--phi-series-4:#cf222e;"
    "--phi-series-5:#bf8700;--phi-series-6:#bc4c00}",
    "@media(prefers-color-scheme:dark){svg{"
    "--phi-background:#0d1117;--phi-foreground:#f0f6fc;"
    "--phi-muted:#6e7681;--phi-muted-foreground:#9198a1;"
    "--phi-border:#3d444d;--phi-destructive:#ff7b72;"
    "--phi-series-1:#58a6ff;--phi-series-2:#3fb950;"
    "--phi-series-3:#bc8cff;--phi-series-4:#ff7b72;"
    "--phi-series-5:#d29922;--phi-series-6:#ffa657}}",
]

COLORS = {
    "batch_accept": SERIES[1],
    "aggregate_send": SERIES[2],
    "aggregate_receive": SERIES[3],
    "aggregate_accept": SERIES[4],
    "aggregate_complete": SERIES[4],
    "aggregate_pending": SERIES[6],
    "aggregate_error": DESTRUCTIVE,
    "state_read": SERIES[5],
    "state_write": SERIES[5],
    "effects_egress": SERIES[2],
    "fast_issue": SERIES[2],
    "retained_issue": SERIES[5],
    "selectable": SERIES[1],
    "same_actor_only": SERIES[6],
    "executor_blocked": SERIES[4],
    "no_actor_work": MUTED,
    "waiting_egress_credit": SERIES[3],
    "internal_other": MUTED,
}


def numbered_components(events: list[Event], prefix: str) -> list[str]:
    return sorted(
        {
            event.component
            for event in events
            if event.component.startswith(prefix)
            and event.component.removeprefix(prefix).isdigit()
        },
        key=lambda name: int(name.removeprefix(prefix)),
    )


def phi_groups(events: list[Event]) -> tuple[list[list[str]], list[str]]:
    schedulers = numbered_components(events, "phi_")
    planes = sorted(
        {
            event.component
            for event in events
            if event.component.startswith("phi_")
            and event.component.endswith("_plane")
        }
    )
    if not schedulers or not planes or len(schedulers) % len(planes) != 0:
        raise SystemExit("cannot infer phi scheduler shards and planes")
    group_size = len(schedulers) // len(planes)
    return [
        schedulers[index:index + group_size]
        for index in range(0, len(schedulers), group_size)
    ], planes


def phi_router_map(events: list[Event], schedulers: list[str]) -> dict[str, str]:
    routers = numbered_components(events, "window_router_")
    if len(routers) < len(schedulers):
        raise SystemExit("cannot map phi schedulers to effect routers")
    return dict(zip(schedulers, routers[-len(schedulers):], strict=True))


def source_fragment_destination_table(
    source: str, plane: str
) -> dict[int, list[int]] | None:
    """Invert the generated source-fragment plane's per-destination heads.

    A source-fragment plane stores one FIFO bank per reduction lane.  Its
    `pop_sources` table says which source head each lane consumes for a given
    destination.  Inverting every lane permutation recovers the same stable
    source-to-destinations metadata emitted explicitly by the older
    joined transport, without adding any hardware solely for profiling.
    """
    marker = f"struct Phi_{plane}ReductionFragmentQueue"
    if marker not in source:
        return None
    match = re.search(
        rf"proc Phi_{plane}ReductionPlane\s*\{{.*?"
        rf"let pop_sources = match output_slot \{{(?P<body>.*?)\n\s*_ =>",
        source,
        re.DOTALL,
    )
    if not match:
        raise SystemExit(
            f"cannot parse source-fragment destinations for phi {plane}"
        )
    inverse = {}
    for row in re.finditer(
        r"u32:(\d+)\s*=>\s*\[([^]]+)\]", match.group("body")
    ):
        inverse[int(row.group(1))] = [
            int(value) for value in re.findall(r"u32:(\d+)", row.group(2))
        ]
    if not inverse:
        raise SystemExit(
            f"empty source-fragment destination table for phi {plane}"
        )
    populations = {len(sources) for sources in inverse.values()}
    if len(populations) != 1:
        raise SystemExit(
            f"ragged source-fragment destination table for phi {plane}"
        )
    population = populations.pop()
    actor_count = len(inverse)
    expected = set(range(actor_count))
    destinations = {
        source_actor: [None] * population
        for source_actor in range(actor_count)
    }
    for destination, sources in inverse.items():
        if destination not in expected:
            raise SystemExit(
                f"sparse source-fragment destinations for phi {plane}"
            )
        for lane, source_actor in enumerate(sources):
            if source_actor not in expected:
                raise SystemExit(
                    f"invalid source-fragment source for phi {plane}"
                )
            if destinations[source_actor][lane] is not None:
                raise SystemExit(
                    f"non-bijective source-fragment lane for phi {plane}"
                )
            destinations[source_actor][lane] = destination
    if any(
        destination is None
        for rows in destinations.values()
        for destination in rows
    ):
        raise SystemExit(
            f"incomplete source-fragment destinations for phi {plane}"
        )
    return {
        source_actor: [int(destination) for destination in rows]
        for source_actor, rows in destinations.items()
    }


def parse_reduction_topology(
    path: Path | None,
) -> tuple[dict[str, dict[int, list[int]]], set[str]]:
    if path is None or not path.exists():
        return {}, set()
    source = path.read_text(encoding="utf-8")
    tables = {}
    source_fragment_planes = set()
    for plane in ("x", "z"):
        match = re.search(
            rf"fn phi_{plane}_reduction_destinations\(source: u32\).*?"
            rf"\{{\s*match source \{{(?P<body>.*?)\n\s*_ =>",
            source,
            re.DOTALL,
        )
        if match:
            table = {}
            for row in re.finditer(
                r"u32:(\d+)\s*=>\s*\[([^]]+)\]", match.group("body")
            ):
                table[int(row.group(1))] = [
                    int(value)
                    for value in re.findall(r"u32:(\d+)", row.group(2))
                ]
            if table:
                tables[plane] = table
        fragment_table = source_fragment_destination_table(source, plane)
        if fragment_table is not None:
            tables[plane] = fragment_table
            source_fragment_planes.add(plane)
    return tables, source_fragment_planes


def parse_destination_tables(path: Path | None) -> dict[str, dict[int, list[int]]]:
    """Retain the original table-only helper for callers outside this tool."""
    return parse_reduction_topology(path)[0]


def event_site(event: Event) -> str | None:
    return detail_fields(event.detail).get("site")


def dependency_graph(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    router_map: dict[str, str],
    destination_tables: dict[str, dict[int, list[int]]],
    source_fragment_planes: set[str] | None = None,
) -> list[Dependency]:
    """Infer preserved-order dependencies between observed handshakes.

    The trace deliberately contains no synthetic transaction identifier.  The
    scheduler egress FIFO and each reduction-batch channel preserve order, so
    their handshakes can be paired exactly.  Contribution-to-aggregate edges
    additionally use the generated static destination table.
    """
    dependencies: list[Dependency] = []
    source_fragment_planes = source_fragment_planes or set()
    by_component: dict[str, list[Event]] = defaultdict(list)
    for event in events:
        by_component[event.component].append(event)

    # A completion makes the matching actor selectable; the next read of that
    # slot consumes it.  Reads and writes are paired per slot so overlapped
    # visits remain unambiguous.
    visit_site: dict[int, str] = {}
    write_read: dict[int, Event] = {}
    for scheduler in [item for group in groups for item in group]:
        pending_completion: dict[int, deque[Event]] = defaultdict(deque)
        pending_read: dict[int, deque[Event]] = defaultdict(deque)
        for event in by_component[scheduler]:
            if event.slot is None:
                continue
            if event.event == "aggregate_complete":
                pending_completion[event.slot].append(event)
            elif event.event == "state_read":
                if pending_completion[event.slot]:
                    completion = pending_completion[event.slot].popleft()
                    dependencies.append(Dependency(
                        completion, event, "completion_to_read",
                        f"completed {event_site(completion) or 'reduction'} "
                        f"selects actor {event.slot}",
                    ))
                    site = event_site(completion)
                    if site:
                        visit_site[id(event)] = site
                pending_read[event.slot].append(event)
            elif event.event == "state_write" and pending_read[event.slot]:
                read = pending_read[event.slot].popleft()
                dependencies.append(Dependency(
                    read, event, "actor_visit",
                    f"actor {event.slot} state transaction",
                ))
                write_read[id(event)] = read

    # A state write and effect-bundle enqueue are the two retirement actions
    # of one callback transaction.  Pair the enqueues with router accepts using
    # the scheduler FIFO's preserved order.
    scheduler_geometry = {
        scheduler: (len(group), shard)
        for group in groups
        for shard, scheduler in enumerate(group)
    }
    routed_accepts: dict[str, list[tuple[Event, int | None]]] = defaultdict(list)
    for scheduler, router in router_map.items():
        writes_by_cycle = {
            event.cycle: event
            for event in by_component[scheduler]
            if event.event == "state_write"
        }
        egresses = [
            event for event in by_component[scheduler]
            if event.event == "effects_egress"
        ]
        accepts = [
            event for event in by_component[router]
            if event.event == "effects_accept"
        ]
        for egress, accepted in zip(egresses, accepts):
            write = writes_by_cycle.get(egress.cycle)
            if write is not None:
                dependencies.append(Dependency(
                    write, egress, "retirement",
                    f"actor {write.slot} retires an effect bundle",
                ))
            dependencies.append(Dependency(
                egress, accepted, "egress_fifo",
                "scheduler egress FIFO preserves bundle order",
            ))
            if write is None or write.slot is None:
                source_actor = None
            else:
                shard_count, shard = scheduler_geometry[scheduler]
                source_actor = write.slot * shard_count + shard
            routed_accepts[router].append((accepted, source_actor))

    # Match each reduction router's accepted bundle with that shard's next
    # plane input handshake.  The trace's batch slot is the packed batch's
    # final destination; the static table makes it possible to recover the
    # source actor and all four destinations without adding profiling bits to
    # the hardware interface.
    batch_sources: dict[int, int] = {}
    for group, plane in zip(groups, planes, strict=True):
        tag = "x" if "_x_" in plane else "z"
        table = destination_tables.get(tag, {})
        source_fragment = tag in source_fragment_planes
        inverse_last = {
            destinations[-1]: source
            for source, destinations in table.items()
            if destinations
        }
        batches_by_shard: dict[int, deque[Event]] = defaultdict(deque)
        for event in by_component[plane]:
            if event.event != "batch_accept":
                continue
            fields = detail_fields(event.detail)
            shard = int(fields.get("source", "-1"))
            batches_by_shard[shard].append(event)
            if source_fragment and event.slot is not None:
                batch_sources[id(event)] = event.slot
            elif event.slot in inverse_last:
                batch_sources[id(event)] = inverse_last[event.slot]
        for shard, scheduler in enumerate(group):
            router = router_map[scheduler]
            sends = [
                event for event in by_component[router]
                if event.event == "reduction_send"
            ]
            if sends:
                unmatched_accepts = list(routed_accepts[router])
                matched_sends: list[tuple[Event, Event, int | None]] = []
                for sent in sends:
                    source = (
                        sent.slot if source_fragment
                        else inverse_last.get(sent.slot)
                    )
                    candidates = [
                        (index, accepted)
                        for index, (accepted, accepted_source) in
                        enumerate(unmatched_accepts)
                        if accepted.cycle <= sent.cycle
                        and (source is None or accepted_source == source)
                    ]
                    if not candidates:
                        continue
                    accepted_index, accepted = candidates[-1]
                    unmatched_accepts.pop(accepted_index)
                    dependencies.append(Dependency(
                        accepted, sent, "router_dispatch",
                        "accepted effect bundle is emitted as a reduction batch",
                    ))
                    matched_sends.append((accepted, sent, source))
                unmatched_sends = list(matched_sends)
                delivered: dict[int, Event] = {}
                for batch in batches_by_shard[shard]:
                    source = batch_sources.get(id(batch))
                    candidates = [
                        (index, sent)
                        for index, (_accepted, sent, sent_source) in
                        enumerate(unmatched_sends)
                        if sent.cycle <= batch.cycle
                        and (source is None or sent_source == source)
                    ]
                    if not candidates:
                        continue
                    sent_index, sent = candidates[-1]
                    unmatched_sends.pop(sent_index)
                    delivered[id(sent)] = batch
                    dependencies.append(Dependency(
                        sent, batch, "reduction_fifo",
                        "reduction channel FIFO delivers the batch to the plane"
                        if source is None else
                        f"source actor {source} batch enters the shared plane",
                    ))
                for (_previous_accept, previous_send, _source), \
                        (accepted, _send, _next_source) in zip(
                            matched_sends, matched_sends[1:]
                        ):
                    previous_batch = delivered.get(id(previous_send))
                    if (
                        previous_batch is not None
                        and accepted.cycle > previous_batch.cycle
                    ):
                        dependencies.append(Dependency(
                            previous_batch, accepted, "router_capacity",
                            "the plane drains the one-entry reduction FIFO",
                        ))
            else:
                # Older traces predate the explicit router-output probe.  The
                # source identity and ordered handshakes still recover the
                # coarser router-to-plane edge.
                unmatched = list(routed_accepts[router])
                matched: list[tuple[Event, Event]] = []
                for batch in batches_by_shard[shard]:
                    source = batch_sources.get(id(batch))
                    candidates = [
                        (index, accepted)
                        for index, (accepted, accepted_source) in
                        enumerate(unmatched)
                        if accepted.cycle <= batch.cycle
                        and (source is None or accepted_source == source)
                    ]
                    if not candidates:
                        continue
                    accepted_index, accepted = candidates[-1]
                    unmatched.pop(accepted_index)
                    dependencies.append(Dependency(
                        accepted, batch, "router_to_plane",
                        "reduction batch enters the shared plane"
                        if source is None else
                        f"source actor {source} batch enters the shared plane",
                    ))
                    matched.append((accepted, batch))
                for (_previous_accept, previous_batch), \
                        (accepted, _batch) in zip(matched, matched[1:]):
                    if accepted.cycle > previous_batch.cycle:
                        dependencies.append(Dependency(
                            previous_batch, accepted, "router_capacity",
                            "the previous batch frees the router's single active slot",
                        ))

        if not table:
            continue
        population = len(next(iter(table.values())))
        contributions: dict[tuple[int, int], deque[Event]] = defaultdict(deque)
        for event in by_component[plane]:
            if event.event == "batch_accept":
                source = batch_sources.get(id(event))
                if source is not None:
                    for lane, destination in enumerate(table[source]):
                        contributions[(destination, lane)].append(event)
            elif event.event == "aggregate_send" and event.slot is not None:
                shard = int(detail_fields(event.detail).get("shard", "-1"))
                destination = event.slot * len(group) + shard
                members = [
                    contributions[(destination, lane)].popleft()
                    for lane in range(population)
                    if contributions[(destination, lane)]
                ]
                if len(members) == population:
                    for member in members:
                        source = batch_sources.get(id(member))
                        dependencies.append(Dependency(
                            member, event, "contribution",
                            f"source actor {source} contributes to "
                            f"destination actor {destination}",
                        ))

    # Plane output and scheduler aggregate input are a direct handshake.
    for group, plane in zip(groups, planes, strict=True):
        for sent in by_component[plane]:
            if sent.event != "aggregate_send" or sent.slot is None:
                continue
            shard = int(detail_fields(sent.detail).get("shard", "-1"))
            if not 0 <= shard < len(group):
                continue
            receives = [
                event for event in by_component[group[shard]]
                if event.event == "aggregate_complete"
                and event.cycle == sent.cycle
                and event.slot == sent.slot
            ]
            if receives:
                dependencies.append(Dependency(
                    sent, receives[0], "aggregate_delivery",
                    f"aggregate delivered to {group[shard]} actor {sent.slot}",
                ))
    return dependencies


def parse_trace(path: Path) -> list[Event]:
    result = []
    with path.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            raw_slot = row["slot"]
            slot = None if raw_slot in ("", "-1") else int(raw_slot)
            result.append(
                Event(
                    cycle=int(row["cycle"]),
                    component=row["component"],
                    event=row["event"],
                    slot=slot,
                    detail=row["detail"],
                )
            )
    return result


def detail_fields(detail: str) -> dict[str, str]:
    return dict(
        field.split("=", 1)
        for field in detail.split(";")
        if "=" in field
    )


def choose_window(
    events: list[Event],
    scheduler: str,
    occurrence: int,
    slot: int | None,
    site: str | None,
    before: int,
    after: int,
) -> tuple[int, int, Event]:
    anchors = [
        event
        for event in events
        if event.component == scheduler
        and event.event == "aggregate_complete"
        and (slot is None or event.slot == slot)
        and (site is None or detail_fields(event.detail).get("site") == site)
    ]
    if not anchors:
        raise SystemExit(
            f"no matching aggregate_complete event for scheduler {scheduler!r}"
        )
    index = min(max(occurrence - 1, 0), len(anchors) - 1)
    anchor = anchors[index]
    return max(0, anchor.cycle - before), anchor.cycle + after, anchor


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def infer_plane(events: list[Event], scheduler: str) -> str:
    schedulers = sorted(
        {
            event.component
            for event in events
            if event.component.startswith("phi_")
            and event.component.removeprefix("phi_").isdigit()
        },
        key=lambda name: int(name.removeprefix("phi_")),
    )
    planes = sorted(
        {
            event.component
            for event in events
            if event.component.startswith("phi_")
            and event.component.endswith("_plane")
        }
    )
    if scheduler not in schedulers or not planes:
        raise SystemExit(f"cannot infer a reduction plane for {scheduler!r}")
    group_size = (len(schedulers) + len(planes) - 1) // len(planes)
    plane_index = min(schedulers.index(scheduler) // group_size, len(planes) - 1)
    return planes[plane_index]


def event_label(event: Event, inherited_detail: str = "") -> str:
    component = event.component.replace("phi_", "").replace("_plane", "")
    detail = event.detail.replace("source=", "s").replace("shard=", "h")
    fields = detail_fields(inherited_detail)
    fields.update(detail_fields(event.detail))
    site = fields.get("site")
    key = fields.get("key")
    reduction = "" if site is None else f" {site}"
    reduction += "" if key is None else f" k{key}"
    slot = "" if event.slot is None else f" a{event.slot}"
    if event.event == "batch_accept":
        return f"{component}:{detail}"
    if event.event == "aggregate_send":
        return f"{component}:{detail}{slot}{reduction}"
    if event.event.startswith("aggregate_"):
        return f"{event.event.removeprefix('aggregate_')}{slot}{reduction}"
    if event.event == "state_read":
        return f"R a{event.slot}"
    if event.event == "state_write":
        return f"W a{event.slot}"
    return event.event.replace("_", " ")


def selection_runs(events: list[Event], scheduler: str, start: int, end: int):
    samples = {
        event.cycle: event.detail
        for event in events
        if event.component == scheduler
        and event.event == "selection"
        and start <= event.cycle <= end
    }
    runs = []
    run_start = start
    status = samples.get(start, "unobserved")
    for cycle in range(start + 1, end + 2):
        next_status = samples.get(cycle, "unobserved") if cycle <= end else None
        if next_status != status:
            runs.append((run_start, cycle - 1, status))
            run_start = cycle
            status = next_status
    return runs


def render_svg(
    events: list[Event],
    scheduler: str,
    plane: str,
    start: int,
    end: int,
    anchor: Event,
    width: int,
    id_suffix: str = "",
) -> str:
    compact = width <= 360
    medium = width <= 560
    left = 92 if compact else 112 if medium else 154
    right = 8 if medium else 18
    top = 22 if compact else 50
    row_height = 48
    lanes = (
        [
            ("Batches", "batches"),
            ("Aggregate", "plane"),
            ("Intake", "intake"),
            ("Ready", "selection"),
            ("State RAM", "state"),
            ("Effects", "effects"),
        ]
        if compact
        else [
            ("Neighbor batches", "batches"),
            ("Reduction plane", "plane"),
            ("Scheduler intake", "intake"),
            ("Ready selection", "selection"),
            ("Actor state RAM", "state"),
            ("Effect retirement", "effects"),
        ]
    )
    height = top + row_height * len(lanes) + 54
    span = max(1, end - start + 1)
    plot_width = width - left - right

    def x(cycle: float) -> float:
        return left + (cycle - start) * plot_width / span

    rows = {key: top + index * row_height for index, (_, key) in enumerate(lanes)}
    title_id = f"phi-timeline-title{id_suffix}"
    desc_id = f"phi-timeline-desc{id_suffix}"
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width} {height}" role="img" '
        f'aria-labelledby="{title_id} {desc_id}" '
        'style="width:100%;height:auto;display:block">',
        f'<title id="{title_id}">Clock-aligned phi reduction timeline</title>',
        f'<desc id="{desc_id}">Neighbor batches are folded in the reduction plane, delivered to one scheduler, accepted as a completed reduction, followed by an actor state read, state write, and new effects.</desc>',
        '<style>',
        *SVG_THEME_CSS,
        f'text{{fill:{FOREGROUND};font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px}}',
        f'.muted{{fill:{MUTED_FOREGROUND}}}',
        f'.grid{{stroke:{BORDER};stroke-width:1}}',
        f'.axis{{stroke:{FOREGROUND};stroke-width:1}}',
        f'.mark{{stroke:{BACKGROUND};stroke-width:1}}',
        '</style>',
        f'<rect width="100%" height="100%" fill="{BACKGROUND}"/>',
    ]
    site = detail_fields(anchor.detail).get("site", "reduction")
    title = (
        f"{scheduler} ← {plane}: one {site} completion "
        f"around clock {anchor.cycle}"
    )
    if not compact:
        svg.append(
            f'<text x="0" y="17" style="font-family:inherit;font-size:14px;font-weight:500">{esc(title)}</text>'
        )
        svg.append(
            f'<text class="muted" x="0" y="35">Actual VPI handshakes; clocks {start}–{end}</text>'
        )

    tick_step = 5 if span <= 24 else 10 if medium else 5 if span <= 70 else 10
    for cycle in range(start, end + 1):
        if cycle == start or cycle == end or cycle % tick_step == 0:
            xpos = x(cycle)
            svg.append(
                f'<line class="grid" x1="{xpos:.2f}" y1="{top - 8}" '
                f'x2="{xpos:.2f}" y2="{height - 35}"/>'
            )
            svg.append(
                f'<text class="muted" x="{xpos:.2f}" y="{height - 17}" text-anchor="middle">{cycle}</text>'
            )
    svg.append(
        f'<text class="muted" x="{left + plot_width / 2:.2f}" y="{height - 2}" text-anchor="middle">clock</text>'
    )
    for label, key in lanes:
        ypos = rows[key]
        svg.append(
            f'<text x="0" y="{ypos + 25}" style="font-family:inherit">{esc(label)}</text>'
        )
        svg.append(
            f'<line class="axis" x1="{left}" y1="{ypos + 31}" x2="{width - right}" y2="{ypos + 31}"/>'
        )

    # Selection is continuous, so show it as phase-colored clock runs.
    for run_start, run_end, status in selection_runs(
        events, scheduler, start, end
    ):
        xpos = x(run_start)
        run_width = max(2.0, x(run_end + 1) - xpos)
        color = COLORS.get(status, MUTED)
        ypos = rows["selection"] + 10
        svg.append(
            f'<rect x="{xpos:.2f}" y="{ypos}" width="{run_width:.2f}" height="21" '
            f'fill="{color}" opacity="0.72" data-tooltip="{esc(status)}: clocks {run_start}–{run_end}"/>'
        )
        if run_width >= 62:
            label = status.replace("_", " ")
            svg.append(
                f'<text x="{xpos + 4:.2f}" y="{ypos + 15}" fill="{FOREGROUND}">{esc(label)}</text>'
            )

    visible = [event for event in events if start <= event.cycle <= end]
    aggregate_details = {
        (event.cycle, event.slot): event.detail
        for event in visible
        if event.component == scheduler
        and event.event in ("aggregate_receive", "aggregate_complete")
    }
    plotted = []
    for event in visible:
        lane = None
        if event.component == plane and event.event == "batch_accept":
            lane = "batches"
        elif event.component == plane and event.event == "aggregate_send":
            lane = "plane"
        elif event.component == scheduler and event.event.startswith("aggregate_"):
            lane = "intake"
        elif event.component == scheduler and event.event in (
            "state_read",
            "state_write",
        ):
            lane = "state"
        elif event.component == scheduler and event.event.startswith("effects_"):
            lane = "effects"
        if lane is not None:
            plotted.append((event, lane))

    offsets: dict[tuple[str, int], int] = {}
    for event, lane in plotted:
        key = (lane, event.cycle)
        ordinal = offsets.get(key, 0)
        offsets[key] = ordinal + 1
        xpos = x(event.cycle + 0.5)
        ypos = rows[lane] + 20 - min(ordinal, 2) * 8
        color = COLORS.get(event.event, FOREGROUND)
        inherited_detail = aggregate_details.get(
            (event.cycle, event.slot), ""
        )
        label = event_label(event, inherited_detail)
        tooltip = f"clock {event.cycle}: {event.component} {label}"
        if event.event in ("state_read", "state_write"):
            svg.append(
                f'<path d="M {xpos - 5:.2f} {ypos} L {xpos:.2f} {ypos - 6} L {xpos + 5:.2f} {ypos} L {xpos:.2f} {ypos + 6} Z" '
                f'fill="{color}" class="mark" data-tooltip="{esc(tooltip)}"/>'
            )
        else:
            svg.append(
                f'<circle cx="{xpos:.2f}" cy="{ypos}" r="5" fill="{color}" '
                f'class="mark" data-tooltip="{esc(tooltip)}"/>'
            )
        if ordinal == 0 and not medium:
            anchor_mode = "start" if xpos < width - 110 else "end"
            dx = 7 if anchor_mode == "start" else -7
            svg.append(
                f'<text x="{xpos + dx:.2f}" y="{rows[lane] + 9}" text-anchor="{anchor_mode}">{esc(label)}</text>'
            )

    anchor_x = x(anchor.cycle + 0.5)
    svg.append(
        f'<line x1="{anchor_x:.2f}" y1="{top - 8}" x2="{anchor_x:.2f}" '
        f'y2="{height - 35}" stroke="{FOREGROUND}" stroke-width="1" stroke-dasharray="3 3"/>'
    )
    svg.append('</svg>')
    return "\n".join(svg) + "\n"


def render(
    events: list[Event],
    scheduler: str,
    plane: str,
    start: int,
    end: int,
    anchor: Event,
    fragment: bool,
) -> str:
    if not fragment:
        return render_svg(
            events, scheduler, plane, start, end, anchor, width=960
        )
    medium_start = max(start, anchor.cycle - 14)
    medium_end = min(end, anchor.cycle + 14)
    compact_start = max(start, anchor.cycle - 8)
    compact_end = min(end, anchor.cycle + 8)
    return (
        '<div id="phi-reduction-clock-timeline">\n'
        '<style>\n'
        '#phi-reduction-clock-timeline .phi-medium,'
        '#phi-reduction-clock-timeline .phi-compact{display:none}\n'
        '@media(max-width:735px){'
        '#phi-reduction-clock-timeline .phi-wide{display:none}'
        '#phi-reduction-clock-timeline .phi-medium{display:block}}\n'
        '@media(max-width:519px){'
        '#phi-reduction-clock-timeline .phi-medium{display:none}'
        '#phi-reduction-clock-timeline .phi-compact{display:block}}\n'
        '</style>\n'
        '<div class="phi-wide">\n'
        + render_svg(
            events, scheduler, plane, start, end, anchor, 736, "-wide"
        )
        + '</div>\n<div class="phi-medium">\n'
        + render_svg(
            events,
            scheduler,
            plane,
            medium_start,
            medium_end,
            anchor,
            520,
            "-medium",
        )
        + '</div>\n<div class="phi-compact">\n'
        + render_svg(
            events,
            scheduler,
            plane,
            compact_start,
            compact_end,
            anchor,
            320,
            "-compact",
        )
        + '</div>\n</div>\n'
    )


def cross_shard_title(
    scheduler: str, slot: int | None, cycle: int
) -> str:
    actor = "" if slot is None else f" actor {slot}"
    return f"Phi shard causality: {scheduler}{actor} egress at clock {cycle}"


def event_tooltip(event: Event, extra: str = "") -> str:
    slot = "" if event.slot is None else f" actor {event.slot}"
    detail = "" if not event.detail else f" ({event.detail})"
    suffix = "" if not extra else f" — {extra}"
    return (
        f"clock {event.cycle}: {event.component} "
        f"{event.event.replace('_', ' ')}{slot}{detail}{suffix}"
    )


def cross_shard_svg(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    router_map: dict[str, str],
    dependencies: list[Dependency],
    start: int,
    end: int,
    focus_cycle: int,
    focus_scheduler: str,
    width: int,
    id_suffix: str,
) -> str:
    compact = width <= 400
    medium = width <= 760
    left = 86 if compact else 124 if medium else 164
    right = 8 if compact else 14
    top = 56 if compact else 62
    scheduler_height = 54 if compact else 62
    plane_height = 54 if compact else 62
    panel_gap = 18
    lane_y: dict[str, float] = {}
    cursor = top
    lane_specs: list[tuple[str, str, str]] = []
    for group_index, (group, plane) in enumerate(
        zip(groups, planes, strict=True)
    ):
        plane_letter = "X" if "_x_" in plane else "Z"
        for shard, scheduler in enumerate(group):
            lane_y[scheduler] = cursor
            label = f"φ{scheduler.removeprefix('phi_')} {plane_letter}{shard}"
            lane_specs.append((scheduler, label, "scheduler"))
            cursor += scheduler_height
        lane_y[plane] = cursor
        lane_specs.append((plane, f"{plane_letter} reduce", "plane"))
        cursor += plane_height
        if group_index + 1 < len(groups):
            cursor += panel_gap
    height = int(cursor + 42)
    span = max(1, end - start + 1)
    plot_width = width - left - right

    def x(cycle: float) -> float:
        return left + (cycle - start) * plot_width / span

    marker_id = f"phi-causal-arrow{id_suffix}"
    title_id = f"phi-causal-title{id_suffix}"
    desc_id = f"phi-causal-desc{id_suffix}"
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width} {height}" role="img" '
        f'aria-labelledby="{title_id} {desc_id}" '
        'style="width:100%;height:auto;display:block">',
        f'<title id="{title_id}">Cross-shard phi data dependencies</title>',
        f'<desc id="{desc_id}">Six phi scheduler rows and two reduction planes share one clock axis. Directed arrows connect aggregate delivery, actor state transactions, effect queues, router acceptance, reduction batches, and completed aggregates.</desc>',
        '<defs>',
        f'<marker id="{marker_id}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 8 4 L 0 8 Z" fill="context-stroke"/></marker>',
        '</defs>',
        '<style>',
        *SVG_THEME_CSS,
        f'text{{fill:{FOREGROUND};font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px}}',
        f'.muted{{fill:{MUTED_FOREGROUND}}}',
        f'.grid{{stroke:{BORDER};stroke-width:1}}',
        f'.baseline{{stroke:{BORDER};stroke-width:1}}',
        f'.dependency{{fill:none;stroke:{MUTED_FOREGROUND};stroke-width:1;opacity:.25}}',
        f'.dependency.focus{{stroke:{FOREGROUND};stroke-width:1.6;opacity:.82}}',
        '.contribution{stroke-dasharray:3 3}',
        f'.event{{stroke:{BACKGROUND};stroke-width:1}}',
        '</style>',
        f'<rect width="100%" height="100%" fill="{BACKGROUND}"/>',
    ]
    focus_writes = [
        event for event in events
        if event.component == focus_scheduler
        and event.event == "state_write"
        and event.cycle == focus_cycle
    ]
    focus_slot = focus_writes[0].slot if focus_writes else None
    visible_title = (
        f"φ{focus_scheduler.removeprefix('phi_')} actor "
        f"{focus_slot} egress · clock {focus_cycle}"
        if compact and focus_slot is not None else
        cross_shard_title(focus_scheduler, focus_slot, focus_cycle)
    )
    svg.append(
        f'<text id="{title_id}-visible" x="0" y="17" '
        f'style="font-family:inherit;font-size:14px;font-weight:500">'
        f'{esc(visible_title)}</text>'
    )
    if not compact:
        svg.append(
            f'<text class="muted" x="0" y="37">'
            f'Actual handshakes; arrows follow FIFO order and static reduction destinations</text>'
        )

    tick_step = 2 if span <= 18 else 5
    for cycle in range(start, end + 1):
        if cycle in (start, end, focus_cycle) or cycle % tick_step == 0:
            xpos = x(cycle + 0.5)
            svg.append(
                f'<line class="grid" x1="{xpos:.2f}" y1="{top - 9}" '
                f'x2="{xpos:.2f}" y2="{height - 30}"/>'
            )
            svg.append(
                f'<text class="muted" x="{xpos:.2f}" y="{height - 13}" '
                f'text-anchor="middle">{cycle}</text>'
            )
    focus_x = x(focus_cycle + 0.5)
    svg.append(
        f'<line x1="{focus_x:.2f}" y1="{top - 9}" x2="{focus_x:.2f}" '
        f'y2="{height - 30}" stroke="{FOREGROUND}" stroke-width="1" '
        f'stroke-dasharray="3 3"/>'
    )

    all_schedulers = [item for group in groups for item in group]
    for component, label, kind in lane_specs:
        ypos = lane_y[component]
        is_scheduler = kind == "scheduler"
        baseline = ypos + (27 if compact else 29)
        svg.append(
            f'<text x="0" y="{baseline + 4:.2f}" '
            f'style="font-family:inherit">{esc(label)}</text>'
        )
        if is_scheduler and not compact:
            svg.append(
                f'<text class="muted" x="{left - 7}" y="{ypos + 51:.2f}" '
                f'text-anchor="end">router</text>'
            )
        svg.append(
            f'<line class="baseline" x1="{left}" y1="{baseline:.2f}" '
            f'x2="{width - right}" y2="{baseline:.2f}"/>'
        )
        if is_scheduler:
            router_y = ypos + (44 if compact else 49)
            svg.append(
                f'<line class="baseline" x1="{left}" y1="{router_y:.2f}" '
                f'x2="{width - right}" y2="{router_y:.2f}"/>'
            )

    # Thin selection strips retain scheduler context without occupying another
    # row. They are not dependency endpoints.
    for scheduler in all_schedulers:
        ypos = lane_y[scheduler] + 3
        for run_start, run_end, status in selection_runs(
            events, scheduler, start, end
        ):
            xpos = x(run_start)
            run_width = max(1.5, x(run_end + 1) - xpos)
            svg.append(
                f'<rect x="{xpos:.2f}" y="{ypos:.2f}" '
                f'width="{run_width:.2f}" height="7" '
                f'fill="{COLORS.get(status, MUTED)}" opacity=".55" '
                f'data-tooltip="{esc(scheduler)} {esc(status)}: clocks '
                f'{run_start}–{run_end}"/>'
            )
        router = router_map[scheduler]
        wait_samples = {
            event.cycle: event.detail
            for event in events
            if event.component == router
            and event.event == "effects_wait"
            and start <= event.cycle <= end
        }
        if wait_samples:
            runs = []
            run_start = None
            last_cycle = None
            for cycle in sorted(wait_samples):
                if last_cycle is None or cycle != last_cycle + 1:
                    if run_start is not None:
                        runs.append((run_start, last_cycle))
                    run_start = cycle
                last_cycle = cycle
            if run_start is not None:
                runs.append((run_start, last_cycle))
            router_y = lane_y[scheduler] + (44 if compact else 49)
            for run_start, run_end in runs:
                svg.append(
                    f'<rect x="{x(run_start):.2f}" y="{router_y - 4:.2f}" '
                    f'width="{max(1.5, x(run_end + 1) - x(run_start)):.2f}" '
                    f'height="8" fill="{SERIES[4]}" opacity=".32" '
                    f'data-tooltip="{esc(router)} waits for downstream capacity: '
                    f'clocks {run_start}–{run_end}"/>'
                )

    event_positions: dict[int, tuple[float, float]] = {}
    visible = [event for event in events if start <= event.cycle <= end]
    scheduler_events = {
        "aggregate_complete": (0.18, "aggregate"),
        "state_read": (0.38, "read"),
        "state_write": (0.60, "write"),
        "effects_egress": (0.82, "egress"),
    }
    router_owner = {router: scheduler for scheduler, router in router_map.items()}
    for event in visible:
        if event.component in lane_y and event.component in all_schedulers:
            if event.event not in scheduler_events:
                continue
            x_offset, _shape = scheduler_events[event.event]
            event_positions[id(event)] = (
                x(event.cycle + x_offset), lane_y[event.component] +
                (27 if compact else 29),
            )
        elif event.component in router_owner and event.event in {
            "effects_accept", "reduction_send", "credit_return",
            "window_request", "window_grant", "window_release"
        }:
            scheduler = router_owner[event.component]
            event_positions[id(event)] = (
                x(event.cycle + {
                    "effects_accept": 0.66,
                    "reduction_send": 0.82,
                    "credit_return": 0.94,
                }.get(event.event, 0.82)), lane_y[scheduler] +
                (44 if compact else 49),
            )
        elif event.component in planes and event.event in {
            "batch_accept", "aggregate_send"
        }:
            event_positions[id(event)] = (
                x(event.cycle + (0.32 if event.event == "batch_accept" else 0.72)),
                lane_y[event.component] +
                (20 if event.event == "batch_accept" else 40),
            )

    # Highlight the finite path from the selected egress through the four
    # aggregate deliveries. Stop at delivery to avoid coloring the next round.
    focus_events = {
        id(event) for event in visible
        if event.component == focus_scheduler
        and event.event == "effects_egress"
        and event.cycle == focus_cycle
    }
    focused_edges: set[int] = set()
    backward_frontier = set(focus_events)
    for _depth in range(3):
        next_frontier = set()
        for index, dependency in enumerate(dependencies):
            if id(dependency.target) not in backward_frontier or \
                    dependency.kind not in {
                        "retirement", "actor_visit", "completion_to_read"
                    }:
                continue
            focused_edges.add(index)
            next_frontier.add(id(dependency.source))
        backward_frontier = next_frontier
    frontier = set(focus_events)
    for _depth in range(5):
        next_frontier = set()
        for index, dependency in enumerate(dependencies):
            if id(dependency.source) not in frontier:
                continue
            focused_edges.add(index)
            if dependency.kind != "aggregate_delivery":
                next_frontier.add(id(dependency.target))
        frontier = next_frontier
    focused_targets = {
        id(dependencies[index].target) for index in focused_edges
    }
    for index, dependency in enumerate(dependencies):
        if (
            dependency.kind == "router_capacity"
            and id(dependency.target) in focused_targets
        ):
            focused_edges.add(index)

    # Draw dependencies behind their event marks. Curves separate same-row
    # queues from cross-shard aggregate delivery.
    for index, dependency in enumerate(dependencies):
        source = event_positions.get(id(dependency.source))
        target = event_positions.get(id(dependency.target))
        if source is None or target is None:
            continue
        sx, sy = source
        tx, ty = target
        bend = -10 if sy == ty else (ty - sy) * 0.46
        middle = (sx + tx) / 2
        classes = ["dependency"]
        if dependency.kind == "contribution":
            classes.append("contribution")
        if index in focused_edges:
            classes.append("focus")
        svg.append(
            f'<path class="{" ".join(classes)}" '
            f'd="M {sx:.2f} {sy:.2f} C {middle:.2f} {sy + bend:.2f}, '
            f'{middle:.2f} {ty - bend:.2f}, {tx:.2f} {ty:.2f}" '
            f'marker-end="url(#{marker_id})" '
            f'data-tooltip="{esc(dependency.detail)}"/>'
        )
        if (
            index in focused_edges
            and dependency.kind in {
                "egress_fifo", "router_dispatch", "reduction_fifo",
                "router_to_plane"
            }
            and tx - sx > 28
            and not compact
        ):
            delta = dependency.target.cycle - dependency.source.cycle
            svg.append(
                f'<text x="{middle:.2f}" y="{min(sy, ty) - 5:.2f}" '
                f'text-anchor="middle">+{delta}</text>'
            )

    # Event marks are shape-coded so the diagram remains legible without
    # relying on color. The focus egress receives a neutral outer ring.
    causal_details = {
        id(dependency.target): dependency.detail
        for dependency in dependencies
        if dependency.kind in {"reduction_fifo", "router_to_plane"}
    }
    for event in visible:
        position = event_positions.get(id(event))
        if position is None:
            continue
        xpos, ypos = position
        color = COLORS.get(event.event, FOREGROUND)
        tooltip = event_tooltip(event, causal_details.get(id(event), ""))
        if event.event == "aggregate_complete":
            shape = (
                f'<path d="M {xpos:.2f} {ypos - 6:.2f} L {xpos + 6:.2f} '
                f'{ypos + 5:.2f} L {xpos - 6:.2f} {ypos + 5:.2f} Z"'
            )
        elif event.event in {"state_read", "batch_accept"}:
            shape = (
                f'<path d="M {xpos:.2f} {ypos - 6:.2f} L {xpos + 6:.2f} '
                f'{ypos:.2f} L {xpos:.2f} {ypos + 6:.2f} L {xpos - 6:.2f} '
                f'{ypos:.2f} Z"'
            )
        elif event.event in {"state_write", "window_grant"}:
            shape = (
                f'<rect x="{xpos - 5:.2f}" y="{ypos - 5:.2f}" '
                f'width="10" height="10"'
            )
        elif event.event == "aggregate_send":
            shape = (
                f'<path d="M {xpos - 6:.2f} {ypos - 5:.2f} L {xpos + 6:.2f} '
                f'{ypos - 5:.2f} L {xpos:.2f} {ypos + 6:.2f} Z"'
            )
        else:
            shape = f'<circle cx="{xpos:.2f}" cy="{ypos:.2f}" r="5"'
        fill = (
            BACKGROUND if event.event == "effects_accept" else color
        )
        stroke = color if event.event == "effects_accept" else BACKGROUND
        svg.append(
            f'{shape} fill="{fill}" stroke="{stroke}" stroke-width="1.5" '
            f'data-tooltip="{esc(tooltip)}"/>'
        )
        if id(event) in focus_events:
            svg.append(
                f'<circle cx="{xpos:.2f}" cy="{ypos:.2f}" r="9" fill="none" '
                f'stroke="{FOREGROUND}" stroke-width="1.5"/>'
            )

    # A compact in-plot legend keeps the dependency vocabulary visible.
    legend_y = top - (13 if compact else 15)
    legend = (
        [("△", "done"), ("◇", "read / batch"), ("□", "write"),
         ("●", "egress"), ("○", "router")]
        if not compact else
        [("△", "done"), ("◇", "read"), ("●", "out"), ("○", "route")]
    )
    legend_x = left
    for symbol, label in legend:
        svg.append(
            f'<text x="{legend_x}" y="{legend_y}">{symbol} {esc(label)}</text>'
        )
        legend_x += 76 if not compact else 55
    svg.append('</svg>')
    return "\n".join(svg) + "\n"


def render_cross_shard(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    router_map: dict[str, str],
    dependencies: list[Dependency],
    focus_cycle: int,
    focus_scheduler: str,
    before: int,
    after: int,
    fragment: bool,
) -> str:
    start = max(0, focus_cycle - before)
    end = focus_cycle + after
    if not fragment:
        return cross_shard_svg(
            events, groups, planes, router_map, dependencies,
            start, end, focus_cycle, focus_scheduler, 1200, "-file"
        )
    medium_start = max(0, focus_cycle - min(before, 5))
    medium_end = focus_cycle + min(after, 16)
    compact_start = max(0, focus_cycle - min(before, 3))
    compact_end = focus_cycle + min(after, 10)
    return (
        '<div id="phi-cross-shard-causality">\n'
        '<style>\n'
        '#phi-cross-shard-causality .phi-medium,'
        '#phi-cross-shard-causality .phi-compact{display:none}\n'
        '@media(max-width:759px){'
        '#phi-cross-shard-causality .phi-wide{display:none}'
        '#phi-cross-shard-causality .phi-medium{display:block}}\n'
        '@media(max-width:419px){'
        '#phi-cross-shard-causality .phi-medium{display:none}'
        '#phi-cross-shard-causality .phi-compact{display:block}}\n'
        '</style>\n'
        '<div class="phi-wide">\n'
        + cross_shard_svg(
            events, groups, planes, router_map, dependencies,
            start, end, focus_cycle, focus_scheduler, 1024, "-wide"
        )
        + '</div>\n<div class="phi-medium">\n'
        + cross_shard_svg(
            events, groups, planes, router_map, dependencies,
            medium_start, medium_end, focus_cycle, focus_scheduler,
            736, "-medium"
        )
        + '</div>\n<div class="phi-compact">\n'
        + cross_shard_svg(
            events, groups, planes, router_map, dependencies,
            compact_start, compact_end, focus_cycle, focus_scheduler,
            360, "-compact"
        )
        + '</div>\n</div>\n'
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--scheduler", default="phi_0")
    parser.add_argument("--plane")
    parser.add_argument("--occurrence", type=int, default=100)
    parser.add_argument("--slot", type=int)
    parser.add_argument(
        "--site", choices=("gathering", "comparing", "flipping")
    )
    parser.add_argument("--before", type=int, default=32)
    parser.add_argument("--after", type=int, default=18)
    parser.add_argument(
        "--focus-cycle",
        type=int,
        help="center an all-shards view on this clock",
    )
    parser.add_argument(
        "--all-shards",
        action="store_true",
        help="render every phi shard and both reduction planes",
    )
    parser.add_argument(
        "--dependencies",
        action="store_true",
        help="draw FIFO and reduction data-dependency arrows",
    )
    parser.add_argument(
        "--topology",
        type=Path,
        help="generated DSLX topology containing reduction destinations",
    )
    parser.add_argument(
        "--fragment",
        action="store_true",
        help="wrap the SVG in an embeddable HTML fragment",
    )
    args = parser.parse_args()
    events = parse_trace(args.trace)
    if args.all_shards:
        groups, planes = phi_groups(events)
        schedulers = [item for group in groups for item in group]
        router_map = phi_router_map(events, schedulers)
        topology = args.topology
        if topology is None:
            candidate = args.trace.parent / "phi_decoder_profile_topology.x"
            topology = candidate if candidate.exists() else None
        destination_tables, source_fragment_planes = \
            parse_reduction_topology(topology)
        dependencies = dependency_graph(
            events, groups, planes, router_map, destination_tables,
            source_fragment_planes,
        ) if args.dependencies else []
        focus_cycle = args.focus_cycle
        if focus_cycle is None:
            _, _, anchor = choose_window(
                events,
                args.scheduler,
                args.occurrence,
                args.slot,
                args.site,
                args.before,
                args.after,
            )
            later_egresses = [
                event.cycle
                for event in events
                if event.component == args.scheduler
                and event.event == "effects_egress"
                and event.cycle >= anchor.cycle
            ]
            focus_cycle = (
                later_egresses[0] if later_egresses else anchor.cycle
            )
        args.output.write_text(
            render_cross_shard(
                events,
                groups,
                planes,
                router_map,
                dependencies,
                focus_cycle,
                args.scheduler,
                args.before,
                args.after,
                args.fragment,
            ),
            encoding="utf-8",
        )
        return
    plane = args.plane or infer_plane(events, args.scheduler)
    start, end, anchor = choose_window(
        events,
        args.scheduler,
        args.occurrence,
        args.slot,
        args.site,
        args.before,
        args.after,
    )
    args.output.write_text(
        render(
            events,
            args.scheduler,
            plane,
            start,
            end,
            anchor,
            args.fragment,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
