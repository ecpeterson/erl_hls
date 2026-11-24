"""Join nextpnr's numeric fixed-route PIPs to bound wires and exact BEL-pin attachments."""
from pathlib import Path
from openxc7_chipdb import ChipGrid


def build_routes(grid: ChipGrid, fixed: Path, native: dict, limit: int) -> dict:
    """Produce the shared route-renderer tables, retaining missing endpoints and raw wire names."""
    by_net = {name: [] for name in native}
    selected_pips = 0
    with fixed.open(encoding="utf-8") as stream:
        if not stream.readline().startswith("# nextpnr-xilinx fixed-routes:"):
            raise ValueError("unsupported native fixed-route header")
        for row in stream:
            name, switch = row.rstrip("\n").rsplit(" ", 1)
            if name in by_net:
                selected_pips += 1
                if selected_pips > limit:
                    raise ValueError("native PIP limit")
                by_net[name].append(switch)
    rows = []
    count = unresolved = 0

    def charge(n: int = 1) -> None:
        """Reserve all output rows before extending the graph."""
        nonlocal count
        count += n
        if count > limit:
            raise ValueError("route object limit")

    for name, raw in sorted(native.items()):
        nodes, pips, pins, issues = [], [], [], []
        names = {}
        charge(1 + len(raw["aliases"]))
        for wire, binding in raw["wires"].items():
            parts = wire.split("/", 2)
            owner = parts[1] if parts[0] == "SITEWIRE" else parts[0]
            key = grid.wire_key(owner, binding["index"])
            if key in names:
                raise ValueError(f"duplicate native wire identity on {name}")
            names[key] = wire
            charge()
            footprint = grid.wires(key, limit - count)
            charge(len(footprint))
            nodes.append({"id": wire, "wires": footprint})
        observed = set()
        for switch in by_net[name]:
            tile, pair = switch.rsplit("/", 1)
            source, target = (grid.wire_key(tile, int(i)) for i in pair.split("."))
            start, end = names.get(source), names.get(target)
            incoming = raw["wires"].get(end, {}).get("incoming")
            if incoming and incoming in observed:
                raise ValueError(f"ambiguous PIP occurrence on {name}: {incoming}")
            observed.add(incoming)
            available = start is not None and end is not None and incoming is not None
            charge()
            loc = grid.location(tile)
            pips.append({"id": incoming or switch, "native_switch": switch,
                         "from_node": start if available else None, "to_node": end,
                         "direction_status": "directional" if available else "unavailable",
                         "tile": tile, "x": loc["x"], "y": loc["y"]})
            if not available:
                issues.append({"stage": "pip", "object": switch, "reason": "unresolved bound wire"})
        for wire, binding in raw["wires"].items():
            incoming = binding["incoming"]
            if incoming and incoming not in observed:
                charge()
                pips.append({"id": incoming, "native_switch": None, "from_node": None,
                             "to_node": wire, "direction_status": "unavailable",
                             "tile": None, "x": None, "y": None})
                issues.append({"stage": "pip", "object": incoming, "reason": "missing fixed-route PIP"})
        for ref in raw["pins"]:
            charge()
            cell, port, wire = ref["cell"], ref["port"], ref["wire"]
            pin = f"{cell}/{port}" if cell else f"$external/{port}"
            bel_pin = f'{ref["bel"]}/{ref["bel_pin"]}' if ref["bel"] else None
            resolved = bool(bel_pin and wire in raw["wires"])
            pins.append({"pin": pin, "cell": cell, "port": port, "direction": ref["direction"],
                         "status": "resolved" if resolved else "unavailable",
                         "bel_pins": [bel_pin] if bel_pin else [], "site_pins": [],
                         "bel_wire": wire, "routing_node": wire if resolved else None})
            if not resolved:
                issues.append({"stage": "pin", "object": pin, "reason": "missing bound BEL-pin wire"})
        charge(len(issues))
        unresolved += len(issues)
        rows.append({"id": name, "aliases": raw["aliases"],
                     "status": "partial" if issues else "complete",
                     "route_status": "ROUTED" if nodes else "NO_BOUND_WIRES",
                     "nodes": nodes, "pips": pips, "pin_attachments": pins, "issues": issues})
    return {"schema": 1, "nets": rows, "objects": count, "unresolved": unresolved}
