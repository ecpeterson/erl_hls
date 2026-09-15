#!/usr/bin/env python3
"""Check bounded conservation/stall safety on generated direct Service ports."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

from topology_debug import quote

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, nargs="+")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--yosys", default=os.environ.get("ERL_HLS_YOSYS") or
                        shutil.which("yosys") or str(ROOT / "experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"))
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=True)
    for rtl in args.rtl:
        prefix = args.stage / rtl.stem
        script = "read_verilog -sv " + " ".join(map(quote, [
            ROOT / "test/rtl/direct_admission_formal.sv", rtl.resolve()])) + "\n"
        script += "prep -top direct_admission_formal -flatten\nmemory_map\nopt\n"
        script += ("sat -verify -prove ok 1 -set legal 1 -set-at 1 reset 1 "
                   "-set-def-inputs -seq 24 -timeout 60 "
                   f"-dump_vcd {quote(prefix.with_suffix('.vcd'))}\n")
        prefix.with_suffix(".ys").write_text(script)
        with prefix.with_suffix(".log").open("w") as log:
            subprocess.run([args.yosys, "-Q", "-T", "-s", str(prefix.with_suffix(".ys"))],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        print(f"PASS: 24-step credit conservation and stalled outputs: {rtl.name}", flush=True)


if __name__ == "__main__":
    main()
