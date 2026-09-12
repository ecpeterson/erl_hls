"""Bind compiler projections to the public write ports of scheduler state RAMs."""


def check_write_contract(module):
    """Require the actual memory write to accept precisely wr_en at posedge clk.

    Yosys proc introduces muxes with don't-care disabled address/data arms.
    Resolve those arms under wr_en rather than relying on internal signal names.
    """
    ports, cells = module["ports"], list(module.get("cells", {}).values())
    writes = [c for c in cells if c["type"].startswith("$memwr")]
    if len(writes) != 1 or writes[0]["type"] != "$memwr_v2":
        raise ValueError("unsupported state RAM write implementation")
    write = writes[0]
    parameters, connections = write["parameters"], write["connections"]
    if (int(parameters["CLK_ENABLE"], 2) != 1 or int(parameters["CLK_POLARITY"], 2) != 1 or
            connections["CLK"] != ports["clk"]["bits"]):
        raise ValueError("state RAM write clock mismatch")
    def selected(bits, enabled):
        seen = set()
        while tuple(bits) not in seen:
            seen.add(tuple(bits))
            muxes = [c["connections"] for c in cells if c["type"] == "$mux" and
                     c["connections"]["Y"] == bits and c["connections"]["S"] == ports["wr_en"]["bits"]]
            if not muxes:
                return bits
            bits = muxes[0]["B" if enabled else "A"]
        raise ValueError("cyclic RAM write logic")
    width = len(ports["wr_data"]["bits"])
    memory = module.get("memories", {}).get(parameters["MEMID"].lstrip("\\"), {})
    if (memory.get("width") != width or memory.get("size") != 1 << len(ports["wr_addr"]["bits"]) or
            memory.get("start_offset") != 0):
        raise ValueError("state RAM memory dimensions mismatch")
    if (selected(connections["ADDR"], True) != ports["wr_addr"]["bits"] or
            selected(connections["DATA"], True) != ports["wr_data"]["bits"] or
            selected(connections["EN"], True) != ["1"]*width or
            selected(connections["EN"], False) != ["0"]*width):
        raise ValueError("state RAM accepted-write contract mismatch")


def discover(projection, root, hierarchy, flat, top, clock_bit):
    if projection.get("schema") != 2 or not projection.get("banks"):
        raise ValueError("expected a nonempty scheduler projection, schema 2")
    module = hierarchy["modules"][top]
    for instance in root:
        module = hierarchy["modules"][module["cells"][instance]["type"]]
    banks, keys = [], set()
    for index, bank in enumerate(projection["banks"]):
        if bank["index"] != index:
            raise ValueError("scheduler bank indices must be contiguous")
        slots, width = bank["slots"], bank["width"]
        if type(slots) is not int or slots < 1 or type(width) is not int or width < 33:
            raise ValueError("invalid scheduler RAM dimensions")
        address_width = max(1, (slots - 1).bit_length())
        path = (*root, bank["ram"])
        ram = hierarchy["modules"][module["cells"][bank["ram"]]["type"]]
        if ram.get("attributes", {}).get("hdlname", "").removeprefix("\\") != "hls_1r1w_ram":
            raise ValueError(f"unsupported state RAM at {'.'.join(path)}")
        check_write_contract(ram)
        expected = {"clk": ("input", 1), "wr_en": ("input", 1),
                    "wr_addr": ("input", address_width), "wr_data": ("input", width)}
        def bits(name):
            return flat["netnames"][".".join((*path, name))]["bits"]
        for name, (direction, size) in expected.items():
            port = ram["ports"][name]
            if port["direction"] != direction or len(port["bits"]) != size or len(bits(name)) != size:
                raise ValueError(f"state RAM port mismatch: {'.'.join(path)}.{name}")
        if bits("clk") != [clock_bit]:
            raise ValueError("state RAM is in a different clock domain")
        fields = bank["fields"]
        selected = []
        for name, size in (("phase", 8), ("enter_pending", 1), ("failure", 16)):
            field = fields[name]
            offset = field["offset"]
            if field["width"] != size or type(offset) is not int or not 0 <= offset <= width-size:
                raise ValueError(f"invalid actor field: {name}")
            selected.extend(range(offset, offset+size))
        if len(set(selected)) != 25:
            raise ValueError("overlapping actor fields")
        phases = bank["phases"]
        if not 1 <= len(phases) <= 256 or len(set(phases)) != len(phases) or not all(isinstance(p, str) for p in phases):
            raise ValueError("invalid phase codebook")
        if [a["slot"] for a in bank["actors"]] != list(range(slots)):
            raise ValueError("actor slots must cover the bank exactly")
        for actor in bank["actors"]:
            key = actor["key"]
            if len(key) != 64 or any(c not in "0123456789abcdef" for c in key) or key in keys:
                raise ValueError("invalid or duplicate actor identity")
            keys.add(key)
        taps = bits("wr_en") + bits("wr_addr") + [bits("wr_data")[i] for i in selected]
        banks.append(dict(bank, path=list(path), address_width=address_width, taps=taps))
    return banks


def resources(banks, first_id):
    return [dict(actor, id=first_id+i, kind="actor", width=26, bank=bank["index"],
                 module=bank["module"], phases=bank["phases"], failures=bank["failures"])
            for i, (bank, actor) in enumerate((bank, actor) for bank in banks for actor in bank["actors"])]


def wrapper(banks, first_id, clock, reset, active_low):
    offset, resource = 0, first_id
    lines = []
    for bank in banks:
        address_width = bank["address_width"]
        lines.append(f"hls_actor_snapshot #(.SLOTS({bank['slots']}), .ADDRESS_WIDTH({address_width})) "
                     f"snapshot_{bank['index']} (.clk(\\{clock} ), "
                     f".reset({'!' if active_low else ''}\\{reset} ), "
                     f".write_enable(actor_writes[{offset}]), "
                     f".write_address(actor_writes[{offset+1} +: {address_width}]), "
                     f".write_value(actor_writes[{offset+1+address_width} +: 25]), "
                     f".values(probe_values[{resource*32} +: {bank['slots']*32}]));\n")
        offset += len(bank["taps"])
        resource += bank["slots"]
    return "".join(lines)
