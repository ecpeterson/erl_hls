#!/usr/bin/env python3
"""Exercise the N=6 repetition roles, packet boundary and host coordinators."""

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

from escript_test import run_self_test

ROOT = Path(__file__).resolve().parent
APPLICATION = ROOT / "application"


def command(arguments: list[object], timeout: int = 60) -> str:
    """Run one bounded check and return its merged diagnostics."""
    result = subprocess.run([str(value) for value in arguments], check=False, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout)
    output = result.stdout.strip()
    if output:
        print(output, flush=True)
    result.check_returncode()
    return output


def rename_role(generated: Path, stage: Path, role: str, device: int) -> tuple[Path, Path]:
    """Namespace generated modules and expose one common role-model wrapper."""
    source = (generated / f"repetition_application_{role}.v").read_text()
    names = re.findall(r"(?m)^module\s+([^\s(#]+)", source)
    if not names:
        raise ValueError(f"no generated modules in role {role}")
    mapping = {name: f"{role}__{name}" for name in names}
    pattern = re.compile(
        r"(?<![A-Za-z0-9_$])(" +
        "|".join(map(re.escape, sorted(names, key=len, reverse=True))) +
        r")(?![A-Za-z0-9_$])")
    role_source = stage / f"role-{role}.v"
    role_source.write_text(pattern.sub(lambda match: mapping[match.group(1)], source))

    wrapper = (generated / f"repetition_application_{role}_ram.v").read_text()
    wrapper = re.sub(
        rf"(?<![A-Za-z0-9_$])phi_device_{device}_ram(?![A-Za-z0-9_$])",
        "role_model", wrapper)
    wrapper = re.sub(
        rf"(?<![A-Za-z0-9_$])phi_device_{device}(?![A-Za-z0-9_$])",
        mapping[f"__phi_device_{device}__Top_0_next"], wrapper)
    role_wrapper = stage / f"role-{role}-ram.v"
    role_wrapper.write_text(wrapper)
    return role_source, role_wrapper


def simulate_role(stage: Path, role: str, sources: tuple[Path, Path]) -> None:
    """Require scheduler-memory activity and one private packet from an exact role."""
    source, wrapper = sources
    defines = ["-DROLE_B"] if role == "b" else []
    executable = stage / f"role-{role}.vvp"
    command(["iverilog", "-g2012", *defines, "-s", "repetition_role_rtl_tb",
             "-o", executable, APPLICATION / "repetition_role_rtl_tb.sv",
             source, wrapper, APPLICATION / "hls_1r1w_ram_zero_model.v"])
    output = command(["vvp", executable], 120)
    match = re.search(
        r"RESULT app_in_words=(\d+) app_out_words=(\d+) app_out_frames=(\d+) "
        r"link_words=(\d+) link_frames=(\d+) state_reads=(\d+) "
        r"state_writes=(\d+) mailbox_reads=(\d+) mailbox_writes=(\d+)", output)
    if not match or int(match.group(1)) != 17 or min(map(int, match.groups()[1:])) < 1:
        raise AssertionError(f"role {role} did not exercise every scheduler boundary: {output}")

    packet = stage / f"packet-{role}.vvp"
    command(["iverilog", "-g2012", *defines, "-s", "repetition_packet_role_tb",
             "-o", packet, APPLICATION / "repetition_packet_role_tb.sv",
             source, wrapper, APPLICATION / "hls_1r1w_ram_zero_model.v",
             ROOT / "zynq_ps_probe.v", ROOT / "ethernet/cdc_slot.v",
             ROOT / "ethernet/dma_packets.v",
             APPLICATION / "partition_link_packets.v"])
    output = command(["vvp", packet], 120)
    if "PASS: exact role" not in output:
        raise AssertionError(f"role {role} did not publish a complete private frame")


def check_generated(generated: Path) -> None:
    """Validate a fresh role manifest and run bounded role/packet witnesses."""
    manifest = json.loads((generated / "manifest.json").read_text())
    if manifest["size"] != 6 or manifest["split"] != [3, 3] or \
            manifest["pipeline_stages"] != 2:
        raise AssertionError(f"unexpected repetition profile: {manifest}")
    with tempfile.TemporaryDirectory(prefix="repetition-link-") as directory:
        stage = Path(directory)
        roles = {role: rename_role(generated, stage, role, device)
                 for role, device in (("a", 0), ("b", 1))}
        for role in ("a", "b"):
            simulate_role(stage, role, roles[role])


def run(generated: Path | None) -> None:
    """Run offline coordinator checks and optional exact generated-RTL witnesses."""
    run_self_test(APPLICATION / "check_repetition_link.escript", timeout=60)
    command(["python3", ROOT / "test_restart_repetition_pair.py"])
    for script in (APPLICATION / "install_repetition_link.sh",
                   APPLICATION / "reload_repetition_pl.sh",
                   APPLICATION / "repetition-network.start"):
        command(["sh", "-n", script])
    if generated is not None:
        check_generated(generated)


def main() -> None:
    """Select an optional freshly generated pair for the slower RTL checks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path,
                        help="directory produced by build_repetition_link_application.py")
    args = parser.parse_args()
    run(args.generated.resolve() if args.generated else None)


if __name__ == "__main__":
    main()
