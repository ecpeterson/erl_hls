#!/usr/bin/env python3
"""Check generated observation ports against the Erlang fixture's compiler-owned expectations."""
import argparse
import json
from pathlib import Path
import re


def check(stage: Path) -> None:
    """Require exact output widths and valid/ready ports for all diagnostic fixtures."""
    for name in ("hls_dense_statem_fixture", "debug_scalar", "debug_rectangle"):
        verilog = (stage / f"{name}.v").read_text()
        text = re.search(r"module " + name + r"\s*\((.*?)\);", verilog, re.S).group(1)
        expected = json.loads((stage / f"{name}.json").read_text())
        ports = {port: int(high) + 1 for high, port in re.findall(
            r"output wire \[(\d+):0\] (_(?:actor|family).*?_debug_out(?:__\d+_\d+)?)(?:,|\s*$)", text, re.M)}
        if ports != {entry["port"]: entry["width"] for entry in expected}:
            raise ValueError((name, ports, expected))
        for entry in expected:
            port = re.escape(entry["port"])
            if not re.search(r"input wire " + port + r"_rdy(?:,|\s*$)", text, re.M):
                raise ValueError(("missing ready port", name, entry))
            if not re.search(r"output wire " + port + r"_vld(?:,|\s*$)", text, re.M):
                raise ValueError(("missing valid port", name, entry))
        print(f"PASS: {name}: {len(expected)} compiler-bound diagnostic ports")


def main() -> None:
    """Inspect one generated fixture directory without compiling or modifying it."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    check(parser.parse_args().stage)


if __name__ == "__main__":
    main()
