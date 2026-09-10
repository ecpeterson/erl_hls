#!/usr/bin/env python3
"""Render a standalone cross-shard phi profile SVG from a VPI trace."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
import csv
from dataclasses import dataclass
import html
from itertools import groupby
from pathlib import Path
import re


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
MUTED_FOREGROUND = "var(--muted-foreground, var(--phi-muted-foreground))"
BORDER = "var(--border, var(--phi-border))"
SERIES = {
    index: f"var(--viz-series-{index}, var(--phi-series-{index}))"
    for index in range(1, 7)
}

# The private variables make files portable to browsers and editor previews;
# Codex's unprefixed variables still take precedence when the SVG is embedded.
THEME_CSS = [
    "svg{color-scheme:light dark;"
    "--phi-background:#ffffff;--phi-foreground:#1f2328;"
    "--phi-muted:#afb8c1;--phi-muted-foreground:#59636e;"
    "--phi-border:#d0d7de;"
    "--phi-series-1:#0969da;--phi-series-2:#1a7f37;"
    "--phi-series-3:#8250df;--phi-series-4:#cf222e;"
    "--phi-series-5:#bf8700;--phi-series-6:#bc4c00}",
    "@media(prefers-color-scheme:dark){svg{"
    "--phi-background:#0d1117;--phi-foreground:#f0f6fc;"
    "--phi-muted:#6e7681;--phi-muted-foreground:#9198a1;"
    "--phi-border:#3d444d;"
    "--phi-series-1:#58a6ff;--phi-series-2:#3fb950;"
    "--phi-series-3:#bc8cff;--phi-series-4:#ff7b72;"
    "--phi-series-5:#d29922;--phi-series-6:#ffa657}}",
]

COLORS = {
    "aggregate_receive": SERIES[4],
    "state_read": SERIES[5],
    "state_write": SERIES[5],
    "effects_egress": SERIES[2],
    "effects_accept": SERIES[2],
    "reduction_send": SERIES[3],
    "batch_accept": SERIES[1],
    "aggregate_send": SERIES[4],
}


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def fields(detail: str) -> dict[str, str]:
    return dict(
        field.split("=", 1)
        for field in detail.split(";")
        if "=" in field
    )


def read_trace(path: Path) -> list[Event]:
    events = []
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        expected = {"cycle", "component", "event", "slot", "detail"}
        if reader.fieldnames is None or set(reader.fieldnames) != expected:
            raise SystemExit(
                "trace must have columns cycle,component,event,slot,detail"
            )
        for row in reader:
            raw_slot = row["slot"]
            events.append(Event(
                cycle=int(row["cycle"]),
                component=row["component"],
                event=row["event"],
                slot=None if raw_slot in ("", "-1") else int(raw_slot),
                detail=row["detail"],
            ))
    if any(left.cycle > right.cycle for left, right in zip(events, events[1:])):
        raise SystemExit("trace events are not ordered by clock")
    return events


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


def discover_components(
    events: list[Event],
) -> tuple[list[list[str]], list[str], dict[str, str]]:
    schedulers = numbered_components(events, "phi_")
    planes = sorted({
        event.component
        for event in events
        if event.component in {"phi_x_plane", "phi_z_plane"}
    })
    if len(schedulers) < 2 or len(schedulers) % 2 != 0:
        raise SystemExit(
            "expected an equal nonempty X/Z pair of phi scheduler groups, "
            f"found {len(schedulers)} schedulers: "
            f"{', '.join(schedulers) or 'none'}"
        )
    if planes != ["phi_x_plane", "phi_z_plane"]:
        raise SystemExit(
            "expected phi_x_plane and phi_z_plane in the trace"
        )
    routers = numbered_components(events, "window_router_")
    if len(routers) < len(schedulers):
        raise SystemExit(
            f"expected at least {len(schedulers)} effect-window routers, "
            f"found {len(routers)}"
        )
    # The topology emits non-phi schedulers first, then equally sharded X and Z
    # phi groups. The dedicated tracer sees only those final phi routers, while
    # older traces can also contain the preceding routers.
    router_map = dict(zip(
        schedulers,
        routers[-len(schedulers):],
        strict=True,
    ))
    shard_count = len(schedulers) // 2
    return [
        schedulers[:shard_count],
        schedulers[shard_count:],
    ], planes, router_map


def fragment_destination_table(source: str, plane: str) -> dict[int, list[int]]:
    marker = f"proc Phi_{plane}ReductionPlane"
    if marker not in source:
        raise SystemExit(
            f"topology has no source-fragment reduction plane for phi {plane}"
        )
    match = re.search(
        rf"proc Phi_{plane}ReductionPlane\s*\{{.*?"
        rf"let pop_sources = match output_slot \{{(?P<body>.*?)\n\s*_ =>",
        source,
        re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"cannot parse phi {plane} pop_sources table")
    sources_by_destination = {
        int(row.group(1)): [
            int(value) for value in re.findall(r"u32:(\d+)", row.group(2))
        ]
        for row in re.finditer(
            r"u32:(\d+)\s*=>\s*\[([^]]+)\]", match.group("body")
        )
    }
    if not sources_by_destination:
        raise SystemExit(f"empty phi {plane} pop_sources table")
    actor_count = len(sources_by_destination)
    expected = set(range(actor_count))
    if set(sources_by_destination) != expected:
        raise SystemExit(f"sparse phi {plane} pop_sources table")
    populations = {len(row) for row in sources_by_destination.values()}
    if len(populations) != 1:
        raise SystemExit(f"ragged phi {plane} pop_sources table")
    population = populations.pop()
    destinations: dict[int, list[int | None]] = {
        source_actor: [None] * population
        for source_actor in range(actor_count)
    }
    for destination, row in sources_by_destination.items():
        for lane, source_actor in enumerate(row):
            if source_actor not in expected:
                raise SystemExit(f"invalid phi {plane} source {source_actor}")
            if destinations[source_actor][lane] is not None:
                raise SystemExit(f"non-bijective phi {plane} lane {lane}")
            destinations[source_actor][lane] = destination
    if any(value is None for row in destinations.values() for value in row):
        raise SystemExit(f"incomplete phi {plane} destination table")
    return {
        source_actor: [int(value) for value in row]
        for source_actor, row in destinations.items()
    }


def read_destination_tables(path: Path) -> dict[str, dict[int, list[int]]]:
    if not path.exists():
        raise SystemExit(f"topology file does not exist: {path}")
    source = path.read_text(encoding="utf-8")
    return {
        plane: fragment_destination_table(source, plane)
        for plane in ("x", "z")
    }


def pair_before(
    sources: list[tuple[Event, int | None]],
    target: Event,
    source_actor: int | None,
) -> tuple[Event, int | None] | None:
    candidates = [
        (index, item)
        for index, item in enumerate(sources)
        if item[0].cycle <= target.cycle
        and (source_actor is None or item[1] == source_actor)
    ]
    if not candidates:
        return None
    index, item = candidates[-1]
    sources.pop(index)
    return item


def aggregate_identity(event: Event) -> tuple[int, int, str, int]:
    metadata = fields(event.detail)
    missing = {"site", "key", "valid", "failed"} - metadata.keys()
    if event.slot is None or missing:
        raise SystemExit(
            f"aggregate event lacks slot/metadata {sorted(missing)}: {event}"
        )
    if metadata["site"] not in {"gathering", "comparing", "flipping"}:
        raise SystemExit(f"aggregate has an invalid site: {event}")
    if metadata["valid"] != "1" or metadata["failed"] != "0":
        raise SystemExit(f"reduction plane emitted an invalid aggregate: {event}")
    try:
        key = int(metadata["key"])
    except ValueError as error:
        raise SystemExit(f"aggregate has a nonnumeric key: {event}") from error
    return event.cycle, event.slot, metadata["site"], key


def validate_aggregate_transactions(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    pipeline_stages: int,
) -> dict[str, int]:
    """Checks stable transport/retirement signals around each aggregate.

    The clean aggregate-only service no longer exposes the old implementation
    locals named aggregate_accept/complete/error.  We therefore do not invent
    semantic equivalents for those signals: the profile checks every public
    aggregate payload, its exact plane-to-scheduler channel delivery, and the
    state transaction it makes runnable.  The enclosing self-checking bench
    remains responsible for detecting a callback-level rejection.
    """
    by_component: dict[str, list[Event]] = defaultdict(list)
    for event in events:
        by_component[event.component].append(event)

    sends = 0
    receives = 0
    visit_starts = 0
    visit_retires = 0
    trailing_receptacles = 0
    trailing_visits = 0
    for group, plane in zip(groups, planes, strict=True):
        all_plane_sends = [
            event for event in by_component[plane]
            if event.event == "aggregate_send"
        ]
        assigned_plane_sends = 0
        for shard, scheduler in enumerate(group):
            plane_sends = [
                event for event in by_component[plane]
                if event.event == "aggregate_send"
                and fields(event.detail).get("shard") == str(shard)
            ]
            scheduler_receives = [
                event for event in by_component[scheduler]
                if event.event == "aggregate_receive"
            ]
            if len(plane_sends) != len(scheduler_receives):
                raise SystemExit(
                    f"{plane} shard {shard} sent {len(plane_sends)} "
                    f"aggregates, but {scheduler} received "
                    f"{len(scheduler_receives)}"
                )
            for sent, received in zip(
                plane_sends, scheduler_receives, strict=True
            ):
                if aggregate_identity(sent) != aggregate_identity(received):
                    raise SystemExit(
                        "aggregate changed during direct plane-to-scheduler "
                        f"delivery: {sent} -> {received}"
                    )
            sends += len(plane_sends)
            assigned_plane_sends += len(plane_sends)
            receives += len(scheduler_receives)

            pending_receives: dict[int, deque[Event]] = defaultdict(deque)
            pending_reads: dict[int, deque[Event]] = defaultdict(deque)
            scheduler_events = by_component[scheduler]
            for _cycle, grouped in groupby(
                scheduler_events, key=lambda event: event.cycle
            ):
                cycle_events = [
                    event for event in grouped if event.slot is not None
                ]
                for event in cycle_events:
                    if event.event == "aggregate_receive":
                        if pending_receives[event.slot]:
                            raise SystemExit(
                                f"{scheduler} accepted a second aggregate "
                                f"for pending actor slot {event.slot}"
                            )
                        pending_receives[event.slot].append(event)
                for event in cycle_events:
                    if (event.event == "state_read" and
                            pending_receives[event.slot]):
                        received = pending_receives[event.slot].popleft()
                        pending_reads[event.slot].append(event)
                        visit_starts += 1
                        if received.cycle > event.cycle:
                            raise SystemExit(
                                f"aggregate visit precedes receipt: {event}"
                            )
                for event in cycle_events:
                    if (event.event == "state_write" and
                            pending_reads[event.slot]):
                        pending_reads[event.slot].popleft()
                        visit_retires += 1
            scheduler_trailing_receptacles = sum(
                len(queue) for queue in pending_receives.values()
            )
            scheduler_trailing_visits = sum(
                len(queue) for queue in pending_reads.values()
            )
            if scheduler_trailing_visits > pipeline_stages:
                raise SystemExit(
                    f"{scheduler} has {scheduler_trailing_visits} trailing "
                    f"aggregate visits, exceeding its {pipeline_stages}-stage "
                    "executor pipeline"
                )
            trailing_receptacles += scheduler_trailing_receptacles
            trailing_visits += scheduler_trailing_visits
        if assigned_plane_sends != len(all_plane_sends):
            raise SystemExit(
                f"{plane} has an aggregate assigned to no known shard"
            )

    if visit_starts + trailing_receptacles != receives:
        raise SystemExit("aggregate receive/actor-visit accounting mismatch")
    if visit_retires + trailing_visits != visit_starts:
        raise SystemExit("aggregate actor-visit retirement accounting mismatch")
    return {
        "aggregate_sends": sends,
        "aggregate_receives": receives,
        "aggregate_visit_starts": visit_starts,
        "aggregate_visit_retires": visit_retires,
        "aggregate_payload_errors": 0,
        "trailing_aggregate_receptacles": trailing_receptacles,
        "trailing_aggregate_visits": trailing_visits,
    }


def build_dependencies(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    router_map: dict[str, str],
    tables: dict[str, dict[int, list[int]]],
) -> list[Dependency]:
    dependencies: list[Dependency] = []
    by_component: dict[str, list[Event]] = defaultdict(list)
    for event in events:
        by_component[event.component].append(event)

    # Completed aggregates enable an actor visit. Reads and writes are paired
    # by slot, so several overlapped RAM transactions remain distinguishable.
    for scheduler in [item for group in groups for item in group]:
        receives: dict[int, deque[Event]] = defaultdict(deque)
        reads: dict[int, deque[Event]] = defaultdict(deque)
        for event in by_component[scheduler]:
            if event.slot is None:
                continue
            if event.event == "aggregate_receive":
                receives[event.slot].append(event)
            elif event.event == "state_read":
                if receives[event.slot]:
                    received = receives[event.slot].popleft()
                    dependencies.append(Dependency(
                        received, event, "aggregate_to_read",
                        f"aggregate makes actor {event.slot} runnable",
                    ))
                reads[event.slot].append(event)
            elif event.event == "state_write" and reads[event.slot]:
                read = reads[event.slot].popleft()
                dependencies.append(Dependency(
                    read, event, "actor_visit",
                    f"actor {event.slot} state transaction",
                ))

    # The state write and effect enqueue retire one actor transaction. Pair
    # the scheduler and router FIFOs in their observed, order-preserving order.
    scheduler_geometry = {
        scheduler: (len(group), shard)
        for group in groups
        for shard, scheduler in enumerate(group)
    }
    accepted_by_router: dict[str, list[tuple[Event, int | None]]] = {}
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
        if len(egresses) != len(accepts):
            raise SystemExit(
                f"{scheduler} emitted {len(egresses)} effect bundles, but "
                f"{router} accepted {len(accepts)}"
            )
        accepted = []
        for egress, router_accept in zip(egresses, accepts, strict=True):
            if egress.cycle != router_accept.cycle:
                raise SystemExit(
                    "direct scheduler-to-router handshake changed clocks: "
                    f"{egress} -> {router_accept}"
                )
            write = writes_by_cycle.get(egress.cycle)
            if write is not None:
                dependencies.append(Dependency(
                    write, egress, "retirement",
                    f"actor {write.slot} retires its effect bundle",
                ))
            dependencies.append(Dependency(
                egress, router_accept, "egress_fifo",
                "scheduler egress FIFO preserves bundle order",
            ))
            if write is None or write.slot is None:
                source_actor = None
            else:
                shard_count, shard = scheduler_geometry[scheduler]
                source_actor = write.slot * shard_count + shard
            accepted.append((router_accept, source_actor))
        accepted_by_router[router] = accepted

    # Each source-fragment batch travels router -> reduction plane. The batch
    # slot is its global source actor; source= in the detail is its shard.
    batch_source: dict[int, int] = {}
    for group, plane in zip(groups, planes, strict=True):
        batches_by_shard: dict[int, deque[Event]] = defaultdict(deque)
        for event in by_component[plane]:
            if event.event != "batch_accept" or event.slot is None:
                continue
            batch_source[id(event)] = event.slot
            try:
                shard = int(fields(event.detail)["source"])
            except (KeyError, ValueError) as error:
                raise SystemExit(
                    f"batch_accept lacks a numeric source shard: {event}"
                ) from error
            if not 0 <= shard < len(group):
                raise SystemExit(
                    f"batch_accept has invalid source shard {shard}: {event}"
                )
            batches_by_shard[shard].append(event)
        for shard, scheduler in enumerate(group):
            router = router_map[scheduler]
            unmatched_accepts = list(accepted_by_router[router])
            sends = [
                event for event in by_component[router]
                if event.event == "reduction_send"
            ]
            sent_sources: list[tuple[Event, int | None]] = []
            for sent in sends:
                source_actor = sent.slot
                matched = pair_before(unmatched_accepts, sent, source_actor)
                if matched is None:
                    raise SystemExit(
                        f"{router} reduction send has no accepted effect "
                        f"bundle: {sent}"
                    )
                accepted, inferred_source = matched
                dependencies.append(Dependency(
                    accepted, sent, "router_dispatch",
                    "router dispatches the accepted reduction bundle",
                ))
                sent_sources.append((
                    sent,
                    inferred_source if source_actor is None else source_actor,
                ))
            batches = list(batches_by_shard[shard])
            if len(sent_sources) != len(batches):
                raise SystemExit(
                    f"{router} sent {len(sent_sources)} reduction batches, "
                    f"but {plane} source {shard} accepted {len(batches)}"
                )
            for (sent, inferred_source), batch in zip(
                sent_sources, batches, strict=True
            ):
                source_actor = batch_source[id(batch)]
                if (sent.slot != batch.slot or sent.cycle > batch.cycle or
                        inferred_source not in (None, source_actor)):
                    raise SystemExit(
                        "reduction batch changed identity/order between "
                        f"router and plane: {sent} -> {batch}"
                    )
                dependencies.append(Dependency(
                    sent, batch, "reduction_fifo",
                    f"source actor {source_actor} batch enters {plane}",
                ))

        # Dashed edges show which four accepted source fragments form each
        # aggregate. This relation is inferred from generated pop_sources.
        table = tables["x" if plane == "phi_x_plane" else "z"]
        population = len(next(iter(table.values())))
        contributions: dict[tuple[int, int], deque[Event]] = defaultdict(deque)
        for event in by_component[plane]:
            if event.event == "batch_accept" and id(event) in batch_source:
                source_actor = batch_source[id(event)]
                for lane, destination in enumerate(table[source_actor]):
                    contributions[(destination, lane)].append(event)
            elif event.event == "aggregate_send" and event.slot is not None:
                try:
                    shard = int(fields(event.detail)["shard"])
                except (KeyError, ValueError):
                    continue
                destination = event.slot * len(group) + shard
                missing = [
                    lane for lane in range(population)
                    if not contributions[(destination, lane)]
                ]
                if missing:
                    raise SystemExit(
                        f"{event} lacks contribution lanes {missing}"
                    )
                members = [
                    contributions[(destination, lane)].popleft()
                    for lane in range(population)
                ]
                for member in members:
                    source_actor = batch_source[id(member)]
                    dependencies.append(Dependency(
                        member, event, "contribution",
                        f"actor {source_actor} contributes to actor "
                        f"{destination}",
                    ))

        batch_count = sum(
            1 for event in by_component[plane]
            if event.event == "batch_accept"
        )
        aggregate_count = sum(
            1 for event in by_component[plane]
            if event.event == "aggregate_send"
        )
        actor_count = len(table)
        trailing_batches = batch_count - aggregate_count
        # Each source/lane queue has current + lookahead storage, and the
        # plane may hold one already assembled aggregate at shutdown.
        max_trailing_batches = 2 * actor_count + 1
        if not 0 <= trailing_batches <= max_trailing_batches:
            raise SystemExit(
                f"{plane} has {trailing_batches} trailing batches; the "
                f"two-entry fragment queues plus held output allow at most "
                f"{max_trailing_batches}"
            )

    # Plane output and scheduler aggregate input are the same direct channel
    # handshake and therefore share a clock in the trace.
    for group, plane in zip(groups, planes, strict=True):
        for sent in by_component[plane]:
            if sent.event != "aggregate_send" or sent.slot is None:
                continue
            try:
                shard = int(fields(sent.detail)["shard"])
            except (KeyError, ValueError):
                continue
            if not 0 <= shard < len(group):
                continue
            received = next((
                event for event in by_component[group[shard]]
                if event.event == "aggregate_receive"
                and event.cycle == sent.cycle
                and event.slot == sent.slot
            ), None)
            if received is not None:
                dependencies.append(Dependency(
                    sent, received, "aggregate_delivery",
                    f"aggregate delivered to {group[shard]} actor {sent.slot}",
                ))
    return dependencies


def choose_focus(
    events: list[Event],
    scheduler: str,
    occurrence: int,
    focus_cycle: int | None,
) -> int:
    if focus_cycle is not None:
        return focus_cycle
    anchors = [
        event for event in events
        if event.component == scheduler
        and event.event == "aggregate_receive"
        and fields(event.detail).get("site") == "gathering"
    ]
    if not anchors:
        anchors = [
            event for event in events
            if event.component == scheduler
            and event.event == "aggregate_receive"
        ]
    if not anchors:
        raise SystemExit(f"no aggregate_receive events for {scheduler}")
    index = min(max(occurrence - 1, 0), len(anchors) - 1)
    anchor = anchors[index]
    egresses = [
        event.cycle for event in events
        if event.component == scheduler
        and event.event == "effects_egress"
        and event.cycle >= anchor.cycle
    ]
    return egresses[0] if egresses else anchor.cycle


def event_tooltip(event: Event) -> str:
    slot = "" if event.slot is None else f" actor {event.slot}"
    detail = "" if not event.detail else f" ({event.detail})"
    return (
        f"clock {event.cycle}: {event.component} "
        f"{event.event.replace('_', ' ')}{slot}{detail}"
    )


def render(
    events: list[Event],
    groups: list[list[str]],
    planes: list[str],
    router_map: dict[str, str],
    dependencies: list[Dependency],
    focus_scheduler: str,
    focus_cycle: int,
    before: int,
    after: int,
) -> str:
    start = max(0, focus_cycle - before)
    end = focus_cycle + after
    width = 1200
    left = 170
    right = 18
    top = 64
    scheduler_height = 62
    plane_height = 62
    panel_gap = 18
    lane_y: dict[str, float] = {}
    lane_specs: list[tuple[str, str, str]] = []
    cursor = top
    for group, plane in zip(groups, planes, strict=True):
        letter = "X" if plane == "phi_x_plane" else "Z"
        for shard, scheduler in enumerate(group):
            lane_y[scheduler] = cursor
            lane_specs.append((
                scheduler,
                f"φ{scheduler.removeprefix('phi_')} {letter}{shard}",
                "scheduler",
            ))
            cursor += scheduler_height
        lane_y[plane] = cursor
        lane_specs.append((plane, f"{letter} reduction plane", "plane"))
        cursor += plane_height + panel_gap
    height = int(cursor + 28)
    span = max(1, end - start + 1)
    plot_width = width - left - right
    scheduler_count = sum(len(group) for group in groups)

    def x(cycle: float) -> float:
        return left + (cycle - start) * plot_width / span

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} '
        f'{height}" role="img" aria-labelledby="title description" '
        'style="width:100%;height:auto;display:block">',
        '<title id="title">D3 phi cross-shard causal timeline</title>',
        f'<desc id="description">{scheduler_count} phi schedulers and two '
        'source-fragment reduction planes share a clock axis. Solid arrows '
        'are observed FIFO or state dependencies; dashed arrows are inferred '
        'contributions.</desc>',
        '<defs><marker id="arrow" viewBox="0 0 8 8" refX="7" refY="4" '
        'markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
        '<path d="M 0 0 L 8 4 L 0 8 Z" fill="context-stroke"/>'
        '</marker></defs>',
        '<style>',
        *THEME_CSS,
        f'text{{fill:{FOREGROUND};font-family:ui-monospace,SFMono-Regular,'
        'Menlo,monospace;font-size:11px}}',
        f'.muted{{fill:{MUTED_FOREGROUND}}}',
        f'.grid,.baseline{{stroke:{BORDER};stroke-width:1}}',
        f'.dependency{{fill:none;stroke:{MUTED_FOREGROUND};stroke-width:1;'
        'opacity:.24}}',
        f'.dependency.focus{{stroke:{FOREGROUND};stroke-width:1.8;opacity:.9}}',
        '.contribution{stroke-dasharray:3 3}',
        f'.event{{stroke:{BACKGROUND};stroke-width:1.5}}',
        '</style>',
        f'<rect width="100%" height="100%" fill="{BACKGROUND}"/>',
        f'<text x="0" y="18" style="font-size:14px;font-weight:500">'
        f'D3 phi causal overlap: {esc(focus_scheduler)} egress at clock '
        f'{focus_cycle}</text>',
        '<text class="muted" x="0" y="39">Solid = observed ordering; '
        'dashed = generated source-to-destination contribution</text>',
    ]
    tick_step = 2 if span <= 20 else 5
    for cycle in range(start, end + 1):
        if cycle in (start, end, focus_cycle) or cycle % tick_step == 0:
            xpos = x(cycle + 0.5)
            svg.extend([
                f'<line class="grid" x1="{xpos:.2f}" y1="{top - 9}" '
                f'x2="{xpos:.2f}" y2="{height - 30}"/>',
                f'<text class="muted" x="{xpos:.2f}" y="{height - 12}" '
                f'text-anchor="middle">{cycle}</text>',
            ])
    focus_x = x(focus_cycle + 0.5)
    svg.append(
        f'<line x1="{focus_x:.2f}" y1="{top - 9}" x2="{focus_x:.2f}" '
        f'y2="{height - 30}" stroke="{FOREGROUND}" stroke-width="1" '
        'stroke-dasharray="3 3"/>'
    )
    for component, label, kind in lane_specs:
        ypos = lane_y[component]
        baseline = ypos + 27
        svg.extend([
            f'<text x="0" y="{baseline + 4:.2f}">{esc(label)}</text>',
            f'<line class="baseline" x1="{left}" y1="{baseline:.2f}" '
            f'x2="{width - right}" y2="{baseline:.2f}"/>',
        ])
        if kind == "scheduler":
            router_y = ypos + 49
            svg.extend([
                f'<text class="muted" x="{left - 8}" y="{router_y + 4:.2f}" '
                'text-anchor="end">egress router</text>',
                f'<line class="baseline" x1="{left}" y1="{router_y:.2f}" '
                f'x2="{width - right}" y2="{router_y:.2f}"/>',
            ])

    all_schedulers = [item for group in groups for item in group]
    router_owner = {router: owner for owner, router in router_map.items()}
    event_positions: dict[int, tuple[float, float]] = {}
    visible = [event for event in events if start <= event.cycle <= end]
    offsets = {
        "aggregate_receive": .15,
        "state_read": .36,
        "state_write": .59,
        "effects_egress": .80,
        "effects_accept": .35,
        "reduction_send": .76,
        "batch_accept": .30,
        "aggregate_send": .72,
    }
    for event in visible:
        if event.component in all_schedulers and event.event in {
            "aggregate_receive", "state_read", "state_write", "effects_egress"
        }:
            event_positions[id(event)] = (
                x(event.cycle + offsets[event.event]),
                lane_y[event.component] + 27,
            )
        elif event.component in router_owner and event.event in {
            "effects_accept", "reduction_send"
        }:
            owner = router_owner[event.component]
            event_positions[id(event)] = (
                x(event.cycle + offsets[event.event]),
                lane_y[owner] + 49,
            )
        elif event.component in planes and event.event in {
            "batch_accept", "aggregate_send"
        }:
            event_positions[id(event)] = (
                x(event.cycle + offsets[event.event]),
                lane_y[event.component]
                + (19 if event.event == "batch_accept" else 39),
            )

    focus_events = {
        id(event) for event in visible
        if event.component == focus_scheduler
        and event.event == "effects_egress"
        and event.cycle == focus_cycle
    }
    focused_edges: set[int] = set()
    frontier = set(focus_events)
    # Include the actor transaction which generated the selected egress.
    for _depth in range(3):
        next_frontier = set()
        for index, dependency in enumerate(dependencies):
            if id(dependency.target) in frontier and dependency.kind in {
                "retirement", "actor_visit", "aggregate_to_read"
            }:
                focused_edges.add(index)
                next_frontier.add(id(dependency.source))
        frontier = next_frontier
    # Follow dispatch, four contributions, delivery, and the next actor visit.
    frontier = set(focus_events)
    for _depth in range(7):
        next_frontier = set()
        for index, dependency in enumerate(dependencies):
            if id(dependency.source) in frontier:
                focused_edges.add(index)
                next_frontier.add(id(dependency.target))
        frontier = next_frontier

    for index, dependency in enumerate(dependencies):
        source = event_positions.get(id(dependency.source))
        target = event_positions.get(id(dependency.target))
        if source is None or target is None:
            continue
        sx, sy = source
        tx, ty = target
        middle = (sx + tx) / 2
        bend = -10 if sy == ty else (ty - sy) * .45
        classes = ["dependency"]
        if dependency.kind == "contribution":
            classes.append("contribution")
        if index in focused_edges:
            classes.append("focus")
        svg.append(
            f'<path class="{" ".join(classes)}" d="M {sx:.2f} {sy:.2f} '
            f'C {middle:.2f} {sy + bend:.2f}, {middle:.2f} '
            f'{ty - bend:.2f}, {tx:.2f} {ty:.2f}" '
            'marker-end="url(#arrow)" '
            f'data-tooltip="{esc(dependency.detail)}"/>'
        )

    for event in visible:
        position = event_positions.get(id(event))
        if position is None:
            continue
        xpos, ypos = position
        color = COLORS[event.event]
        if event.event in {"aggregate_receive", "aggregate_send"}:
            shape = (
                f'<path d="M {xpos:.2f} {ypos - 6:.2f} L '
                f'{xpos + 6:.2f} {ypos + 5:.2f} L {xpos - 6:.2f} '
                f'{ypos + 5:.2f} Z"'
            )
        elif event.event in {"state_read", "batch_accept"}:
            shape = (
                f'<path d="M {xpos:.2f} {ypos - 6:.2f} L '
                f'{xpos + 6:.2f} {ypos:.2f} L {xpos:.2f} '
                f'{ypos + 6:.2f} L {xpos - 6:.2f} {ypos:.2f} Z"'
            )
        elif event.event == "state_write":
            shape = (
                f'<rect x="{xpos - 5:.2f}" y="{ypos - 5:.2f}" '
                'width="10" height="10"'
            )
        else:
            shape = f'<circle cx="{xpos:.2f}" cy="{ypos:.2f}" r="5"'
        hollow = event.event == "effects_accept"
        fill = BACKGROUND if hollow else color
        stroke = color if hollow else BACKGROUND
        svg.append(
            f'{shape} fill="{fill}" stroke="{stroke}" stroke-width="1.5" '
            f'data-tooltip="{esc(event_tooltip(event))}"/>'
        )
        if id(event) in focus_events:
            svg.append(
                f'<circle cx="{xpos:.2f}" cy="{ypos:.2f}" r="9" '
                f'fill="none" stroke="{FOREGROUND}" stroke-width="1.5"/>'
            )

    legend = [
        ("△", "aggregate"), ("◇", "read / batch"),
        ("□", "write"), ("●", "egress / send"),
        ("○", "router accept"),
    ]
    legend_x = left
    for symbol, label in legend:
        svg.append(
            f'<text x="{legend_x}" y="{top - 15}">{symbol} '
            f'{esc(label)}</text>'
        )
        legend_x += 105
    svg.append("</svg>")
    return "\n".join(svg) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--topology",
        type=Path,
        help="generated topology DSLX (default: beside the trace)",
    )
    parser.add_argument("--scheduler", default="phi_0")
    parser.add_argument("--occurrence", type=int, default=100)
    parser.add_argument("--before", type=int, default=8)
    parser.add_argument("--after", type=int, default=22)
    parser.add_argument("--pipeline-stages", type=int, default=2)
    parser.add_argument("--focus-cycle", type=int)
    args = parser.parse_args()
    if args.pipeline_stages < 1:
        raise SystemExit("pipeline stages must be positive")
    events = read_trace(args.trace)
    groups, planes, router_map = discover_components(events)
    schedulers = [item for group in groups for item in group]
    if args.scheduler not in schedulers:
        raise SystemExit(
            f"scheduler must be one of {', '.join(schedulers)}"
        )
    topology = args.topology or (
        args.trace.parent / "phi_decoder_profile_topology.x"
    )
    tables = read_destination_tables(topology)
    validation = validate_aggregate_transactions(
        events, groups, planes, args.pipeline_stages
    )
    dependencies = build_dependencies(
        events, groups, planes, router_map, tables
    )
    focus_cycle = choose_focus(
        events, args.scheduler, args.occurrence, args.focus_cycle
    )
    args.output.write_text(render(
        events,
        groups,
        planes,
        router_map,
        dependencies,
        args.scheduler,
        focus_cycle,
        args.before,
        args.after,
    ), encoding="utf-8")
    print(
        "TRACE_VALIDATION "
        + " ".join(f"{name}={value}" for name, value in validation.items())
        + " aggregate_semantic_outcome=bench_validated_not_individually_observed"
    )


if __name__ == "__main__":
    main()
