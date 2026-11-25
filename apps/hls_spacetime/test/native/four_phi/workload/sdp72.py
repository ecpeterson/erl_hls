"""Check the Apio techmap with 72 independent logical writes and physical RAMB36E1 readbacks."""

import argparse
import json
import subprocess
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[6] / "platforms/xc7/bram"))
from check_yosys import audit_probe_netlist

HERE = Path(__file__).resolve().parent


def check(yosys: Path, models: Path, work: Path) -> None:
    """Require one simple-dual-port block and run its emitted netlist with the functional UNISIM model."""
    work.mkdir()
    (work / "memory.sv").symlink_to(HERE / "sdp72.sv")
    subprocess.run(
        [
            yosys,
            "-Q",
            "-q",
            "-p",
            "read_verilog memory.sv; synth_xilinx -family xc7 -noiopad -noclkbuf -top parity_memory; write_json memory.json; write_verilog -noattr mapped.v",
        ],
        cwd=work,
        check=True,
    )
    subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-s",
            "sdp72_tb",
            "-s",
            "glbl",
            "-y",
            models / "unisims",
            "-o",
            "test",
            HERE / "sdp72_tb.sv",
            "mapped.v",
            models / "glbl.v",
        ],
        cwd=work,
        check=True,
    )
    subprocess.run(["vvp", "test"], cwd=work, check=True)
    audit_probe_netlist(json.loads((work / "memory.json").read_bytes()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("yosys", "models", "work"):
        parser.add_argument(key, type=lambda p: Path(p).resolve())
    check(**vars(parser.parse_args()))
