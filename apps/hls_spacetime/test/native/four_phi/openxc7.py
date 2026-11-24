"""Trace a selected RAM bit to a DSP contributing to the observed product in the XC7 implementation."""

import json
import re
from collections import Counter, defaultdict, deque
from collections.abc import Iterator
from pathlib import Path

from replay import FACTOR, SELECTED_BIT, require
from vivado import EXECUTOR, REGISTERS


def pins(cell: dict, direction: str) -> Iterator[tuple[str, int, int]]:
    """Yield connected, nonconstant pins as (port, lane, net) from Yosys or nextpnr JSON."""
    for port, bits in cell["connections"].items():
        if cell["port_directions"][port] == direction:
            for lane, bit in enumerate(bits):
                if isinstance(bit, int):
                    yield port, lane, bit


def logic_arc(cell: dict, src: str, sink: str) -> bool:
    """Admit structural LUT, carry and mux arcs; stop at registers and memory boundaries."""
    attrs = cell["attributes"]
    kind = attrs.get("X_ORIG_TYPE", cell["type"])
    src = attrs.get("X_ORIG_PORT_" + src, src)
    sink = attrs.get("X_ORIG_PORT_" + sink, sink)
    if "X_LUT_AS_DRAM" in attrs or "X_LUT_AS_SRL" in attrs:
        return False
    if re.fullmatch(r"LUT[1-6]", kind):
        return bool(re.fullmatch(r"I[0-5]", src)) and sink == "O"
    if kind in ("MUXF7", "MUXF8"):
        return src in ("S", "I0", "I1") and sink == "O"
    if kind == "INV":
        return src == "I" and sink == "O"
    if kind != "CARRY4":
        return False
    out = re.fullmatch(r"(CO|O)\[([0-3])\]", sink)
    if not out:
        return False
    if src in ("CI", "CYINIT"):
        return True
    inp = re.fullmatch(r"(DI|S)\[([0-3])\]", src)
    return bool(
        inp
        and (
            inp[2] < out[2] or (inp[2] == out[2] and (inp[1] == "S" or out[1] == "CO"))
        )
    )


def product_dsps(lowered: dict, mapped: dict) -> set[str]:
    """Join the exact lowered multiply to the partial-product cells created by Yosys mul2dsp."""
    prefix = EXECUTOR.replace("/", ".") + "."
    nets = lowered["netnames"]
    inputs = nets[prefix + "rounded__3"]["bits"]
    outputs = nets[prefix + "umul_164656"]["bits"]
    factor = list(reversed(f"{FACTOR:038b}"))
    sources = [
        n
        for n, c in lowered["cells"].items()
        if c["type"] == "$mul"
        and c["connections"] == {"A": inputs, "B": factor, "Y": outputs}
    ]
    require(len(sources) == 1, "ambiguous lowered multiply")
    dsps = {
        n
        for n, c in mapped["cells"].items()
        if c["type"] == "DSP48E1"
        and n.startswith(sources[0] + ".genblk")
        and "mul2dsp.v:" in c["attributes"].get("src", "")
    }
    require(bool(dsps), "no mapped partial products for the observed multiply")
    return dsps


def memory_pin(module: dict) -> tuple[str, str]:
    """Identify the unique RAM read output driving the selected logical lane."""
    nets = module["netnames"]
    q = nets["decoder.scheduler_2_state.rd_data"]["bits"][SELECTED_BIT]
    require(
        q == nets["decoder.scheduler_2_state_rd_data"]["bits"][SELECTED_BIT],
        "RAM alias mismatch",
    )
    matches = []
    for name, cell in module["cells"].items():
        if cell["type"] not in ("RAMB18E1", "RAMB36E1"):
            continue
        for port, lane, net in pins(cell, "output"):
            if net == q:
                require(port == "DOADO", "unexpected RAM output bank")
                matches.append((name, f"{port}[{lane}]"))
    require(len(matches) == 1, "ambiguous synthesis RAM output")
    return matches[0]


def connected_path(
    module: dict, ram: str, original: str, targets: set[str]
) -> list[dict]:
    """Walk directed packed nets and combinational pin arcs to the nearest qualified DSP operand."""
    cells = module["cells"]
    block = cells[ram]
    outputs = [
        p
        for p, _, _ in pins(block, "output")
        if block["attributes"].get("X_ORIG_PORT_" + p) == original
    ]
    require(len(outputs) == 1, "packed BRAM output correspondence")
    root = (ram, outputs[0])
    users = defaultdict(list)
    for name, cell in cells.items():
        for port, _, bit in pins(cell, "input"):
            users[bit].append((name, port))
    queue = deque([root])
    parents = {root: None}
    while queue:
        prev = queue.popleft()
        (bit,) = cells[prev[0]]["connections"][prev[1]]
        for name, inp in users[bit]:
            cell = cells[name]
            if name in targets and re.fullmatch(r"[AB]\d+", inp):
                path = [(name, inp, None)]
                while prev != root:
                    last, entered = parents[prev]
                    path.append((prev[0], entered, prev[1]))
                    prev = last
                path.append((ram, None, root[1]))
                steps = [visit(cells[n], n, i, o) for n, i, o in reversed(path)]
                netnames = defaultdict(list)
                for signal, net in module["netnames"].items():
                    if len(net["bits"]) == 1:
                        netnames[net["bits"][0]].append(signal)
                for left, right in zip(steps, steps[1:]):
                    (bit,) = cells[left["cell"]]["connections"][left["output"]]
                    require(
                        [bit] == cells[right["cell"]]["connections"][right["input"]],
                        "packed net mismatch",
                    )
                    require(len(netnames[bit]) == 1, "ambiguous packed net name")
                    right["net"] = netnames[bit][0]
                return steps
            for out, _, _ in pins(cell, "output"):
                node = name, out
                if node not in parents and logic_arc(cell, inp, out):
                    parents[node] = (prev, inp)
                    queue.append(node)
    raise ValueError("no packed RAM-to-product DSP path")


def visit(cell: dict, name: str, inp: str | None, out: str | None) -> dict:
    """Retain the placed BEL and the connected input/output pipeline configuration."""
    site, bel = cell["attributes"]["NEXTPNR_BEL"].split("/")
    row = dict(cell=name, kind=cell["type"], site=site, bel=bel, input=inp, output=out)
    if cell["type"] == "DSP48E1_DSP48E1":
        row["stages"] = {key: int(cell["parameters"][key], 2) for key in REGISTERS}
    return row


def placed_path(directory: Path, mode: str) -> dict:
    """Cross-check synthesis lane, packed cell, source port, checkpoint stage and connectivity."""
    synth = json.loads((directory / "synth.json").read_bytes())["modules"][
        "phi_timing_harness"
    ]
    ram, original = memory_pin(synth)
    lowered = json.loads((directory / "lowered.json").read_bytes())["modules"][
        "phi_timing_harness"
    ]
    dsps = product_dsps(lowered, synth)
    del lowered
    clocks = {n: synth["cells"][n]["connections"]["CLK"] for n in dsps}
    counts = Counter(c["type"] for c in synth["cells"].values())
    srl_addresses = [
        bits
        for cell in synth["cells"].values()
        if cell["type"] in ("SRL16E", "SRLC32E")
        for port, bits in cell["connections"].items()
        if port.startswith("A")
    ]
    fixed_taps = all(b in ("0", "1") for address in srl_addresses for b in address)
    del synth
    require(mode in ("placed", "routed"), "unknown native checkpoint stage")
    checkpoint = directory / f"{mode}.json"
    require(checkpoint.stat().st_size <= 512 << 20, "native checkpoint byte limit")
    (packed,) = json.loads(checkpoint.read_bytes())["modules"].values()
    require(all(n in packed["cells"] for n in dsps), "DSP identity lost in packing")
    for name, pin in (("clock", "Y14"), ("activity", "V13")):
        pad = packed["cells"][name]
        attrs = pad["attributes"]
        require(
            pad["type"] == "PAD"
            and attrs["LOC"] == attrs["PACKAGE_PIN"] == pin
            and attrs["NEXTPNR_BEL"].endswith("/PAD"),
            f"native package pin {name}",
        )
    settings = packed["settings"]
    require(
        bool(int(settings.get("route", "0"), 2)) == (mode == "routed")
        and float(settings["target_freq"]) == 50e6
        and int(settings["seed.arg"], 2) == 1
        and settings["placer"] == "heap"
        and settings["router"] == "router2",
        "native route or clock constraint",
    )
    path = connected_path(packed, ram, original, dsps)
    grounds = {
        bit
        for cell in packed["cells"].values()
        if cell["type"] == "PSEUDO_GND"
        for _, _, bit in pins(cell, "output")
    }
    product = []
    for name in dsps:
        cell = packed["cells"][name]
        require(
            cell["type"] == "DSP48E1_DSP48E1"
            and clocks[name] == ["0"]
            and len(cell["connections"]["CLK"]) == 1
            and cell["connections"]["CLK"][0] in grounds
            and all(int(cell["parameters"][k], 2) == 0 for k in REGISTERS),
            "partial-product DSP register",
        )
        product.append(visit(cell, name, None, None))
    dsp = path[-1]
    dsp["clock"] = "constant low"
    modes = packed["cells"][ram]["parameters"]
    require(
        modes["RAM_MODE"] == "SDP"
        and modes["WRITE_MODE_A"] == modes["WRITE_MODE_B"] == "READ_FIRST"
        and int(modes["DOA_REG"], 2) == int(modes["DOB_REG"], 2) == 0,
        "packed RAM mode",
    )
    return dict(
        backend="openXC7",
        basis=f"{mode} netlist connectivity",
        path=path,
        ramMode=f"SDP{int(modes['READ_WIDTH_A'], 2)} READ_FIRST, DO_REG=0",
        fixedSrlTaps=fixed_taps,
        productDsps=sorted(product, key=lambda s: s["cell"]),
        workloadPREG=sum(
            int(c["parameters"]["PREG"], 2)
            for c in packed["cells"].values()
            if c["type"] == "DSP48E1_DSP48E1"
        ),
        hardCells={
            k: counts[k]
            for k in ("DSP48E1", "RAMB18E1", "RAMB36E1", "SRL16E", "SRLC32E")
        },
    )
