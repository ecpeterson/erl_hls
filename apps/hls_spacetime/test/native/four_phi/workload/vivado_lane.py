"""Qualify the two-worker Vivado state lane against its RAM wiring, routed pin arcs and settled samples."""

import re
from collections import defaultdict, deque
from pathlib import Path

from execution import CYCLES, require
from vivado import module, properties


def state_path(vendor: Path, cells: list, nets: list, arcs: list) -> dict:
    """Follow state bit 84 to the nearest combinational executor DSP across at most one FDRE capture."""
    names, kinds = zip(*cells)
    text = (vendor / "routed.v").read_text()
    wrapper = module(text, "phi_decoder_profile_top")
    ram = re.search(r"(\w+) scheduler_1_state\s+\((.*?)\);", wrapper, re.S)
    require(
        ram and ".rd_data(scheduler_1_state_rd_data)" in ram[2],
        "scheduler state read bus",
    )
    drivers = [
        (instance, 84 - int(low))
        for instance, ports in re.findall(
            r"\n    (memory_reg\w*)\s+\((.*?)\);", module(text, ram[1]), re.S
        )
        for high, low in re.findall(r"\.DOADO\(rd_data\[(\d+):(\d+)\]\)", ports)
        if int(low) <= 84 <= int(high)
    ]
    require(len(drivers) == 1, "state bit 84 RAM output")
    instance, bit = drivers[0]
    src = names.index("decoder/scheduler_1_state/" + instance), f"DOADO[{bit}]"
    props = properties((vendor / "hard-primitives.rpt").read_text())
    require(props[names[src[0]]]["DOA_REG"] == "0", "selected RAM output mode")
    targets = {
        i
        for i, (n, k) in enumerate(cells)
        if k == "DSP48E1"
        and "/__phi_halo_cell__SharedExecutor" in n
        and re.search(r"/smul\w+_return(?:__\d+)?$", n)
        and all(props[n][r] == "0" for r in ("AREG", "BREG", "MREG", "PREG"))
    }
    graph, ff, launches = defaultdict(list), {}, []
    for i, (a, b, _, _) in enumerate(nets + arcs):
        k = kinds[a[0]]
        if b == src and a == (src[0], "CLKARDCLK"):
            launches.append(i)
        if i < len(nets) or k.startswith(("LUT", "CARRY", "MUXF")):
            graph[a].append((b, i))
        elif k == "FDRE" and a[1] == "C" and b[1] == "Q":
            ff[(a[0], "D")] = (b, i)
    require(len(launches) == 1, "state RAM clock launch")
    for allow_capture in (False, True):
        root = (src, False)
        parents = {root: None}
        queue = deque([root])
        while queue:
            pin, crossed = key = queue.popleft()
            if pin[0] in targets and re.fullmatch(r"[AB]\[\d+\]", pin[1]):
                trail = []
                while parents[key] is not None:
                    key, row, boundary = parents[key]
                    trail.append((row, boundary))
                segments = [launches.copy()]
                probes = {
                    "ram": [names[src[0]], src[1]],
                    "dsp": [names[pin[0]], pin[1]],
                }
                for row, boundary in reversed(trail):
                    if boundary:
                        segments.append([])
                        dst = arcs[row - len(nets)][1]
                        probes["q"] = [names[dst[0]], dst[1]]
                    segments[-1].append(row)
                return dict(segments=segments, probes=probes)
            for dest, row in graph[pin]:
                key = (dest, crossed)
                if key not in parents:
                    parents[key] = ((pin, crossed), row, False)
                    queue.append(key)
            if allow_capture and not crossed and pin in ff:
                dest, row = ff[pin]
                if (dest, True) not in parents:
                    parents[dest, True] = ((pin, False), row, True)
                    queue.append((dest, True))
    raise ValueError("no state RAM to executor operand path within one capture")


def monitor(probes: dict) -> str:
    """Sample the three named mapped pins and the FDRE controls on the functional harness clocks."""
    require(
        "q" in probes, "expected one intervening register in the two-worker witness"
    )

    def ref(cell: str, pin: str) -> str:
        """Escape each Verilog hierarchy element independently, including bus-like instance names."""
        require(
            not re.search(r"\s", cell) and re.fullmatch(r"\w+(?:\[\d+\])?", pin),
            "mapped pin name",
        )
        return (
            "functional_tb.dut."
            + ".".join("\\" + s + " " for s in cell.split("/"))
            + "."
            + pin
        )

    register = probes["q"][0]
    return f"""`timescale 1ns/1ps
module state_lane; integer c=0; reg d,ce,r;
always @(posedge functional_tb.clock) begin
  d={ref(register, "D")}; ce={ref(register, "CE")}; r={ref(register, "R")};
  #2; $display("STATE %0d %b %b %b %b %b %b", c, {ref(*probes["ram"])}, d,ce,r, {ref(*probes["q"])}, {ref(*probes["dsp"])});
  c=c+1;
end endmodule
"""


def changes(work: Path, native_work: Path) -> dict:
    """Check known logical RAM reads and pre-edge FDRE captures, then return known adjacent transitions."""

    def rows(file: Path, prefix: str) -> list:
        """Require exactly one named measurement per clock in order."""
        result = [
            s.split()[1:]
            for s in file.read_text().splitlines()
            if s.startswith(prefix + " ")
        ]
        require(
            [int(r[0]) for r in result] == list(range(CYCLES)),
            prefix + " sample clocks",
        )
        return result

    vendor = rows(work / "vivado-sim-guard/console.log", "STATE")
    rtl = rows(native_work / "rtl-sim-guard/console.log", "LANE")
    transitions = {k: [] for k in ("ram", "q", "dsp")}
    known = 0
    for i, ((_, ram, d, ce, r, q, dsp), reference) in enumerate(
        zip(vendor, rtl, strict=True)
    ):
        if reference[1] in ("0", "1"):
            require(ram == reference[1], "Vivado RAM bit 84 at C" + str(i))
            known += 1
        expected = "x"
        if r == "1":
            expected = "0"
        elif r == "0" and ce == "1":
            expected = d
        elif i and r == "0" and ce == "0":
            expected = vendor[i - 1][5]
        if expected in ("0", "1"):
            require(q == expected, "Vivado FDRE capture at C" + str(i))
        if i:
            for k, j, now in (("ram", 1, ram), ("q", 5, q), ("dsp", 6, dsp)):
                if {vendor[i - 1][j], now} == {"0", "1"}:
                    transitions[k].append(i)
    require(known and all(transitions.values()), "inactive selected pin")
    return dict(knownRamClocks=known, transitions=transitions)
