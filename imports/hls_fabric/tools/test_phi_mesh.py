#!/usr/bin/env python3
"""Build and profile the complete D6 torus on eighteen independently clocked 4×2 patches."""
import argparse
from pathlib import Path
from compiler_paths import compiler_root
from backend_paths import ROOT
from phi_mesh_build import build



def main() -> None:
    """Choose native tools and a resumable build directory; profiling uses the completed RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--xls", type=Path, required=True)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--devices", type=int, nargs="+", help="build only these device IDs; the profiler still requires all eighteen")
    parser.add_argument("--jobs", type=int, choices=(1, 2), default=1)
    parser.add_argument("--phi-actors-per-scheduler", type=int, choices=(1, 2, 4), default=4,
                        help="share the four local phi actors across four, two, or one RAM executors")
    parser.add_argument("--reductions", choices=("ordinary", "source_fragments"), default="source_fragments")
    parser.add_argument("--tiles", action="store_true", help="compile one congruent tile; bind seeds/addresses in per-board wrappers")
    parser.add_argument("--tile-cache", type=Path, default=ROOT/"_build/phi-tile-cache",
                        help="verified content-addressed cache independent of per-board constants")
    parser.add_argument("--reuse-actors", type=Path,
                        help="reuse checked unchanged actor RTL; compile only packed links and new identity gateways")
    parser.add_argument("--link-words", type=int, choices=(1, 2, 4), help="enable packed transfers of this many 32-bit words")
    parser.add_argument("--link-credits", type=int, choices=range(1, 17), default=4)
    parser.add_argument("--link-compact", action="store_true", help="use lossless compact headers where frame metadata permits")
    parser.add_argument('--delay-model', default='unit')
    parser.add_argument('--delay-table', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    if args.delay_model != 'unit' and not args.tiles:
        parser.error('custom timing models currently require --tiles')
    if (args.delay_model == 'xc7_7030') != (args.delay_table is not None):
        parser.error('xc7_7030 requires --delay-table; other models do not accept one')
    if args.tiles and args.reuse_actors is not None:
        parser.error('--tiles and --reuse-actors are separate build modes')
    args.tile_cache = args.tile_cache.resolve()
    if args.link_compact and args.link_words is None:
        parser.error('--link-compact requires --link-words')
    if args.reuse_actors is not None:
        if args.link_words is None:
            parser.error('--reuse-actors requires --link-words')
        args.reuse_actors = args.reuse_actors.resolve()
    args.transport = 'serial' if args.link_words is None else {'words': args.link_words, 'credits': args.link_credits}
    if args.link_compact:
        args.transport['compact'] = True
    for name in ("stage", "erl_hls", "xls"):
        setattr(args, name, getattr(args, name).resolve())
    args.shape, args.planes = [6, 6], ["x", "z"]
    args.memory, args.memory_case, args.placement = True, "mesh_memory", "coalesced"
    build(args)


if __name__ == "__main__":
    main()
