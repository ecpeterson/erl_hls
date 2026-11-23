#!/usr/bin/env python3
"""Exercise the partition-link framing, packet probe and routed debug boundary."""

import argparse
import subprocess
import tempfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from backend_paths import application_directory

from escript_test import run_self_test

ROOT = Path(__file__).resolve().parent


def simulate(stage: Path, name: str, sources: list[Path]) -> None:
    """Compile and run one bounded SystemVerilog witness."""
    executable = stage / f"{name}.vvp"
    subprocess.run(["iverilog", "-g2012", "-s", name, "-o", executable,
                    *map(str, sources)], check=True, timeout=30)
    result = subprocess.run(["vvp", executable], check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=30)
    print(result.stdout.strip(), flush=True)


def run(public: Path | None = None) -> None:
    """Run framing/probe witnesses and the host checker's offline invariants."""
    public = public or application_directory("erl_hls", "default")
    fabric = public / "priv/rtl/fabric"
    ingress = fabric / "hls_fabric_ingress.v"
    egress = fabric / "hls_fabric_egress.v"
    if not ingress.is_file() or not egress.is_file():
        raise FileNotFoundError(f"prepared public compiler RTL is missing: {fabric}")
    application = ROOT / "application"
    ethernet = ROOT / "ethernet"
    with tempfile.TemporaryDirectory(prefix="partition-link-") as directory:
        stage = Path(directory)
        simulate(stage, "partition_link_packets_tb", [
            ROOT / "zynq_ps_probe.v", ethernet / "cdc_slot.v",
            ethernet / "dma_packets.v", application / "partition_link_packets.v",
            application / "partition_link_packets_tb.sv",
        ])
        simulate(stage, "partition_packet_probe_tb", [
            application / "partition_packet_probe.v",
            application / "partition_packet_probe_tb.sv",
        ])
        simulate(stage, "partition_debug_route_tb", [
            ingress, egress, application / "partition_debug_route_tb.sv",
        ])
    run_self_test(application / "check_partition_link.escript")


def main() -> None:
    """Accept the prepared public compiler checkout used for fabric RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public", type=Path, default=None)
    args = parser.parse_args()
    run(args.public.resolve() if args.public else None)


if __name__ == "__main__":
    main()
