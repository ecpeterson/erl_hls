#!/usr/bin/env python3
"""Build and profile the complete D6 torus on eighteen independently clocked 4×2 patches."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
from pathlib import Path
from backend_paths import PUBLIC
import shutil
import sys
from collections.abc import Callable

from test_actor_rtl import digest, erl_command, execute
from test_phi_bridge import ROOT, inputs, build_device, instrument_device


def artifacts(directory: Path) -> dict:
    """Hash retained RTL, source, manifests and compiler output for resumable builds."""
    return {str(p.relative_to(directory)): digest(p) for p in sorted(directory.rglob("*"))
            if p.is_file() and p.suffix in (".x", ".v", ".ir", ".json", ".term", ".gz")
            and p.name != "complete.json"}


def compact(directory: Path) -> None:
    """Retain digests of checked elaboration intermediates and compress verbose tool logs."""
    record = directory / "pruned.json"
    removed = json.loads(record.read_text()) if record.exists() else {}
    for name in ("flat.json", "instrumented.json", "hierarchy.json"):
        path = directory / "debug" / name
        if path.exists():
            removed[name] = digest(path)
            path.unlink()
    for name in ("elaborate.log", "export.log"):
        path = directory / "debug" / name
        if path.exists():
            removed[name] = digest(path)
            path.with_suffix(".log.gz").write_bytes(gzip.compress(path.read_bytes(), compresslevel=6, mtime=0))
            path.unlink()
    record.write_text(json.dumps(removed, indent=2)+"\n")


def build_inputs(args: argparse.Namespace) -> dict:
    """Include transport settings and any immutable reused actor build in the build identity."""
    provenance = inputs(args)
    provenance['config']['phi_actors_per_scheduler'] = args.phi_actors_per_scheduler
    provenance['config']['reductions'] = args.reductions
    provenance['config']['transport'] = args.transport
    provenance['config']['tiles'] = getattr(args, 'tiles', False)
    provenance['config']['delay_model'] = getattr(args, 'delay_model', 'unit')
    if getattr(args, 'delay_table', None) is not None:
        provenance['config']['delay_table_sha256'] = digest(args.delay_table)
    provenance['files']['private/tools/phi_tiles.py'] = digest(ROOT/'tools/phi_tiles.py')
    provenance['files']['private/tools/test_phi_mesh.py'] = digest(Path(__file__))
    provenance['files']['private/tools/phi_mesh_components.py'] = digest(ROOT/'tools/phi_mesh_components.py')
    if args.reuse_actors is not None:
        provenance['actor_base'] = {'path': str(args.reuse_actors),
                                    'inputs_sha256': digest(args.reuse_actors/'inputs.json')}
    return provenance


def build(args: argparse.Namespace, *, transform: Callable[[Path], None] | None = None,
          experiment: dict | None = None) -> None:
    """Build verified devices, optionally applying an explicitly fingerprinted source experiment."""
    if (transform is None) != (experiment is None):
        raise ValueError('a source transform requires its experiment identity')
    provenance = build_inputs(args)
    if experiment is not None:
        provenance['experiment'] = experiment
    stamp = args.stage / "inputs.json"
    source = args.stage / "source"
    if stamp.exists():
        if json.loads(stamp.read_text()) != provenance:
            raise ValueError("build inputs changed; choose a fresh stage")
        if json.loads((args.stage / "source-hashes.json").read_text()) != artifacts(source):
            raise ValueError("generated source changed")
    else:
        args.stage.mkdir(parents=True, exist_ok=False)
        source.mkdir()
        transport = ('serial' if args.transport == 'serial' else
                     f"#{{words => {args.link_words}, credits => {args.link_credits}"
                     + (", compact => true" if args.link_compact else "") + "}")
        execute(erl_command(args.erl_hls,
            "ok = hls_phi_memory_fixture:write(hd(init:get_plain_arguments()), coalesced, mesh_memory, "
            f"#{{phi_halo_cell => {args.phi_actors_per_scheduler}}}, {args.reductions}, {transport}, "
            f"{str(getattr(args, 'tiles', False)).lower()}), halt().",
            source), args.stage, "generation", timeout=600)
        for library in ("lib", "fabric"):
            for path in (args.erl_hls / "priv/xls" / library).glob("*.x"):
                shutil.copy(path, source)
        for path in (ROOT / "priv/xls").rglob("*.x"):
            shutil.copy(path, source)
        shutil.copy(args.erl_hls / "src/examples/phi_decoder/phi_field.x", source)
        if transform is not None:
            transform(source)
        stamp.write_text(json.dumps(provenance, indent=2, sort_keys=True)+"\n")
        (args.stage / "source-hashes.json").write_text(json.dumps(artifacts(source), indent=2)+"\n")
    devices = json.loads((source / "bridge.json").read_text())["devices"]
    if len(devices) != 18 or any(len(d["links"]) != 4 for d in devices):
        raise ValueError("D6 requires eighteen patches and four distinct peers each")
    selected = devices if args.devices is None else [d for d in devices if d["id"] in args.devices]
    if args.devices is not None and sorted(d["id"] for d in selected) != sorted(args.devices):
        raise ValueError("--devices must contain distinct IDs from 0 through 17")
    sys.path.insert(0, str(args.erl_hls / "tools"))
    if args.reuse_actors is not None:
        import phi_mesh_components
        phi_mesh_components.prepare(args, selected)

    tile = None
    if getattr(args, 'tiles', False):
        import phi_tiles
        tile = phi_tiles.prepare(args, devices)

    def compile_device(device: dict) -> None:
        """Resume a device only when all its retained outputs match their digest."""
        directory = args.stage / f"device{device['id']}"
        complete = directory / "complete.json"
        if complete.exists():
            if json.loads(complete.read_text()) != artifacts(directory):
                raise ValueError(f"device {device['id']} changed after compilation")
            compact(directory)
            complete.write_text(json.dumps(artifacts(directory), indent=2)+"\n")
            print(f"Reusing verified device {device['id']}", flush=True)
            return
        if directory.exists():
            raise ValueError(f"incomplete device build at {directory}; inspect its logs and remove it before retrying")
        if tile is not None:
            phi_tiles.bind(args, device, tile)
            instrument_device(args, device)
        elif args.reuse_actors is None:
            build_device(args, device)
        else:
            phi_mesh_components.link_device(args, device)
            instrument_device(args, device)
        # These large elaboration intermediates have already passed equality and SCC checks.
        compact(directory)
        complete.write_text(json.dumps(artifacts(directory), indent=2)+"\n")

    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        list(workers.map(compile_device, selected))
    current = build_inputs(args)
    if experiment is not None:
        current['experiment'] = experiment
    if current != provenance:
        raise ValueError("inputs changed while compiling devices")
    print(f"PASS: {len(selected)} selected four-peer devices compiled and instrumented: {args.stage}")


def main() -> None:
    """Choose native tools and a resumable build directory; profiling uses the completed RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
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
