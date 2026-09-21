"""Select exact, retained Vivado board images by profile and digest."""

import json
from pathlib import Path

from check_zynq_boot import bit_payload
from prepare_te0715_boot import digest

REFERENCE = Path(__file__).resolve().parent.parent / "results/vivado-reference-2026-09-21.json"


def verify_reference(profile: str, bitstream: Path, report: Path = REFERENCE) -> dict:
    """Reject unknown, swapped or altered images and require the exact chip/package."""
    reference = json.loads(report.read_text())
    if profile not in reference["profiles"]:
        raise ValueError(f"unknown board profile: {profile}")
    expected = reference["profiles"][profile]["artifacts_sha256"]["candidate.bit"]
    if digest(bitstream) != expected:
        raise ValueError(f"bitstream differs from retained {profile} reference")
    bit_payload(bitstream.read_bytes())
    return reference
