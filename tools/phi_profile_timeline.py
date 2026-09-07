#!/usr/bin/env python3
"""Render a clock-aligned SVG timeline from the phi VPI trace CSV."""

from __future__ import annotations

import argparse
import csv
import html
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Event:
    cycle: int
    component: str
    event: str
    slot: int | None
    detail: str


COLORS = {
    "batch_accept": "var(--viz-series-1)",
    "aggregate_send": "var(--viz-series-2)",
    "aggregate_receive": "var(--viz-series-3)",
    "aggregate_accept": "var(--viz-series-4)",
    "aggregate_complete": "var(--viz-series-4)",
    "aggregate_pending": "var(--viz-series-6)",
    "aggregate_error": "var(--destructive)",
    "state_read": "var(--viz-series-5)",
    "state_write": "var(--viz-series-5)",
    "effects_egress": "var(--viz-series-2)",
    "selectable": "var(--viz-series-1)",
    "same_actor_only": "var(--viz-series-6)",
    "executor_blocked": "var(--viz-series-4)",
    "no_actor_work": "var(--muted)",
    "waiting_egress_credit": "var(--viz-series-3)",
    "internal_other": "var(--muted)",
}


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
        f'<svg viewBox="0 0 {width} {height}" role="img" '
        f'aria-labelledby="{title_id} {desc_id}" '
        'style="width:100%;height:auto;display:block">',
        f'<title id="{title_id}">Clock-aligned phi reduction timeline</title>',
        f'<desc id="{desc_id}">Neighbor batches are folded in the reduction plane, delivered to one scheduler, accepted as a completed reduction, followed by an actor state read, state write, and new effects.</desc>',
        '<style>',
        'text{fill:var(--foreground);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px}',
        '.muted{fill:var(--muted-foreground)}',
        '.grid{stroke:var(--border);stroke-width:1}',
        '.axis{stroke:var(--foreground);stroke-width:1}',
        '.mark{stroke:var(--background);stroke-width:1}',
        '</style>',
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
        color = COLORS.get(status, "var(--muted)")
        ypos = rows["selection"] + 10
        svg.append(
            f'<rect x="{xpos:.2f}" y="{ypos}" width="{run_width:.2f}" height="21" '
            f'fill="{color}" opacity="0.72" data-tooltip="{esc(status)}: clocks {run_start}–{run_end}"/>'
        )
        if run_width >= 62:
            label = status.replace("_", " ")
            svg.append(
                f'<text x="{xpos + 4:.2f}" y="{ypos + 15}" fill="var(--foreground)">{esc(label)}</text>'
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
        color = COLORS.get(event.event, "var(--foreground)")
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
        f'y2="{height - 35}" stroke="var(--foreground)" stroke-width="1" stroke-dasharray="3 3"/>'
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
        "--fragment",
        action="store_true",
        help="wrap the SVG in an embeddable HTML fragment",
    )
    args = parser.parse_args()
    events = parse_trace(args.trace)
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
