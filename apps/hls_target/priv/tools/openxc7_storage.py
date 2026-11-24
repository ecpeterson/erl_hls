"""Qualify declared RTL word bits against original drivers and connected packed FDRE roles."""
from collections import defaultdict


def qualify_words(words: list[str], synth: dict, packed: dict, timing: dict, limit: int) -> list[dict]:
    """Trace LSB-first Yosys signal bits through one recognized driver; leave other bits unknown."""
    drivers = defaultdict(list)
    origins = defaultdict(list)
    for name, cell in synth["cells"].items():
        for port, bits in cell["connections"].items():
            if cell["port_directions"][port] in ("output", "inout"):
                for bit in bits:
                    if isinstance(bit, int):
                        drivers[bit].append((name, port))
    for name, cell in packed.items():
        origins[cell["attributes"].get("SPACETIME_CELL")].append(name)
    result = []
    seen = set()
    remaining = limit
    for word in words:
        resource, sep, net = word.partition("=")
        if not sep or not resource or resource in seen or net not in synth["netnames"]:
            raise ValueError(f"invalid resource=RTL-net declaration: {word}")
        seen.add(resource)
        signal = synth["netnames"][net]
        bits = []
        for i, wire in enumerate(signal["bits"]):
            remaining -= 1
            if remaining < 0:
                raise ValueError("storage bit limit")
            candidate = None
            if len(drivers[wire]) == 1:
                name, port = drivers[wire][0]
                if port == "Q" and len(origins[name]) == 1:
                    placed = origins[name][0]
                    candidate = fdre(synth["cells"][name], packed[placed], timing["cells"][placed])
                    if candidate is not None:
                        candidate.update(cell=placed, original=name, pin="Q")
            bits.append({"bit": i, **(candidate or {"status": "unknown",
                         "evidence": "No unique FDRE with complete matching configuration and bound D/Q/CK/CE/SR"})})
        result.append({"resource": resource, "net": net, "bits": bits})
    return result


def fdre(source: dict, packed: dict, native: dict) -> dict | None:
    """Admit positive-edge, non-inverted synchronous reset and connected active-high enable only."""
    attrs = packed["attributes"]
    if (source["type"] != "FDRE" or packed["type"] != "SLICE_FFX" or native["type"] != "SLICE_FFX" or
            attrs.get("X_ORIG_TYPE") != "FDRE" or attrs.get("X_FFSYNC", "").strip() != "1"):
        return None
    initial = source["parameters"].get("INIT", "0")
    if initial not in ("0", "1") or packed["parameters"].get("INIT", "0") != initial:
        return None
    for params, supported in [(source["parameters"], {"IS_C_INVERTED", "IS_D_INVERTED", "IS_R_INVERTED"}),
                              (packed["parameters"], {"IS_CLK_INVERTED", "IS_D_INVERTED", "IS_SR_INVERTED"})]:
        if any(key != "INIT" and (key not in supported or set(value.strip()) != {"0"})
               for key, value in params.items()):
            return None
    roles = {"D": ("D", "register_input"), "Q": ("Q", "register_output"), "CK": ("C", "clock_input"),
             "CE": ("CE", "register_input"), "SR": ("R", "register_input")}
    for pin, (original, kind) in roles.items():
        row = native["ports"].get(pin, {})
        origin = attrs.get("SPACETIME_PORT_" + original)
        if (not origin or origin != row.get("net_origin") or not row.get("wire") or not row.get("bound") or
                attrs.get("X_ORIG_PORT_" + pin) != original or row.get("bel_pin") != pin or
                row.get("class") != kind or len(source["connections"].get(original, [])) != 1):
            return None
        if kind != "clock_input" and [(c["port"], c["edge"]) for c in row["clocks"]] != [("CK", "rising")]:
            return None
    return {"status": "supported", "initial": int(initial), "edge": "rising",
            "roles": {"d": "D", "q": "Q", "clock": "CK", "ce": "CE", "reset": "SR"},
            "evidence": "Synthesis Q bit, pre-pack port/net origins, FDRE configuration and bound packed BEL-pin wires"}
