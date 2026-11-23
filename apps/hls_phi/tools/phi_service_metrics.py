"""Account public ready/valid cycles in a specified complete-status window."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import Counter
import json
from pathlib import Path


PORTS = {"link_out": 6, "link_in": 4, "app_out": 2, "app_in": 0}
STATES = ("idle_unready", "idle_ready", "blocked", "accepted")


def cycles(start: int, stop: int, edge: int, until: int, period: int) -> int:
    """Count rising edges in the intersection of [start, stop) and [edge, until)."""
    first = max(0, (start-edge+period-1)//period)
    past = max(0, (min(stop, until)-edge+period-1)//period)
    return max(0, past-first)


def summarize(stage: Path, periods: list[int], ports: dict[str, int] = PORTS) -> dict:
    """Combine status intervals and exact public port cycle occupancy; keep each device separate."""
    progress = json.loads((stage / "progress.json").read_text())
    start, stop = [progress["complete_rounds"][i]["time_ns"] for i in (0, -1)]
    rows: dict[int, list[tuple[int, int]]] = {d: [] for d in range(len(periods))}
    for line in (stage / "activity.log").read_text().splitlines():
        time, device, _cycle, bits = line.split()
        if "x" in bits or "z" in bits:
            raise ValueError("unknown public handshake")
        rows[int(device)].append((int(time), int(bits, 16)))
    devices = []
    for device, period in enumerate(periods):
        counters = {port: Counter({state: 0 for state in STATES}) for port in ports}
        changes = rows[device]
        if not changes or changes[0][0] > start:
            raise ValueError("missing initial public port observation")
        for (edge, bits), (until, _) in zip(changes, [*changes[1:], (stop, 0)]):
            count = cycles(start, stop, edge, until, period)
            for port, shift in ports.items():
                counters[port][STATES[(bits >> shift) & 3]] += count
        devices.append({"device": device, "period_ns": period,
            "ports": {port: {**dict(counts),
                "accepted_transfers_per_step": counts["accepted"]/len(progress["intervals_ns"]),
                "accepted_fraction": counts["accepted"]/sum(counts.values()),
                "blocked_fraction": counts["blocked"]/sum(counts.values())}
                for port, counts in counters.items()}})
    report = {"scope": "Public gateway and link port edges in the progress report’s complete-round window; zero-time host, real protocol and CDC. No internal state sampled.",
        "window_ns": [start, stop], "progress": progress, "devices": devices}
    (stage / "service.json").write_text(json.dumps(report, indent=2)+"\n")
    return report
