#!/usr/bin/env python3
"""Exercise packet ownership and AXI bursts, including an optional mapped BRAM run."""

import argparse
import gzip
import json
import re
import subprocess
import tempfile
from pathlib import Path

from build_te0715_kernel import kernel_config
from prepare_te0715_boot import fetch


def run(yosys: Path | None) -> None:
    """Simulate every routed frame size and verify BRAM inference when Yosys is given."""
    root = Path(__file__).resolve().parent
    config = b"CONFIG_PL330_DMA=y\nCONFIG_MODVERSIONS=y\n"
    assert kernel_config(b"ARM boot" + gzip.compress(b"kernelIKCFG_ST" + gzip.compress(config))) == config
    for invalid in (b"", b"IKCFG_STinvalid", gzip.compress(b"kernel without config")):
        try:
            kernel_config(invalid)
        except ValueError:
            continue
        raise AssertionError("accepted a missing/invalid kernel config")
    with tempfile.TemporaryDirectory(prefix="zynq-dma-") as directory:
        stage = Path(directory)
        tool = stage / "check_dma_device"
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        str(root / "dma/check_dma_device.c"), "-o", str(tool)], check=True)
        if subprocess.run([str(tool)], capture_output=True).returncode != 2:
            raise AssertionError("board diagnostic did not reject missing device argument")
        sources = [str(root / "dma/zynq_dma_mailbox.v"), str(root / "dma/zynq_dma_mailbox_tb.sv")]
        for mapped in ([False, True] if yosys else [False]):
            flags = []
            extra = []
            if mapped:
                script = (f'read_verilog "{sources[0]}"; synth_xilinx -noiopad -flatten '
                          '-family xc7 -top zynq_dma_mailbox; check -assert; '
                          'select -assert-count 2 t:RAMB18E1; select -clear; '
                          'rename zynq_dma_mailbox zynq_dma_mailbox_mapped; '
                          f'write_verilog -noattr "{stage / "mapped.v"}"')
                subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / "yosys.log"), "-p", script], check=True)
                config_tool = yosys.with_name("yosys-config")
                data = (Path(subprocess.check_output([str(config_tool), "--datdir"], text=True).strip())
                        if config_tool.is_file() else yosys.parent.parent / "share/yosys")
                # Yosys supplies only a BRAM black box. Use AMD's functional model.
                cache = root / "build/dma-models"
                cache.mkdir(parents=True, exist_ok=True)
                models = [fetch(p, cache) for p in json.loads((root / "dma/models.lock.json").read_text()).values()]
                cells, replaced = re.subn(r"\bmodule RAMB18E1\b.*?\bendmodule\b", "",
                                         (data / "xilinx/cells_sim.v").read_text(), flags=re.S)
                if replaced != 1:
                    raise ValueError("expected one RAMB18E1 black box")
                (stage / "cells.v").write_text(cells)
                extra = [str(stage / "mapped.v"), str(stage / "cells.v"), *map(str, models)]
                flags = ["-DMAPPED", "-s", "glbl"]
            subprocess.run(["iverilog", "-g2012", *flags, "-s", "zynq_dma_mailbox_tb",
                            "-o", str(stage / "mailbox.vvp"), *sources, *extra], check=True)
            subprocess.run(["vvp", str(stage / "mailbox.vvp")], check=True, timeout=60)


def main() -> None:
    """Run portable tests, optionally including the FPGA-mapped memory implementation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path)
    args = parser.parse_args()
    run(args.yosys.resolve() if args.yosys else None)


if __name__ == "__main__":
    main()
