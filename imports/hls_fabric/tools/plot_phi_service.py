#!/usr/bin/env python3
"""Render cycle-level port activity and debug projections, with public query cross-checks."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

from phi_service_metrics import PORTS, cycles
from phi_cycle_trace import read as read_cycles, verify_queries


BLUE, RED, GREEN, PURPLE, AMBER = "#0969da", "#cf222e", "#1a7f37", "#8250df", "#bf8700"


def observations(stage: Path, periods: list[int]) -> tuple[dict, dict, dict]:
    """Read public signal changes and align captured debug cycles to each device's reset epoch."""
    activity = defaultdict(list)
    offsets = {}
    for line in (stage / "activity.log").read_text().splitlines():
        time, device, cycle, bits = line.split()
        d, t = int(device), int(time)
        activity[d].append((t, int(bits, 16)))
        offset = t-int(cycle)*periods[d]
        if d in offsets and offsets[d] != offset:
            raise ValueError("device clock/reset changed inside the profile")
        offsets[d] = offset
    occupancy = json.loads((stage / "occupancy.json").read_text())
    resources, samples = {}, defaultdict(list)
    for device in occupancy:
        d = device["device"]
        for resource in device["resources"]:
            resources[d, resource["id"]] = resource
        for sample in device["samples"]:
            time = offsets[d] + sample["cycle"]*periods[d]
            samples[d, sample["id"]].append({**sample, "time_ns": time})
    return activity, resources, samples


def label(device: int, resource: dict) -> str:
    """Retain logical actor identity or the FIFO's catalog name without generated hierarchy prefixes."""
    name = resource["name"]
    if resource["kind"] == "actor":
        return f"D{device} " + name.removeprefix("{actor,{family,").removesuffix("}}")
    if name.endswith("fifo__transmit_words_"):
        return f"D{device} transmit_words"
    match = re.search(r"fifo__(\w+)__(\d+)_$", name)
    return f"D{device} {match[1]}[{match[2]}]" if match else f"D{device} resource {resource['id']}"


def render(stage: Path, first: int, last: int, output: Path, zoom_ns: int | None = None, devices: list[int] | None = None) -> None:
    """Show cycle-level port duty, committed actor metadata and FIFO depth, with independent query samples."""
    inputs = json.loads((stage / "profile-inputs.json").read_text())
    progress = json.loads((stage / "progress.json").read_text())
    rounds = {r["step"]: r["time_ns"] for r in progress["complete_rounds"]}
    start, stop = rounds[first], rounds[last]
    if zoom_ns is not None:
        stop = min(stop, start+zoom_ns)
    activity, resources, samples = observations(stage, inputs["device_periods_ns"])
    _, histories = read_cycles(stage)
    verify_queries(stage, histories)
    selected_devices = devices if devices is not None else list(range(len(inputs["device_periods_ns"])))
    resources = {k: r for k, r in resources.items() if k[0] in selected_devices}
    actors = [k for k, r in resources.items() if r["kind"] == "actor"]
    fifos = [k for k, r in resources.items() if r["kind"] == "fifo"]
    height = [4, max(3, len(actors)*0.30), max(3, len(fifos)*0.22)]
    plt.rcParams.update({"font.size": 9, "font.family": "DejaVu Sans", "svg.fonttype": "none"})
    fig, axes = plt.subplots(3, 1, figsize=(15, sum(height)+1.5), sharex=True,
                             gridspec_kw={"height_ratios": height}, layout="constrained")
    t = lambda ns: (ns-start)/1000
    # Fixed 100 ns bins prevent subpixel stripes from hiding busy or blocked cycles.
    bin_ns = 10 if stop-start <= 2000 else 100
    bins = list(range(start, stop, bin_ns))
    port_labels = []
    port_layout = inputs.get("port_layout", PORTS)
    visible_ports = inputs.get("plot_ports", ["link_out", "link_in", "app_out"])
    for d in selected_devices:
        changes = activity[d]
        period = inputs["device_periods_ns"][d]
        for port in visible_ports:
            row = len(port_labels)
            port_labels.append(f"D{d} " + inputs.get("port_labels", {}).get(str(d), {}).get(port, port))
            accepted, blocked = [0.0]*len(bins), [0.0]*len(bins)
            shift = port_layout[port]
            for (edge, bits), (until, _) in zip(changes, [*changes[1:], (stop, 0)]):
                state = (bits >> shift) & 3
                if state not in (2, 3):
                    continue
                first_edge = edge+max(0, (start-edge+period-1)//period)*period
                for time in range(first_edge, min(until, stop), period):
                    index = (time-start)//bin_ns
                    (accepted if state == 3 else blocked)[index] += 1
            denominators = [cycles(b, min(b+bin_ns, stop), changes[0][0], stop, period) for b in bins]
            accepted = [n/d if d else 0 for n, d in zip(accepted, denominators)]
            blocked = [n/d if d else 0 for n, d in zip(blocked, denominators)]
            xs = [t(b) for b in bins]
            axes[0].bar(xs, accepted, width=bin_ns/1000, bottom=row, align="edge", color=BLUE, linewidth=0)
            axes[0].bar(xs, blocked, width=bin_ns/1000,
                        bottom=[row+a for a in accepted], align="edge", color=RED, linewidth=0)
    axes[0].set_yticks([i+0.45 for i in range(len(port_labels))], port_labels)
    axes[0].set_ylim(-0.1, len(port_labels)+0.15)
    axes[0].invert_yaxis()
    axes[0].set_title(f"Public handshakes · occupied fraction of each {bin_ns} ns bin", loc="left", weight="bold")
    axes[0].legend(handles=[Patch(color=BLUE, label="accepted"), Patch(color=RED, label="valid, blocked")],
                   loc="upper right", ncol=2)
    for ax, keys, title in [(axes[1], actors, "Actor committed metadata · mailbox depth / capacity; red = waiting for egress"),
                             (axes[2], fifos, "FIFO occupancy · exact per-cycle state; circles = independent debug queries")]:
        ax.set_title(title, loc="left", weight="bold")
        for row, key in enumerate(keys):
            resource = resources[key]
            history = histories.get(key, [])
            for sample, next_sample in zip(history, [*history[1:], {"time_ns": stop}]):
                left, right = max(start, sample["time_ns"]), min(stop, next_sample["time_ns"])
                if left >= right:
                    continue
                if resource["kind"] == "actor":
                    count = sample.get("message_queue_len")
                    if isinstance(count, int):
                        fraction = count/resource["mailbox_capacity"]
                        ax.fill_between([t(left), t(right)], row-0.32, row-0.32+0.64*fraction, color=BLUE, alpha=0.6, linewidth=0)
                    if sample.get("waiting_for_egress"):
                        ax.plot([t(left), t(right)], [row+0.30]*2, color=RED, lw=2)
                    if sample.get("state_write") and start <= sample["time_ns"] <= stop:
                        phase = sample.get("phase", "")
                        color = {"gathering": PURPLE, "comparing": AMBER, "flipping": GREEN}.get(phase, BLUE)
                        ax.scatter([t(sample["time_ns"] )], [row-0.40], marker="|", s=20, color=color)
                elif sample["occupancy"]:
                    ax.fill_between([t(left), t(right)], row-0.25, row-0.25+0.5*sample["occupancy"]/resource["capacity"], color=GREEN, alpha=0.7, linewidth=0)
            series = [s for s in samples[key] if start <= s["time_ns"] <= stop]
            for sample in series:
                x = t(sample["time_ns"])
                if resource["kind"] == "actor":
                    count = sample.get("message_queue_len")
                    if not isinstance(count, int):
                        continue
                    fraction = count/resource["mailbox_capacity"]
                    ax.vlines(x, row-0.32, row-0.32+0.64*fraction, color=BLUE, lw=2)
                    phase = sample.get("phase", "")
                    color = {"gathering": PURPLE, "comparing": AMBER, "flipping": GREEN}.get(phase, BLUE)
                    ax.scatter([x], [row-0.32+0.64*fraction], s=11, color=color, zorder=3)
                    if sample.get("waiting_for_egress") is True:
                        ax.scatter([x], [row+0.22], marker="x", s=16, color=RED)
                else:
                    full = sample["occupancy"] > 0
                    ax.scatter([x], [row], s=12, edgecolors=GREEN if full else "#afb8c1",
                               facecolors=GREEN if full else "none", linewidths=0.7)
        ax.set_yticks(range(len(keys)), [label(k[0], resources[k]) for k in keys])
        ax.set_ylim(-0.7, max(1, len(keys))-0.3)
        ax.invert_yaxis()
    axes[1].legend(handles=[Line2D([], [], color=c, marker="o", linestyle="", label=l)
        for c, l in [(BLUE, "other phase"), (PURPLE, "gathering"), (AMBER, "comparing"), (GREEN, "flipping")]],
        loc="upper right", ncol=4, fontsize=8)
    for ax in axes:
        for step, time in rounds.items():
            if start <= time <= stop:
                ax.axvline(t(time), color="#59636e", alpha=0.3, lw=0.8)
        ax.set_xlim(0, t(stop))
        ax.spines[["top", "right"]].set_visible(False)
        ax.grid(axis="x", alpha=0.15)
    for step, time in rounds.items():
        if start <= time <= stop:
            axes[0].annotate(str(step), (t(time), 0), xycoords=("data", "axes fraction"),
                             xytext=(2, -13), textcoords="offset points", color="#59636e", fontsize=8)
    axes[-1].set_xlabel(f"Simulated time since complete status round {first} (µs)")
    summary = json.loads((stage / "memory-result.json").read_text())["summary"]
    witness = (f"decoder prefix through step {summary['through_step']}"
               if summary.get("kind") == "status_prefix" else "complete measurement witness")
    periods = "/".join(map(str, sorted(set(inputs["device_periods_ns"]))))
    transport = inputs.get("transport", "serial")
    link = ("serial, one credit/lane" if transport == "serial" else
            f"{32*transport['words']}-bit data, {transport['credits']} credits/lane"
            + (", compact" if transport.get('compact', False) else ""))
    fig.suptitle(f"D{inputs.get('distance', 3)} service profile · {inputs['placement']} · device periods {periods} ns · "
                 f"{link} · {witness}\n"
                 "Cycle-level passive taps, checked against public queries. Clocks are not physically qualified.",
                 fontsize=12, weight="bold")
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output)
    if output.suffix.lower() == ".svg":
        output.write_text("\n".join(line.rstrip() for line in output.read_text().splitlines())+"\n")
    fig.savefig(output.with_suffix(".png"), dpi=110)
    plt.close(fig)


def main() -> None:
    """Render a chosen pair of complete status rounds from a retained experiment directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--rounds", type=int, nargs=2, default=[10, 12])
    parser.add_argument("--devices", type=int, nargs="+", help="show only these device IDs")
    parser.add_argument("--zoom-ns", type=int, help="show this many ns from the first round boundary")
    args = parser.parse_args()
    if args.rounds[0] >= args.rounds[1]:
        parser.error("round range must increase")
    if args.zoom_ns is not None and args.zoom_ns < 1:
        parser.error("zoom must be positive")
    render(args.stage, *args.rounds, args.output, args.zoom_ns, args.devices)


if __name__ == "__main__":
    main()
