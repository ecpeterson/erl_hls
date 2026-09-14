#!/usr/bin/env python3
"""Build the decoder profile and its wrapper as one published artifact set."""
import argparse
from pathlib import Path
import re
import signal
import subprocess

from compile_xls import build, duration, interrupted, sha


def main():
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("timeout", nargs="?", type=duration, default=7200)
    parser.add_argument("shards", nargs="?", type=int, default=3)
    parser.add_argument("pipeline_stages", nargs="?", type=int, default=2)
    parser.add_argument("initiation_interval", nargs="?", type=int, default=1)
    args = parser.parse_args()
    if min(args.shards, args.pipeline_stages, args.initiation_interval) < 1:
        parser.error("shards, pipeline stages, and initiation interval must be positive")
    stage = args.stage.resolve()

    def metadata(snapshot):
        source = (snapshot / "phi_decoder_profile_topology.x").read_text()
        dimensions = {name.lower(): int(re.search(rf"const {name} = u16:(\d+);", source)[1])
                      for name in ("WIDTH", "HEIGHT")}
        return {"profile": {**dimensions, "shards_per_plane": args.shards,
                            "pipeline_stages": args.pipeline_stages, "initiation_interval": args.initiation_interval,
                            "delay_model": "unit", "flop_inputs": False, "flop_outputs": True},
                "ram_configuration": sha(snapshot / "assets/phi_scheduler_rams.sh")}

    def ram_configurations(snapshot):
        return subprocess.check_output([
            "bash", "-c", 'set -euo pipefail; source "$1"; phi_scheduler_ram_configurations "$2"',
            "bash", str(snapshot / "assets/phi_scheduler_rams.sh"), str(2 + 2 * args.shards)], text=True).strip()

    build(stage / "phi_decoder_profile_topology.x", args.xls_root, stage / "compiled",
          name="phi_decoder_profile", pipeline_stages=args.pipeline_stages,
          initiation_interval=args.initiation_interval, ram_configurations=ram_configurations,
          assets=[stage / name for name in ("phi_decoder_profile_top.v", "hls_1r1w_ram.v", "phi_scheduler_rams.sh")],
          metadata=metadata, timeout=args.timeout)


if __name__ == "__main__":
    main()
