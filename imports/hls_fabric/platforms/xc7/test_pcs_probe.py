#!/usr/bin/env python3
"""Test PCS event filtering, boundary counters and the userspace diagnostic."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from ethernet.prepare import fix_config_pulses

ROOT = Path(__file__).resolve().parent


def check_references() -> None:
    """Require the PCS and corrected packet records to retain their exact source closures."""
    for profile in ("pcs-external", "ethernet-external-autoneg"):
        record = json.loads((ROOT / "boot" / f"{profile}.json").read_text())
        for name, expected in record["source_sha256"].items():
            actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError(f"{profile} reference source changed: {name}")


def check_event_filter(stage: Path) -> None:
    """Require pulse clearing and rejection of the empty break-link word."""
    source = stage / "pcs.py"
    source.write_text(
        "        self.sync.eth_rx += [\n"
        "            If(self.rx.seen_config_reg,\n"
        "                        If(self.rx.config_reg[14],\n"
        "                            rx_config_reg_ack.i.eq(1),\n"
        "                        # Ability match.\n"
        "                        ).Else(\n"
        "                            rx_config_reg_abi.i.eq(1),\n"
        "                        )\n"
        "            If(rx_config_reg_abi.o,\n"
        "                NextState(\"AUTONEG-WAIT-ACK\")\n"
        "            ),\n")
    fix_config_pulses(source)
    result = source.read_text()
    if "rx_config_reg_abi.i.eq(0)" not in result or \
            ").Elif(self.rx.config_reg != 0," not in result or \
            "If(rx_config_reg_abi.o | rx_config_reg_ack.o," not in result:
        raise AssertionError("PCS configuration-event filter was not applied")


def check_late_peer(iverilog: Path, stage: Path, generated: Path) -> None:
    """Accelerate production timers and exercise independently released peers."""
    text = generated.read_text()
    replacements = {"21'd1250000": "21'd80", "18'd200000": "18'd16",
                    "20'd750000": "20'd200"}
    expected = {"21'd1250000": 6, "18'd200000": 3, "20'd750000": 1}
    for old, new in replacements.items():
        if text.count(old) != expected[old]:
            raise AssertionError(f"unexpected generated timer occurrences: {old}")
        text = text.replace(old, new)
    accelerated = stage / "liteeth_pcs_probe.v"
    accelerated.write_text(text)
    shutil.copyfile(generated.with_name("liteeth_pcs_probe_mem_6b5b.init"),
                    stage / "liteeth_pcs_probe_mem_6b5b.init")
    simulation = stage / "pcs-autoneg.vvp"
    subprocess.run([str(iverilog), "-g2012", "-s", "pcs_autoneg_tb", "-o", str(simulation),
                    str(accelerated), str(ROOT / "ethernet/pcs_autoneg_tb.sv")], check=True)
    for late_cycles in (80, 81, 100, 137, 200, 400, 800, 1600):
        subprocess.run([str(iverilog.with_name("vvp")), str(simulation),
                        f"+late_cycles={late_cycles}"], cwd=stage,
                       check=True, timeout=10)


def run(iverilog: Path, generated: Path | None) -> None:
    """Compile and execute the RTL and host-side fixtures."""
    check_references()
    with tempfile.TemporaryDirectory(prefix="pcs-probe-") as directory:
        stage = Path(directory)
        check_event_filter(stage)
        simulation = stage / "pcs-probe.vvp"
        subprocess.run([str(iverilog), "-g2012", "-s", "pcs_probe_tb", "-o", str(simulation),
                        str(ROOT / "ethernet/pcs_probe_sample.v"),
                        str(ROOT / "ethernet/pcs_probe_tb.sv")], check=True)
        subprocess.run([str(iverilog.with_name("vvp")), str(simulation)], check=True, timeout=10)
        if generated is not None:
            check_late_peer(iverilog, stage, generated)
        for name in ("probe_pcs", "test_probe_pcs"):
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                            str(ROOT / "ethernet" / f"{name}.c"), "-o", str(stage / name)], check=True)
        subprocess.run([str(stage / "test_probe_pcs")], check=True, timeout=20)


def main() -> None:
    """Require the simulator path used by the pinned toolchain."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", type=Path, required=True)
    parser.add_argument("--generated-pcs", type=Path)
    args = parser.parse_args()
    run(args.iverilog.resolve(), args.generated_pcs.resolve() if args.generated_pcs else None)


if __name__ == "__main__":
    main()
