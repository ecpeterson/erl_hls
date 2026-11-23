"""Compile and resume the independently clocked Phi mesh with bound build evidence."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
from pathlib import Path
import shutil

from backend_commands import digest, execute
from backend_build_profile import emit as emit_profile
from backend_paths import ROOT, erl_command
from phi_build_artifacts import mesh_artifacts
from phi_device_build import inputs, build_device, instrument_device


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
    provenance['files']['private/apps/hls_phi/tools/phi_tiles.py'] = digest(ROOT/'apps/hls_phi/tools/phi_tiles.py')
    provenance['files']['private/apps/hls_phi/tools/test_phi_mesh.py'] = digest(ROOT/'apps/hls_phi/tools/test_phi_mesh.py')
    provenance['files']['private/apps/hls_phi/tools/phi_mesh_build.py'] = digest(Path(__file__))
    provenance['files']['private/apps/hls_phi/tools/phi_mesh_components.py'] = digest(ROOT/'apps/hls_phi/tools/phi_mesh_components.py')
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
        if json.loads((args.stage / "source-hashes.json").read_text()) != mesh_artifacts(source):
            raise ValueError("generated source changed")
    else:
        args.stage.mkdir(parents=True, exist_ok=False)
        source.mkdir()
        emit_profile(source/"build-profile.json", profile="test", public=args.erl_hls,
                     initiation_interval=None, delay_model=getattr(args, "delay_model", "unit"))
        transport = ('serial' if args.transport == 'serial' else
                     f"#{{words => {args.link_words}, credits => {args.link_credits}"
                     + (", compact => true" if args.link_compact else "") + "}")
        execute(erl_command(args.erl_hls,
            "ok = hls_phi_memory_fixture:write(hd(init:get_plain_arguments()), coalesced, mesh_memory, "
            f"#{{phi_halo_cell => {args.phi_actors_per_scheduler}}}, {args.reductions}, {transport}, "
            f"{str(getattr(args, 'tiles', False)).lower()}), halt().",
            source, profile="test"), args.stage, "generation", timeout=600)
        for library in ("lib", "fabric"):
            for path in (args.erl_hls / "priv/xls" / library).glob("*.x"):
                shutil.copy(path, source)
        for path in (ROOT / "apps/hls_lowering/priv/xls").rglob("*.x"):
            shutil.copy(path, source)
        shutil.copy(ROOT / "apps/hls_phi/src/phi_field.x", source)
        if transform is not None:
            transform(source)
        stamp.write_text(json.dumps(provenance, indent=2, sort_keys=True)+"\n")
        (args.stage / "source-hashes.json").write_text(json.dumps(mesh_artifacts(source), indent=2)+"\n")
    devices = json.loads((source / "bridge.json").read_text())["devices"]
    if len(devices) != 18 or any(len(d["links"]) != 4 for d in devices):
        raise ValueError("D6 requires eighteen patches and four distinct peers each")
    selected = devices if args.devices is None else [d for d in devices if d["id"] in args.devices]
    if args.devices is not None and sorted(d["id"] for d in selected) != sorted(args.devices):
        raise ValueError("--devices must contain distinct IDs from 0 through 17")
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
            if json.loads(complete.read_text()) != mesh_artifacts(directory):
                raise ValueError(f"device {device['id']} changed after compilation")
            compact(directory)
            complete.write_text(json.dumps(mesh_artifacts(directory), indent=2)+"\n")
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
        complete.write_text(json.dumps(mesh_artifacts(directory), indent=2)+"\n")

    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        list(workers.map(compile_device, selected))
    if json.loads((args.stage / "source-hashes.json").read_text()) != mesh_artifacts(source):
        raise ValueError("generated source changed while compiling devices")
    current = build_inputs(args)
    if experiment is not None:
        current['experiment'] = experiment
    if current != provenance:
        raise ValueError("inputs changed while compiling devices")
    print(f"PASS: {len(selected)} selected four-peer devices compiled and instrumented: {args.stage}")
