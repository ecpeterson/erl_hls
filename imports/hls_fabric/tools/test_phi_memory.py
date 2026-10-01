#!/usr/bin/env python3
"""Run the complete D3 memory experiment across two independently clocked RTL devices."""
import argparse
from pathlib import Path
from backend_paths import PUBLIC
import test_phi_bridge as bridge


def main() -> None:
    """Build or validate the hardware, then compare corrections and measurements with BEAM."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--stage", type=Path, default=bridge.ROOT / "_build/phi-memory")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--clock-halves", type=int, nargs=2, default=[3, 7])
    parser.add_argument("--reuse-build", action="store_true")
    parser.add_argument("--placement", choices=("direct", "shared", "coalesced"), default="direct")
    parser.add_argument("--reductions", choices=("ordinary", "source_fragments"), default="ordinary")
    parser.add_argument("--compiler-timeout", type=int, default=1200,
                        help="per-stage XLS deadline in seconds; slow native builds may need more")
    parser.add_argument("--simulation-timeout", type=int,
                        help="total host-run deadline; defaults to 720s direct or 1500s RAM-backed")
    parser.add_argument("--memory-case", choices=("d3", "board_memory", "board_quiet"), default="d3")
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if min(args.clock_halves) < 1:
        parser.error("clock half periods must be positive")
    if args.placement == "direct" and args.reductions != "ordinary":
        parser.error("source-fragment reductions require shared schedulers")
    if args.simulation_timeout is None:
        args.simulation_timeout = 720 if args.placement == "direct" else 1500
    if args.simulation_timeout < 1:
        parser.error("simulation timeout must be positive")
    distance = 3 if args.memory_case == "d3" else 2
    args.memory, args.shape, args.planes = True, [distance, distance], ["x", "z"]
    if args.memory_case != "d3" and not args.build_only:
        parser.error("board cases use --build-only, followed by profile_phi_memory.py")
    for name in ("xls", "erl_hls", "stage"):
        setattr(args, name, getattr(args, name).resolve())
    if args.reuse_build:
        bridge.validate_build(args)
    else:
        bridge.build(args)
    if not args.build_only:
        bridge.simulate(args)


if __name__ == "__main__":
    main()
