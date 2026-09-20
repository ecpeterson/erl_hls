#!/usr/bin/env python3
"""Test the carrier status probe against Trenz's slave and the host MMIO contract."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from test_te0715_qemu import INIT, run as check_linux


def run(yosys: Path | None, ghdl: Path | None = None) -> None:
    """Test C and raw/mapped RTL; optionally regenerate the vendor reference with GHDL."""
    root = Path(__file__).resolve().parent
    sfp = root / "sfp"
    reference = sfp / "vendor/ddsrpi_slave.v"
    source = sfp / "vendor/ddsrpi_slave.vhd"
    lock = json.loads((sfp / "vendor/source.json").read_text())
    for path, key in ((source, "member_sha256"), (reference, "verilog_sha256")):
        if hashlib.sha256(path.read_bytes()).hexdigest() != lock[key]:
            raise ValueError(f"vendor reference changed: {path}")
    with tempfile.TemporaryDirectory(prefix="sfp-probe-") as directory:
        stage = Path(directory)
        if ghdl:
            # Use the same relative source path because GHDL embeds it in comments.
            regenerated = subprocess.check_output([str(ghdl), "synth", "--std=08", "--out=verilog",
                "experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd", "-e", "ddsrpi_slave"], cwd=root.parent.parent)
            if regenerated != reference.read_bytes():
                raise ValueError("GHDL output differs from the pinned slave reference")
        for name in ("probe_sfp", "test_probe_sfp"):
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                            str(sfp / f"{name}.c"), "-o", str(stage / name)], check=True)
        subprocess.run([str(stage / "test_probe_sfp")], check=True)
        for mapped in ([False, True] if yosys else [False]):
            arguments = ["iverilog", "-g2012", "-s", "sfp_status_tb", "-o", str(stage / "test.vvp")]
            sources = [sfp / "rgpio_reader.v", sfp / "sfp_status_tb.sv", reference]
            if mapped:
                script = (f'read_verilog "{sfp / "rgpio_reader.v"}"; '
                    'chparam -set QUARTER_CYCLES 4 sfp_status; '
                    'synth_xilinx -noiopad -flatten -family xc7 -top sfp_status; '
                    'check -assert; scc -expect 0; rename sfp_status sfp_status_mapped; '
                    f'write_verilog -noattr "{stage / "mapped.v"}"')
                subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / "yosys.log"), "-p", script], check=True)
                config = yosys.with_name("yosys-config")
                data = (Path(subprocess.check_output([str(config), "--datdir"], text=True).strip())
                        if config.is_file() else yosys.parent.parent / "share/yosys")
                sources += [stage / "mapped.v", data / "xilinx/cells_sim.v"]
                arguments.append("-DMAPPED")
            subprocess.run([*arguments, *map(str, sources)], check=True)
            subprocess.run(["vvp", str(stage / "test.vvp")], check=True, timeout=20)


def main() -> None:
    """Select optional mapping and vendor-reference regeneration tools."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path)
    parser.add_argument("--ghdl", type=Path)
    parser.add_argument("--candidate", type=Path, help="also check static ARM diagnostics in native QEMU")
    args = parser.parse_args()
    run(args.yosys.resolve() if args.yosys else None, args.ghdl.resolve() if args.ghdl else None)
    if args.candidate:
        init = INIT.replace(b"probe_zynq_ps", b"probe_sfp").replace(
            b"'unexpected identity/ABI; no writes attempted'",
            b"'unexpected identity/ABI; no writes attempted (raw=00000000)'")
        print(check_linux(args.candidate.resolve(), 45, programs=("probe_sfp", "test_probe_sfp"), init=init))


if __name__ == "__main__":
    main()
