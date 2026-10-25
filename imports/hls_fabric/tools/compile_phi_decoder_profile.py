#!/usr/bin/env python3
"""Build the decoder profile and its wrapper as one published artifact set."""
import argparse
import json
from pathlib import Path
import signal

try:
    import compile_xls
except ModuleNotFoundError:
    from compiler_paths import PUBLIC

from compile_xls import build, duration, interrupted, sha


INPUTS = "phi_decoder_profile.inputs.json"
PROFILE = "phi_decoder_profile.json"
TOPOLOGY = "phi_decoder_profile_topology.x"
WRAPPER = "phi_decoder_profile_top.v"


def checked_inputs(snapshot: Path, *, assets: Path | None = None) -> dict:
    """Bind compiler-produced metadata to the immutable generated source and wrapper bytes.

    This is an integrity boundary for a trusted local Erlang build, not a second
    topology compiler or authentication of caller-supplied files. An explicit
    assets directory also supports checking a flat prepared experiment stage.
    """
    assets = snapshot / "assets" if assets is None else assets
    manifest = json.loads((assets / INPUTS).read_text())
    if not isinstance(manifest, dict):
        raise ValueError("profile input manifest must be an object")
    if type(manifest.get("version")) is not int or manifest["version"] != 1:
        raise ValueError("unsupported profile input manifest version")
    inputs = manifest.get("inputs")
    if not isinstance(inputs, dict) or not {TOPOLOGY, WRAPPER, PROFILE} <= inputs.keys():
        raise ValueError("profile input manifest omits required generated files")
    for name, expected in inputs.items():
        if Path(name).name != name or not (name.endswith(".x") or name in (WRAPPER, PROFILE)):
            raise ValueError(f"invalid profile input name: {name!r}")
        path = snapshot / name if name.endswith(".x") else assets / name
        if sha(path) != expected:
            raise ValueError(f"generated profile input changed: {name}")
    if not isinstance(manifest.get("ram_configurations"), str) or not manifest["ram_configurations"]:
        raise ValueError("profile input manifest omits RAM configurations")
    recipe = manifest.get("ram_configuration")
    if not isinstance(recipe, str) or len(recipe) != 64 or any(c not in "0123456789abcdef" for c in recipe):
        raise ValueError("profile input manifest omits a valid RAM recipe identity")
    return manifest


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
        """Read the Erlang-owned population after checking the snapshotted build inputs."""
        inputs = checked_inputs(snapshot)
        config = json.loads((snapshot / "assets" / PROFILE).read_text())
        if config["shards_per_plane"] != args.shards:
            raise ValueError("requested shards disagree with the staged configuration")
        return {"profile": {**config,
                            "pipeline_stages": args.pipeline_stages, "initiation_interval": args.initiation_interval,
                            "delay_model": args.delay_model, "flop_inputs": False, "flop_outputs": True},
                "ram_configuration": inputs["ram_configuration"]}

    def ram_configurations(snapshot: Path) -> str:
        """Pass through RAM bindings emitted from the same checked scheduler plan."""
        return checked_inputs(snapshot)["ram_configurations"]

    build(stage / TOPOLOGY, args.xls_root, stage / "compiled",
          name="phi_decoder_profile", pipeline_stages=args.pipeline_stages,
          initiation_interval=args.initiation_interval, ram_configurations=ram_configurations,
          assets=[stage / name for name in (WRAPPER, "hls_1r1w_ram.v", PROFILE, INPUTS)],
          metadata=metadata, timeout=args.timeout, delay_model=args.delay_model, delay_table=args.delay_table)


if __name__ == "__main__":
    main()
