"""nextpnr --post-route hook. Capture selected net handles before native state is discarded."""
import json
from pathlib import Path


def capture(context, request: dict) -> dict:
    """Keep aliases, routed wire names and the router's exact packed-port/BEL-pin attachment."""
    remaining = request["max_objects"]

    def charge() -> None:
        """Abort the export before adding a record beyond its preregistered ceiling."""
        nonlocal remaining
        remaining -= 1
        if remaining < 0:
            raise ValueError("native route object limit")

    aliases = {}
    for alias, target in context.net_aliases:
        charge()
        aliases[alias] = target
    names = {aliases.get(name, name) for name in request["nets"]}
    all_routes = request.get("all", False)
    by_net = {name: [] for name in names}
    for alias, target in aliases.items():
        if all_routes or target in by_net:
            by_net.setdefault(target, []).append(alias)
    nets = {}
    for name, net in context.nets:
        if not all_routes and name not in names:
            continue
        charge()
        wires = {}
        for wire, binding in net.wires:
            charge()
            wires[wire] = {"incoming": binding.pip, "index": context.getWireChecksum(wire)}
        pins = []

        def pin(ref, direction: str) -> None:
            """Use the same explicit pin override or packed port as getNetinfo{Source,Sink}Wire."""
            charge()
            cell = ref.cell
            if cell is None:
                pins.append({"cell": None, "port": ref.port, "direction": direction,
                             "bel": None, "bel_pin": None, "wire": None})
                return
            port = ref.port
            bel = cell.bel
            port_map = {logical: physical for logical, physical in cell.pins}
            bel_pin = port_map.get(port, port)
            wire = context.getBelPinWire(bel, bel_pin) if bel else None
            pins.append({"cell": cell.name, "port": port, "direction": direction,
                         "bel": bel, "bel_pin": bel_pin if bel else None, "wire": wire})

        pin(net.driver, "OUT")
        for user in net.users:
            pin(user, "IN")
        nets[name] = {"wires": wires, "pins": pins,
                      "aliases": sorted(by_net.get(name, []))}
    if not all_routes and names != set(nets):
        raise ValueError(f"selected nets absent after packing: {sorted(names - set(nets))}")
    return nets


with Path("native-pins.json").open("x") as output:
    json.dump(capture(ctx, json.loads(Path("route-request.json").read_bytes())),  # noqa: F821
              output, sort_keys=True, separators=(",", ":"))
