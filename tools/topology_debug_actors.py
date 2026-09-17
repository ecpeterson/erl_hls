"""Bind compiler projections to committed RAM writes and actor observation ports."""


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


def reduction_bits(reduction, phases, width):
    """Validate the compiler's packed projection before exposing any RAM bits."""
    selected = []
    observation_offset = 56
    sizes = {"status": (2, 2), "site": (1, 8), "key": (32, 32),
             "remaining": (1, 8), "failure": (16, 16)}
    for name, (minimum, maximum) in sizes.items():
        field = reduction["fields"][name]
        offset, size = field["offset"], field["width"]
        if (type(size) is not int or not minimum <= size <= maximum or
                type(offset) is not int or not 0 <= offset <= width-size or
                field["observation_offset"] != observation_offset):
            raise ValueError(f"invalid reduction field: {name}")
        selected.extend(range(offset, offset+size))
        observation_offset += size
    if reduction["width"] != observation_offset-56:
        raise ValueError("invalid reduction width")
    sites = reduction["sites"]
    if (not 1 <= len(sites) <= 256 or
            [s["id"] for s in sites] != list(range(len(sites))) or
            len(sites) > 1 << reduction["fields"]["site"]["width"]):
        raise ValueError("invalid reduction sites")
    for site in sites:
        population = site["population"]
        size = population["size"]
        if (site["phase"] not in phases or not isinstance(site["name"], str) or
                type(size) is not int or not 1 <= size <= 255 or
                size >= 1 << reduction["fields"]["remaining"]["width"] or
                population["mode"] not in ("count", "members")):
            raise ValueError("invalid reduction population")
        if population["mode"] == "members":
            members = population["members"]
            if (len(members) != size or len(set(members)) != size or
                    not all(type(m) is int and 0 <= m < 2**32 for m in members)):
                raise ValueError("invalid reduction members")
    return selected


def selected_fields(bank, keys):
    width, slots = bank["width"], bank["slots"]
    fields = bank["fields"]
    selected = []
    for name, size in (("phase", 8), ("enter_pending", 1), ("failure", 16)):
        field = fields[name]
        offset = field["offset"]
        if field["width"] != size or type(offset) is not int or not 0 <= offset <= width-size:
            raise ValueError(f"invalid actor field: {name}")
        selected.extend(range(offset, offset+size))
    if reduction := bank.get("reduction"):
        selected.extend(reduction_bits(reduction, bank["phases"], width))
    if len(set(selected)) != len(selected):
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
    return selected


def ram_source(bank, root, module, hierarchy, flat, clock_bit):
    slots, width = bank["slots"], bank["width"]
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
    return path, address_width, bits("wr_en") + bits("wr_addr"), bits("wr_data")


def direct_source(bank, root, module, hierarchy, flat, clock_bit):
    if bank["slots"] != 1 or "mailbox" not in bank or "ram" in bank:
        raise ValueError("invalid direct actor observation provider")
    port, width = bank["port"], bank["width"]
    matches = [(name, cell) for name, cell in module["cells"].items()
               if port in cell.get("connections", {})]
    if len(matches) != 1:
        raise ValueError("expected one generated direct actor observation output")
    name, cell = matches[0]
    app = hierarchy["modules"][cell["type"]]
    path = (*root, name)
    def bits(signal):
        return flat["netnames"][".".join((*path, signal))]["bits"]
    for signal, direction, size in ((port, "output", width),
            (port+"_vld", "output", 1), (port+"_rdy", "input", 1)):
        description = app["ports"][signal]
        if (description["direction"] != direction or len(description["bits"]) != size or
                len(cell["connections"][signal]) != size or len(bits(signal)) != size):
            raise ValueError("direct actor observation port mismatch")
    if cell["connections"][port+"_rdy"] != ["1"] or bits(port+"_rdy") != ["1"]:
        raise ValueError("direct actor observation output must always be ready")
    if bits("clk") != [clock_bit]:
        raise ValueError("direct actor observation clock mismatch")
    # One row per direct actor; its observation has no RAM address.
    return path, 1, bits(port+"_vld") + ["0"], bits(port)


def discover(projection, root, hierarchy, flat, top, clock_bit):
    shared, direct = projection.get("banks", []), projection.get("direct", [])
    if projection.get("schema") != 4 or not (shared or direct):
        raise ValueError("expected a nonempty actor projection, schema 4")
    module = hierarchy["modules"][top]
    for instance in root:
        module = hierarchy["modules"][module["cells"][instance]["type"]]
    banks, keys = [], set()
    for index, bank in enumerate(shared + direct):
        if bank["index"] != index:
            raise ValueError("actor bank indices must be contiguous")
        slots, width = bank["slots"], bank["width"]
        is_direct = index >= len(shared)
        if (type(slots) is not int or slots < 1 or type(width) is not int or
                width < (49 if is_direct else 33)):
            raise ValueError("invalid actor observation dimensions")
        selected = selected_fields(bank, keys)
        source = direct_source if is_direct else ram_source
        path, address_width, prefix, values = source(bank, root, module, hierarchy, flat, clock_bit)
        taps = prefix + [values[i] for i in selected]
        mailbox = bank.get("mailbox")
        if mailbox is not None:
            if (mailbox["width"] != 24 or not 1 <= mailbox["capacity"] <= 255 or
                    mailbox["kind"] != ("direct" if is_direct else "shared")):
                raise ValueError("invalid mailbox projection")
            if is_direct:
                offset = mailbox["offset"]
                if (type(offset) is not int or not 0 <= offset <= width-24 or
                        set(selected).intersection(range(offset, offset+24)) or
                        len(selected) + 24 != width):
                    raise ValueError("invalid direct mailbox fields")
                # Both halves are one publication, retained on the same edge.
                taps += prefix[:1] + values[offset:offset+24]
            else:
                taps += mailbox_source(mailbox["port"], slots, root, module,
                                       hierarchy, flat, clock_bit)
        banks.append(dict(bank, path=list(path), address_width=address_width, taps=taps))
    return banks


def mailbox_source(port, slots, root, module, hierarchy, flat, clock_bit):
    matches = [(name, cell) for name, cell in module["cells"].items()
               if port in cell.get("connections", {})]
    if len(matches) != 1:
        raise ValueError("expected one generated mailbox observation output")
    name, cell = matches[0]
    app = hierarchy["modules"][cell["type"]]
    def observed(signal):
        return flat["netnames"][".".join((*root, name, signal))]["bits"]
    for signal, direction, size in ((port, "output", 24*slots),
            (port+"_vld", "output", 1), (port+"_rdy", "input", 1)):
        description = app["ports"][signal]
        if (description["direction"] != direction or len(description["bits"]) != size or
                len(cell["connections"][signal]) != size or len(observed(signal)) != size):
            raise ValueError("mailbox observation port mismatch")
    if cell["connections"][port+"_rdy"] != ["1"] or observed(port+"_rdy") != ["1"]:
        raise ValueError("mailbox observation output must always be ready")
    if observed("clk") != [clock_bit]:
        raise ValueError("mailbox observation clock mismatch")
    return observed(port+"_vld") + observed(port)


def resources(banks, first_id):
    return [dict(actor, id=first_id+i, kind="actor", width=56+bank["reduction"]["width"] if "reduction" in bank else (56 if "mailbox" in bank else 26),
                 **({"reduction": bank["reduction"]} if "reduction" in bank else {}), bank=bank["index"],
                 **({"mailbox_capacity": bank["mailbox"]["capacity"], "mailbox_kind": bank["mailbox"]["kind"]} if "mailbox" in bank else {}),
                 module=bank["module"], phases=bank["phases"], failures=bank["failures"])
            for i, (bank, actor) in enumerate((bank, actor) for bank in banks for actor in bank["actors"])]


def wrapper(banks, first_id, clock, reset, active_low):
    """Select physical probes or one row per actor bank at the query address.

    Keeping actor rows behind an indexed read port permits memory inference;
    exporting every row as a separate wire would turn the store into registers.
    """
    offset, resource = 0, first_id
    lines = ["wire [31:0] probe_address;\nwire [127:0] probe_value;\n"]
    selected = [f"(probe_address < 32'd{first_id} ? probe_values[probe_address*64 +: 64] : 128'b0)"]
    for bank in banks:
        index, slots = bank["index"], bank["slots"]
        address_width = bank["address_width"]
        reduction_width = bank.get("reduction", {}).get("width", 0)
        write_width = 25 + reduction_width
        mailbox_offset = offset + 1 + address_width + write_width
        mailbox_valid = f"actor_writes[{mailbox_offset}]" if "mailbox" in bank else "1'b0"
        mailbox_values = f"actor_writes[{mailbox_offset+1} +: {24*bank['slots']}]" if "mailbox" in bank else "'0"
        # Decode the full resource ID, but subtract only the low row-address
        # bits. A 32-bit subtract per bank needlessly lengthens the query path.
        row_base = resource % (1 << address_width)
        lines.append(f"wire [{address_width-1}:0] actor_address_{index} = "
                     f"probe_address[{address_width-1}:0] - {address_width}'d{row_base};\n"
                     f"wire [127:0] actor_value_{index};\n"
                     f"hls_actor_snapshot #(.SLOTS({slots}), .ADDRESS_WIDTH({address_width}), "
                     f".MAILBOX({int('mailbox' in bank)}), .REDUCTION_WIDTH({reduction_width})) "
                     f"snapshot_{bank['index']} (.clk(\\{clock} ), "
                     f".reset({'!' if active_low else ''}\\{reset} ), "
                     f".write_enable(actor_writes[{offset}]), "
                     f".write_address(actor_writes[{offset+1} +: {address_width}]), "
                     f".write_value(actor_writes[{offset+1+address_width} +: {write_width}]), "
                     f".mailbox_valid({mailbox_valid}), .mailbox_values({mailbox_values}), "
                     f".read_address(actor_address_{index}), "
                     f".value(actor_value_{index}));\n")
        selected.append(f"(probe_address >= 32'd{resource} && probe_address < 32'd{resource+slots} "
                        f"? actor_value_{index} : 128'b0)")
        offset += len(bank["taps"])
        resource += bank["slots"]
    lines.append("assign probe_value = " + " |\n    ".join(selected) + ";\n")
    return "".join(lines)
