"""Resolve only undefined storage configuration bits as encoded by the pinned XC7 FASM writer."""

import json
import re
import sys
from collections import Counter
from pathlib import Path


def configured(source: Path, output: Path, receipt: Path) -> None:
    """Preserve known bits and connectivity. Reject undefined parameters outside the qualified FF/BRAM cases."""
    design = json.loads(source.read_bytes())
    counts = Counter()
    for cell in design["modules"]["phi_timing_harness"]["cells"].values():
        kind = cell["type"]
        for name, value in cell["parameters"].items():
            if not re.fullmatch(r"[01xz]*[xz][01xz]*", value):
                continue
            ff = kind == "FDRE" and name == "INIT"
            ram = kind in ("RAMB18E1", "RAMB36E1") and re.fullmatch(
                r"INITP?_[0-9A-F]{2}|(?:INIT|SRVAL)_[AB]", name
            )
            if not (ff or ram):
                raise ValueError(f"unqualified configuration parameter {kind}.{name}")
            if (
                ram
                and name in ("INIT_A", "INIT_B", "SRVAL_A", "SRVAL_B")
                and "1" in value
            ):
                raise ValueError(
                    "nonzero BRAM output initialization outside this witness"
                )
            counts[kind + "." + re.sub(r"_[0-9A-F]{2}$", "_nn", name)] += value.count(
                "x"
            ) + value.count("z")
            cell["parameters"][name] = value.replace("x", "0").replace("z", "0")
    with output.open("x") as f:
        json.dump(design, f, separators=(",", ":"))
    receipt.write_text(json.dumps(counts, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    configured(*(Path(p) for p in sys.argv[1:]))
