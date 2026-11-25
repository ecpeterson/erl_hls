"""Recover the selected four-Phi RAM launch and multiplier from the archived routed Vivado reports."""

import re
from pathlib import Path

from replay import SELECTED_BIT, require

REGISTERS = ("AREG", "BREG", "MREG", "PREG")
RAM = "decoder/scheduler_2_state/memory_reg_1"
EXECUTOR = (
    "decoder/application/__phi_decoder_profile_topology__SchedulerGrid_0_next_inst/"
    "__phi_halo_cell__SharedService_0__2_2_2_2_next_inst/__phi_halo_cell__SharedExecutor_0_next_inst"
)


def properties(report: str) -> dict:
    """Index the per-cell report_property blocks by their unique full instance name."""
    cells = {}
    for block in re.split(
        r"^Property\s+Type\s+Read-only\s+Value\s*$", report, flags=re.M
    )[1:]:
        values = dict(
            re.findall(
                r"^([A-Z0-9_]+)[ \t]+\S+[ \t]+(?:true|false)[ \t]+([^\n]*?) *$",
                block,
                re.M,
            )
        )
        name = values["NAME"]
        require(name not in cells, f"duplicate property block {name}")
        cells[name] = values
    return cells


def module(netlist: str, name: str) -> str:
    """Select the uniquely named module definition in the pinned write_verilog output."""
    matches = re.findall(
        rf"^module {re.escape(name)}(?=[\s(]).*?^endmodule", netlist, re.M | re.S
    )
    require(len(matches) == 1, f"nonunique module {name}")
    return matches[0]


def placed_path(directory: Path, source: Path) -> dict:
    """Cross-check logical bus slices, placed primitive properties and one reported setup path."""
    xdc = (directory / "effective.xdc").read_text().splitlines()
    for line in (
        "create_clock -period 20.000 -name workload [get_ports clock]",
        "set_property PACKAGE_PIN Y14 [get_ports clock]",
        "set_property PACKAGE_PIN V13 [get_ports activity]",
    ):
        require(line in xdc, "Vivado constraint mismatch")
    rtl = module(source.read_text(), "__phi_halo_cell__SharedExecutor_0_next")
    require(
        "assign rounded__3 = {add_164502, magnitude__3[0]};" in rtl
        and "assign umul_164656 = umul76b_38b_x_38b(rounded__3, 38'h2a_aaaa_aaab);"
        in rtl,
        "source partial-product operand",
    )
    netlist = (directory / "routed.v").read_text()
    wrapper = module(netlist, "phi_decoder_profile_top")
    declaration = re.search(r"(\w+) scheduler_2_state\s+\((.*?)\);", wrapper, re.S)
    require(
        declaration is not None
        and ".rd_data(scheduler_2_state_rd_data)" in declaration[2]
        and ".wr_data(scheduler_2_state_wr_data)" in declaration[2],
        "Vivado state bus",
    )
    ram = module(netlist, declaration[1])
    instance = re.search(r"\n    memory_reg_1\s+\((.*?)\);", ram, re.S)[1]
    for port, signal in [("DOADO", "rd_data"), ("DIADI", "wr_data")]:
        bus = re.search(rf"\.{port}\({signal}\[(\d+):(\d+)\]\)", instance)
        require(
            bus is not None
            and int(bus[1]) - int(bus[2]) == 31
            and int(bus[2]) + 12 == SELECTED_BIT,
            f"Vivado {port} bit correspondence",
        )
    data = properties((directory / "hard-primitives.rpt").read_text())
    modes = data[RAM]
    require(
        all(
            modes[k] == v
            for k, v in dict(
                RAM_MODE="SDP",
                WRITE_MODE_A="READ_FIRST",
                WRITE_MODE_B="READ_FIRST",
                DOA_REG="0",
                DOB_REG="0",
                READ_WIDTH_A="72",
            ).items()
        ),
        "Vivado RAM mode",
    )
    blocks = re.split(
        r"(?=^Slack \()", (directory / "setup-paths.rpt").read_text(), flags=re.M
    )[1:]
    block = next(
        b
        for b in blocks
        if f"Source:                 {RAM}/CLKARDCLK" in b
        and f"{RAM}/DOADO[12]" in b
        and "DSP48E1" in b
    )
    require("Setup (Max at Slow Process Corner)" in block, "Vivado setup corner")
    # Each Prop row names the cell's input and output. Long rows wrap before the pin name.
    visits = re.finditer(
        r"^\s*(\w+_X\d+Y\d+)\s+(\w+) \(Prop_\w+?_([A-Za-z0-9\[\]]+)_([A-Za-z0-9\[\]]+)\)"
        r"\s+[\d.]+\s+[\d.]+\s+[rf]\s+([^\s]+)",
        block,
        re.M,
    )
    executor = module(netlist, "__phi_halo_cell__SharedExecutor_0_next")
    # Both input slices are checked on the path. Inventory the remaining partial products
    # with the same rounded__3 adder output on A or B, excluding unrelated multipliers.
    product = []
    for cell, ports in re.findall(
        r"DSP48E1 #\(.*?\)\s+(\w+)\s+\((.*?)\);", executor, re.S
    ):
        operands = re.findall(r"\.[AB]\(([^)]*)\)", ports)
        if not any("add_164502[" in operand for operand in operands):
            continue
        props = data[EXECUTOR + "/" + cell]
        require(
            ".CLK(1'b0)" in ports and all(props[k] == "0" for k in REGISTERS),
            "product DSP register",
        )
        product.append(
            dict(
                cell=EXECUTOR + "/" + cell,
                kind="DSP48E1",
                site=props["LOC"],
                bel=props["BEL"],
                stages={k: int(props[k]) for k in REGISTERS},
            )
        )
    path = []
    previous_end = None
    for entry in visits:
        site, kind, incoming, outgoing, endpoint = entry.groups()
        name, pin = endpoint.rsplit("/", 1)
        if not path and name != RAM:
            continue
        require(outgoing == pin, f"reported primitive pin {endpoint}")
        step = dict(cell=name, kind=kind, site=site, input=incoming, output=outgoing)
        if name in data:
            require(data[name]["LOC"] == site, "report site mismatch")
            step["bel"] = data[name]["BEL"]
        if previous_end is not None:
            section = block[previous_end : entry.start()]
            nets = re.findall(
                r"^\s*net \(fo=\d+, routed\)\s+[\d.]+\s+[\d.]+\s+(\S+)", section, re.M
            )
            require(
                len(nets) == 1 and "(Prop_" not in section,
                "unsupported intermediate Vivado path step",
            )
            step["net"] = nets[0]
        previous_end = entry.end()
        if kind == "DSP48E1":
            require(
                name.startswith(EXECUTOR + "/") and data[name]["LOC"] == site,
                "DSP instance placement",
            )
            dsp = re.search(
                rf"\n    {re.escape(name.split('/')[-1])}\s+\((.*?)\);",
                executor,
                re.S,
            )[1]
            require(
                ".CLK(1'b0)" in dsp and "add_164502[" in dsp, "DSP operand or clock"
            )
            step["stages"] = {key: int(data[name][key]) for key in REGISTERS}
            step["clock"] = "constant low"
        path.append(step)
        if kind == "DSP48E1" and incoming.startswith("PCIN"):
            break
    require(
        path
        and path[0]["site"] == modes["LOC"]
        and path[0]["output"] == "DOADO[12]"
        and [s["kind"] for s in path[-2:]] == ["DSP48E1", "DSP48E1"]
        and path[-2]["output"] == "PCOUT[47]"
        and path[-1]["input"] == "PCIN[47]",
        "incomplete Vivado RAM to DSP cascade",
    )
    return dict(
        backend="Vivado",
        basis="reported setup path",
        path=path,
        ramMode="SDP72 READ_FIRST, DO_REG=0",
        productDsps=sorted(product, key=lambda s: s["cell"]),
        workloadPREG=sum(
            p.get("REF_NAME") == "DSP48E1" and p["PREG"] == "1" for p in data.values()
        ),
        slackNs=float(re.search(r"Slack \(MET\)\s*:\s*([\d.]+)ns", block)[1]),
        fullDataDelayNs=float(re.search(r"Data Path Delay:\s*([\d.]+)ns", block)[1]),
        hardCells={
            k: sum(v.get("REF_NAME") == k for v in data.values())
            for k in ("DSP48E1", "RAMB18E1", "RAMB36E1")
        },
    )
