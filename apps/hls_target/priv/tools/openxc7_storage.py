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
    constants = {}
    for name, cell in packed.items():
        if cell["type"] in ("PSEUDO_VCC", "PSEUDO_GND"):
            for bit in cell["connections"].get("Y", []):
                constants[bit] = "1" if cell["type"] == "PSEUDO_VCC" else "0"
        origins[cell["attributes"].get("SPACETIME_CELL")].append(name)
    # XC7 control muxes are shared by the placed FFs in a slice.
    driven_controls = set()
    for cell in packed.values():
        if cell["type"] == "SLICE_FFX":
            site = cell["attributes"].get("NEXTPNR_BEL", "").partition("/")[0]
            for port, inactive in (("SR", "0"), ("CE", "1")):
                if any(constants.get(bit) != inactive for bit in cell.get("connections", {}).get(port, [])):
                    driven_controls.add((site, port))
    roots = set(timing.get("roots", []))
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
            reason = "Constant or absent synthesis driver" if not drivers[wire] else "Multiple synthesis drivers"
            if len(drivers[wire]) == 1:
                name, port = drivers[wire][0]
                reason = "No unique packed FDRE Q correspondence"
                if roots and name not in roots:
                    reason = "Outside selected timing roots" if synth["cells"][name]["type"] == "FDRE" else reason
                elif port == "Q" and len(origins[name]) == 1:
                    reason = "FDRE configuration, slice control or bound port identity unqualified"
                    placed = origins[name][0]
                    candidate = fdre(synth["cells"][name], packed[placed], timing["cells"][placed], constants, driven_controls)
                    if candidate is not None:
                        candidate.update(cell=placed, original=name, pin="Q")
            bits.append({"bit": i, **(candidate or {"status": "unknown",
                         "evidence": reason})})
        result.append({"resource": resource, "net": net, "bits": bits})
    return result


def fdre(source: dict, packed: dict, native: dict, constants: dict | None = None,
         driven_controls: set | None = None) -> dict | None:
    """Admit positive-edge, non-inverted synchronous reset and connected active-high enable only."""
    attrs = packed["attributes"]
    if (source["type"] != "FDRE" or packed["type"] != "SLICE_FFX" or native["type"] != "SLICE_FFX" or
            attrs.get("X_ORIG_TYPE") != "FDRE" or attrs.get("X_FFSYNC", "").strip() != "1"):
        return None
    initial = source["parameters"].get("INIT", "0")
    if initial not in ("0", "1", "x") or packed["parameters"].get("INIT", "0") != initial:
        return None
    for params, supported in [(source["parameters"], {"IS_C_INVERTED", "IS_D_INVERTED", "IS_R_INVERTED"}),
                              (packed["parameters"], {"IS_CLK_INVERTED", "IS_D_INVERTED", "IS_SR_INVERTED"})]:
        if any(key != "INIT" and (key not in supported or set(value.strip()) != {"0"})
               for key, value in params.items()):
            return None
    roles = {"D": ("D", "register_input"), "Q": ("Q", "register_output"), "CK": ("C", "clock_input"),
             "CE": ("CE", "register_input"), "SR": ("R", "register_input")}
    local = {}
    for pin, (original, kind) in roles.items():
        row = native["ports"].get(pin, {})
        origin = attrs.get("SPACETIME_PORT_" + original)
        source_bits = source["connections"].get(original, [])
        packed_bits = packed.get("connections", {}).get(pin, [])
        idle = {"CE": "1", "SR": "0"}.get(pin)
        site = attrs.get("NEXTPNR_BEL", "").partition("/")[0]
        if (idle and source_bits == [idle] and packed.get("connections", {}).get(pin) == []
                and not row and origin and attrs.get("X_ORIG_PORT_" + pin) == original
                and site and driven_controls is not None and (site, pin) not in driven_controls):
            local[pin] = int(idle)
            continue
        tied = (pin in ("CE", "SR") and len(packed_bits) == 1 and len(source_bits) == 1
                and source_bits[0] in ("0", "1") and (constants or {}).get(packed_bits[0]) == source_bits[0])
        if (not (origin and origin == row.get("net_origin") or tied) or not row.get("wire") or not row.get("bound") or
                attrs.get("X_ORIG_PORT_" + pin) != original or row.get("bel_pin") != pin or
                row.get("class") != kind or len(source["connections"].get(original, [])) != 1):
            return None
        if kind != "clock_input" and [(c["port"], c["edge"]) for c in row["clocks"]] != [("CK", "rising")]:
            return None
    return {"local_controls": local, "status": "supported", "initial": None if initial == "x" else int(initial), "edge": "rising",
            "roles": {"d": "D", "q": "Q", "clock": "CK", "ce": None if "CE" in local else "CE",
                      "reset": None if "SR" in local else "SR"},
            "evidence": "Synthesis Q bit, pre-pack port/net origins, FDRE configuration with routed BEL-pin wires or checked slice-local control ties"}
