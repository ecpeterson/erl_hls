#!/usr/bin/env python3
"""Check the PS probe's board profile and AXI/reset boundary, optionally after synthesis."""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from test_zynq_dma import run as check_dma
from test_qemu_cosim import run as check_cosim
from test_gtx_probe import run as check_gtx
from test_sfp_probe import run as check_sfp


def run(yosys: Path | None) -> None:
    """Check board assets, AXI and the socket bridge; --yosys also verifies mapped cores."""
    root = Path(__file__).resolve().parent
    subprocess.run([sys.executable, str(root / "test_te0715_boot.py")], check=True)
    subprocess.run([sys.executable, str(root / "test_te0715_runtime.py")], check=True)
    check_dma(yosys)
    check_cosim()
    check_gtx(yosys)
    check_sfp(yosys)
    source, bench = root / "zynq_ps_probe.v", root / "zynq_ps_probe_tb.sv"
    with tempfile.TemporaryDirectory(prefix="zynq-ps-probe-") as directory:
        stage = Path(directory)
        for name in ("probe_zynq_ps", "test_probe_zynq_ps"):
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                            str(root / f"{name}.c"), "-o", str(stage / name)], check=True)
        subprocess.run([str(stage / "test_probe_zynq_ps")], check=True)
        modes = [(mapped, extended) for mapped in ([False, True] if yosys else [False])
                 for extended in (False, True)]
        for mapped, extended in modes:
            arguments = ["iverilog", "-g2012", "-s", "zynq_ps_probe_tb", "-o", str(stage / "test.vvp")]
            sources = [str(source), str(bench)]
            if extended:
                arguments.append("-DEXTENDED")
            if mapped:
                # Native bundles provide yosys-config; distro runtime packages
                # may omit it while installing models under <prefix>/share/yosys.
                parameters = 'chparam -set EXTENDED 1 -set ABI 2 zynq_ps_probe; ' if extended else ''
                script = (f'read_verilog "{source}"; {parameters}synth_xilinx -noiopad -flatten '
                          '-family xc7 -top zynq_ps_probe; check -assert; '
                          'rename zynq_ps_probe zynq_ps_probe_mapped; '
                          f'write_verilog -noattr "{stage / "mapped.v"}"')
                subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / "yosys.log"), "-p", script], check=True)
                config = yosys.with_name("yosys-config")
                data = (Path(subprocess.check_output([str(config), "--datdir"], text=True).strip())
                        if config.is_file() else yosys.parent.parent / "share/yosys")
                models = data / "xilinx/cells_sim.v"
                if not models.is_file():
                    raise FileNotFoundError(f"Yosys simulation models not found: {models}")
                sources += [str(stage / "mapped.v"), str(models)]
                arguments.append("-DMAPPED")
            subprocess.run([*arguments, *sources], check=True)
            subprocess.run(["vvp", str(stage / "test.vvp")], check=True, timeout=30)


def main() -> None:
    """Accept an optional Yosys executable and run the portable RTL regression."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path)
    args = parser.parse_args()
    run(args.yosys.resolve() if args.yosys else None)


if __name__ == "__main__":
    main()
