"""Map existing debug projections to passive cycle-level VPI observations."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections.abc import Iterable
import gzip
import hashlib
import json
from pathlib import Path


def plan(build: Path, stage: Path, devices: tuple[int, ...] = (0, 1),
         channels: bool = False, all_channels: bool = False,
         actor_devices: set[int] | None = None) -> None:
    """Record all FIFO/actor projections; optionally restrict detailed internal channels to selected devices."""
    if actor_devices is not None and (not all_channels or not actor_devices <= set(devices)):
        raise ValueError('detailed actor devices must belong to an all-channel capture')
    rows = []
    for d in devices:
        manifest = json.loads((build / f"device{d}/debug/manifest.json").read_text())
        if manifest["schema"] != 5:
            raise ValueError("cycle profiler requires topology schema 5")
        resources = manifest["resources"]
        for resource in resources:
            if resource["kind"] == "fifo":
                rows.append((d, "F", resource["id"], 64*resource["id"], resource["width"], -1, -1, 0, 0))
        complete = all_channels and (actor_devices is None or d in actor_devices)
        if channels or complete:
            selected = {r[side] for r in resources if r["kind"] == "fifo"
                        and any(name in r["name"] for name in
                                ("__outgoing_", "__received_", "__link_", "__transmit_words_"))
                        for side in ("push", "pop")}
            selected.update(r["id"] for r in resources if r["name"].startswith("_link_"))
            for resource in resources:
                if resource["kind"] == "channel" and (complete or resource["id"] in selected):
                    rows.append((d, "C", resource["id"], 64*resource["id"], 2, -1, -1, 0, 0))
        offset = 0
        for bank in manifest["actor_projection"]["banks"]:
            slots = bank["slots"]
            address = max(1, (slots-1).bit_length())
            width = 25 + bank.get("reduction", {}).get("width", 0)
            mailbox = offset+1+address+width
            if bank["mailbox"]["kind"] != "shared":
                raise ValueError("cycle actor profiling currently requires shared RAM projections")
            for resource in resources:
                if resource["kind"] == "actor" and resource["bank"] == bank["index"]:
                    slot, ident = resource["slot"], resource["id"]
                    rows.append((d, "S", ident, offset+1+address, width, offset, offset+1, address, slot))
                    rows.append((d, "M", ident, mailbox+1+24*slot, 24, mailbox, -1, 0, 0))
            offset = mailbox+1+24*slots
    (stage / "cycle-probes.txt").write_text("".join(" ".join(map(str, row))+"\n" for row in rows))


def executor_requests(resources: Iterable[dict], module: str | None = None) -> list[dict]:
    """Locate executor acceptance ports and any directly attached storage queue.

    Resources describe one device. Depth-zero channels have no FIFO occupancy
    resource; their acceptance port remains observable. Ambiguous queues fail.
    """
    resources = list(resources)
    consumers = [r for r in resources if r['kind'] == 'channel'
                 and '__SharedExecutor_' in r['name'] and r['name'].endswith('/_request_in')
                 and (module is None or module in r['name'])]
    requests = []
    for consumer in consumers:
        connected = [r for r in resources if r['kind'] == 'fifo' and r['pop'] == consumer['id']]
        if len(connected) > 1:
            raise ValueError('executor input has ambiguous recorded queues')
        requests.append({'owner': consumer['name'].rsplit('/', 2)[0], 'accept': consumer['id'],
                         'queue': connected[0] if connected else None})
    return sorted(requests, key=lambda r: r['owner'])


def capture_path(stage: Path) -> Path:
    """Find a complete cycle recording, accepting raw or streamed gzip storage."""
    raw = stage / 'cycle-trace.csv'
    return raw if raw.is_file() else raw.with_suffix('.csv.gz')


def trace_digest(path: Path) -> str:
    """Identify decoded CSV bytes independently of their raw or gzip storage format."""
    checksum = hashlib.sha256()
    with (gzip.open(path, 'rb') if path.suffix == '.gz' else path.open('rb')) as source:
        while block := source.read(1024*1024):
            checksum.update(block)
    return checksum.hexdigest()


def read(stage: Path, devices: set[int] | None = None, trace: Path | None = None,
         kinds: set[str] | None = None, selected: set[tuple[int, int]] | None = None) -> tuple[dict, dict]:
    """Reconstruct selected public observations; committed writes appear at the next sampling edge."""
    import csv
    from collections import defaultdict
    resources, histories = {}, defaultdict(list)
    periods = json.loads((stage / "profile-inputs.json").read_text())["device_periods_ns"]
    for device in range(len(periods)):
        if devices is not None and device not in devices:
            continue
        manifest = json.loads((stage / f"device{device}-manifest.json").read_text())
        resources.update({(device, r["id"]): r for r in manifest["resources"]})
    updates = {}
    path = trace or capture_path(stage)
    with (gzip.open(path, "rt") if path.suffix == ".gz" else path.open()) as stream:
        for row in csv.DictReader(stream):
            if kinds is not None and row["kind"] not in kinds:
                continue
            if selected is not None and (int(row["device"]), int(row["id"])) not in selected:
                continue
            if devices is not None and int(row["device"]) not in devices:
                continue
            d, ident, cycle, time = [int(row[k]) for k in ("device", "id", "cycle", "time_ns")]
            value, kind = int(row["value"], 16), row["kind"]
            if kind == "F":
                if value > resources[d, ident]["capacity"]:
                    raise ValueError("FIFO occupancy exceeds its declared capacity")
                histories[d, ident].append({"cycle": cycle, "time_ns": time, "value": value, "occupancy": value})
            elif kind == "C":
                if value > 3 or resources[d, ident]["kind"] != "channel":
                    raise ValueError("invalid channel observation")
                histories[d, ident].append({"cycle": cycle, "time_ns": time, "value": value})
            else:
                update = updates.setdefault((d, ident, cycle), {"time_ns": time})
                update[kind] = value
    values = defaultdict(int)
    for (d, ident, cycle), update in sorted(updates.items(), key=lambda pair: (pair[0][2], pair[0][0], pair[0][1])):
        value = values[d, ident]
        if "S" in update:
            raw = update["S"]
            value = (value & (((1 << 24)-1) << 32)) | (raw & ((1 << 25)-1)) | (1 << 25) | ((raw >> 25) << 56)
        if "M" in update:
            value = (value & ~(((1 << 24)-1) << 32)) | (update["M"] << 32)
        values[d, ident] = value
        # Schema 5's public actor observation layout; query decoding independently checks these values.
        resource = resources[d, ident]
        initialized = bool(value & (1 << 25))
        mailbox = (value >> 32) & ((1 << 24)-1)
        sample = {"cycle": cycle+1, "time_ns": update["time_ns"]+periods[d], "value": value,
            "phase": resource["phases"][value & 255] if initialized else None,
            "message_queue_len": mailbox & 255 if mailbox & (1 << 23) else None,
            "waiting_for_egress": bool(mailbox & (1 << 19)),
            "in_flight": bool(mailbox & (1 << 16)), "state_write": "S" in update}
        histories[d, ident].append(sample)
    return resources, dict(histories)


def verify_queries(stage: Path, histories: dict) -> dict:
    """Require every independent hardware query to equal the passive reconstruction at its capture cycle."""
    from bisect import bisect_right
    report = {}
    for device in json.loads((stage / "occupancy.json").read_text()):
        d, matched = device["device"], 0
        for sample in device["samples"]:
            history = histories.get((d, sample["id"]), [])
            index = bisect_right([s["cycle"] for s in history], sample["cycle"])-1
            actual = history[index]["value"] if index >= 0 else 0
            if actual != sample["value"]:
                raise ValueError(f"query/tap mismatch D{d} resource {sample['id']} cycle {sample['cycle']}: {actual:x} != {sample['value']:x}")
            matched += 1
        report[str(d)] = matched
    (stage / "query-tap-check.json").write_text(json.dumps(report, indent=2)+"\n")
    return report
