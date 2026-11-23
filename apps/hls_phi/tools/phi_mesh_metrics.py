"""Attribute mesh wire traffic to physical neighbors and cross-check exact public handshake totals."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import Counter, defaultdict
import json
from pathlib import Path

from phi_service_analysis import occupancy
from phi_service_metrics import STATES, summarize
from phi_link_packet import transfer_words, packets as decode_packets, frame_header, word_kind


PORTS = {**{f"link_{i}_out": 2*i for i in range(4)},
         **{f"link_{i}_in": 8+2*i for i in range(4)}, "app_out": 16, "app_in": 18}


def layout(stage: Path) -> dict:
    """Name each physical stream from the actual checked directional geometry."""
    devices = json.loads((stage / "bridge.json").read_text())["devices"]
    geometry, = [g for g in json.loads((stage / "geometry.json").read_text()) if g["distance"] == 6]
    directions = {(r["device"], r["peer"]): r for r in geometry["directions"] if not r["local"]}
    if len(directions) != 72:
        raise ValueError("D6 must have four distinct neighbors on each of eighteen boards")
    labels = {str(d["id"]): {f"link_{l['index']}_{flow}": f"{directions[d['id'], l['peer']]['direction']} {flow} ↔ D{l['peer']}"
              for l in d["links"] for flow in ("out", "in")} for d in devices}
    return {"port_layout": PORTS, "port_labels": labels,
            "plot_ports": [*(f"link_{i}_out" for i in range(4)), "app_out"]}


def analyze(stage: Path) -> dict:
    """Decode every wire packet, retain per-link pressure and all published FIFO/mailbox occupancies."""
    inputs = json.loads((stage / "profile-inputs.json").read_text())
    service = summarize(stage, inputs["device_periods_ns"], PORTS)
    start, stop = service["window_ns"]
    devices = json.loads((stage / "bridge.json").read_text())["devices"]
    links = {(d["id"], l["index"]): l["peer"] for d in devices for l in d["links"]}
    catalog = {(r["device"], r["peer"], r["lane"]): r
               for r in json.loads((stage / "lane-catalog.json").read_text())}
    transfers = Counter()
    transport = inputs.get("transport", "serial")
    capacity = 1 if transport == "serial" else transport["words"]
    words, messages, lane_counts = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter)
    path = stage / 'traffic.log'
    for line in path.read_text().splitlines():
        timestamp, device, port, _ = line.split()
        if start <= int(timestamp) < stop:
            transfers[int(device), int(port)] += 1
    for key, packets in decode_packets(path, transport).items():
        d, i = key
        peer = links[key]
        for packet in packets:
            lane, credit = packet['lane'], packet['credit']
            route = (peer, d, lane) if credit else (d, peer, lane)
            if route not in catalog:
                raise ValueError(f"invalid link lane D{d} L{i}")
            header = frame_header(packet)
            if header is not None:
                schema, = [s for s in catalog[d, peer, lane]['schemas'] if s['tag'] == header >> 24]
                if header & 255 != (schema['bits']+31)//32 or header & 0x00ffff00:
                    raise ValueError('invalid application header')
                index = 0 if packet['compact'] else 1
                if start <= packet['word_times_ns'][index] < stop:
                    messages[key][schema['name']] += 1
                    lane_counts[key][lane] += 1
            for index, (word, time) in enumerate(zip(packet['words'], packet['word_times_ns'])):
                kind = word_kind(packet, index)
                if kind == 'padding' and word & 0xffffffff:
                    raise ValueError('nonzero frame padding')
                if start <= time < stop:
                    words[key][kind] += 1
    result = []
    for (d, i), peer in sorted(links.items()):
        counts = service["devices"][d]["ports"][f"link_{i}_out"]
        if transfers[d, i] != counts["accepted"]:
            raise ValueError(f"wire/handshake accounting differs on D{d} L{i}")
        result.append({"device": d, "link": i, "peer": peer, "words": dict(words[d, i]),
            "frames": dict(messages[d, i]), "pressure": counts,
            "word_capacity_utilization": sum(words[d, i].values())/(capacity*sum(counts[state] for state in STATES)),
            "transfer_fill": sum(words[d, i].values())/(capacity*transfers[d, i]) if transfers[d, i] else 0,
            "lanes": [{**catalog[d, peer, lane], "frames": n} for lane, n in sorted(lane_counts[d, i].items())]})
    report = {"window_ns": [start, stop], "links": result, "occupancy": occupancy(stage, start, stop)}
    (stage / "analysis.json").write_text(json.dumps(report, indent=2)+"\n")
    return report
