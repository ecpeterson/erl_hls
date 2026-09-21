#!/usr/bin/env python3
"""Exercise native patches using retained Ethernet netlists, with deterministic native packing/routing."""

import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from gtx.coverage import enabled_features

PREFIX = "GTX_COMMON_X186Y23."
SWING = PREFIX + "GTXE2_COMMON.IBUFDS_GTE2.CLKSWING_CFG"


def run(backend: Path, chipdb: Path, netlist: dict, directory: Path, route: bool) -> dict:
    """Run packing or deterministic routing and retain each input/output."""
    directory.mkdir(parents=True)
    source = directory / "input.json"
    source.write_text(json.dumps(netlist))
    constraints = (Path(__file__).resolve().parent.parent / "ethernet/te0715_ethernet.xdc").read_text()
    cells = netlist["modules"]["te0715_ethernet_top"]["cells"]
    if any(cell["type"].startswith("PLLE2") for cell in cells.values()):
        constraints = constraints.replace("MMCME2_ADV", "PLLE2_ADV")
    xdc = directory / "constraints.xdc"
    xdc.write_text(constraints)
    command = [str(backend), "--chipdb", str(chipdb), "--json", str(source), "--xdc", str(xdc),
               "--write", str(directory / "output.json"), "--timing-allow-fail"]
    command += (["--fasm", str(directory / "output.fasm"), "--seed", "1", "--router", "router2",
                 "--freq", "125"]
                if route else ["--pack-only"])
    with (directory / "tool.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    return json.loads((directory / "output.json").read_text())


def check(backend: Path, chipdb: Path, stage: Path, output: Path) -> dict:
    """Check omitted/explicit refclock settings and BASE versus ADV clock retention.

    Non-default buffer settings are inert writer tests, never board candidates.
    The input stage must contain netlist.json and probe.fasm from
    ethernet/board.py; output must be new so failures cannot reuse old evidence.
    """
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    source = json.loads((stage / "netlist.json").read_text())
    original_features = {f for f in enabled_features((stage / "probe.fasm").read_text()) if f.startswith(PREFIX)}
    cases = 0
    for swing, cm, trst in ((None, True, True), (0, True, True), (1, True, True),
                             (2, True, True), (3, True, True), (3, False, True), (3, True, False)):
        changed = copy.deepcopy(source)
        cells = changed["modules"]["te0715_ethernet_top"]["cells"]
        buffer, = [c for c in cells.values() if c["type"] == "IBUFDS_GTE2"]
        buffer["parameters"] = {"CLKCM_CFG": "TRUE" if cm else "FALSE", "CLKRCV_TRST": "TRUE" if trst else "FALSE"}
        if swing is not None:
            buffer["parameters"]["CLKSWING_CFG"] = f"{swing:02b}"
        directory = output / f"refclk-{swing}-{int(cm)}-{int(trst)}"
        run(backend, chipdb, changed, directory, True)
        actual = {f for f in enabled_features((directory / "output.fasm").read_text()) if f.startswith(PREFIX)}
        modified = {SWING + "[0]", SWING + "[1]", PREFIX + "IBUFDS_GTE2_Y1.CLKCM_CFG",
                    PREFIX + "IBUFDS_GTE2_Y1.CLKRCV_TRST"}
        expected = original_features - modified
        value = 3 if swing is None else swing
        expected |= {SWING + f"[{bit}]" for bit in range(2) if value & (1 << bit)}
        if cm:
            expected.add(PREFIX + "IBUFDS_GTE2_Y1.CLKCM_CFG")
        if trst:
            expected.add(PREFIX + "IBUFDS_GTE2_Y1.CLKRCV_TRST")
        if actual != expected:
            raise ValueError(f"unexpected refclk features: extra {actual-expected}, missing {expected-actual}")
        cases += 1
    for kind in ("MMCME2", "PLLE2"):
        for advanced in (False, True):
            changed = copy.deepcopy(source)
            cells = changed["modules"]["te0715_ethernet_top"]["cells"]
            clocks = [c for c in cells.values() if c["type"] == "MMCME2_BASE"]
            if len(clocks) != 2:
                raise ValueError("expected two base MMCMs")
            for cell in clocks:
                cell["type"] = kind + ("_ADV" if advanced else "_BASE")
                if kind == "PLLE2":
                    for old, new in (("CLKFBOUT_MULT_F", "CLKFBOUT_MULT"), ("CLKOUT0_DIVIDE_F", "CLKOUT0_DIVIDE")):
                        cell["parameters"][new] = f"{int(float(cell['parameters'].pop(old))):032b}"
                if advanced:
                    cell["port_directions"].update(CLKIN2="input", CLKINSEL="input")
                    cell["connections"].update(CLKIN2=["0"], CLKINSEL=["1"])
            directory = output / (kind + ("-advanced" if advanced else "-base"))
            packed = run(backend, chipdb, changed, directory, False)
            clocks = [c for c in next(iter(packed["modules"].values()))["cells"].values()
                      if c["type"].startswith(kind + "_ADV")]
            if len(clocks) != 2 or any(bool(c["connections"].get("CLKIN2")) != advanced for c in clocks):
                raise ValueError("BASE/ADV clock selection changed unexpectedly")
            cases += 1
    result = {"cases": cases, "passed": True, "hardware_qualified": False}
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Select a patched backend and the retained native loopback build."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("nextpnr", "chipdb", "stage", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(args.nextpnr.resolve(), args.chipdb.resolve(), args.stage.resolve(), args.output.resolve())))


if __name__ == "__main__":
    main()
