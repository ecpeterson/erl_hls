#!/usr/bin/env python3
"""Generate the PCS-boundary diagnostic RTL from hash-checked source archives."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from ethernet.prepare import environment


def select_basex(source: Path) -> None:
    """Specialize to 1000BASE-X and register long TX control paths."""
    text = source.read_text()
    old = "            is_sgmii.eq(self.lp_abi.o[0]),\n"
    new = "            is_sgmii.eq(0), # Diagnostic is fixed to 1000BASE-X.\n"
    if text.count(old) != 1:
        raise ValueError("pinned PCS mode-selection source changed; review the specialization")
    text = text.replace(old, new)
    marker = "class PCS(LiteXModule):"
    prefix, pcs = text.split(marker)
    if pcs.count("self.tx.config_valid") != 4 or pcs.count("self.tx.config_reg") != 6:
        raise ValueError("pinned PCS TX-control source changed; review the pipeline")
    pcs = pcs.replace("self.tx.config_valid", "tx_config_valid")
    pcs = pcs.replace("self.tx.config_reg", "tx_config_reg")
    anchor = "        self.autoneg_ack  = autoneg_ack  = Signal()\n"
    pipeline = (anchor +
                "        tx_config_valid = Signal()\n"
                "        tx_config_reg   = Signal(16)\n"
                "        tx_config_valid_pipe = Signal()\n"
                "        tx_config_reg_pipe   = Signal(16)\n"
                "        self.sync.eth_tx += [\n"
                "            tx_config_valid_pipe.eq(tx_config_valid),\n"
                "            tx_config_reg_pipe.eq(tx_config_reg),\n"
                "            self.tx.config_valid.eq(tx_config_valid_pipe),\n"
                "            self.tx.config_reg.eq(tx_config_reg_pipe),\n"
                "        ]\n")
    if pcs.count(anchor) != 1:
        raise ValueError("pinned PCS signal declarations changed; review the pipeline")
    pcs = pcs.replace(anchor, pipeline)
    link_anchor = "        self.autoneg_ack  = autoneg_ack  = Signal()\n"
    link_pipeline = (link_anchor +
                     "        linkdown_now = Signal()\n"
                     "        self.sync.eth_tx += linkdown.eq(linkdown_now)\n")
    if pcs.count(link_anchor) != 1 or pcs.count("linkdown.eq(") != 2:
        raise ValueError("pinned PCS link-down source changed; review the pipeline")
    pcs = pcs.replace("linkdown.eq(", "linkdown_now.eq(").replace(link_anchor, link_pipeline)
    source.write_text(prefix + marker + pcs)


def generate(output: Path) -> None:
    """Regenerate the production PCS and its related-clock gearbox."""
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pcs-sources-", dir=output) as directory:
        env = environment(output / "sources", Path(directory))
        liteeth_root = next(Path(root) for root in env["PYTHONPATH"].split(os.pathsep)
                            if Path(root).name.startswith("liteeth-"))
        select_basex(liteeth_root / "liteeth/phy/pcs_1000basex.py")
        for script in ("generate_pcs_probe.py", "generate_gearbox.py"):
            subprocess.run([sys.executable, "-S", str(ROOT / "ethernet" / script),
                            str(output / "generated")], env=env, check=True, timeout=30)


def main() -> None:
    """Accept one explicit build directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    generate(args.output.resolve())


if __name__ == "__main__":
    main()
