#!/usr/bin/env python3
"""Test the raw-symbol sampler before building the external GTX diagnostic."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent


def check_reference() -> None:
    """Require every source named by the routed symbol record to retain its digest."""
    record = json.loads((ROOT / "boot/symbol-external.json").read_text())
    for name, expected in record["source_sha256"].items():
        actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"symbol reference source changed: {name}")


def run(yosys: Path | None) -> None:
    """Run source and mapped sampler simulations plus the host diagnostic fixture."""
    check_reference()
    with tempfile.TemporaryDirectory(prefix="symbol-probe-") as directory:
        stage = Path(directory)
        sources = [ROOT / "zynq_ps_probe.v", ROOT / "ethernet/symbol_probe_sample.v",
                   ROOT / "ethernet/symbol_probe_tb.sv"]
        for mapped in ([False, True] if yosys else [False]):
            additions: list[Path] = []
            arguments = ["iverilog", "-g2012", "-s", "symbol_probe_tb",
                         "-o", str(stage / "test.vvp")]
            if mapped:
                target = stage / "symbol_probe_sample.v"
                script = (f'read_verilog "{ROOT / "zynq_ps_probe.v"}" '
                          f'"{ROOT / "ethernet/symbol_probe_sample.v"}"; '
                          'synth_xilinx -noiopad -flatten -family xc7 '
                          '-top ethernet_symbol_probe_sample; check -assert; '
                          'rename ethernet_symbol_probe_sample ethernet_symbol_probe_sample_mapped; '
                          f'write_verilog -noattr "{target}"')
                subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / "yosys.log"),
                                "-p", script], check=True)
                config = yosys.with_name("yosys-config")
                data = (Path(subprocess.check_output([str(config), "--datdir"], text=True).strip())
                        if config.is_file() else yosys.parent.parent / "share/yosys")
                additions = [target, data / "xilinx/cells_sim.v"]
                arguments.append("-DMAPPED")
            subprocess.run([*arguments, *map(str, sources + additions)], check=True)
            subprocess.run(["vvp", str(stage / "test.vvp")], check=True, timeout=30)
        for name in ("probe_symbols", "test_probe_symbols"):
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                            str(ROOT / "ethernet" / f"{name}.c"), "-o", str(stage / name)],
                           check=True)
        subprocess.run([str(stage / "test_probe_symbols")], check=True, timeout=20)


def main() -> None:
    """Accept an optional synthesizer for mapped sampler validation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path)
    args = parser.parse_args()
    run(args.yosys.resolve() if args.yosys else None)


if __name__ == "__main__":
    main()
