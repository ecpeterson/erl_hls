#!/usr/bin/env python3
"""Restart both complete repetition-link roles by paired PS reset or PL reload."""

import argparse
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Target:
    """One board role and its PS-Ethernet address."""

    role: str
    host: str


def ssh_command(target: Target, key: str, remote: str,
                timeout: int) -> subprocess.CompletedProcess[str]:
    """Run one noninteractive board command and retain its complete result."""
    command = [
        "ssh", "-nT", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
        "-o", "ConnectTimeout=5", "-i", key, f"root@{target.host}", remote,
    ]
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout)


def reload_target(target: Target, key: str) -> tuple[Target, subprocess.CompletedProcess[str]]:
    """Run the installed full-PL reload and retain its complete result."""
    return target, ssh_command(
        target, key, f"/opt/erl-hls/bin/reload_repetition_pl {target.role}", 30)


def warm_reboot_target(target: Target, key: str) -> tuple[Target, subprocess.CompletedProcess[str]]:
    """Request one PS reset; the later down/up observation is authoritative."""
    try:
        result = ssh_command(target, key, "sync; reboot", 15)
    except subprocess.TimeoutExpired:
        result = subprocess.CompletedProcess([], 124, "", "SSH closed during reboot")
    return target, result


def boot_identity(target: Target, key: str) -> tuple[Target, str]:
    """Read the kernel boot identity used to prove that a PS reset occurred."""
    result = ssh_command(target, key, "cat /proc/sys/kernel/random/boot_id", 10)
    result.check_returncode()
    return target, result.stdout.strip()


def await_reboot(target: Target, key: str, previous: str,
                 deadline: float) -> tuple[Target, str]:
    """Require a new kernel plus healthy PL/DMA state at the same address."""
    check = (
        "cat /proc/sys/kernel/random/boot_id && "
        "test -c /dev/hls-dma0 && test -c /dev/hls-dma1 && "
        "test \"$(cat /sys/class/fpga_manager/fpga0/state)\" = operating && "
        "/opt/erl-hls/bin/check_repetition_link --check-install"
    )
    last = "board did not return"
    while time.monotonic() < deadline:
        try:
            result = ssh_command(target, key, check, 10)
        except subprocess.TimeoutExpired:
            last = "SSH timed out"
        else:
            if result.returncode:
                last = result.stderr.strip() or result.stdout.strip()
            else:
                identity, _, output = result.stdout.partition("\n")
                if identity != previous:
                    return target, output
                last = "kernel boot identity has not changed"
        time.sleep(1)
    raise RuntimeError(f"role {target.role} did not complete warm reboot: {last}")


def main() -> None:
    """Restart both complete roles together and verify their local endpoints."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-a", default="192.168.77.31")
    parser.add_argument("--host-b", default="192.168.77.32")
    parser.add_argument("--key", default="~/.ssh/id_ed25519")
    parser.add_argument("--method", choices=("reload", "reboot"), default="reboot",
                        help="reboot is the proven paired reset; reload is experimental")
    parser.add_argument("--reboot-timeout", type=int, default=120)
    args = parser.parse_args()
    key = str(Path(args.key).expanduser())
    targets = [Target("a", args.host_a), Target("b", args.host_b)]
    previous = {}
    if args.method == "reboot":
        with ThreadPoolExecutor(max_workers=2) as executor:
            previous = dict((target.role, identity) for target, identity in
                            executor.map(lambda target: boot_identity(target, key), targets))
    worker = reload_target if args.method == "reload" else warm_reboot_target
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda target: worker(target, key), targets))
    if args.method == "reboot":
        deadline = time.monotonic() + args.reboot_timeout
        with ThreadPoolExecutor(max_workers=2) as executor:
            completed = list(executor.map(
                lambda target: await_reboot(target, key, previous[target.role], deadline), targets))
        for target, output in completed:
            print(f"role {target.role} ({target.host}):")
            print(output, end="")
        print("PASS: both PS instances rebooted; both complete PL roles and DMA endpoints returned")
        return
    failed = False
    for target, result in results:
        print(f"role {target.role} ({target.host}):")
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        failed = failed or result.returncode != 0
    if failed:
        raise SystemExit(
            "paired PL reload failed; reset both PS instances before another application run")
    print("PASS: both PL roles reloaded concurrently; Linux and SSH stayed up")


if __name__ == "__main__":
    main()
