#!/usr/bin/env python3
"""Build the decoder profile and its wrapper as one published artifact set."""
import argparse
import json
from pathlib import Path
import re
import signal
import subprocess

from compile_xls import build, duration, interrupted, sha


def main() -> None:
    """Compile the requested profile with checked geometry and explicit timing settings."""
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("timeout", nargs="?", type=duration, default=7200)
    parser.add_argument("shards", nargs="?", type=int, default=3)
    parser.add_argument("pipeline_stages", nargs="?", type=int, default=2)
    parser.add_argument("initiation_interval", nargs="?", type=int, default=1)
    parser.add_argument("--delay-model", default="unit")
    parser.add_argument("--delay-table", type=Path)
    args = parser.parse_args()
    if min(args.shards, args.pipeline_stages, args.initiation_interval) < 1:
        parser.error("shards, pipeline stages, and initiation interval must be positive")
    stage = args.stage.resolve()

    def metadata(snapshot: Path) -> dict:
        """Reject mismatched topology metadata and record the actual schedule settings."""
        source = (snapshot / "phi_decoder_profile_topology.x").read_text()
        dimensions = {name.lower(): int(re.search(rf"const {name} = u16:(\d+);", source)[1])
                      for name in ("WIDTH", "HEIGHT")}
        config = json.loads((snapshot / "assets/phi_decoder_profile.json").read_text())
        if dimensions != {key: config[key] for key in dimensions} or config["shards_per_plane"] != args.shards:
            raise ValueError("profile dimensions/shards disagree with the staged configuration")
        planes = [plane for plane in ("x", "z") if f"proc Phi_{plane}ReductionPlane" in source]
        actors = len(planes) * dimensions["width"] * dimensions["height"]
        expected = {**dimensions, "planes": planes, "shards_per_plane": args.shards,
                    "scheduler_count": len(planes) * (1 + args.shards),
                    "source_scheduler_count": len(planes), "phi_actor_count": actors, "source_actor_count": actors}
        routers = sorted(map(int, re.findall(r"^proc SchedulerRouter([0-9]+) \{", source, re.MULTILINE)))
        if config != expected or routers != list(range(expected["scheduler_count"])):
            raise ValueError("profile population/schedulers disagree with the staged configuration")
        return {"profile": {**config,
                            "pipeline_stages": args.pipeline_stages, "initiation_interval": args.initiation_interval,
                            "delay_model": args.delay_model, "flop_inputs": False, "flop_outputs": True},
                "ram_configuration": sha(snapshot / "assets/phi_scheduler_rams.sh")}

    def ram_configurations(snapshot: Path) -> str:
        """Bind the scheduler RAM ports from the immutable source snapshot."""
        return subprocess.check_output([
            "bash", "-c", 'set -euo pipefail; source "$1"; phi_scheduler_ram_configurations "$2"',
            "bash", str(snapshot / "assets/phi_scheduler_rams.sh"), str(json.loads((snapshot / "assets/phi_decoder_profile.json").read_text())["scheduler_count"])], text=True).strip()

    build(stage / "phi_decoder_profile_topology.x", args.xls_root, stage / "compiled",
          name="phi_decoder_profile", pipeline_stages=args.pipeline_stages,
          initiation_interval=args.initiation_interval, ram_configurations=ram_configurations,
          assets=[stage / name for name in ("phi_decoder_profile_top.v", "hls_1r1w_ram.v", "phi_scheduler_rams.sh", "phi_decoder_profile.json")],
          metadata=metadata, timeout=args.timeout, delay_model=args.delay_model, delay_table=args.delay_table)


if __name__ == "__main__":
    main()
